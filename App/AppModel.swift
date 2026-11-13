import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    let preferences = AppPreferences()
    let neoSpring = NeoSpringController()
    let vpn = LocalVPNMonitor()
    @Published var packs: [WallpaperPack] = []
    @Published var selected: Set<UUID> = []
    @Published var receipts: [TransactionReceipt] = []
    @Published var container: VerifiedContainer?
    @Published var manualPath = ""
    var host: String { vpn.peerIP }
    @Published private(set) var selectedEngine = InjectionEngine.worseQuery
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var plan: InjectionPlan?
    @Published var logs: [String] = []
    private let queue = DispatchQueue(label: "Pawster.work", qos: .userInitiated)
    private let query = DeviceQuery()
    private var cancellation: CancellationToken?
    private let repository = WallpaperRepository()
    private let injector = InjectionService()
    private let airlift = AirliftInjectionService()
    private let pocket = PocketTrashInjectionService()
    var pocketTargetReady: Bool { (try? PocketTarget.normalize(manualPath)) != nil }
    var engineLabel: String { (try? engine().title) ?? L10n.text("compatibility.unsupported") }
    var availableEngines: [InjectionEngine] { EnginePolicy.available(for: .current, build: SystemVersion.currentBuild) }
    private var enginePreferenceKey: String { "enginePreference.\(SystemVersion.current.text).\(SystemVersion.currentBuild)" }
    func engine() throws -> InjectionEngine {
        try EnginePolicy.select(.current, build: SystemVersion.currentBuild, preferred: selectedEngine)
    }
    func selectEngine(_ engine: InjectionEngine) {
        guard !busy, availableEngines.contains(engine), engine != selectedEngine else { return }
        selectedEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: enginePreferenceKey)
        container = nil; plan = nil; error = nil
        status = L10n.text("compatibility.engineChanged")
        log(L10n.text("compatibility.engineSelected", [engine.rawValue]))
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: enginePreferenceKey),
           let engine = InjectionEngine(rawValue: saved), availableEngines.contains(engine) { selectedEngine = engine }
        else { selectedEngine = availableEngines.first ?? .worseQuery }
        manualPath = UserDefaults.standard.string(forKey: "containerPath") ?? ""
        reload()
        do { _ = try pocket.cleanup() } catch { self.error = error.localizedDescription }
        log("Pawster " + AppInformation.version + " · " + ProcessInfo.processInfo.operatingSystemVersionString)
    }
    func reload() {
        do {
            packs = try repository.load()
            selected.formIntersection(packs.map(\.id))
            receipts = try injector.receipts()
        } catch { self.error = error.localizedDescription }
    }
    private func log(_ message: String) {
        // Never pass pairing file contents, PINs, certificates or host private keys here.
        guard preferences.hasConsent, preferences.effectiveLogLimit > 0 else { return }
        let formatter = DateFormatter(); formatter.locale = L10n.locale
        formatter.dateStyle = .none; formatter.timeStyle = .medium
        let timestamp = formatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)"); trimLogs()
    }
    func trimLogs() {
        let limit = preferences.effectiveLogLimit
        if logs.count > limit { logs.removeFirst(logs.count - limit) }
    }
    func clearLogs() throws {
        let url = AppFiles.diagnosticExport
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        logs.removeAll(); status = L10n.text("status.logsCleared")
    }
    func withdrawConsent() throws {
        guard !busy else { throw BridgeError.message(L10n.text("error.operationActive")) }
        try clearLogs()
        neoSpring.dismissNotice(); neoSpring.disableAutomatic(); vpn.resetStatus(); preferences.withdrawConsent()
        status = L10n.text("status.consentWithdrawn")
    }
    private func work<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in queue.async { do { cont.resume(returning: try operation()) } catch { cont.resume(throwing: error) } } }
    }
    private func begin(_ message: String, requiresConsent: Bool = true, requiresPairing: Bool = false) -> CancellationToken? {
        guard !busy else { return nil }
        guard !requiresConsent || preferences.hasConsent else {
            error = L10n.text("error.consentRequired"); return nil
        }
        guard !requiresPairing || preferences.hasPairingConsent else {
            error = L10n.text("error.pairingConsentRequired"); return nil
        }
        busy = true; status = message; error = nil; plan = nil
        let token = CancellationToken(); cancellation = token; log(message); return token
    }
    private func finish(_ message: String) { status = message; busy = false; cancellation = nil; reload(); log(message) }
    private func fail(_ error: Error) {
        self.error = error is CancellationError ? L10n.text("status.operationCancelled") : error.localizedDescription
        status = self.error!; busy = false; cancellation = nil; reload(); log(status)
    }
    func cancel() {
        if neoSpring.request != nil { neoSpring.cancel(); return }
        cancellation?.cancel(); query.cancel(); airlift.cancel(); status = L10n.text("status.cancelling")
    }
    func importWallpaper(_ url: URL) {
        guard let token = begin(L10n.text("status.importing")) else { return }
        let repository = repository
        Task {
            do { let pack = try await work { try repository.importPack(url, token: token) }; selected.insert(pack.id); finish(L10n.text("status.imported", [String(describing: pack.name)])) }
            catch { fail(error) }
        }
    }
    func deleteWallpaper(_ pack: WallpaperPack) {
        guard !busy, packs.contains(where: { $0.id == pack.id }),
              let token = begin(L10n.text("status.deletingPack"), requiresConsent: false) else { return }
        let repository = repository
        Task {
            do {
                try await work { try token.check(); try repository.remove(pack) }
                selected.remove(pack.id)
                finish(L10n.text("status.packDeleted"))
            } catch { fail(error) }
        }
    }
    func discover() {
        guard let token = begin(L10n.text("status.queryingPath"), requiresPairing: true) else { return }
        let query = query; let host = host; let allowFallbacks = vpn.allowsFallbacks
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work {
                        let path = try query.find(host: host, allowFallbacks: allowFallbacks, token: token); try token.check()
                        if engine == .airlift { return try AirliftInjectionService.locatedContainer(path) }
                        if engine == .pocketTrash { return try PocketTarget.container(path, authoritative: true) }
                        return try ContainerInspector().inspect(path: path, authoritative: true, engine: engine)
                    }
                    container = result; manualPath = result.path
                    UserDefaults.standard.set(host, forKey: "gateway"); UserDefaults.standard.set(result.path, forKey: "containerPath")
                    result.diagnostics.forEach(log)
                    finish(L10n.text(engine == .pocketTrash ? "pocket.pathOnly" : engine == .airlift ? "airlift.pathOnly" : "status.pathVerified"))
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func validateManual() {
        guard let token = begin(L10n.text("status.checkingManualPath"), requiresPairing: selectedEngine == .airlift) else { return }
        let path = manualPath; let query = query; let host = host; let allowFallbacks = vpn.allowsFallbacks
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work {
                        try token.check()
                        if engine == .pocketTrash { return try PocketTarget.container(path) }
                        if engine == .airlift {
                            let expected = try ContainerPath.normalize(path)
                            guard try query.find(host: host, allowFallbacks: allowFallbacks, token: token) == expected else {
                                throw BridgeError.message(L10n.text("error.containerChanged"))
                            }
                            return try AirliftInjectionService.locatedContainer(expected)
                        }
                        return try ContainerInspector().inspect(path: path, authoritative: false, engine: engine)
                    }
                    container = result; UserDefaults.standard.set(result.path, forKey: "containerPath")
                    result.diagnostics.forEach(log); finish(L10n.text(engine == .pocketTrash ? "pocket.pathOnly" : engine == .airlift ? "airlift.pathOnly" : "status.manualPathVerified"))
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func preview() {
        guard let token = begin(L10n.text("status.preparingPlan"), requiresPairing: selectedEngine.requiresPairing) else { return }
        let chosen = packs.filter { selected.contains($0.id) }; let query = query; let host = host; let allowFallbacks = vpn.allowsFallbacks; let injector = injector; let airlift = airlift; let pocket = pocket; let manual = manualPath
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work {
                        if engine == .pocketTrash {
                            return try pocket.plan(packs: chosen, container: PocketTarget.container(manual), token: token)
                        }
                        let path = try query.find(host: host, allowFallbacks: allowFallbacks, token: token); try token.check()
                        if engine == .airlift {
                            return try airlift.plan(packs: chosen, container: AirliftInjectionService.locatedContainer(path), token: token)
                        }
                        let live = try ContainerInspector().inspect(path: path, authoritative: true, engine: engine)
                        return try injector.plan(packs: chosen, container: live, engine: engine, token: token)
                    }
                    container = result.container; finish(L10n.text("status.planReady"))
                    plan = result
                } catch { fail(error) }
            }
        } catch { fail(error) }
    }
    func install(_ confirmed: InjectionPlan) {
        guard let token = begin(L10n.text("status.injecting"), requiresPairing: confirmed.engine.requiresPairing) else { return }
        do {
            guard confirmed.engine == (try engine()) else { throw BridgeError.message(L10n.text("error.enginePlanChanged")) }
            if confirmed.engine == .pocketTrash, try PocketTarget.normalize(manualPath) != confirmed.container.path {
                throw BridgeError.message(L10n.text("error.containerChanged"))
            }
        } catch { fail(error); return }
        let packs = packs; let query = query; let host = host; let allowFallbacks = vpn.allowsFallbacks; let injector = injector; let airlift = airlift; let pocket = pocket
        let automaticNeoSpring = neoSpring.automatic
        Task {
            do {
                try await work {
                    if confirmed.engine.requiresPairing {
                        guard try query.find(host: host, allowFallbacks: allowFallbacks, token: token) == confirmed.container.path else { throw BridgeError.message(L10n.text("error.containerChanged")) }
                    }
                    try token.check()
                    let progress: (String) -> Void = { message in DispatchQueue.main.async { self.status = message } }
                    if confirmed.engine == .pocketTrash {
                        try pocket.inject(confirmed, packs: packs, token: token, progress: progress)
                    } else if confirmed.engine == .airlift {
                        try airlift.inject(confirmed, packs: packs, host: host, allowFallbacks: allowFallbacks, token: token, progress: progress)
                    } else { try injector.inject(confirmed, packs: packs, token: token, progress: progress) }
                }
                try token.check()
                finish(L10n.text(confirmed.engine == .pocketTrash ? "pocket.sent" : confirmed.engine == .airlift ? "airlift.sent" : "status.injectionComplete"))
                if automaticNeoSpring && !confirmed.engine.isWriteOnly { runNeoSpring(afterInjection: true) }
            } catch { fail(error) }
        }
    }
    func runNeoSpring(afterInjection: Bool = false) {
        guard begin(L10n.text("status.neoSpring")) != nil else { return }
        let failurePrefix = afterInjection ? L10n.text("error.neoSpringAfterInjection") : L10n.text("error.neoSpringIncomplete")
        do {
            try neoSpring.start { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .ended, .interrupted:
                    self.finish(L10n.text("status.neoSpringEnded"))
                case .cancelled:
                    self.finish(L10n.text("status.neoSpringCancelled"))
                case .timedOut:
                    self.fail(BridgeError.message(failurePrefix + L10n.text("error.timedOut")))
                case .failed(let message):
                    self.fail(BridgeError.message(failurePrefix + message))
                }
            }
        } catch { fail(BridgeError.message(failurePrefix + error.localizedDescription)) }
    }
    func requestNeoSpring() {
        guard !busy else { return }
        guard preferences.hasConsent else { error = L10n.text("error.consentRequired"); return }
        neoSpring.requestManualRefresh()
    }
    func updateReceipt(_ receipt: TransactionReceipt, rollback: Bool) {
        guard let token = begin(rollback ? L10n.text("status.checkingRollback") : L10n.text("status.refreshingRegistration"), requiresPairing: true) else { return }
        do {
            // Receipts retain their original engine; never bypass policy after an OS update.
            guard !receipt.engine.isWriteOnly else { throw BridgeError.message(L10n.text("error.airliftHistoryUnsupported")) }
            _ = try EnginePolicy.select(.current, build: SystemVersion.currentBuild, preferred: receipt.engine)
        } catch { fail(error); return }
        let query = query; let host = host; let allowFallbacks = vpn.allowsFallbacks; let injector = injector
        Task {
            do {
                try await work {
                    let path = try query.find(host: host, allowFallbacks: allowFallbacks, token: token); try token.check()
                    let live = try ContainerInspector().inspect(path: path, authoritative: true, engine: receipt.engine)
                    if rollback { try injector.rollback(receipt, live: live, token: token) { message in DispatchQueue.main.async { self.status = message } } }
                    else { try injector.refresh(receipt, live: live, token: token) }
                }
                finish(rollback ? L10n.text("status.rolledBack") : L10n.text("status.registrationRefreshed"))
            } catch { fail(error) }
        }
    }
    func configurePocketTarget() -> Bool {
        guard !busy, preferences.hasConsent, selectedEngine == .pocketTrash else { return false }
        do {
            _ = try EnginePolicy.select(.current, build: SystemVersion.currentBuild, preferred: .pocketTrash)
            let target = try PocketTarget.container(manualPath)
            container = target; manualPath = target.path; plan = nil
            UserDefaults.standard.set(target.path, forKey: "containerPath")
            status = L10n.text("pocket.pathOnly"); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func cleanupPocket(_ receipt: TransactionReceipt) {
        guard let _ = begin(L10n.text("pocket.cleaning"), requiresConsent: false) else { return }
        let pocket = pocket
        Task {
            do { _ = try await work { try pocket.cleanup(expected: receipt.id) }; finish(L10n.text("pocket.cleaned")) }
            catch { fail(error) }
        }
    }
    func recoverAirlift(_ receipt: TransactionReceipt) {
        guard let token = begin(L10n.text("airlift.recovering"), requiresPairing: true) else { return }
        let airlift = airlift; let host = host; let allowFallbacks = vpn.allowsFallbacks
        Task {
            do {
                try await work { try airlift.recover(receipt, host: host, allowFallbacks: allowFallbacks, token: token) }
                finish(L10n.text("airlift.recovered"))
            } catch { fail(error) }
        }
    }
    func acknowledgeAirliftRetry(_ receipt: TransactionReceipt) {
        guard !busy else { return }
        do {
            if receipt.engine == .pocketTrash { try pocket.acknowledgeRetry(receipt) }
            else { try airlift.acknowledgeRetry(receipt) }
            plan = nil; reload(); status = L10n.text("airlift.retryAllowed")
        }
        catch { self.error = error.localizedDescription }
    }
    func exportLogs() throws -> URL {
        let url = AppFiles.diagnosticExport
        let receiptText = receipts.map { "\($0.id): \($0.state), \($0.entries.count) targets, \($0.engine.rawValue)" }.joined(separator: "\n")
        let text = logs.joined(separator: "\n") + "\n\n" + receiptText
        try text.write(to: url, atomically: true, encoding: .utf8); return url
    }
}
