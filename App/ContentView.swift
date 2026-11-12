import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var pairing: PairingService
    @ObservedObject var guide: PairingGuide
    @ObservedObject var neoSpring: NeoSpringController
    @ObservedObject var preferences: AppPreferences
    @State private var showImporter = false
    @State private var importingPair = false
    @State private var pendingReceipt: TransactionReceipt?
    @State private var rollback = false
    @State private var confirmReceipt = false
    @State private var logFile: URL?
    @State private var showPolicyNotice = false
    @State private var didShowPolicyNotice = false
    @State private var confirmForgetPairing = false
    @State private var confirmWithdrawConsent = false
    @State private var confirmPairingConsent = false
    @State private var pendingPairingOperation: (() -> Void)?
    var dataActionsLocked: Bool { model.busy || pairing.running }
    var locked: Bool { dataActionsLocked || !preferences.hasConsent }
    var body: some View {
        TabView {
            NavigationStack { wallpapers }.tabItem { Label(L10n.text("tab.wallpapers"), systemImage: "photo.on.rectangle") }
            NavigationStack { connection }.tabItem { Label(L10n.text("tab.connection"), systemImage: "link") }
            NavigationStack { settings }.tabItem { Label(L10n.text("tab.settings"), systemImage: "gearshape") }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onAppear {
            if !didShowPolicyNotice {
                showPolicyNotice = !preferences.hasConsent; didShowPolicyNotice = true
            }
        }
        .onChange(of: preferences.logLimit) { _, _ in model.trimLogs() }
        .sheet(isPresented: $showPolicyNotice) {
            PolicyNoticeView(alreadyAccepted: preferences.hasConsent, accept: {
                preferences.acceptPolicies(); showPolicyNotice = false
            }, decline: { showPolicyNotice = false })
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if guide.phase != .idle {
                GuidePreview(guide: guide)
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 360)
                    .padding(.vertical, 8).frame(maxWidth: .infinity).background(.background)
            }
        }
        .fullScreenCover(item: Binding(get: { neoSpring.request }, set: { if $0 == nil { neoSpring.cancel() } })) { request in
            NeoSpringScreen(request: request) { outcome in neoSpring.complete(request.id, outcome: outcome) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            neoSpring.didEnterBackground()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                if importingPair { do { try pairing.importCredentials(url) } catch { model.error = error.localizedDescription } }
                else { model.importWallpaper(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $model.plan) { plan in
            NavigationStack {
                List {
                    Section(L10n.text("plan.operation")) {
                        LabeledContent(L10n.text("plan.engine"), value: plan.engine.rawValue)
                        LabeledContent(L10n.text("plan.newDirectories"), value: L10n.text("count.items", [String(describing: plan.items.count)]))
                    }
                    Section(L10n.text("plan.container")) { Text(plan.container.path).font(.caption).textSelection(.enabled) }
                    Section(L10n.text("plan.destinations")) { ForEach(plan.items) { item in Text(item.destinationRelative).font(.caption) } }
                    Section {
                        Button {
                            requestPairingConsent { model.plan = nil; model.install(plan) }
                        } label: {
                            Text(L10n.text("action.inject"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
                                .foregroundStyle(.white)
                                .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .navigationTitle(L10n.text("plan.title"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("action.cancel")) { model.plan = nil } } }
            }
        }
        .alert(L10n.text("alert.operation"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L10n.text("action.ok")) { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog(rollback ? L10n.text("rollback.confirmTitle") : L10n.text("registration.confirmTitle"), isPresented: $confirmReceipt, titleVisibility: .visible) {
            Button(rollback ? L10n.text("rollback.confirmAction") : L10n.text("registration.confirmAction"), role: rollback ? .destructive : nil) {
                if let receipt = pendingReceipt { requestPairingConsent { model.updateReceipt(receipt, rollback: rollback) } }
            }
        } message: {
            Text(rollback ? L10n.text("rollback.confirmMessage") : L10n.text("registration.confirmMessage"))
        }
        .confirmationDialog(L10n.text("credentials.removeTitle"), isPresented: $confirmForgetPairing, titleVisibility: .visible) {
            Button(L10n.text("action.remove"), role: .destructive) {
                do { try pairing.forgetCredentials(); preferences.withdrawPairingConsent() }
                catch { model.error = error.localizedDescription }
            }.disabled(dataActionsLocked)
        } message: { Text(L10n.text("credentials.removeMessage")) }
        .confirmationDialog(L10n.text("consent.withdrawTitle"), isPresented: $confirmWithdrawConsent, titleVisibility: .visible) {
            Button(L10n.text("consent.withdrawAction"), role: .destructive) {
                do {
                    guide.stop(); try model.withdrawConsent(); logFile = nil
                } catch { model.error = error.localizedDescription }
            }.disabled(dataActionsLocked)
        } message: { Text(L10n.text("consent.withdrawMessage")) }
        .confirmationDialog(L10n.text("consent.pairingTitle"), isPresented: $confirmPairingConsent, titleVisibility: .visible) {
            Button(L10n.text("consent.pairingAccept")) {
                preferences.acceptPairingConsent()
                let operation = pendingPairingOperation; pendingPairingOperation = nil; operation?()
            }
            Button(L10n.text("action.cancel"), role: .cancel) { pendingPairingOperation = nil }
        } message: {
            Text(L10n.text("consent.pairingMessage"))
        }
    }
    private func requestPairingConsent(_ operation: @escaping () -> Void) {
        guard preferences.hasConsent else { showPolicyNotice = true; return }
        if preferences.hasPairingConsent { operation() }
        else { pendingPairingOperation = operation; confirmPairingConsent = true }
    }
    @ViewBuilder private var operationStatus: some View {
        if model.busy || !model.status.isEmpty {
            Section {
                if model.busy { ProgressView(); Button(L10n.text("action.cancelOperation"), role: .cancel) { model.cancel() } }
                Text(model.status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var wallpapers: some View {
        List {
            Section {
                Label(L10n.text("app.name"), systemImage: "sparkles").font(.title2.bold())
                if !preferences.hasConsent { Button(L10n.text("action.readIntroduction")) { showPolicyNotice = true } }
            }
            Section {
                Button(L10n.text("action.importTendies"), systemImage: "square.and.arrow.down") { importingPair = false; showImporter = true }.disabled(locked)
            }
            Section(L10n.text("packs.title", [String(describing: model.packs.count)])) {
                if model.packs.isEmpty { Text(L10n.text("packs.empty")).foregroundStyle(.secondary) }
                ForEach(model.packs) { pack in
                    Button {
                        if model.selected.contains(pack.id) { model.selected.remove(pack.id) } else { model.selected.insert(pack.id) }
                    } label: {
                        HStack(spacing: 12) {
                            if let preview = pack.preview, let image = UIImage(contentsOfFile: AppFiles.packs.appendingPathComponent(pack.directory).appendingPathComponent(preview).path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            } else { Image(systemName: "photo").frame(width: 54, height: 72) }
                            VStack(alignment: .leading) { Text(pack.name).foregroundStyle(.primary); Text(L10n.text("count.descriptors", [String(describing: pack.descriptors.count)])).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: model.selected.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .disabled(dataActionsLocked)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) { model.deleteWallpaper(pack) } label: {
                            Label(L10n.text("action.delete"), systemImage: "trash")
                        }
                        .disabled(dataActionsLocked)
                    }
                }
            }
            Section {
                Toggle(L10n.text("neoSpring.automatic"), isOn: $neoSpring.automatic)
                    .toggleStyle(CheckboxToggleStyle()).disabled(locked)
                Button(L10n.text("action.previewPlan"), systemImage: "checklist") { requestPairingConsent { model.preview() } }
                    .disabled(locked || model.selected.isEmpty || !pairing.hasCredentials)
            }
            Section {
                Button { model.runNeoSpring() } label: {
                    Label("NeoSpring", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
                        .foregroundStyle(.white)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).disabled(locked)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            operationStatus
        }.navigationTitle(L10n.text("tab.wallpapers"))
    }
    private var connection: some View {
        List {
            Section(L10n.text("connection.pairingFile")) {
                LabeledContent(L10n.text("label.status"), value: pairing.hasCredentials ? L10n.text("credentials.saved") : L10n.text("credentials.notConfigured"))
                Button(L10n.text("action.importPairingFile")) { requestPairingConsent { importingPair = true; showImporter = true } }.disabled(locked)
                Text(L10n.text("connection.vpnInstruction")).font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("connection.localPairing")) {
                if !pairing.running {
                    Button(L10n.text("action.startPairing")) { requestPairingConsent { pairing.start() } }.disabled(locked || SystemVersion.current.major < 27)
                }
                if pairing.running {
                    if let pin = pairing.pin { Text(pin).font(.largeTitle.monospacedDigit().bold()).textSelection(.enabled); Button(L10n.text("action.copyCode")) { pairing.copyPIN() } }
                    Button(L10n.text("action.cancelPairing"), role: .cancel) { pairing.cancel() }
                }
                Text(pairing.status).font(.footnote)
                Text(L10n.text("pairing.settingsPath")).font(.footnote).foregroundStyle(.secondary)
                if !guide.note.isEmpty { Text(guide.note).font(.caption).foregroundStyle(.secondary) }
                Button(L10n.text("action.openAppSettings")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section(L10n.text("connection.compatibility")) {
                TextField(L10n.text("connection.gateway"), text: $model.host).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                LabeledContent(L10n.text("connection.system"), value: SystemVersion.current.text)
                LabeledContent(L10n.text("plan.engine"), value: model.engineLabel)
                if SystemVersion.current == .init(major: 27, minor: 0, patch: 0) {
                    Toggle(L10n.text("connection.beta4Confirmation"), isOn: $model.confirmedBeta4).disabled(locked)
                }
                Button(L10n.text("action.discoverPath")) { requestPairingConsent { model.discover() } }.disabled(locked || !pairing.hasCredentials)
                TextField(L10n.text("connection.containerPath"), text: $model.manualPath, axis: .vertical).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                Button(L10n.text("action.verifyManualPath")) { model.validateManual() }.disabled(locked || model.manualPath.isEmpty)
                if let container = model.container {
                    Label(L10n.text("connection.verified", [String(describing: container.source)]), systemImage: "checkmark.shield")
                }
            }
            operationStatus
        }.navigationTitle(L10n.text("connection.title"))
    }
    private var history: some View {
        List {
            if model.receipts.isEmpty { Text(L10n.text("history.empty")) }
            ForEach(model.receipts) { receipt in
                Section(L10n.date(receipt.createdAt)) {
                    Text(receipt.id.uuidString).font(.caption).textSelection(.enabled)
                    LabeledContent(L10n.text("label.status"), value: stateName(receipt.state))
                    LabeledContent(L10n.text("history.targetCount"), value: "\(receipt.entries.count)")
                    if let refresh = receipt.refresh { LabeledContent(L10n.text("history.registration"), value: refresh.state == "written" ? L10n.text("history.filesVerified") : L10n.text("history.interrupted")) }
                    if let failure = receipt.failure { Text(failure).foregroundStyle(.red).font(.caption) }
                    if receipt.state == "filesVerified", receipt.refresh == nil {
                        Button(L10n.text("action.refreshRegistration")) { pendingReceipt = receipt; rollback = false; confirmReceipt = true }.disabled(locked)
                    }
                    if receipt.state != "rolledBack" {
                        Button(L10n.text("action.rollback"), role: .destructive) { pendingReceipt = receipt; rollback = true; confirmReceipt = true }.disabled(locked)
                    }
                }
            }
            operationStatus
        }.navigationTitle(L10n.text("history.title"))
    }
    private var settings: some View {
        List {
            Section(L10n.text("settings.tools")) {
                NavigationLink { history } label: { Label(L10n.text("history.title"), systemImage: "clock.arrow.circlepath") }
                NavigationLink { diagnostics } label: { Label(L10n.text("diagnostics.title"), systemImage: "list.bullet.rectangle") }
            }
            Section(L10n.text("settings.preferences")) {
                Picker(L10n.text("settings.appearance"), selection: $preferences.appearance) {
                    ForEach(AppPreferences.Appearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }
                Toggle(L10n.text("neoSpring.automatic"), isOn: $neoSpring.automatic)
                    .toggleStyle(CheckboxToggleStyle()).disabled(locked)
                Picker(L10n.text("settings.logLimit"), selection: $preferences.logLimit) {
                    ForEach(AppPreferences.logLimits, id: \.self) { count in
                        Text(count == 0 ? L10n.text("settings.noLogging") : L10n.text("count.logEntries", [String(describing: count)])).tag(count)
                    }
                }.disabled(dataActionsLocked)
            }
            Section(L10n.text("settings.privacy")) {
                LabeledContent(L10n.text("settings.authorization"), value: preferences.hasConsent ? L10n.text("consent.accepted") : L10n.text("consent.notEnabled"))
                if let date = preferences.acceptedAt, preferences.hasConsent {
                    LabeledContent(L10n.text("consent.acceptedAt"), value: L10n.date(date))
                }
                Button(L10n.text("action.readPolicies")) { showPolicyNotice = true }
                if preferences.hasPairingConsent {
                    Button(L10n.text("action.withdrawPairingConsent"), role: .destructive) {
                        preferences.withdrawPairingConsent()
                    }.disabled(dataActionsLocked)
                }
                Button(L10n.text("action.clearLogs"), role: .destructive) {
                    do { try model.clearLogs(); logFile = nil } catch { model.error = error.localizedDescription }
                }.disabled(dataActionsLocked)
                Button(L10n.text("action.removeCredentials"), role: .destructive) { confirmForgetPairing = true }.disabled(dataActionsLocked)
                if preferences.hasConsent {
                    Button(L10n.text("consent.withdrawAction"), role: .destructive) { confirmWithdrawConsent = true }.disabled(dataActionsLocked)
                }
            }
            Section(L10n.text("settings.about")) {
                LabeledContent("App", value: AppInformation.name)
                LabeledContent(L10n.text("about.version"), value: AppInformation.version)
                if let channel = AppInformation.channel { LabeledContent(L10n.text("about.channel"), value: channel) }
                if let revision = AppInformation.revision { LabeledContent(L10n.text("about.revision"), value: revision) }
                LabeledContent(L10n.text("about.developer"), value: AppInformation.developer)
                Link(L10n.text("about.repository"), destination: AppInformation.repository)
                Link(L10n.text("about.feedback"), destination: AppInformation.feedback)
                Link(AppInformation.contact, destination: AppInformation.email)
                NavigationLink(L10n.text("legal.openSourceNotices")) { OpenSourceNoticesView() }
                NavigationLink(L10n.text("legal.terms")) { BundledDocumentView(title: L10n.text("legal.terms"), resource: "Terms") }
                NavigationLink(L10n.text("legal.privacy")) { BundledDocumentView(title: L10n.text("legal.privacy"), resource: "Privacy") }
            }
        }.navigationTitle(L10n.text("tab.settings"))
    }
    private var diagnostics: some View {
        List {
            Section {
                Button(L10n.text("action.prepareLogs")) { do { logFile = try model.exportLogs() } catch { model.error = error.localizedDescription } }.disabled(dataActionsLocked)
                if let logFile { ShareLink(L10n.text("action.shareLogs"), item: logFile) }
            }
            Section(L10n.text("diagnostics.recent")) { ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()).textSelection(.enabled) } }
        }.navigationTitle(L10n.text("diagnostics.title"))
    }
    private func stateName(_ raw: String) -> String {
        switch raw { case "writing": return L10n.text("history.writing"); case "filesVerified": return L10n.text("history.filesWritten"); case "partial": return L10n.text("history.partial"); case "rolledBack": return L10n.text("history.rolledBack"); default: return raw }
    }
}
