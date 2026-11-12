import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    let preferences = AppPreferences()
    let neoSpring = NeoSpringController()
    @Published var packs: [WallpaperPack] = []
    @Published var selected: Set<UUID> = []
    @Published var receipts: [TransactionReceipt] = []
    @Published var container: VerifiedContainer?
    @Published var manualPath = ""
    @Published var host = "10.7.0.1"
    @Published var confirmedBeta4 = false
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
    var engineLabel: String { (try? engine().rawValue) ?? L10n.text("compatibility.unsupported") }
    func engine() throws -> InjectionEngine { try EnginePolicy.select(.current, confirmedBeta4: confirmedBeta4) }

    init() {
        host = UserDefaults.standard.string(forKey: "gateway") ?? "10.7.0.1"
        manualPath = UserDefaults.standard.string(forKey: "containerPath") ?? ""
        reload()
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
        neoSpring.automatic = false; preferences.withdrawConsent()
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
        cancellation?.cancel(); query.cancel(); status = L10n.text("status.cancelling")
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
        let query = query; let host = host
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work {
                        let path = try query.find(host: host, token: token); try token.check()
                        return try ContainerInspector().inspect(path: path, authoritative: true, engine: engine)
                    }
                    container = result; manualPath = result.path
                    UserDefaults.standard.set(host, forKey: "gateway"); UserDefaults.standard.set(result.path, forKey: "containerPath")
                    result.diagnostics.forEach(log)
                    finish(L10n.text("status.pathVerified"))
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func validateManual() {
        guard let token = begin(L10n.text("status.checkingManualPath")) else { return }
        let path = manualPath
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work { try token.check(); return try ContainerInspector().inspect(path: path, authoritative: false, engine: engine) }
                    container = result; UserDefaults.standard.set(result.path, forKey: "containerPath")
                    result.diagnostics.forEach(log); finish(L10n.text("status.manualPathVerified"))
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func preview() {
        guard let token = begin(L10n.text("status.preparingPlan"), requiresPairing: true) else { return }
        let chosen = packs.filter { selected.contains($0.id) }; let query = query; let host = host; let injector = injector
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work {
                        let path = try query.find(host: host, token: token); try token.check()
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
        guard let token = begin(L10n.text("status.injecting"), requiresPairing: true) else { return }
        let packs = packs; let query = query; let host = host; let injector = injector
        let automaticNeoSpring = neoSpring.automatic
        Task {
            do {
                try await work {
                    guard try query.find(host: host, token: token) == confirmed.container.path else { throw BridgeError.message(L10n.text("error.containerChanged")) }
                    try token.check()
                    try injector.inject(confirmed, packs: packs, token: token) { message in DispatchQueue.main.async { self.status = message } }
                }
                try token.check()
                finish(L10n.text("status.injectionComplete"))
                if automaticNeoSpring { runNeoSpring(afterInjection: true) }
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
    func updateReceipt(_ receipt: TransactionReceipt, rollback: Bool) {
        guard let token = begin(rollback ? L10n.text("status.checkingRollback") : L10n.text("status.refreshingRegistration"), requiresPairing: true) else { return }
        let query = query; let host = host; let injector = injector
        Task {
            do {
                try await work {
                    let path = try query.find(host: host, token: token); try token.check()
                    let live = try ContainerInspector().inspect(path: path, authoritative: true, engine: receipt.engine)
                    if rollback { try injector.rollback(receipt, live: live, token: token) { message in DispatchQueue.main.async { self.status = message } } }
                    else { try injector.refresh(receipt, live: live, token: token) }
                }
                finish(rollback ? L10n.text("status.rolledBack") : L10n.text("status.registrationRefreshed"))
            } catch { fail(error) }
        }
    }
    func exportLogs() throws -> URL {
        let url = AppFiles.diagnosticExport
        let receiptText = receipts.map { "\($0.id): \($0.state), \($0.entries.count) targets, \($0.engine.rawValue)" }.joined(separator: "\n")
        let text = logs.joined(separator: "\n") + "\n\n" + receiptText
        try text.write(to: url, atomically: true, encoding: .utf8); return url
    }
}
