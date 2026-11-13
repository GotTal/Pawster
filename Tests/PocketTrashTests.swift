import XCTest
import Darwin
@testable import Pawster

private final class FakePocketReceiver {
    var calls = 0
    var inspect: ((URL) throws -> Void)?
    let sink: URL
    init(_ sink: URL) { self.sink = sink }
    func move(_ source: URL) throws {
        calls += 1; try inspect?(source)
        try FileManager.default.moveItem(at: source, to: sink.appendingPathComponent(source.lastPathComponent))
    }
}

final class PocketTrashTests: XCTestCase {
    private struct Fixture {
        var root: URL; var documents: URL; var transactions: URL; var source: URL
        var receiver: FakePocketReceiver; var service: PocketTrashInjectionService
        var pack: WallpaperPack; var plan: InjectionPlan
        var marker: URL { root.appendingPathComponent("PocketTrashLink.json") }
        var receipts: [TransactionReceipt] { get throws { try InjectionService(transactionRoot: transactions).receipts() } }
    }
    private func fixture() throws -> Fixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), documents = root.appendingPathComponent("Documents")
        let transactions = root.appendingPathComponent("Transactions"), sink = root.appendingPathComponent("fake-target")
        for folder in [source, documents, sink] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        addTeardownBlock { try? fm.removeItem(at: root) }
        try Data("Synthetic wallpaper".utf8).write(to: source.appendingPathComponent(".asset"))
        let receiver = FakePocketReceiver(sink)
        let service = PocketTrashInjectionService(transactionRoot: transactions, documentsRoot: documents,
            source: { _, _ in source }, trash: receiver.move, policy: {})
        let pack = WallpaperPack(id: UUID(), name: "Synthetic", hash: "synthetic-pocket-pack", directory: "unused", descriptors: ["descriptor"], bytes: 19, preview: nil)
        let target = try PocketTarget.container(UUID().uuidString)
        let plan = try service.plan(packs: [pack], container: target, token: CancellationToken())
        return Fixture(root: root, documents: documents, transactions: transactions, source: source, receiver: receiver, service: service, pack: pack, plan: plan)
    }
    private func send(_ f: Fixture, token: CancellationToken = CancellationToken()) throws {
        try f.service.inject(f.plan, packs: [f.pack], token: token, progress: { _ in })
    }
    private func seedInterruptedOperation(_ f: Fixture) throws -> URL {
        let name = URL(fileURLWithPath: f.plan.items[0].destinationRelative).lastPathComponent
        let stage = f.documents.appendingPathComponent(name)
        try FileManager.default.copyItem(at: f.source, to: stage)
        var info = stat(); XCTAssertEqual(Darwin.lstat(stage.path, &info), 0)
        let receipt = TransactionReceipt(id: f.plan.id, createdAt: Date(), engine: .pocketTrash, container: f.plan.container.path,
            packHashes: f.plan.packHashes, entries: f.plan.items.map { ReceiptEntry(item: $0, state: "pocketSending") }, state: "pocketSending")
        let directory = f.transactions.appendingPathComponent(receipt.id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AppFiles.write(receipt, to: directory.appendingPathComponent("receipt.json"))
        let target = receipt.container + "/" + PocketTarget.parent
        try FileManager.default.createSymbolicLink(atPath: f.documents.appendingPathComponent(".Trash").path, withDestinationPath: target)
        let record: [String: Any] = ["receipt": receipt.id.uuidString, "target": target,
            "stages": [["name": name, "inode": UInt64(info.st_ino), "device": Int64(info.st_dev)]]]
        try JSONSerialization.data(withJSONObject: record).write(to: f.marker)
        return stage
    }
    func testUUIDPathAndBoundedTextImportDoNotChangeTheSourceFile() throws {
        let id = UUID().uuidString
        XCTAssertEqual(try PocketTarget.normalize(" \(id.lowercased())\n"), ContainerPath.base + "/" + id)
        XCTAssertEqual(try PocketTarget.normalize("/private" + ContainerPath.base + "/" + id + "/"), ContainerPath.base + "/" + id)
        for bad in ["", "not-a-uuid", ContainerPath.base + "/" + id + "/Library", "/tmp/" + id, "../" + id] {
            XCTAssertThrowsError(try PocketTarget.normalize(bad))
        }
        let f = try fixture(), file = f.root.appendingPathComponent("NuggetPosterBoardHash")
        let bytes = Data((id + "\n").utf8); try bytes.write(to: file)
        XCTAssertEqual(try PocketTarget.read(file), ContainerPath.base + "/" + id)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        try Data(repeating: 65, count: 4097).write(to: file)
        XCTAssertThrowsError(try PocketTarget.read(file))
    }
    func testLocalHashVerificationAndJournalPrecedeUnverifiedSubmission() throws {
        let f = try fixture()
        f.receiver.inspect = { stage in
            let receipt = try XCTUnwrap(f.receipts.first)
            XCTAssertEqual(receipt.state, "pocketSending")
            XCTAssertEqual(receipt.entries.first?.state, "pocketSending")
            XCTAssertEqual(try FileDigest.tree(stage), f.plan.items[0].expectedTreeHash)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.documents.appendingPathComponent(".Trash").path), f.plan.container.path + "/" + PocketTarget.parent)
        }
        defer { f.receiver.inspect = nil }
        try send(f)
        let receipt = try XCTUnwrap(f.receipts.first)
        XCTAssertEqual(receipt.state, "pocketSent"); XCTAssertEqual(receipt.pocketCleanupCompleted, true)
        XCTAssertNil(receipt.refresh); XCTAssertEqual(f.receiver.calls, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: f.documents.appendingPathComponent(".Trash").path))
        XCTAssertEqual(try FileDigest.tree(f.source), f.plan.items[0].expectedTreeHash)
    }
    func testExistingTrashDirectoryAndItsContentsAreNeverRemoved() throws {
        let f = try fixture(), trash = f.documents.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let file = trash.appendingPathComponent("precious.txt"), bytes = Data("Keep this".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try send(f)); XCTAssertEqual(f.receiver.calls, 0)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
    }
    func testForeignSymlinkIsNotReplacedOrDeleted() throws {
        let f = try fixture(), link = f.documents.appendingPathComponent(".Trash")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.receiver.sink)
        XCTAssertThrowsError(try send(f)); XCTAssertEqual(f.receiver.calls, 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), f.receiver.sink.path)
    }
    func testAStageNameCollisionDoesNotDeleteExistingLocalData() throws {
        let f = try fixture()
        let name = URL(fileURLWithPath: f.plan.items[0].destinationRelative).lastPathComponent
        let existing = f.documents.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let file = existing.appendingPathComponent("keep.txt"), bytes = Data("Existing local directory".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try send(f))
        XCTAssertEqual(f.receiver.calls, 0)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try f.receipts.first?.state, "pocketPartial")
    }
    func testFailurePreservesReceiptAndCleansOnlyItsLocalCopies() throws {
        let f = try fixture()
        f.receiver.inspect = { _ in throw BridgeError.message("Synthetic provider failure") }
        XCTAssertThrowsError(try send(f))
        let receipt = try XCTUnwrap(f.receipts.first)
        XCTAssertEqual(receipt.state, "pocketPartial"); XCTAssertNotNil(receipt.failure)
        XCTAssertEqual(receipt.pocketCleanupCompleted, true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.documents.path).isEmpty)
        XCTAssertEqual(try FileDigest.tree(f.source), f.plan.items[0].expectedTreeHash)
    }
    func testInterruptedCleanupWorksWithoutPairingAndDoesNotClaimInstallation() throws {
        let f = try fixture(); let stage = try seedInterruptedOperation(f)
        XCTAssertEqual(try f.service.cleanup(expected: f.plan.id), f.plan.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
        XCTAssertEqual(try f.receipts.first?.pocketCleanupCompleted, true)
        XCTAssertEqual(try f.receipts.first?.state, "pocketSending")
        XCTAssertEqual(f.receiver.calls, 0)
    }
    func testCleanupRefusesAReplacedStageInode() throws {
        let f = try fixture(), stage = try seedInterruptedOperation(f)
        try FileManager.default.moveItem(at: stage, to: f.root.appendingPathComponent("old-stage"))
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let bytes = Data("Foreign replacement".utf8), file = stage.appendingPathComponent("keep.txt")
        try bytes.write(to: file)
        XCTAssertThrowsError(try f.service.cleanup(expected: f.plan.id))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.marker.path))
    }
    func testCancellationAndUnsafeTargetCannotReachTrashService() throws {
        var f = try fixture(); let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try send(f, token: token)); XCTAssertEqual(f.receiver.calls, 0)
        f.plan.items[0].destinationRelative = "Library/Preferences/com.apple.PosterBoard.plist"
        XCTAssertThrowsError(try send(f)); XCTAssertEqual(f.receiver.calls, 0)
        XCTAssertTrue(try f.receipts.isEmpty)
    }
    func testRetryRequiresExplicitAcknowledgementAndRetainsOriginalRecord() throws {
        let f = try fixture(); try send(f)
        XCTAssertThrowsError(try f.service.plan(packs: [f.pack], container: f.plan.container, token: CancellationToken()))
        let receipt = try XCTUnwrap(f.receipts.first)
        try f.service.acknowledgeRetry(receipt)
        let next = try f.service.plan(packs: [f.pack], container: f.plan.container, token: CancellationToken())
        XCTAssertNotEqual(next.id, f.plan.id); XCTAssertEqual(try f.receipts.first?.state, "pocketSent")
        XCTAssertEqual(f.receiver.calls, 1)
        let scoped = InjectionService(transactionRoot: f.transactions)
        XCTAssertThrowsError(try scoped.rollback(receipt, live: f.plan.container, token: CancellationToken(), progress: { _ in }))
        XCTAssertThrowsError(try scoped.refresh(receipt, live: f.plan.container, token: CancellationToken()))
    }
}
