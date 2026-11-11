import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var packs: [WallpaperPack] = []
    @Published var selected: Set<UUID> = []
    @Published var receipts: [TransactionReceipt] = []
    @Published var container: VerifiedContainer?
    @Published var manualPath = ""
    @Published var host = "10.7.0.1"
    @Published var confirmedBeta4 = false
    @Published var busy = false
    @Published var status = "先导入配对文件或完成本机配对，再连接 LocalDevVPN。"
    @Published var error: String?
    @Published var plan: InjectionPlan?
    @Published var logs: [String] = []
    private let queue = DispatchQueue(label: "Pawster.work", qos: .userInitiated)
    private let query = DeviceQuery()
    private var cancellation: CancellationToken?
    private let repository = WallpaperRepository()
    private let injector = InjectionService()
    var engineLabel: String { (try? engine().rawValue) ?? "尚未支持此系统" }
    func engine() throws -> InjectionEngine { try EnginePolicy.select(.current, confirmedBeta4: confirmedBeta4) }

    init() {
        host = UserDefaults.standard.string(forKey: "gateway") ?? "10.7.0.1"
        manualPath = UserDefaults.standard.string(forKey: "containerPath") ?? ""
        reload()
        log("Pawster 0.1.0 · " + ProcessInfo.processInfo.operatingSystemVersionString)
    }
    func reload() {
        do { packs = try repository.load(); receipts = try injector.receipts() } catch { self.error = error.localizedDescription }
    }
    private func log(_ message: String) {
        // Never pass pairing file contents, PINs, certificates or host private keys here.
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)"); if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
    private func work<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in queue.async { do { cont.resume(returning: try operation()) } catch { cont.resume(throwing: error) } } }
    }
    private func begin(_ message: String) -> CancellationToken? {
        guard !busy else { return nil }
        busy = true; status = message; error = nil; plan = nil
        let token = CancellationToken(); cancellation = token; log(message); return token
    }
    private func finish(_ message: String) { status = message; busy = false; cancellation = nil; reload(); log(message) }
    private func fail(_ error: Error) {
        self.error = error is CancellationError ? "操作已取消。若已开始写入，请检查历史记录。" : error.localizedDescription
        status = self.error!; busy = false; cancellation = nil; reload(); log(status)
    }
    func cancel() { cancellation?.cancel(); query.cancel(); status = "正在安全结束当前步骤…" }
    func importWallpaper(_ url: URL) {
        guard let token = begin("正在检查并导入壁纸包…") else { return }
        let repository = repository
        Task {
            do { let pack = try await work { try repository.importPack(url, token: token) }; selected.insert(pack.id); finish("已导入 \(pack.name)，未修改系统壁纸。") }
            catch { fail(error) }
        }
    }
    func discover() {
        guard let token = begin("正在向系统查询 PosterBoard 路径…") else { return }
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
                    finish("路径已通过系统查询和只读检查；未修改壁纸。")
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func validateManual() {
        guard let token = begin("正在只读核验手动路径…") else { return }
        let path = manualPath
        do {
            let engine = try engine()
            Task {
                do {
                    let result = try await work { try token.check(); return try ContainerInspector().inspect(path: path, authoritative: false, engine: engine) }
                    container = result; UserDefaults.standard.set(result.path, forKey: "containerPath")
                    result.diagnostics.forEach(log); finish("手动路径身份核验通过；注入前仍会重新查询系统。")
                } catch { container = nil; fail(error) }
            }
        } catch { fail(error) }
    }
    func preview() {
        guard let token = begin("正在复核路径并生成注入计划…") else { return }
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
                    container = result.container; finish("注入计划已就绪，请检查目标和数量。")
                    plan = result
                } catch { fail(error) }
            }
        } catch { fail(error) }
    }
    func install(_ confirmed: InjectionPlan) {
        guard let token = begin("正在复核并开始注入…") else { return }
        let packs = packs; let query = query; let host = host; let injector = injector
        Task {
            do {
                try await work {
                    guard try query.find(host: host, token: token) == confirmed.container.path else { throw BridgeError.message("系统返回的容器路径已变化，请重新预览。") }
                    try token.check()
                    try injector.inject(confirmed, packs: packs, token: token) { message in DispatchQueue.main.async { self.status = message } }
                }
                finish("文件已写入并校验。请按需刷新注册，再到系统壁纸界面检查实际效果。")
            } catch { fail(error) }
        }
    }
    func updateReceipt(_ receipt: TransactionReceipt, rollback: Bool) {
        guard let token = begin(rollback ? "正在核验撤回条件…" : "正在备份并准备刷新注册…") else { return }
        let query = query; let host = host; let injector = injector
        Task {
            do {
                try await work {
                    let path = try query.find(host: host, token: token); try token.check()
                    let live = try ContainerInspector().inspect(path: path, authoritative: true, engine: receipt.engine)
                    if rollback { try injector.rollback(receipt, live: live, token: token) { message in DispatchQueue.main.async { self.status = message } } }
                    else { try injector.refresh(receipt, live: live, token: token) }
                }
                finish(rollback ? "本次注入内容已撤回。" : "注册偏好已备份、合并并校验；请关闭并重新打开系统壁纸界面检查。")
            } catch { fail(error) }
        }
    }
    func exportLogs() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pawster-Diagnostics.txt")
        let receiptText = receipts.map { "\($0.id): \($0.state), \($0.entries.count) targets, \($0.engine.rawValue)" }.joined(separator: "\n")
        let text = logs.joined(separator: "\n") + "\n\n" + receiptText
        try text.write(to: url, atomically: true, encoding: .utf8); return url
    }
}
