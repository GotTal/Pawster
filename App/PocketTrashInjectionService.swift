// SPDX-License-Identifier: GPL-3.0-only
// Adapted from leminlimez/Pocket-Poster fb07aa45586ea4d2590c6f6d258777b207e1b8c9:
// SymHandler.swift / PosterBoardManager.swift, created by lemin in 2025.
// Original exploit credited upstream to Nathan and DuyKhanhTran.
// See ThirdParty/Pocket-Poster-GPL-3.0.txt and ThirdParty/SOURCES.md.
import Foundation
import Darwin

enum PocketTarget {
    static let parent = ContainerPath.store + "/61/Extensions/" + ContainerPath.extensions[0] + "/descriptors"
    static func normalize(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: value) { return ContainerPath.base + "/" + id.uuidString }
        guard let path = try? ContainerPath.normalize(value) else { throw BridgeError.message(L10n.text("pocket.invalidTarget")) }
        guard let id = UUID(uuidString: URL(fileURLWithPath: path).lastPathComponent) else { throw BridgeError.message(L10n.text("pocket.invalidTarget")) }
        return ContainerPath.base + "/" + id.uuidString
    }
    static func container(_ input: String, authoritative: Bool = false) throws -> VerifiedContainer {
        VerifiedContainer(path: try normalize(input), source: authoritative ? "InstallationProxy/PocketTrash" : "Manual/PocketTrash",
            checkedAt: Date(), storeVersion: "61", extensionIDs: [ContainerPath.extensions[0]],
            identity: authoritative ? "com.apple.PosterBoard" : nil, diagnostics: [L10n.text("pocket.pathOnly")])
    }
    static func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let bytes = try file.read(upToCount: 4097) ?? Data()
        guard bytes.count <= 4096, let value = String(data: bytes, encoding: .utf8) else {
            throw BridgeError.message(L10n.text("pocket.invalidTarget"))
        }
        return try normalize(value)
    }
}

final class PocketTrashInjectionService {
    private struct Stage: Codable { var name: String; var inode: UInt64; var device: Int64 }
    private struct LinkRecord: Codable { var receipt: UUID; var target: String; var stages: [Stage] }
    private static let lock = NSRecursiveLock()
    private let fm = FileManager.default
    private let root: URL
    private let documents: URL
    private let sourceFor: (WallpaperPack, String) throws -> URL
    private let sendToTrash: (URL) throws -> Void
    private let checkSystem: () throws -> Void
    private var marker: URL { root.deletingLastPathComponent().appendingPathComponent("PocketTrashLink.json") }
    private var link: URL { documents.appendingPathComponent(".Trash") }
    init(transactionRoot: URL = AppFiles.transactions,
         documentsRoot: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
         source: @escaping (WallpaperPack, String) throws -> URL = { try WallpaperRepository().source(pack: $0, descriptor: $1) },
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         policy: @escaping () throws -> Void = { _ = try EnginePolicy.select(.current, build: SystemVersion.currentBuild, preferred: .pocketTrash) }) {
        root = transactionRoot; documents = documentsRoot; sourceFor = source; sendToTrash = trash; checkSystem = policy
    }
    private func entry(_ url: URL) throws -> stat? {
        var value = stat()
        if Darwin.lstat(url.path, &value) == 0 { return value }
        let code = errno
        if code == ENOENT { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    private func isLink(_ info: stat) -> Bool { info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) }
    private func receiptURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathComponent("receipt.json") }
    private func save(_ receipt: TransactionReceipt) throws { try AppFiles.write(receipt, to: receiptURL(receipt.id)) }
    private func save(_ record: LinkRecord) throws { try AppFiles.write(record, to: marker) }
    private func removeOwnedLink(_ record: LinkRecord) throws {
        guard let info = try entry(link) else { return }
        guard isLink(info), try fm.destinationOfSymbolicLink(atPath: link.path) == record.target else {
            throw BridgeError.message(L10n.text("pocket.foreignTrash"))
        }
        // unlink removes only the link entry, never its destination or a replacement directory.
        guard Darwin.unlink(link.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    @discardableResult
    func cleanup(expected: UUID? = nil) throws -> UUID? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let markerInfo = try entry(marker) else {
            if let expected {
                guard case nil = try entry(link) else { throw BridgeError.message(L10n.text("pocket.foreignTrash")) }
                var receipt = try JSONDecoder().decode(TransactionReceipt.self, from: Data(contentsOf: receiptURL(expected)))
                guard receipt.id == expected, receipt.engine == .pocketTrash else { throw BridgeError.message(L10n.text("pocket.cleanupRecordInvalid")) }
                receipt.pocketCleanupCompleted = true; try save(receipt)
            }
            return nil
        }
        guard markerInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), markerInfo.st_size >= 0, markerInfo.st_size <= 64 * 1024,
              let record = try? JSONDecoder().decode(LinkRecord.self, from: Data(contentsOf: marker)),
              expected == nil || expected == record.receipt,
              let receipt = try? JSONDecoder().decode(TransactionReceipt.self, from: Data(contentsOf: receiptURL(record.receipt))),
              receipt.id == record.receipt, receipt.engine == .pocketTrash,
              !receipt.entries.isEmpty, receipt.entries.count <= 30,
              receipt.entries.allSatisfy({ ContainerPath.isManagedDescriptor($0.item.destinationRelative) &&
                  $0.item.destinationRelative.split(separator: "/").dropLast().joined(separator: "/") == PocketTarget.parent }),
              record.target == (try PocketTarget.normalize(receipt.container)) + "/" + PocketTarget.parent,
              record.stages.count <= 30 else { throw BridgeError.message(L10n.text("pocket.cleanupRecordInvalid")) }
        let names = Set(receipt.entries.map { URL(fileURLWithPath: $0.item.destinationRelative).lastPathComponent })
        guard record.stages.allSatisfy({ UUID(uuidString: $0.name) != nil && names.contains($0.name) }) else {
            throw BridgeError.message(L10n.text("pocket.cleanupRecordInvalid"))
        }
        try removeOwnedLink(record)
        for stage in record.stages {
            let url = documents.appendingPathComponent(stage.name)
            guard let info = try entry(url) else { continue }
            guard !isLink(info), info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  UInt64(info.st_ino) == stage.inode, Int64(info.st_dev) == stage.device else {
                throw BridgeError.message(L10n.text("pocket.stageChanged"))
            }
            try fm.removeItem(at: url) // Only the local, inode-matched copy; never a target path.
        }
        var updated = receipt; updated.pocketCleanupCompleted = true; try save(updated)
        try fm.removeItem(at: marker)
        return record.receipt
    }
    func plan(packs: [WallpaperPack], container: VerifiedContainer, token: CancellationToken) throws -> InjectionPlan {
        try InjectionPlanner.make(packs: packs, container: container, engine: .pocketTrash,
            receipts: InjectionService(transactionRoot: root).receipts(), source: sourceFor, token: token)
    }
    func inject(_ plan: InjectionPlan, packs: [WallpaperPack], token: CancellationToken, progress: (String) -> Void) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try checkSystem(); try token.check()
        guard plan.engine == .pocketTrash, plan.container.storeVersion == "61",
              plan.container.extensionIDs == [ContainerPath.extensions[0]],
              ["Manual/PocketTrash", "InstallationProxy/PocketTrash"].contains(plan.container.source),
              !plan.items.isEmpty, plan.items.count <= 30,
              Set(plan.items.map(\.destinationRelative)).count == plan.items.count,
              plan.items.allSatisfy({ ContainerPath.isManagedDescriptor($0.destinationRelative) &&
                  $0.destinationRelative.split(separator: "/").dropLast().joined(separator: "/") == PocketTarget.parent }) else {
            throw BridgeError.message(L10n.text("error.planInvalid"))
        }
        let container = try PocketTarget.normalize(plan.container.path)
        guard (0..<300).contains(Date().timeIntervalSince(plan.createdAt)) else { throw BridgeError.message(L10n.text("error.planExpired")) }
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        _ = try cleanup()
        guard case nil = try entry(link) else { throw BridgeError.message(L10n.text("pocket.foreignTrash")) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: receiptURL(plan.id).deletingLastPathComponent(), withIntermediateDirectories: false)
        var receipt = TransactionReceipt(id: plan.id, createdAt: Date(), engine: .pocketTrash, container: container,
            packHashes: plan.packHashes, entries: plan.items.map { ReceiptEntry(item: $0, state: "planned") }, state: "pocketSending")
        try save(receipt)
        var record = LinkRecord(receipt: receipt.id, target: container + "/" + PocketTarget.parent, stages: [])
        try save(record)
        do {
            for (index, item) in plan.items.enumerated() {
                try token.check()
                guard let pack = packs.first(where: { $0.id == item.packID }), plan.packHashes.contains(pack.hash),
                      pack.descriptors.contains(item.sourceRelative) else { throw BridgeError.message(L10n.text("error.planInvalid")) }
                let source = try sourceFor(pack, item.sourceRelative)
                guard try FileDigest.tree(source) == item.expectedTreeHash else { throw BridgeError.message(L10n.text("error.sourceChanged")) }
                let name = URL(fileURLWithPath: item.destinationRelative).lastPathComponent
                let stage = documents.appendingPathComponent(name, isDirectory: true)
                guard Darwin.mkdir(stage.path, mode_t(0o700)) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                guard let info = try entry(stage) else { throw BridgeError.message(L10n.text("pocket.stageChanged")) }
                record.stages.append(Stage(name: name, inode: UInt64(info.st_ino), device: Int64(info.st_dev)))
                try save(record) // Exclusive mkdir and recorded inode establish ownership before copy/cleanup.
                receipt.entries[index].state = "pocketCopying"; try save(receipt)
                for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    try token.check(); try fm.copyItem(at: child, to: stage.appendingPathComponent(child.lastPathComponent))
                }
                guard try FileDigest.tree(stage) == item.expectedTreeHash else { throw BridgeError.message(L10n.text("error.stagedVerification")) }
                try token.check()
                receipt.entries[index].state = "pocketSending"; try save(receipt)
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: record.target)
                // Keep the ambient .Trash redirection window short: only this call uses it.
                do {
                    try token.check()
                    progress(L10n.text("pocket.sendingProgress", [String(index + 1), String(plan.items.count)]))
                    try sendToTrash(stage)
                } catch {
                    try removeOwnedLink(record); throw error
                }
                try removeOwnedLink(record)
                guard case nil = try entry(stage) else { throw BridgeError.message(L10n.text("pocket.sourceNotMoved")) }
                receipt.entries[index].state = "pocketSent"; try save(receipt)
            }
            _ = try cleanup(expected: receipt.id)
            receipt.state = "pocketSent"; receipt.pocketCleanupCompleted = true; try save(receipt)
        } catch {
            let original = error
            receipt.state = "pocketPartial"; receipt.failure = original is CancellationError ? L10n.text("pocket.cancelled") : original.localizedDescription
            try save(receipt)
            do { _ = try cleanup(expected: receipt.id); receipt.pocketCleanupCompleted = true }
            catch { receipt.failure = (receipt.failure ?? "") + "\n" + error.localizedDescription }
            try save(receipt); throw BridgeError.message(receipt.failure ?? original.localizedDescription)
        }
    }
    func acknowledgeRetry(_ receipt: TransactionReceipt) throws {
        guard receipt.engine == .pocketTrash else { throw BridgeError.message(L10n.text("error.planInvalid")) }
        var updated = receipt; updated.pocketRetryAcknowledged = true; try save(updated)
    }
}
