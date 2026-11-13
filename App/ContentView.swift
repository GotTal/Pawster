import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var pairing: PairingService
    @ObservedObject var guide: PairingGuide
    @ObservedObject var neoSpring: NeoSpringController
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var vpn: LocalVPNMonitor
    @Environment(\.scenePhase) private var scenePhase
    private enum Tab: Hashable { case wallpapers, connection, settings }
    @State private var selectedTab = Tab.wallpapers
    @State private var overrideDraft = ""
    @State private var overrideError: String?
    @State private var showImporter = false
    @State private var importingPair = false
    @State private var importingPocketTarget = false
    @State private var pendingReceipt: TransactionReceipt?
    @State private var retryReceipt: TransactionReceipt?
    @State private var rollback = false
    @State private var confirmReceipt = false
    @State private var logFile: URL?
    @State private var showPolicyNotice = false
    @State private var didShowPolicyNotice = false
    @State private var confirmForgetPairing = false
    @State private var confirmWithdrawConsent = false
    @State private var confirmPairingConsent = false
    @State private var pendingPairingOperation: (() -> Void)?
    @StateObject private var setup = SetupProgress()
    @State private var pendingSetup = false
    var dataActionsLocked: Bool { model.busy || pairing.running }
    var locked: Bool { dataActionsLocked || !preferences.hasConsent }
    private var injectionUnavailable: Bool {
        locked || model.availableEngines.isEmpty || model.selected.isEmpty ||
        (model.selectedEngine.requiresPairing ? !pairing.hasCredentials : !model.pocketTargetReady)
    }
    private var shouldMonitorVPN: Bool {
        preferences.hasConsent && (model.selectedEngine.requiresPairing || preferences.hasPairingConsent)
    }
    private func requestInjectionConsent(for engine: InjectionEngine, operation: @escaping () -> Void) {
        if engine.requiresPairing { requestPairingConsent(operation) }
        else { operation() } // Local operations still enforce overall risk consent in AppModel.
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { wallpapers }.tabItem { Label(L10n.text("tab.wallpapers"), systemImage: "photo.on.rectangle") }.tag(Tab.wallpapers)
            NavigationStack { connection }.tabItem { Label(L10n.text("tab.connection"), systemImage: "link") }.tag(Tab.connection)
            NavigationStack { settings }.tabItem { Label(L10n.text("tab.settings"), systemImage: "gearshape") }.tag(Tab.settings)
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onAppear {
            pairing.refreshCredentials(allowInspection: preferences.hasPairingConsent)
            if !didShowPolicyNotice {
                overrideDraft = vpn.overridePeerIP ?? ""
                showPolicyNotice = !preferences.hasConsent; didShowPolicyNotice = true
            }
            offerSetupIfNeeded()
        }
        .onChange(of: preferences.hasConsent) { _, granted in
            if granted { offerSetupIfNeeded() }
            else { setup.pause() }
        }
        .onChange(of: preferences.logLimit) { _, _ in model.trimLogs() }
        .onChange(of: preferences.hasPairingConsent) { _, granted in pairing.refreshCredentials(allowInspection: granted) }
        .onChange(of: vpn.overridePeerIP) { _, value in overrideDraft = value ?? "" }
        .task(id: scenePhase == .active && shouldMonitorVPN) {
            guard scenePhase == .active, shouldMonitorVPN else { vpn.resetStatus(); return }
            while !Task.isCancelled {
                await vpn.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .sheet(isPresented: $showPolicyNotice, onDismiss: {
            if preferences.hasConsent { offerSetupIfNeeded() }
            else { pendingSetup = false }
        }) {
            PolicyNoticeView(alreadyAccepted: preferences.hasConsent, accept: { risksAcknowledged in
                guard preferences.acceptPolicies(risksAcknowledged: risksAcknowledged) else { return }
                showPolicyNotice = false
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
            if model.selectedEngine == .pocketTrash, model.busy { model.cancel() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            defer { importingPocketTarget = false }
            switch result {
            case .success(let url):
                if importingPocketTarget {
                    do { model.manualPath = try PocketTarget.read(url); _ = model.configurePocketTarget() }
                    catch { model.error = error.localizedDescription }
                } else if importingPair { do { try pairing.importCredentials(url) } catch { model.error = error.localizedDescription } }
                else { model.importWallpaper(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $model.plan) { plan in
            NavigationStack {
                List {
                    Section(L10n.text("plan.operation")) {
                        LabeledContent(L10n.text("plan.engine"), value: plan.engine.title)
                        LabeledContent(L10n.text("plan.newDirectories"), value: L10n.text("count.items", [String(describing: plan.items.count)]))
                    }
                    if plan.engine == .airlift {
                        Section { Text(L10n.text("airlift.warning")).foregroundStyle(.orange) }
                    }
                    if plan.engine == .pocketTrash {
                        Section { Text(L10n.text("pocket.warning")).foregroundStyle(.orange) }
                    }
                    Section(L10n.text("plan.container")) { Text(plan.container.path).font(.caption).textSelection(.enabled) }
                    Section(L10n.text("plan.destinations")) { ForEach(plan.items) { item in Text(item.destinationRelative).font(.caption) } }
                    Section {
                        Button {
                            requestInjectionConsent(for: plan.engine) { model.plan = nil; model.install(plan) }
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
        .confirmationDialog(L10n.text("airlift.retryTitle"), isPresented: Binding(get: { retryReceipt != nil }, set: { if !$0 { retryReceipt = nil } }), titleVisibility: .visible) {
            Button(L10n.text("airlift.retryConfirm")) {
                if let receipt = retryReceipt { model.acknowledgeAirliftRetry(receipt) }
                retryReceipt = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) { retryReceipt = nil }
        } message: { Text(L10n.text(retryReceipt?.engine == .pocketTrash ? "pocket.retryMessage" : "airlift.retryMessage")) }
        .alert(L10n.text("neoSpring.noticeTitle"), isPresented: $neoSpring.showingNotice, presenting: neoSpring.notice) { notice in
            Button(L10n.text(notice.purpose == .enableAutomatic ? "neoSpring.enableAutomatic" : "neoSpring.confirmRefresh")) {
                if neoSpring.confirmNotice(notice.id) {
                    Task { @MainActor in await Task.yield(); model.runNeoSpring() }
                }
            }
            Button(L10n.text("action.cancel"), role: .cancel) { neoSpring.dismissNotice() }
        } message: { notice in
            Text(L10n.text(notice.purpose == .enableAutomatic ? "neoSpring.automaticNotice" : "neoSpring.manualNotice"))
        }
        .confirmationDialog(rollback ? L10n.text("rollback.confirmTitle") : L10n.text("registration.confirmTitle"), isPresented: $confirmReceipt, titleVisibility: .visible) {
            Button(rollback ? L10n.text("rollback.confirmAction") : L10n.text("registration.confirmAction"), role: rollback ? .destructive : nil) {
                if let receipt = pendingReceipt { requestPairingConsent { model.updateReceipt(receipt, rollback: rollback) } }
            }
        } message: {
            if rollback, let receipt = pendingReceipt {
                Text(L10n.text("rollback.namedMessage", [L10n.date(receipt.createdAt),
                    receipt.wallpapers(availablePacks: model.packs).map(\.displayName).joined(separator: "\n")]))
            } else {
                Text(rollback ? L10n.text("rollback.confirmMessage") : L10n.text("registration.confirmMessage"))
            }
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
        .environment(\.pawsterBackgroundMotion,
                     preferences.animatedBackground && !model.busy && !pairing.running && guide.phase == .idle
                     && model.plan == nil && !showPolicyNotice && !showImporter && neoSpring.request == nil)
    }
    private func requestPairingConsent(_ operation: @escaping () -> Void) {
        guard preferences.hasConsent else { showPolicyNotice = true; return }
        if preferences.hasPairingConsent { operation() }
        else { pendingPairingOperation = operation; confirmPairingConsent = true }
    }
    private func openSetupGuide() {
        guard !dataActionsLocked else { return }
        guard !model.availableEngines.isEmpty else { model.error = L10n.text("compatibility.wallpaperUnavailable"); return }
        guard preferences.hasConsent else { pendingSetup = true; showPolicyNotice = true; return }
        selectedTab = .connection; setup.start()
    }
    private func offerSetupIfNeeded() {
        guard preferences.hasConsent, !model.availableEngines.isEmpty, !dataActionsLocked, !setup.showing, pendingSetup || setup.shouldAutoStart else { return }
        pendingSetup = false; openSetupGuide()
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { model.deleteWallpaper(pack) } label: {
                            Label(L10n.text("action.delete"), systemImage: "trash")
                        }
                        .disabled(dataActionsLocked)
                    }
                }
            }
            Section {
                Button { requestInjectionConsent(for: model.selectedEngine) { model.preview() } } label: {
                    VStack(spacing: 4) {
                        Label(L10n.text("action.previewPlan"), systemImage: "checklist").font(.headline)
                        Text(L10n.text("plan.reviewBeforeWrite")).font(.caption)
                    }
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                        .opacity(injectionUnavailable ? 0.45 : 1)
                }
                .buttonStyle(.plain).disabled(injectionUnavailable)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } footer: {
                if model.availableEngines.isEmpty { Text(L10n.text("compatibility.wallpaperUnavailable")) }
                else if model.selectedEngine == .pocketTrash, !model.pocketTargetReady {
                    Button(L10n.text("pocket.configureTarget")) { selectedTab = .connection }
                } else if preferences.hasConsent, model.selectedEngine.requiresPairing, !pairing.hasCredentials {
                    Button(L10n.text("plan.connectFirst")) { selectedTab = .connection }
                } else if model.selected.isEmpty { Text(L10n.text("plan.selectFirst")) }
            }
            operationStatus
            Section {
                Button(L10n.text("neoSpring.action"), systemImage: "arrow.clockwise") { model.requestNeoSpring() }
                    .foregroundStyle(.secondary).disabled(locked)
                Toggle(L10n.text("neoSpring.automatic"), isOn: automaticRefreshBinding)
                    .toggleStyle(CheckboxToggleStyle()).disabled(locked || model.selectedEngine.isWriteOnly)
                if model.selectedEngine == .airlift { Text(L10n.text("airlift.manualRefresh")).font(.footnote).foregroundStyle(.secondary) }
                if model.selectedEngine == .pocketTrash { Text(L10n.text("pocket.manualRefresh")).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text(L10n.text("neoSpring.section")) } footer: { Text(L10n.text("neoSpring.explanation")) }
        }.pawsterBackground().navigationTitle(L10n.text("tab.wallpapers"))
    }
    private var connection: some View {
        Group {
            if setup.showing {
                SetupGuideView(progress: setup, pairing: pairing, guide: guide, vpn: vpn, preferences: preferences, busy: model.busy,
                    startPairing: { requestPairingConsent { pairing.start() } },
                    importPairing: { requestPairingConsent { importingPair = true; showImporter = true } },
                    useSavedPairing: { requestPairingConsent { pairing.refreshCredentials(allowInspection: true) } },
                    localOnly: model.selectedEngine == .pocketTrash, pocketPath: $model.manualPath,
                    completePocketSetup: { if model.configurePocketTarget() { setup.finishLocal(targetReady: true) } })
            } else { connectionDetails }
        }
    }
    private var connectionDetails: some View {
        List {
            Section {
                Button { openSetupGuide() } label: { Label(L10n.text("onboarding.title"), systemImage: "sparkles") }
                    .disabled(dataActionsLocked)
            }
            if model.selectedEngine == .pocketTrash {
                Section(L10n.text("pocket.targetTitle")) {
                    Text(L10n.text("pocket.manualHelp")).font(.footnote)
                    TextField(L10n.text("pocket.targetPlaceholder"), text: $model.manualPath, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                    Button(L10n.text("pocket.configureTarget")) { _ = model.configurePocketTarget() }.disabled(locked || !model.pocketTargetReady)
                    Button(L10n.text("pocket.importTarget")) { importingPair = false; importingPocketTarget = true; showImporter = true }.disabled(locked)
                    Link(L10n.text("pocket.nugget"), destination: URL(string: "https://github.com/leminlimez/Nugget")!)
                    Text(L10n.text("pocket.nuggetHelp")).font(.footnote).foregroundStyle(.secondary)
                    Text(L10n.text("pocket.warning")).font(.footnote).foregroundStyle(.orange)
                }
                Section { Text(L10n.text("pocket.optionalConnection")).font(.footnote).foregroundStyle(.secondary) }
            }
            vpnSection
            Section(L10n.text("connection.pairingFile")) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L10n.text("label.status")).fixedSize()
                    Spacer(minLength: 12)
                    Group {
                        switch pairing.credentialState {
                        case .ready:
                            Label(L10n.text("credentials.ready"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        case .saved:
                            Label(L10n.text("credentials.saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .invalid:
                            Label(L10n.text("credentials.invalid"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        case .missing:
                            Label(L10n.text("credentials.notConfigured"), systemImage: "circle.dashed").foregroundStyle(.secondary)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.body)
                    .imageScale(.small)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                Button(pairing.credentialState.importAction) { requestPairingConsent { importingPair = true; showImporter = true } }.disabled(locked)
                Text(L10n.text("connection.vpnInstruction")).font(.footnote).foregroundStyle(.secondary)
            }
            if pairing.supportsOnDevicePairing {
              Section(L10n.text("connection.localPairing")) {
                if !pairing.running {
                    Button(pairing.credentialState.pairAction) { requestPairingConsent { pairing.start() } }.disabled(locked)
                }
                if pairing.running {
                    if let pin = pairing.pin { Text(pin).font(.largeTitle.monospacedDigit().bold()).textSelection(.enabled); Button(L10n.text("action.copyCode")) { pairing.copyPIN() } }
                    Button(L10n.text("action.cancelPairing"), role: .cancel) { pairing.cancel() }
                }
                if pairing.completedSuccessfully {
                    Label(pairing.status, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green)
                } else {
                    Text(pairing.status).font(.footnote)
                }
                if pairing.retainedCredentialsAfterAttempt {
                    Text(L10n.text("pairing.existingRetained")).font(.footnote).foregroundStyle(.secondary)
                }
                if pairing.running || !pairing.hasCredentials {
                    Text(L10n.text("pairing.settingsPath")).font(.footnote).foregroundStyle(.secondary)
                }
                if !guide.note.isEmpty { Text(guide.note).font(.caption).foregroundStyle(.secondary) }
                Button(L10n.text("action.openAppSettings")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
              }
            } else if model.selectedEngine.requiresPairing {
                Section(L10n.text("connection.pairingMethod")) {
                    Text(L10n.text("onboarding.legacyPairing")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("connection.compatibility")) {
                LabeledContent(L10n.text("connection.system"), value: SystemVersion.current.text)
                LabeledContent(L10n.text("connection.systemBuild"), value: SystemVersion.currentBuild.isEmpty ? "—" : SystemVersion.currentBuild)
                if model.availableEngines.count > 1 {
                    Picker(L10n.text("plan.engine"), selection: Binding(get: { model.selectedEngine }, set: { model.selectEngine($0) })) {
                        ForEach(model.availableEngines, id: \.self) { engine in Text(engine.title).tag(engine) }
                    }.disabled(locked)
                    Text(L10n.text("compatibility.engineSelectionHelp")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent(L10n.text("plan.engine"), value: model.engineLabel)
                }
                if model.selectedEngine == .airlift {
                    Text(L10n.text("airlift.warning")).font(.footnote).foregroundStyle(.orange)
                }
                if model.availableEngines.isEmpty {
                    Text(L10n.text("compatibility.wallpaperUnavailable")).font(.footnote).foregroundStyle(.secondary)
                }
                Button(L10n.text(model.selectedEngine.isWriteOnly ? "action.locateContainer" : "action.discoverPath")) { requestPairingConsent { model.discover() } }.disabled(locked || model.availableEngines.isEmpty || !pairing.hasCredentials)
                if model.selectedEngine != .pocketTrash {
                    TextField(L10n.text("connection.containerPath"), text: $model.manualPath, axis: .vertical).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                    Button(L10n.text("action.verifyManualPath")) { model.validateManual() }.disabled(locked || model.availableEngines.isEmpty || model.manualPath.isEmpty)
                }
                if let container = model.container {
                    Label(L10n.text(model.selectedEngine == .pocketTrash ? "pocket.containerConfigured" : model.selectedEngine == .airlift ? "airlift.containerLocated" : "connection.verified", [container.source]),
                          systemImage: model.selectedEngine.isWriteOnly ? "location" : "checkmark.shield")
                }
            }
            operationStatus
        }.pawsterBackground().navigationTitle(L10n.text("connection.title"))
    }
    private var automaticRefreshBinding: Binding<Bool> {
        Binding(get: { neoSpring.automatic }, set: { neoSpring.requestAutomatic($0) })
    }
    private var vpnSection: some View {
        Section {
            HStack {
                Text(L10n.text("label.status")); Spacer()
                VPNConnectionBadge(state: vpn.snapshot.state)
            }
            LabeledContent(L10n.text("vpn.ifaceIP")) {
                Text(vpn.snapshot.interfaceIP ?? "—").font(.callout.monospaced()).textSelection(.enabled)
            }
            LabeledContent(L10n.text("vpn.peerIP")) {
                Text(vpn.peerIP).font(.callout.monospaced()).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("vpn.overrideLabel")).font(.subheadline)
                TextField(L10n.text("vpn.overridePlaceholder"), text: $overrideDraft)
                    .keyboardType(.numbersAndPunctuation).submitLabel(.done)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced()).disabled(locked)
                    .onSubmit { applyPeerOverride(overrideDraft) }
                if let overrideError { Text(overrideError).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button(L10n.text("vpn.applyOverride")) { applyPeerOverride(overrideDraft) }
                Spacer()
                Button(L10n.text("vpn.restoreAutomatic")) { applyPeerOverride("") }
                    .disabled(vpn.overridePeerIP == nil && overrideDraft.isEmpty)
            }.buttonStyle(.borderless).disabled(locked)
        } header: { Text(L10n.text("vpn.section")) } footer: {
              VStack(alignment: .leading, spacing: 6) {
                  Text(L10n.text("vpn.overrideHelp"))
                  Text(L10n.text("vpn.statusHelp"))
              }
          }
    }
    private func applyPeerOverride(_ text: String) {
        guard !locked else { return }
        do {
            try vpn.setOverride(text); overrideDraft = vpn.overridePeerIP ?? ""; overrideError = nil
            model.container = nil; model.plan = nil
            Task { guard preferences.hasConsent else { return }; await vpn.refresh() }
        } catch { overrideError = error.localizedDescription }
    }
    private var history: some View {
        List {
            if model.receipts.isEmpty { Text(L10n.text("history.empty")) }
            ForEach(model.receipts) { receipt in
                Section(L10n.date(receipt.createdAt)) {
                    ReceiptWallpapersView(receipt: receipt, availablePacks: model.packs)
                    LabeledContent(L10n.text("label.status"), value: stateName(receipt.state))
                    LabeledContent(L10n.text("plan.engine"), value: receipt.engine.title)
                    LabeledContent(L10n.text("history.targetCount"), value: "\(receipt.entries.count)")
                    if let refresh = receipt.refresh { LabeledContent(L10n.text("history.registration"), value: refresh.state == "written" ? L10n.text("history.filesVerified") : L10n.text("history.interrupted")) }
                    if let failure = receipt.failure { Text(failure).foregroundStyle(.red).font(.caption) }
                    ReceiptDetailsView(receipt: receipt)
                    if receipt.engine == .airlift {
                        Text(L10n.text("airlift.historyHelp")).font(.footnote).foregroundStyle(.secondary)
                        if receipt.airliftRecoveryCompleted == true {
                            Label(L10n.text("airlift.recovered"), systemImage: "checkmark.circle").font(.footnote)
                        } else {
                            Button(L10n.text("airlift.recoverAction")) { requestPairingConsent { model.recoverAirlift(receipt) } }.disabled(locked)
                        }
                        if receipt.airliftRetryAcknowledged != true {
                            Button(L10n.text("airlift.retryTitle")) { retryReceipt = receipt }.disabled(locked)
                        }
                    }
                    if receipt.engine == .pocketTrash {
                        Text(L10n.text("pocket.historyHelp")).font(.footnote).foregroundStyle(.secondary)
                        if receipt.pocketCleanupCompleted == true {
                            Label(L10n.text("pocket.cleaned"), systemImage: "checkmark.circle").font(.footnote)
                        } else {
                            Button(L10n.text("pocket.cleanupAction")) { model.cleanupPocket(receipt) }.disabled(dataActionsLocked)
                        }
                        if receipt.pocketRetryAcknowledged != true {
                            Button(L10n.text("airlift.retryTitle")) { retryReceipt = receipt }.disabled(locked)
                        }
                    }
                    if !receipt.engine.isWriteOnly, receipt.state == "filesVerified", receipt.refresh == nil {
                        Button(L10n.text("action.refreshRegistration")) { pendingReceipt = receipt; rollback = false; confirmReceipt = true }.disabled(locked)
                    }
                    if !receipt.engine.isWriteOnly, receipt.state != "rolledBack" {
                        Button(L10n.text("action.rollback"), role: .destructive) { pendingReceipt = receipt; rollback = true; confirmReceipt = true }.disabled(locked)
                    }
                }
            }
            operationStatus
        }.pawsterBackground().navigationTitle(L10n.text("history.title"))
    }
    private var settings: some View {
        List {
            Section(L10n.text("settings.tools")) {
                Button { openSetupGuide() } label: { Label(L10n.text("onboarding.title"), systemImage: "sparkles") }
                    .disabled(dataActionsLocked)
                NavigationLink { history } label: { Label(L10n.text("history.title"), systemImage: "clock.arrow.circlepath") }
                NavigationLink { diagnostics } label: { Label(L10n.text("diagnostics.title"), systemImage: "list.bullet.rectangle") }
            }
            Section(L10n.text("settings.preferences")) {
                Picker(L10n.text("settings.appearance"), selection: $preferences.appearance) {
                    ForEach(AppPreferences.Appearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }
                Toggle(L10n.text("settings.animatedBackground"), isOn: $preferences.animatedBackground)
                Toggle(L10n.text("neoSpring.automatic"), isOn: automaticRefreshBinding)
                    .toggleStyle(CheckboxToggleStyle()).disabled(locked || model.selectedEngine.isWriteOnly)
                if model.selectedEngine.isWriteOnly {
                    Text(L10n.text(model.selectedEngine == .pocketTrash ? "pocket.manualRefresh" : "airlift.manualRefresh")).font(.footnote).foregroundStyle(.secondary)
                }
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
            Section(L10n.text("freeUse.title")) { FreeUseNoticeView() }
            Section(L10n.text("settings.about")) {
                LabeledContent("App", value: AppInformation.name)
                LabeledContent(L10n.text("about.version"), value: AppInformation.version)
                if let channel = AppInformation.channel { LabeledContent(L10n.text("about.channel"), value: channel) }
                if let revision = AppInformation.revision { LabeledContent(L10n.text("about.revision"), value: revision) }
                DeveloperContactRow()
                Link(L10n.text("about.repository"), destination: AppInformation.repository)
                Link(L10n.text("about.feedback"), destination: AppInformation.feedback)
                NavigationLink(L10n.text("legal.openSourceNotices")) { OpenSourceNoticesView() }
                NavigationLink(L10n.text("legal.terms")) { BundledDocumentView(title: L10n.text("legal.terms"), resource: "Terms") }
                NavigationLink(L10n.text("legal.privacy")) { BundledDocumentView(title: L10n.text("legal.privacy"), resource: "Privacy") }
            }
            Section {
                StudioFooterView()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 24, trailing: 0))
            }
        }.pawsterBackground().navigationTitle(L10n.text("tab.settings"))
    }
    private var diagnostics: some View {
        List {
            Section {
                Button(L10n.text("action.prepareLogs")) { do { logFile = try model.exportLogs() } catch { model.error = error.localizedDescription } }.disabled(dataActionsLocked)
                if let logFile { ShareLink(L10n.text("action.shareLogs"), item: logFile) }
            }
            Section(L10n.text("diagnostics.recent")) { ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()).textSelection(.enabled) } }
        }.pawsterBackground().navigationTitle(L10n.text("diagnostics.title"))
    }
    private func stateName(_ raw: String) -> String {
        switch raw {
        case "writing": return L10n.text("history.writing")
        case "filesVerified": return L10n.text("history.filesWritten")
        case "partial": return L10n.text("history.partial")
        case "rolledBack": return L10n.text("history.rolledBack")
        case "airliftSending": return L10n.text("airlift.historySending")
        case "airliftSent": return L10n.text("airlift.historySent")
        case "airliftPartial": return L10n.text("airlift.historyPartial")
        case "pocketSending": return L10n.text("pocket.historySending")
        case "pocketSent": return L10n.text("pocket.historySent")
        case "pocketPartial": return L10n.text("pocket.historyPartial")
        default: return raw
        }
    }
}

private struct DeveloperContactRow: View {
    @Environment(\.openURL) private var openURL
    @State private var showingContact = false

    var body: some View {
        Button { showingContact = true } label: {
            HStack {
                Text(L10n.text("about.developer")).foregroundStyle(.primary)
                Spacer()
                Text(AppInformation.developer).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.text("about.contactDeveloper"))
        .alert(L10n.text("about.contactDeveloper"), isPresented: $showingContact) {
            Button(L10n.text("action.sendEmail")) { openURL(AppInformation.email) }
            Button(L10n.text("action.copyEmail")) {
                UIPasteboard.general.setItems([["public.utf8-plain-text": AppInformation.contact]], options: [.localOnly: true])
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: { Text(AppInformation.contact) }
    }
}

private struct VPNConnectionBadge: View {
    let state: VPNStatusSnapshot.State
    private var appearance: (key: String, symbol: String, color: Color) {
        switch state {
        case .connected: return ("vpn.connected", "checkmark.circle.fill", .green)
        case .disconnected: return ("vpn.disconnected", "xmark.circle.fill", .orange)
        case .unchecked: return ("vpn.unchecked", "ellipsis.circle", .secondary)
        case .unavailable: return ("vpn.unavailable", "questionmark.circle", .secondary)
        }
    }
    var body: some View {
        Label(L10n.text(appearance.key), systemImage: appearance.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(appearance.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(appearance.color.opacity(0.12), in: Capsule())
    }
}
