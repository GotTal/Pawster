import SwiftUI

struct SetupGuideView: View {
    @ObservedObject var progress: SetupProgress
    @ObservedObject var pairing: PairingService
    @ObservedObject var guide: PairingGuide
    @ObservedObject var vpn: LocalVPNMonitor
    @ObservedObject var preferences: AppPreferences
    let busy: Bool
    let startPairing: () -> Void
    let importPairing: () -> Void
    let useSavedPairing: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var linkError: String?
    private var locked: Bool { busy || pairing.running || !preferences.hasConsent }
    private var connected: Bool { vpn.snapshot.state == .connected }
    private var ready: Bool { preferences.hasPairingConsent && pairing.credentialState == .ready }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("onboarding.step", [String(progress.step.number), String(SetupProgress.Step.allCases.count)]))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(progress.step.title).font(.title2.bold())
                    HStack(spacing: 6) {
                        ForEach(SetupProgress.Step.allCases) { step in
                            Capsule().fill(step.number <= progress.step.number ? Color.teal : Color.secondary.opacity(0.15)).frame(height: 4)
                        }
                    }.accessibilityHidden(true)
                }.padding(.vertical, 6)
            }
            switch progress.step {
            case .install: installation
            case .vpn: configuration
            case .developer: developerMode
            case .pairing: pairDevice
            }
            if let linkError {
                Section { Text(linkError).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .pawsterBackground()
        .navigationTitle(L10n.text("onboarding.title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if progress.step != .install {
                    Button(L10n.text("onboarding.back")) { progress.back() }.disabled(locked)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.text("onboarding.later")) { progress.pause() }.disabled(busy || pairing.running)
            }
        }
        .onChange(of: progress.step) { _, _ in linkError = nil }
    }

    private var installation: some View {
        Group {
            Section {
                instruction("1", "onboarding.installInstructions")
                Link(L10n.text("onboarding.downloadVPN"), destination: SetupLinks.vpnStore)
                Link(L10n.text("onboarding.vpnProject"), destination: SetupLinks.vpnProject).font(.footnote)
            } footer: { Text(L10n.text("onboarding.storeHelp")) }
            Section {
                Text(L10n.text("onboarding.alreadyInstalled")).font(.footnote).foregroundStyle(.secondary)
                primary(L10n.text("onboarding.installed")) { progress.advance(vpnConnected: connected) }
            }.listRowBackground(Color.clear)
        }
    }

    private var configuration: some View {
        Group {
            Section {
                instruction("1", "onboarding.vpnOpen")
                instruction("2", "onboarding.vpnAllow")
                instruction("3", "onboarding.vpnReturn")
                Button(L10n.text("onboarding.openVPN")) { openVPN() }.disabled(locked)
            }
            vpnStatus
            Section {
                Button(L10n.text("onboarding.checkVPN")) {
                    Task { await vpn.refresh() }
                }.disabled(locked)
                if !connected { Text(L10n.text("onboarding.vpnTrouble")).font(.footnote).foregroundStyle(.secondary) }
                primary(L10n.text("onboarding.next"), disabled: !connected) { progress.advance(vpnConnected: connected) }
            }.listRowBackground(Color.clear)
        }
    }

    private var developerMode: some View {
        Group {
            Section {
                instruction("1", "onboarding.developerPath")
                instruction("2", "onboarding.developerRestart")
                instruction("3", "onboarding.developerConfirm")
                Text(L10n.text("onboarding.afterRestart")).font(.footnote).foregroundStyle(.secondary)
                Button(L10n.text("onboarding.openVPN")) { openVPN() }.disabled(locked)
                settingsButton
                Link(L10n.text("onboarding.appleHelp"), destination: SetupLinks.developerHelp).font(.footnote)
            }
            Section {
                DisclosureGroup(L10n.text("onboarding.missingDeveloper")) {
                    Text(L10n.text("onboarding.missingDeveloperHelp")).font(.footnote)
                }
                Toggle(L10n.text("onboarding.developerAcknowledgement"), isOn: Binding(
                    get: { progress.developerAcknowledged }, set: { progress.acknowledgeDeveloper($0) }))
                    .disabled(locked)
                primary(L10n.text("onboarding.next"), disabled: !progress.developerAcknowledged) {
                    progress.advance(vpnConnected: connected)
                }
            }.listRowBackground(Color.clear)
        }
    }

    private var pairDevice: some View {
        Group {
            vpnStatus
            if !connected {
                Section {
                    Text(L10n.text("onboarding.reconnectVPN")).font(.footnote)
                    Button(L10n.text("onboarding.openVPN")) { openVPN() }.disabled(locked)
                }
            }
            Section {
                if pairing.completedSuccessfully {
                    Label(pairing.status, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if ready {
                    Label(L10n.text("credentials.ready"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(L10n.text("onboarding.savedReady")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(pairing.status).font(.footnote)
                }
                if !ready {
                    if SystemVersion.current.major >= 27 {
                        instruction("1", "onboarding.pairStart")
                        instruction("2", "onboarding.pairSettings")
                        instruction("3", "onboarding.pairPIN")
                        if !pairing.running {
                            Button(pairing.credentialState.pairAction, action: startPairing)
                                .disabled(locked || !connected)
                        }
                    } else {
                        Text(L10n.text("onboarding.legacyPairing")).font(.footnote)
                    }
                    Text(L10n.text("onboarding.localNetwork")).font(.footnote).foregroundStyle(.secondary)
                }
                if pairing.running {
                    if let pin = pairing.pin {
                        Text(pin).font(.largeTitle.monospacedDigit().bold()).textSelection(.enabled)
                        Button(L10n.text("action.copyCode")) { pairing.copyPIN() }
                    }
                    Button(L10n.text("action.cancelPairing"), role: .cancel) { pairing.cancel() }
                    settingsButton
                    if !guide.note.isEmpty { Text(guide.note).font(.caption).foregroundStyle(.secondary) }
                } else if !ready {
                    if pairing.hasCredentials {
                        Button(L10n.text("onboarding.useSavedPairing"), action: useSavedPairing).disabled(locked)
                    }
                    Button(pairing.credentialState.importAction, action: importPairing).disabled(locked)
                    DisclosureGroup(L10n.text("onboarding.importHelpTitle")) {
                        Text(L10n.text("onboarding.importHelp")).font(.footnote)
                    }
                }
                if pairing.retainedCredentialsAfterAttempt {
                    Text(L10n.text("pairing.existingRetained")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Text(L10n.text("onboarding.finishHelp")).font(.footnote).foregroundStyle(.secondary)
                primary(L10n.text("onboarding.finish"), disabled: !connected || !ready || !progress.developerAcknowledged) {
                    progress.finish(vpnConnected: connected, credentialReady: ready)
                }
            }.listRowBackground(Color.clear)
        }
    }

    private var vpnStatus: some View {
        Section {
            Label(L10n.text(connected ? "vpn.connected" : "onboarding.vpnNotReady"),
                  systemImage: connected ? "checkmark.circle.fill" : "network")
                .foregroundStyle(connected ? Color.green : Color.secondary)
            LabeledContent(L10n.text("vpn.ifaceIP"), value: vpn.snapshot.interfaceIP ?? "—")
            LabeledContent(L10n.text("vpn.peerIP"), value: vpn.peerIP)
            Text(L10n.text("vpn.statusHelp")).font(.caption).foregroundStyle(.secondary)
        } header: { Text(L10n.text("vpn.section")) }
    }
    private var settingsButton: some View {
        Button(L10n.text("action.openAppSettings")) {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        }.disabled(busy)
    }
    private func instruction(_ number: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.callout.monospacedDigit().bold()).foregroundStyle(.teal).frame(width: 20)
            Text(L10n.text(key)).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 3)
    }
    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(.tint, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(locked || disabled).opacity(locked || disabled ? 0.45 : 1)
    }
    private func openVPN() {
        linkError = nil
        openURL(SetupLinks.vpnApp) { accepted in
            if !accepted { Task { @MainActor in linkError = L10n.text("onboarding.vpnOpenFailed") } }
        }
    }
}
