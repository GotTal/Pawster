import XCTest
@testable import Pawster

private final class LocalAccess: ScopedAccess {
    func withAccess<T>(_ path: String, engine: InjectionEngine, readOnly: Bool, operation: () throws -> T) throws -> T { try operation() }
}

final class TransactionTests: XCTestCase {
    struct Fixture {
        var root: URL; var source: URL; var live: VerifiedContainer; var pack: WallpaperPack; var service: InjectionService
    }
    private func fixture() throws -> Fixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let container = root.appendingPathComponent("Container"); let source = root.appendingPathComponent("Source")
        let parent = try ContainerPath.descriptorParent(version: "61", extensionID: ContainerPath.extensions[0])
        try fm.createDirectory(at: container.appendingPathComponent(parent), withIntermediateDirectories: true)
        try fm.createDirectory(at: container.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("7400.DYNAMIC".utf8).write(to: source.appendingPathComponent("descriptor.identifier"))
        let live = VerifiedContainer(path: container.path, source: "test", checkedAt: Date(), storeVersion: "61", extensionIDs: [ContainerPath.extensions[0]], diagnostics: [])
        let pack = WallpaperPack(id: UUID(), name: "Fixture", hash: "fixture-hash", directory: "fixture", descriptors: ["Contents/fixture"], bytes: 12)
        let service = InjectionService(access: LocalAccess(), transactionRoot: root.appendingPathComponent("Transactions"),
            inspector: { container, _ in container }, source: { _, _ in source })
        return Fixture(root: root, source: source, live: live, pack: pack, service: service)
    }
    func testInjectionAndRollbackPreserveUnrelatedWallpaper() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = URL(fileURLWithPath: f.live.path).appendingPathComponent(try ContainerPath.descriptorParent(version: "61", extensionID: f.live.extensionIDs[0])).appendingPathComponent("existing-wallpaper")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: original.appendingPathComponent("asset"))
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        try f.service.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in })
        let receipt = try XCTUnwrap(f.service.receipts().first)
        XCTAssertEqual(receipt.state, "filesVerified")
        XCTAssertEqual(receipt.wallpapers().first?.name, f.pack.name)
        let target = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].destinationRelative)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("descriptor.identifier")), Data("7400.DYNAMIC".utf8))
        try f.service.rollback(receipt, live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("asset")), Data("original".utf8))
        XCTAssertEqual(try f.service.receipts().first?.wallpapers().first?.name, f.pack.name)
    }
    func testExistingIdenticalTargetIsNeverDeletedOnRollback() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        let target = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].destinationRelative)
        try FileManager.default.copyItem(at: f.source, to: target)
        XCTAssertThrowsError(try f.service.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in }))
        try f.service.rollback(XCTUnwrap(f.service.receipts().first), live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testChangedInstalledContentBlocksDeletion() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        try f.service.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in })
        let target = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].destinationRelative)
        try Data("external change".utf8).write(to: target.appendingPathComponent("descriptor.identifier"))
        XCTAssertThrowsError(try f.service.rollback(XCTUnwrap(f.service.receipts().first), live: f.live, token: CancellationToken(), progress: { _ in }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testRefreshMergesAndRestoresExistingPreferences() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let prefs = URL(fileURLWithPath: f.live.path).appendingPathComponent("Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist")
        let before = try PropertyListSerialization.data(fromPropertyList: ["unrelated": "preserved", "PersistedPosterContainerBundleIdentifiers": ["existing.extension"]], format: .binary, options: 0)
        try before.write(to: prefs)
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        try f.service.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in })
        try f.service.refresh(XCTUnwrap(f.service.receipts().first), live: f.live, token: CancellationToken())
        let after = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: prefs), format: nil) as? [String: Any])
        XCTAssertEqual(after["unrelated"] as? String, "preserved")
        XCTAssertTrue((after["PersistedPosterContainerBundleIdentifiers"] as? [String])?.contains("existing.extension") == true)
        try f.service.rollback(XCTUnwrap(f.service.receipts().first), live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: prefs), before)
    }
    func testCancellationLeavesRecoverableJournal() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try f.service.inject(plan, packs: [f.pack], token: token, progress: { _ in }))
        let receipt = try XCTUnwrap(f.service.receipts().first)
        XCTAssertEqual(receipt.state, "partial")
        try f.service.rollback(receipt, live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertEqual(try f.service.receipts().first?.state, "rolledBack")
    }
    func testIncompleteCopyNeverCommitsTargetAndCanBeRolledBack() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let faulty = InjectionService(access: LocalAccess(), transactionRoot: f.root.appendingPathComponent("Transactions"),
            inspector: { container, _ in container }, source: { _, _ in f.source }, copier: { source, stage in
                try FileManager.default.copyItem(at: source, to: stage)
                try FileManager.default.removeItem(at: stage.appendingPathComponent("descriptor.identifier"))
            })
        let plan = try faulty.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        XCTAssertThrowsError(try faulty.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains(L10n.text("digest.missing", ["descriptor.identifier"])))
        }
        let receipt = try XCTUnwrap(faulty.receipts().first)
        XCTAssertEqual(receipt.state, "partial")
        XCTAssertEqual(receipt.entries.first?.state, "pending")
        XCTAssertTrue(receipt.failure?.contains("SHA-256") == true)
        let target = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].destinationRelative)
        let stage = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].stagingRelative)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.path))
        try faulty.rollback(receipt, live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertEqual(try faulty.receipts().first?.state, "rolledBack")
    }

    func testRollbackDoesNotRequireTheImportedSource() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let plan = try f.service.plan(packs: [f.pack], container: f.live, engine: .badQuery, token: CancellationToken())
        try f.service.inject(plan, packs: [f.pack], token: CancellationToken(), progress: { _ in })
        let receipt = try XCTUnwrap(f.service.receipts().first)
        try FileManager.default.removeItem(at: f.source)
        try f.service.rollback(receipt, live: f.live, token: CancellationToken(), progress: { _ in })
        XCTAssertEqual(try f.service.receipts().first?.state, "rolledBack")
        let target = URL(fileURLWithPath: f.live.path).appendingPathComponent(plan.items[0].destinationRelative)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

}
