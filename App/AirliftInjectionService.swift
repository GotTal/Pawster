import Foundation

protocol AirliftSending: AnyObject {
    func send(source: URL, container: String, descriptor: String, recovery: URL, host: String,
              allowFallbacks: Bool, token: CancellationToken) throws
    func recover(directory: URL, host: String, allowFallbacks: Bool, token: CancellationToken) throws
    func cancel()
}

final class AirliftTransport: AirliftSending, @unchecked Sendable {
    private let lock = NSLock()
    private var active: UInt64?
    func cancel() { lock.lock(); defer { lock.unlock() }; if let active { pb_operation_cancel(active) } }
    private func perform(token: CancellationToken, operation: (UInt64, inout UnsafeMutablePointer<CChar>?) -> Int32) throws {
        let id = pb_operation_new()
        lock.lock(); active = id; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock(); pb_operation_free(id) }
        try token.check()
        var failure: UnsafeMutablePointer<CChar>?
        let code = operation(id, &failure)
        defer { pb_string_free(failure) }
        guard code == 0 else {
            let detail = failure.map { String(cString: $0) } ?? L10n.text("error.noDiagnostics")
            if detail == "Cancelled" { throw CancellationError() }
            throw BridgeError.message(L10n.text("error.airliftOperation", [detail]))
        }
    }
    func send(source: URL, container: String, descriptor: String, recovery: URL, host: String,
              allowFallbacks: Bool, token: CancellationToken) throws {
        _ = try EnginePolicy.select(.current, build: SystemVersion.currentBuild, preferred: .airlift)
        try perform(token: token) { id, failure in
            pb_airlift_install(id, AppFiles.pairing.path, host, allowFallbacks ? 1 : 0,
                              container, descriptor, source.path, recovery.path, &failure)
        }
    }
    func recover(directory: URL, host: String, allowFallbacks: Bool, token: CancellationToken) throws {
        // This restores a local journal's Books sync state through AFC, without an exploit.
        // Keep recovery available after an OS update has disabled AirTraffic injection.
        try perform(token: token) { id, failure in
            pb_airlift_recover(id, AppFiles.pairing.path, host, allowFallbacks ? 1 : 0, directory.path, &failure)
        }
    }
}

final class AirliftInjectionService {
    private let sender: any AirliftSending
    private let root: URL
    private let sourceFor: (WallpaperPack, String) throws -> URL
    private let fm = FileManager.default
    init(sender: any AirliftSending = AirliftTransport(), transactionRoot: URL = AppFiles.transactions,
         source: @escaping (WallpaperPack, String) throws -> URL = { try WallpaperRepository().source(pack: $0, descriptor: $1) }) {
        self.sender = sender; root = transactionRoot; sourceFor = source
    }
    func cancel() { sender.cancel() }
    static func locatedContainer(_ path: String) throws -> VerifiedContainer {
        // InstallationProxy confirms identity/path only. Store 61 is an explicit upstream
        // target assumption on the allowed iOS 27 builds, not a filesystem inspection.
        VerifiedContainer(path: try ContainerPath.normalize(path), source: "InstallationProxy/Airlift", checkedAt: Date(),
            storeVersion: "61", extensionIDs: [ContainerPath.extensions[0]], identity: "com.apple.PosterBoard",
            diagnostics: [L10n.text("airlift.pathOnly")])
    }
    func plan(packs: [WallpaperPack], container: VerifiedContainer, token: CancellationToken) throws -> InjectionPlan {
        try InjectionPlanner.make(packs: packs, container: container, engine: .airlift,
            receipts: InjectionService(transactionRoot: root).receipts(), source: sourceFor, token: token)
    }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func recovery(_ receipt: UUID, _ entry: UUID) -> URL {
        directory(receipt).appendingPathComponent("airlift", isDirectory: true).appendingPathComponent(entry.uuidString, isDirectory: true)
    }
    private func save(_ receipt: TransactionReceipt) throws {
        try AppFiles.write(receipt, to: directory(receipt.id).appendingPathComponent("receipt.json"))
    }
    func inject(_ plan: InjectionPlan, packs: [WallpaperPack], host: String, allowFallbacks: Bool,
                token: CancellationToken, progress: (String) -> Void) throws {
        guard plan.engine == .airlift, plan.container.source == "InstallationProxy/Airlift",
              plan.container.storeVersion == "61", plan.container.extensionIDs == [ContainerPath.extensions[0]],
              !plan.items.isEmpty, plan.items.count <= 30 else { throw BridgeError.message(L10n.text("error.planInvalid")) }
        _ = try ContainerPath.normalize(plan.container.path)
        guard (0..<300).contains(Date().timeIntervalSince(plan.createdAt)) else { throw BridgeError.message(L10n.text("error.planExpired")) }
        let parent = try ContainerPath.descriptorParent(version: "61", extensionID: ContainerPath.extensions[0])
        guard plan.items.allSatisfy({ ContainerPath.isManagedDescriptor($0.destinationRelative) &&
            $0.destinationRelative.split(separator: "/").dropLast().joined(separator: "/") == parent }),
            Set(plan.items.map(\.destinationRelative)).count == plan.items.count else { throw BridgeError.message(L10n.text("error.planInvalid")) }
        try token.check()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: directory(plan.id), withIntermediateDirectories: false)
        var receipt = TransactionReceipt(id: plan.id, createdAt: Date(), engine: .airlift, container: plan.container.path,
            packHashes: plan.packHashes, entries: plan.items.map { ReceiptEntry(item: $0, state: "planned") }, state: "airliftSending")
        try save(receipt)
        do {
            for (index, item) in plan.items.enumerated() {
                try token.check()
                guard let pack = packs.first(where: { $0.id == item.packID }), plan.packHashes.contains(pack.hash),
                      pack.descriptors.contains(item.sourceRelative) else { throw BridgeError.message(L10n.text("error.planInvalid")) }
                let source = try sourceFor(pack, item.sourceRelative)
                guard try FileDigest.tree(source) == item.expectedTreeHash else { throw BridgeError.message(L10n.text("error.sourceChanged")) }
                receipt.entries[index].state = "airliftSending"; try save(receipt)
                progress(L10n.text("airlift.sendingProgress", [String(index + 1), String(plan.items.count)]))
                try sender.send(source: source, container: plan.container.path,
                    descriptor: URL(fileURLWithPath: item.destinationRelative).lastPathComponent,
                    recovery: recovery(plan.id, item.id), host: host, allowFallbacks: allowFallbacks, token: token)
                receipt.entries[index].state = "airliftSent"; try save(receipt)
            }
            receipt.state = "airliftSent"; receipt.airliftRecoveryCompleted = true; try save(receipt)
        } catch {
            receipt.state = "airliftPartial"
            receipt.failure = error is CancellationError ? L10n.text("airlift.cancelled") : error.localizedDescription
            try save(receipt); throw error
        }
    }
    func recover(_ receipt: TransactionReceipt, host: String, allowFallbacks: Bool, token: CancellationToken) throws {
        guard receipt.engine == .airlift else { throw BridgeError.message(L10n.text("error.planInvalid")) }
        for entry in receipt.entries {
            try token.check()
            try sender.recover(directory: recovery(receipt.id, entry.item.id), host: host, allowFallbacks: allowFallbacks, token: token)
        }
        var updated = receipt; updated.airliftRecoveryCompleted = true; try save(updated)
    }
    func acknowledgeRetry(_ receipt: TransactionReceipt) throws {
        guard receipt.engine == .airlift else { throw BridgeError.message(L10n.text("error.planInvalid")) }
        var updated = receipt; updated.airliftRetryAcknowledged = true; try save(updated)
    }
}
