import XCTest
@testable import Pawster

final class PolicyTests: XCTestCase {
    func testCanonicalContainerRoot() throws {
        let uuid = "E7A3AB7B-F016-4CD1-ACC7-16A6EDB58C2A"
        XCTAssertEqual(try ContainerPath.normalize(" /private\(ContainerPath.base)/\(uuid)/\n"), ContainerPath.base + "/" + uuid)
        for path in [ContainerPath.base, ContainerPath.base + "/not-a-uuid", ContainerPath.base + "/\(uuid)/Library", "/tmp/\(uuid)", ContainerPath.base + "/../Application/\(uuid)"] {
            XCTAssertThrowsError(try ContainerPath.normalize(path))
        }
    }
    func testStudyFriendsDescriptorIsNotSplitIntoVersionSubfolders() {
        let root = "descriptors/09E9B685-7456-4856-9C10-47DF26B76C33"
        XCTAssertEqual(DescriptorLocator.roots(in: [root + "/providerInfo.plist", root + "/com.apple.posterkit.provider.descriptor.identifier",
            root + "/versions/1/contents/7400.wallpaper/Wallpaper.plist"]), [root])
        XCTAssertEqual(DescriptorLocator.roots(in: ["providerInfo.plist", "versions/1/contents/a.wallpaper/Wallpaper.plist"]), [""])
    }
    func testEngineBoundariesDoNotAssumeFutureSupport() throws {
        XCTAssertEqual(try EnginePolicy.select(.init(major: 26, minor: 6, patch: 1)), .badQuery)
        XCTAssertThrowsError(try EnginePolicy.select(.init(major: 26, minor: 6, patch: 2)))
        XCTAssertEqual(try EnginePolicy.select(.init(major: 27, minor: 2, patch: 1)), .worseQuery)
        XCTAssertThrowsError(try EnginePolicy.select(.init(major: 27, minor: 3, patch: 0)))
        XCTAssertThrowsError(try EnginePolicy.select(.init(major: 27, minor: 0, patch: 0)))
        XCTAssertEqual(try EnginePolicy.select(.init(major: 27, minor: 0, patch: 0), confirmedBeta4: true), .badQuery)
    }
    func testRollbackOnlyAcceptsDescriptorTargets() throws {
        let base = try ContainerPath.descriptorParent(version: "61", extensionID: ContainerPath.extensions[0])
        XCTAssertTrue(ContainerPath.isManagedDescriptor(base + "/" + UUID().uuidString))
        XCTAssertFalse(ContainerPath.isManagedDescriptor(base))
        XCTAssertFalse(ContainerPath.isManagedDescriptor("Library/Preferences/com.apple.PosterBoard.plist"))
        XCTAssertFalse(ContainerPath.isManagedDescriptor(base + "/../../Library"))
        XCTAssertThrowsError(try ContainerPath.descriptorParent(version: "../61", extensionID: ContainerPath.extensions[0]))
    }
    func testTreeHashDetectsModificationAndRejectsLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("original".utf8).write(to: root.appendingPathComponent("Wallpaper.plist"))
        let original = try FileDigest.tree(root)
        try Data("changed".utf8).write(to: root.appendingPathComponent("Wallpaper.plist"))
        XCTAssertNotEqual(original, try FileDigest.tree(root))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: root.appendingPathComponent("Wallpaper.plist").path)
        XCTAssertThrowsError(try FileDigest.tree(root))
    }
}
