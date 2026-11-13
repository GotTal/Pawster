import Foundation
import CryptoKit

final class InjectionService {
    private let fm = FileManager.default
    private let access: any ScopedAccess
    private let transactionRoot: URL
    private let inspect: (VerifiedContainer, InjectionEngine) throws -> VerifiedContainer
    private let sourceFor: (WallpaperPack, String) throws -> URL
    private let copyDescriptor: (URL, URL) throws -> Void
    private let prefs = "Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"

    init(access: any ScopedAccess = AccessBroker.shared, transactionRoot: URL = AppFiles.transactions,
         inspector: @escaping (VerifiedContainer, InjectionEngine) throws -> VerifiedContainer = { container, engine in
             try ContainerInspector().inspect(path: container.path, authoritative: container.source == "InstallationProxy", engine: engine)
         }, source: @escaping (WallpaperPack, String) throws -> URL = { pack, descriptor in
             try WallpaperRepository().source(pack: pack, descriptor: descriptor)
         }, copier: @escaping (URL, URL) throws -> Void = { source, target in
             try FileManager.default.copyItem(at: source, to: target)
         }) {
        self.access = access; self.transactionRoot = transactionRoot; self.inspect = inspector; self.sourceFor = source
        self.copyDescriptor = copier
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
        guard canonicalParent.hasPrefix(canonicalRoot + "/") else { throw BridgeError.message(L10n.text("error.parentLink")) }
        if let attrs = try? fm.attributesOfItem(atPath: target.path), let type = attrs[.type] as? FileAttributeType, type == .typeSymbolicLink {
            throw BridgeError.message(L10n.text("error.targetLink"))
        }
    }
    private func fresh(_ container: VerifiedContainer, engine: InjectionEngine) throws -> VerifiedContainer {
        // Caller performs another InstallationProxy query immediately before reaching here.
        let result = try inspect(container, engine)
        guard result.path == container.path, result.storeVersion == container.storeVersion, result.extensionIDs == container.extensionIDs else { throw BridgeError.message(L10n.text("error.storeChanged")) }
        return result
    }
    func plan(packs: [WallpaperPack], container: VerifiedContainer, engine: InjectionEngine, token: CancellationToken) throws -> InjectionPlan {
        guard !engine.isWriteOnly else { throw BridgeError.message(L10n.text("error.airliftScopedAccess")) }
        let live = try fresh(container, engine: engine)
        return try InjectionPlanner.make(packs: packs, container: live, engine: engine,
            receipts: receipts(), source: sourceFor, token: token)
    }

    func inject(_ plan: InjectionPlan, packs: [WallpaperPack], token: CancellationToken, progress: (String) -> Void) throws {
        guard !plan.engine.isWriteOnly else { throw BridgeError.message(L10n.text("error.airliftScopedAccess")) }
        guard Date().timeIntervalSince(plan.createdAt) < 300 else { throw BridgeError.message(L10n.text("error.planExpired")) }
        _ = try fresh(plan.container, engine: plan.engine)
        try fm.createDirectory(at: directory(plan.id), withIntermediateDirectories: false)
        var receipt = TransactionReceipt(id: plan.id, createdAt: Date(), engine: plan.engine, container: plan.container.path,
            packHashes: plan.packHashes, entries: plan.items.map { ReceiptEntry(item: $0, state: "planned") }, state: "writing")
        try save(receipt) // Persisted journal precedes all target mutations.
        do {
            for (index, item) in plan.items.enumerated() {
                try token.check()
                guard ContainerPath.isManagedDescriptor(item.destinationRelative), let pack = packs.first(where: { $0.id == item.packID }) else { throw BridgeError.message(L10n.text("error.planInvalid")) }
                let source = try sourceFor(pack, item.sourceRelative)
                let expected = try FileDigest.snapshot(source)
                guard expected.digest == item.expectedTreeHash else { throw BridgeError.message(L10n.text("error.sourceChanged")) }
                let target = URL(fileURLWithPath: plan.container.path).appendingPathComponent(item.destinationRelative)
                let stage = URL(fileURLWithPath: plan.container.path).appendingPathComponent(item.stagingRelative)
                progress(L10n.text("status.writingProgress", [String(describing: index + 1), String(describing: plan.items.count)]))
                try access.withAccess(target.deletingLastPathComponent().path, engine: plan.engine) {
                    try assertContained(target, in: plan.container.path)
                    try assertContained(stage, in: plan.container.path)
                    guard !fm.fileExists(atPath: target.path), !fm.fileExists(atPath: stage.path) else { throw BridgeError.message(L10n.text("error.targetExists")) }
                    receipt.entries[index].state = "pending"; try save(receipt)
                    try copyDescriptor(source, stage)
                    let copied = try FileDigest.snapshot(stage)
                    guard copied.digest == item.expectedTreeHash else {
                        throw BridgeError.message(L10n.text("error.stagedVerification") + expected.differences(from: copied))
                    }
                    try token.check()
                    guard !fm.fileExists(atPath: target.path) else { throw BridgeError.message(L10n.text("error.targetAppeared")) }
                    receipt.entries[index].state = "moving"; try save(receipt)
                    do { try fm.moveItem(at: stage, to: target) }
                    catch { receipt.entries[index].state = "pending"; throw error }
                    let installed = try FileDigest.snapshot(target)
                    guard installed.digest == item.expectedTreeHash else {
                        throw BridgeError.message(L10n.text("error.finalVerification") + expected.differences(from: installed))
                    }
                }
                receipt.entries[index].state = "written"; try save(receipt)
            }
            receipt.state = "filesVerified"; try save(receipt)
            progress(L10n.text("status.filesWritten"))
        } catch {
            receipt.state = "partial"; receipt.failure = error is CancellationError ? L10n.text("error.cancelledPartial") : error.localizedDescription
            try save(receipt)
            throw error
        }
    }

    func rollback(_ original: TransactionReceipt, live: VerifiedContainer, token: CancellationToken, progress: (String) -> Void) throws {
        guard !original.engine.isWriteOnly else { throw BridgeError.message(L10n.text("error.airliftHistoryUnsupported")) }
        guard live.path == original.container else { throw BridgeError.message(L10n.text("error.rollbackContainer")) }
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
                guard currentHash == refresh.afterHash else { throw BridgeError.message(L10n.text("error.preferencesModified")) }
                if refresh.existed {
                    let backup = directory(receipt.id).appendingPathComponent("preferences.before.plist")
                    guard try FileDigest.hash(backup) == refresh.beforeHash else { throw BridgeError.message(L10n.text("error.backupInvalid")) }
                    try Data(contentsOf: backup).write(to: target, options: .atomic)
                } else { try fm.removeItem(at: target) }
            }
            receipt.refresh = nil; try save(receipt)
        }
        for index in receipt.entries.indices.reversed() {
            try token.check()
            if ["planned", "rolledBack"].contains(receipt.entries[index].state) { continue }
            let item = receipt.entries[index].item
            guard ContainerPath.isManagedDescriptor(item.destinationRelative) else { throw BridgeError.message(L10n.text("error.receiptUnsafePath")) }
            let target = URL(fileURLWithPath: live.path).appendingPathComponent(item.destinationRelative)
            let parent = target.deletingLastPathComponent()
            let expectedStage = parent.appendingPathComponent(".posterbridge-\(receipt.id.uuidString)-\(target.lastPathComponent)")
            guard expectedStage.path == URL(fileURLWithPath: live.path).appendingPathComponent(item.stagingRelative).path else { throw BridgeError.message(L10n.text("error.receiptStageMismatch")) }
            progress(L10n.text("status.rollbackProgress", [String(describing: receipt.entries.count - index), String(describing: receipt.entries.count)]))
            try access.withAccess(parent.path, engine: original.engine) {
                try assertContained(target, in: live.path)
                try assertContained(expectedStage, in: live.path)
                let ownsTarget = receipt.entries[index].state == "written" || (receipt.entries[index].state == "moving" && !fm.fileExists(atPath: expectedStage.path))
                if ownsTarget && fm.fileExists(atPath: target.path) {
                    guard try FileDigest.tree(target) == item.expectedTreeHash else { throw BridgeError.message(L10n.text("error.wallpaperModified")) }
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
        guard !original.engine.isWriteOnly else { throw BridgeError.message(L10n.text("error.airliftHistoryUnsupported")) }
        guard original.state == "filesVerified", original.container == live.path, original.refresh == nil else { throw BridgeError.message(L10n.text("error.refreshIneligible")) }
        _ = try fresh(live, engine: original.engine); try token.check()
        var receipt = original
        let target = URL(fileURLWithPath: live.path).appendingPathComponent(prefs)
        try access.withAccess(target.deletingLastPathComponent().path, engine: original.engine) {
            try assertContained(target, in: live.path)
            let exists = fm.fileExists(atPath: target.path)
            var dict: [String: Any] = [:]; var beforeHash: String?
            if exists {
                let attrs = try fm.attributesOfItem(atPath: target.path)
                guard ((attrs[.size] as? NSNumber)?.uint64Value ?? .max) <= 1024 * 1024 else { throw BridgeError.message(L10n.text("error.preferencesLarge")) }
                let data = try Data(contentsOf: target)
                guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw BridgeError.message(L10n.text("error.preferencesInvalid")) }
                dict = parsed; beforeHash = try FileDigest.hash(target)
                try data.write(to: directory(receipt.id).appendingPathComponent("preferences.before.plist"), options: .atomic)
            }
            if dict["PersistedPosterContainerBundleIdentifiers"] != nil && !(dict["PersistedPosterContainerBundleIdentifiers"] is [String]) {
                throw BridgeError.message(L10n.text("error.registrationInvalid"))
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
            guard try FileDigest.hash(target) == afterHash else { throw BridgeError.message(L10n.text("error.refreshVerification")) }
            receipt.refresh?.state = "written"; try save(receipt)
        }
    }
}
