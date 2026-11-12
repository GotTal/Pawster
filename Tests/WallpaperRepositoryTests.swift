import XCTest
@testable import Pawster

final class WallpaperRepositoryTests: XCTestCase {
    private let fm = FileManager.default
    private func fixture() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("Packs"), withIntermediateDirectories: true)
        return root
    }
    private func pack(in root: URL) throws -> WallpaperPack {
        let id = UUID()
        let value = WallpaperPack(id: id, name: "Fixture", hash: "hash-" + id.uuidString,
            directory: id.uuidString, descriptors: ["Contents/fixture"], bytes: 5)
        let folder = root.appendingPathComponent("Packs").appendingPathComponent(value.directory)
        try fm.createDirectory(at: folder.appendingPathComponent("Contents/fixture"), withIntermediateDirectories: true)
        try Data("asset".utf8).write(to: folder.appendingPathComponent("Contents/fixture/asset"))
        try Data("archive".utf8).write(to: folder.appendingPathComponent("source.tendies"))
        try AppFiles.write(value, to: folder.appendingPathComponent("pack.json"))
        return value
    }
    func testRemovalOnlyDeletesTheImportedCopy() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let removed = try pack(in: root); let kept = try pack(in: root)
        let originals = ["Original.tendies", "InstalledWallpaper", "TransactionReceipt"]
        for name in originals { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        try WallpaperRepository().remove(removed, from: root.appendingPathComponent("Packs"))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Packs/" + removed.directory).path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Packs/" + kept.directory + "/Contents/fixture/asset")), Data("asset".utf8))
        for name in originals {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), Data(name.utf8))
        }
    }
    func testInvalidDirectoryCannotEscapeTheLibrary() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        var invalid = try pack(in: root)
        let outside = root.appendingPathComponent("outside")
        try Data("preserve".utf8).write(to: outside)
        invalid.directory = "../outside"
        XCTAssertThrowsError(try WallpaperRepository().remove(invalid, from: root.appendingPathComponent("Packs")))
        XCTAssertEqual(try Data(contentsOf: outside), Data("preserve".utf8))
    }
    func testLinkedPackDirectoryIsNotFollowed() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let value = try pack(in: root)
        let folder = root.appendingPathComponent("Packs/" + value.directory)
        let outside = root.appendingPathComponent("outside")
        try fm.moveItem(at: folder, to: outside)
        try fm.createSymbolicLink(atPath: folder.path, withDestinationPath: outside.path)
        XCTAssertThrowsError(try WallpaperRepository().remove(value, from: root.appendingPathComponent("Packs")))
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("Contents/fixture/asset")), Data("asset".utf8))
    }
    func testMismatchedIndexIsPreserved() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let value = try pack(in: root)
        var stale = value; stale.hash = "different-version"
        XCTAssertThrowsError(try WallpaperRepository().remove(stale, from: root.appendingPathComponent("Packs")))
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("Packs/" + value.directory + "/source.tendies").path))
    }
}
