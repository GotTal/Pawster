import XCTest
import CryptoKit
@testable import Pawster

final class FileDigestTests: XCTestCase {
    private let fm = FileManager.default
    private func fixture() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func populate(_ source: URL) throws {
        try fm.createDirectory(at: source.appendingPathComponent("versions/1/contents/empty"), withIntermediateDirectories: true)
        try Data("asset".utf8).write(to: source.appendingPathComponent("versions/1/contents/main.caml"))
        try Data("hidden".utf8).write(to: source.appendingPathComponent(".DS_Store"))
        try Data("config".utf8).write(to: source.appendingPathComponent("versions/1/contents/.options.plist"))
    }
    func testCopiedHiddenStageAndRenamedTargetKeepTheSameDigest() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Source")
        let stage = root.appendingPathComponent(".posterbridge-" + UUID().uuidString)
        let target = root.appendingPathComponent(UUID().uuidString)
        try populate(source)
        let expected = try FileDigest.snapshot(source)
        XCTAssertEqual(expected.fileCount, 3)
        XCTAssertEqual(expected.byteCount, 17)
        XCTAssertTrue(expected.entries.contains { $0.path == ".DS_Store" })
        XCTAssertTrue(expected.entries.contains { $0.path == "versions/1/contents/.options.plist" })
        XCTAssertTrue(expected.entries.contains { $0.path == "versions/1/contents/empty" && $0.kind == "D" })
        try fm.copyItem(at: source, to: stage)
        XCTAssertEqual(try FileDigest.tree(stage), expected.digest)
        try fm.moveItem(at: stage, to: target)
        XCTAssertEqual(try FileDigest.tree(target), expected.digest)
    }
    func testAncestorAliasDoesNotChangeRelativePathsOrDigest() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Source")
        try populate(source)
        let alias = root.appendingPathComponent("different-length-alias")
        try fm.createSymbolicLink(atPath: alias.path, withDestinationPath: root.path)
        let throughAlias = alias.appendingPathComponent("Source")
        XCTAssertEqual(try FileDigest.snapshot(throughAlias).entries, try FileDigest.snapshot(source).entries)
        XCTAssertEqual(try FileDigest.tree(throughAlias), try FileDigest.tree(source))
        // A linked descriptor itself is still refused; only an ancestor alias may vary.
        XCTAssertThrowsError(try FileDigest.tree(alias))
    }
    func testMissingExtraSizeAndSameSizeCorruptionHaveSpecificDiagnostics() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Source"); try populate(source)
        let expected = try FileDigest.snapshot(source)
        let asset = source.appendingPathComponent("versions/1/contents/main.caml")
        try Data("ASSET".utf8).write(to: asset)
        let changed = try FileDigest.snapshot(source)
        XCTAssertNotEqual(changed.digest, expected.digest)
        XCTAssertTrue(expected.differences(from: changed).contains(L10n.text("digest.contentMismatch", ["versions/1/contents/main.caml"])))
        try Data("larger asset".utf8).write(to: asset)
        XCTAssertTrue(try expected.differences(from: FileDigest.snapshot(source)).contains(L10n.text("digest.sizeMismatch", ["versions/1/contents/main.caml", "5", "12"])))
        try fm.removeItem(at: asset)
        XCTAssertTrue(try expected.differences(from: FileDigest.snapshot(source)).contains(L10n.text("digest.missing", ["versions/1/contents/main.caml"])))
        try Data("new".utf8).write(to: source.appendingPathComponent("extra"))
        XCTAssertTrue(try expected.differences(from: FileDigest.snapshot(source)).contains(L10n.text("digest.extra", ["extra"])))
    }
    func testStoredDigestRowFormatIsPreserved() throws {
        let root = try fixture(); defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: false)
        try Data("original".utf8).write(to: root.appendingPathComponent("asset"))
        let sha = SHA256.hash(data: Data("original".utf8)).map { String(format: "%02x", $0) }.joined()
        let oldRows = [["F", "asset", sha], ["D", "empty", ""]]
        let oldDigest = SHA256.hash(data: try JSONSerialization.data(withJSONObject: oldRows)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try FileDigest.tree(root), oldDigest)
    }
}
