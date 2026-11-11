import Foundation
import CryptoKit

final class InjectionService {
    private let fm = FileManager.default
    private let access: any ScopedAccess
    private let transactionRoot: URL
    private let inspect: (VerifiedContainer, InjectionEngine) throws -> VerifiedContainer
    private let sourceFor: (WallpaperPack, String) throws -> URL
    private let prefs = "Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"

    init(access: any ScopedAccess = AccessBroker.shared, transactionRoot: URL = AppFiles.transactions,
         inspector: @escaping (VerifiedContainer, InjectionEngine) throws -> VerifiedContainer = { container, engine in
             try ContainerInspector().inspect(path: container.path, authoritative: container.source == "InstallationProxy", engine: engine)
         }, source: @escaping (WallpaperPack, String) throws -> URL = { pack, descriptor in
             try WallpaperRepository().source(pack: pack, descriptor: descriptor)
         }) {
        self.access = access; self.transactionRoot = transactionRoot; self.inspect = inspector; self.sourceFor = source
    }

    func receipts() throws -> [TransactionReceipt] {
        try fm.createDirectory(at: transactionRoot, withIntermediateDirectories: true)
        return try fm.contentsOfDirectory(at: transactionRoot, includingPropertiesForKeys: nil).compactMap {
            guard UUID(uuidString: $0.lastPathComponent) != nil, let data = try? Data(contentsOf: $0.appendingPathComponent("receipt.json")) else { return nil }
            return try? JSONDecoder().decode(TransactionReceipt.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    private func directory(_ id: UUID) -> URL { transactionRoot.appendingPathComponent(id.uuidString) }
    private func save(_ receipt: TransactionReceipt) throws { try AppFiles.write(receipt, to: directory(receipt.id).appendingPathComponent("receipt.json")) }
    private func assertContained(_ target: URL, in container: String) throws {
        let canonicalRoot = URL(fileURLWithPath: container).resolvingSymlinksInPath().path
        let canonicalParent = target.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard canonicalParent.hasPrefix(canonicalRoot + "/") else { throw BridgeError.message("目标父目录包含指向容器外的链接，已停止。") }
        if let attrs = try? fm.attributesOfItem(atPath: target.path), let type = attrs[.type] as? FileAttributeType, type == .typeSymbolicLink {
            throw BridgeError.message("目标是符号链接，已停止以保护其他文件。")
        }
    }
    private func fresh(_ container: VerifiedContainer, engine: InjectionEngine) throws -> VerifiedContainer {
        // Caller performs another InstallationProxy query immediately before reaching here.
        let result = try inspect(container, engine)
        guard result.path == container.path, result.storeVersion == container.storeVersion, result.extensionIDs == container.extensionIDs else { throw BridgeError.message("壁纸目录结构已改变，请重新生成计划。") }
        return result
    }
    func plan(packs: [WallpaperPack], container: VerifiedContainer, engine: InjectionEngine, token: CancellationToken) throws -> InjectionPlan {
        guard !packs.isEmpty else { throw BridgeError.message("请先选择壁纸。") }
        let live = try fresh(container, engine: engine)
        let prior = try receipts().filter { $0.state != "rolledBack" }
        guard !packs.contains(where: { pack in prior.contains { $0.container == live.path && $0.packHashes.contains(pack.hash) } }) else {
            throw BridgeError.message("所选包已有注入或未完成记录，请先检查历史记录并撤回后再试。")
        }
        let tx = UUID(); var items: [PlanItem] = []
        for pack in packs {
            for descriptor in pack.descriptors {
                try token.check()
                let hash = try FileDigest.tree(sourceFor(pack, descriptor))
                let destinationID = UUID()
                for ext in live.extensionIDs {
                    let parent = try ContainerPath.descriptorParent(version: live.storeVersion, extensionID: ext)
                    items.append(PlanItem(id: UUID(), packID: pack.id, sourceRelative: descriptor,
                        destinationRelative: "\(parent)/\(destinationID.uuidString)",
                        stagingRelative: "\(parent)/.posterbridge-\(tx.uuidString)-\(destinationID.uuidString)", expectedTreeHash: hash))
                }
            }
        }
        guard !items.isEmpty, items.count <= 30 else { throw BridgeError.message("本次描述文件目标数量应在 1–30 之间。") }
        return InjectionPlan(id: tx, createdAt: Date(), engine: engine, container: live, packHashes: packs.map(\.hash), items: items)
    }

    func inject(_ plan: InjectionPlan, packs: [WallpaperPack], token: CancellationToken, progress: (String) -> Void) throws {
        guard Date().timeIntervalSince(plan.createdAt) < 300 else { throw BridgeError.message("计划已过期，请重新预览。") }
        _ = try fresh(plan.container, engine: plan.engine)
        try fm.createDirectory(at: directory(plan.id), withIntermediateDirectories: false)
        var receipt = TransactionReceipt(id: plan.id, createdAt: Date(), engine: plan.engine, container: plan.container.path,
            packHashes: plan.packHashes, entries: plan.items.map { ReceiptEntry(item: $0, state: "planned") }, state: "writing")
        try save(receipt) // Persisted journal precedes all target mutations.
        do {
            for (index, item) in plan.items.enumerated() {
                try token.check()
                guard ContainerPath.isManagedDescriptor(item.destinationRelative), let pack = packs.first(where: { $0.id == item.packID }) else { throw BridgeError.message("注入计划损坏。") }
                let source = try sourceFor(pack, item.sourceRelative)
                guard try FileDigest.tree(source) == item.expectedTreeHash else { throw BridgeError.message("壁纸资源在预览后发生变化，请重新导入。") }
                let target = URL(fileURLWithPath: plan.container.path).appendingPathComponent(item.destinationRelative)
                let stage = URL(fileURLWithPath: plan.container.path).appendingPathComponent(item.stagingRelative)
                progress("正在写入并校验 \(index + 1)/\(plan.items.count)")
                try access.withAccess(target.deletingLastPathComponent().path, engine: plan.engine) {
                    try assertContained(target, in: plan.container.path)
                    try assertContained(stage, in: plan.container.path)
                    guard !fm.fileExists(atPath: target.path), !fm.fileExists(atPath: stage.path) else { throw BridgeError.message("目标已存在，已停止以保护已有壁纸。") }
                    receipt.entries[index].state = "pending"; try save(receipt)
                    try fm.copyItem(at: source, to: stage)
                    guard try FileDigest.tree(stage) == item.expectedTreeHash else { throw BridgeError.message("写入内容校验失败。") }
                    try token.check()
                    guard !fm.fileExists(atPath: target.path) else { throw BridgeError.message("写入期间出现同名目标，保留已有目录。") }
                    receipt.entries[index].state = "moving"; try save(receipt)
                    do { try fm.moveItem(at: stage, to: target) }
                    catch { receipt.entries[index].state = "pending"; throw error }
                    guard try FileDigest.tree(target) == item.expectedTreeHash else { throw BridgeError.message("最终目录校验失败。") }
                }
                receipt.entries[index].state = "written"; try save(receipt)
            }
            receipt.state = "filesVerified"; try save(receipt)
            progress("文件写入和校验完成；尚未确认系统壁纸界面可见。")
        } catch {
            receipt.state = "partial"; receipt.failure = error is CancellationError ? "已取消；请检查并撤回未完成内容。" : error.localizedDescription
            try save(receipt)
            throw error
        }
    }

    func rollback(_ original: TransactionReceipt, live: VerifiedContainer, token: CancellationToken, progress: (String) -> Void) throws {
        guard live.path == original.container else { throw BridgeError.message("当前容器与历史记录不同，拒绝撤回旧路径。") }
        _ = try fresh(live, engine: original.engine)
        var receipt = original
        if let refresh = receipt.refresh {
            let target = URL(fileURLWithPath: live.path).appendingPathComponent(prefs)
            try access.withAccess(target.deletingLastPathComponent().path, engine: original.engine) {
                try assertContained(target, in: live.path)
                let exists = fm.fileExists(atPath: target.path)
                let currentHash = exists ? try FileDigest.hash(target) : nil
                // A crash may happen before the preference write, or after a restore but before journaling it.
                if (refresh.existed && currentHash == refresh.beforeHash) || (!refresh.existed && !exists) { return }
                guard currentHash == refresh.afterHash else { throw BridgeError.message("刷新后的偏好文件已被其他操作修改，保留文件并停止自动撤回。") }
                if refresh.existed {
                    let backup = directory(receipt.id).appendingPathComponent("preferences.before.plist")
                    guard try FileDigest.hash(backup) == refresh.beforeHash else { throw BridgeError.message("偏好文件备份损坏。") }
                    try Data(contentsOf: backup).write(to: target, options: .atomic)
                } else { try fm.removeItem(at: target) }
            }
            receipt.refresh = nil; try save(receipt)
        }
        for index in receipt.entries.indices.reversed() {
            try token.check()
            if ["planned", "rolledBack"].contains(receipt.entries[index].state) { continue }
            let item = receipt.entries[index].item
            guard ContainerPath.isManagedDescriptor(item.destinationRelative) else { throw BridgeError.message("历史记录包含不允许删除的路径。") }
            let target = URL(fileURLWithPath: live.path).appendingPathComponent(item.destinationRelative)
            let parent = target.deletingLastPathComponent()
            let expectedStage = parent.appendingPathComponent(".posterbridge-\(receipt.id.uuidString)-\(target.lastPathComponent)")
            guard expectedStage.path == URL(fileURLWithPath: live.path).appendingPathComponent(item.stagingRelative).path else { throw BridgeError.message("历史记录的临时路径不匹配。") }
            progress("正在撤回 \(receipt.entries.count - index)/\(receipt.entries.count)")
            try access.withAccess(parent.path, engine: original.engine) {
                try assertContained(target, in: live.path)
                try assertContained(expectedStage, in: live.path)
                let ownsTarget = receipt.entries[index].state == "written" || (receipt.entries[index].state == "moving" && !fm.fileExists(atPath: expectedStage.path))
                if ownsTarget && fm.fileExists(atPath: target.path) {
                    guard try FileDigest.tree(target) == item.expectedTreeHash else { throw BridgeError.message("壁纸目录已被其他操作修改，保留目录并停止撤回。") }
                    try fm.removeItem(at: target)
                }
                // A crash/cancel during copy can leave an incomplete stage. It has a unique journal-owned name.
                if fm.fileExists(atPath: expectedStage.path) { try fm.removeItem(at: expectedStage) }
            }
            receipt.entries[index].state = "rolledBack"; try save(receipt)
        }
        receipt.state = "rolledBack"; try save(receipt)
    }

    func refresh(_ original: TransactionReceipt, live: VerifiedContainer, token: CancellationToken) throws {
        guard original.state == "filesVerified", original.container == live.path, original.refresh == nil else { throw BridgeError.message("仅可刷新尚未刷新过的完整注入记录。") }
        _ = try fresh(live, engine: original.engine); try token.check()
        var receipt = original
        let target = URL(fileURLWithPath: live.path).appendingPathComponent(prefs)
        try access.withAccess(target.deletingLastPathComponent().path, engine: original.engine) {
            try assertContained(target, in: live.path)
            let exists = fm.fileExists(atPath: target.path)
            var dict: [String: Any] = [:]; var beforeHash: String?
            if exists {
                let attrs = try fm.attributesOfItem(atPath: target.path)
                guard ((attrs[.size] as? NSNumber)?.uint64Value ?? .max) <= 1024 * 1024 else { throw BridgeError.message("偏好文件过大，停止刷新。") }
                let data = try Data(contentsOf: target)
                guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw BridgeError.message("偏好文件不是有效字典，保留原文件。") }
                dict = parsed; beforeHash = try FileDigest.hash(target)
                try data.write(to: directory(receipt.id).appendingPathComponent("preferences.before.plist"), options: .atomic)
            }
            if dict["PersistedPosterContainerBundleIdentifiers"] != nil && !(dict["PersistedPosterContainerBundleIdentifiers"] is [String]) {
                throw BridgeError.message("原注册列表类型异常，保留原偏好文件。")
            }
            var ids = Set(dict["PersistedPosterContainerBundleIdentifiers"] as? [String] ?? [])
            ids.formUnion(live.extensionIDs)
            ids.formUnion(live.knownExtensionIDs)
            dict["PersistedPosterContainerBundleIdentifiers"] = ids.sorted()
            dict["PBF_RESET_FILE_PROTECTIONS"] = true
            dict["PBF_LOCALE_DID_CHANGE"] = true
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
            let afterHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            receipt.refresh = RefreshRecord(existed: exists, beforeHash: beforeHash, afterHash: afterHash)
            try save(receipt)
            try token.check()
            try data.write(to: target, options: .atomic)
            guard try FileDigest.hash(target) == afterHash else { throw BridgeError.message("刷新偏好文件校验失败。") }
            receipt.refresh?.state = "written"; try save(receipt)
        }
    }
}
