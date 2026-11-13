import XCTest
@testable import Pawster

private final class FakeAirlift: AirliftSending {
    var sends = 0
    var failureAt: Int?
    var beforeSend: (() throws -> Void)?
    var recoveries: [URL] = []
    func send(source: URL, container: String, descriptor: String, recovery: URL, host: String, allowFallbacks: Bool, token: CancellationToken) throws {
        sends += 1; try beforeSend?()
        if sends == failureAt { throw BridgeError.message("Synthetic transport failure") }
    }
    func recover(directory: URL, host: String, allowFallbacks: Bool, token: CancellationToken) throws { recoveries.append(directory) }
    func cancel() {}
}

final class AirliftTests: XCTestCase {
    private struct Fixture {
        var source: URL; var transactions: URL; var sender: FakeAirlift
        var service: AirliftInjectionService; var pack: WallpaperPack; var plan: InjectionPlan
        var receipts: [TransactionReceipt] { get throws { try InjectionService(transactionRoot: transactions).receipts() } }
    }
    private func fixture(descriptors: [String] = ["descriptor"]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), transactions = root.appendingPathComponent("Transactions")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data("Synthetic descriptor".utf8).write(to: source.appendingPathComponent(".asset"))
        let sender = FakeAirlift()
        let service = AirliftInjectionService(sender: sender, transactionRoot: transactions, source: { _, _ in source })
        let pack = WallpaperPack(id: UUID(), name: "Synthetic", hash: "synthetic-pack-hash", directory: "unused",
                                 descriptors: descriptors, bytes: 20, preview: nil)
        let live = try AirliftInjectionService.locatedContainer(ContainerPath.base + "/" + UUID().uuidString)
        let plan = try service.plan(packs: [pack], container: live, token: CancellationToken())
        return Fixture(source: source, transactions: transactions, sender: sender, service: service, pack: pack, plan: plan)
    }
    private func send(_ fixture: Fixture) throws {
        try fixture.service.inject(fixture.plan, packs: [fixture.pack], host: "10.7.0.1", allowFallbacks: false, token: CancellationToken(), progress: { _ in })
    }
    func testJournalPrecedesSendingAndSuccessIsNeverTargetVerified() throws {
        let f = try fixture()
        f.sender.beforeSend = {
            let receipt = try XCTUnwrap(f.receipts.first)
            XCTAssertEqual(receipt.state, "airliftSending")
            XCTAssertEqual(receipt.entries.first?.state, "airliftSending")
        }
        defer { f.sender.beforeSend = nil }
        try send(f)
        let receipt = try XCTUnwrap(f.receipts.first)
        XCTAssertEqual(receipt.engine, .airlift); XCTAssertEqual(receipt.state, "airliftSent")
        XCTAssertNil(receipt.refresh); XCTAssertEqual(receipt.airliftRecoveryCompleted, true)
        XCTAssertEqual(f.sender.sends, 1)
    }
    func testTransportFailurePreservesPartialAttemptAndRecoveryEvidence() throws {
        let f = try fixture(descriptors: ["one", "two"]); f.sender.failureAt = 2
        XCTAssertThrowsError(try send(f))
        let receipt = try XCTUnwrap(f.receipts.first)
        XCTAssertEqual(receipt.state, "airliftPartial")
        XCTAssertEqual(receipt.entries.map(\.state), ["airliftSent", "airliftSending"])
        XCTAssertNil(receipt.airliftRecoveryCompleted); XCTAssertNotNil(receipt.failure)
    }
    func testChangedSourceStopsBeforeTransport() throws {
        let f = try fixture(); try Data("Changed".utf8).write(to: f.source.appendingPathComponent(".asset"))
        XCTAssertThrowsError(try send(f)); XCTAssertEqual(f.sender.sends, 0)
        XCTAssertEqual(try f.receipts.first?.state, "airliftPartial")
    }
    func testUnsafeDestinationCannotReachTransport() throws {
        var f = try fixture(); f.plan.items[0].destinationRelative = "Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"
        XCTAssertThrowsError(try send(f)); XCTAssertEqual(f.sender.sends, 0)
        XCTAssertTrue(try f.receipts.isEmpty)
    }
    func testCancellationBeforeStartCreatesNoReceiptOrTransfer() throws {
        let f = try fixture(); let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try f.service.inject(f.plan, packs: [f.pack], host: "10.7.0.1", allowFallbacks: true, token: token, progress: { _ in }))
        XCTAssertEqual(f.sender.sends, 0); XCTAssertTrue(try f.receipts.isEmpty)
    }
    func testAirliftReceiptCannotUseScopedRollbackOrPreferenceRefresh() throws {
        let f = try fixture(); try send(f)
        let receipt = try XCTUnwrap(f.receipts.first), scoped = InjectionService(transactionRoot: f.transactions)
        XCTAssertThrowsError(try scoped.rollback(receipt, live: f.plan.container, token: CancellationToken(), progress: { _ in }))
        XCTAssertThrowsError(try scoped.refresh(receipt, live: f.plan.container, token: CancellationToken()))
        XCTAssertThrowsError(try scoped.inject(f.plan, packs: [f.pack], token: CancellationToken(), progress: { _ in }))
    }
    func testRecoveryOnlyUsesJournalOwnedDirectoriesAndDoesNotResend() throws {
        let f = try fixture(descriptors: ["one", "two"]); f.sender.failureAt = 1
        XCTAssertThrowsError(try send(f))
        let receipt = try XCTUnwrap(f.receipts.first)
        try f.service.recover(receipt, host: "10.7.0.1", allowFallbacks: false, token: CancellationToken())
        XCTAssertEqual(f.sender.sends, 1); XCTAssertEqual(f.sender.recoveries.count, 2)
        for (path, entry) in zip(f.sender.recoveries, receipt.entries) {
            XCTAssertEqual(path.path, f.transactions.appendingPathComponent(receipt.id.uuidString + "/airlift/" + entry.item.id.uuidString).path)
        }
        XCTAssertEqual(try f.receipts.first?.airliftRecoveryCompleted, true)
        XCTAssertEqual(try f.receipts.first?.state, "airliftPartial")
    }
    func testNewAttemptRequiresAcknowledgementAndKeepsOriginalReceipt() throws {
        let f = try fixture(); try send(f)
        XCTAssertThrowsError(try f.service.plan(packs: [f.pack], container: f.plan.container, token: CancellationToken()))
        let receipt = try XCTUnwrap(f.receipts.first)
        try f.service.acknowledgeRetry(receipt)
        let next = try f.service.plan(packs: [f.pack], container: f.plan.container, token: CancellationToken())
        XCTAssertNotEqual(next.id, f.plan.id)
        XCTAssertNotEqual(next.items[0].destinationRelative, f.plan.items[0].destinationRelative)
        XCTAssertEqual(try f.receipts.first?.state, "airliftSent")
        XCTAssertEqual(try f.receipts.first?.airliftRetryAcknowledged, true)
        XCTAssertEqual(f.sender.sends, 1)
    }
}
