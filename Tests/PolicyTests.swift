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
        let cases: [(SystemVersion, [InjectionEngine])] = [
            (.init(major: 25, minor: 9, patch: 9), []),
            (.init(major: 26, minor: 0, patch: 0), [.worseQuery, .badQuery, .pocketTrash]),
            (.init(major: 26, minor: 6, patch: 1), [.worseQuery, .badQuery]),
            (.init(major: 26, minor: 6, patch: 2), [.worseQuery]),
            (.init(major: 26, minor: 7, patch: 2), [.worseQuery]),
            (.init(major: 26, minor: 7, patch: 3), []),
            (.init(major: 26, minor: 8, patch: 0), []),
            (.init(major: 27, minor: 0, patch: 0), [.worseQuery, .airlift]),
            (.init(major: 27, minor: 0, patch: 1), [.worseQuery, .airlift]),
            (.init(major: 27, minor: 1, patch: 0), [.worseQuery]),
            (.init(major: 27, minor: 2, patch: 0), [.worseQuery]),
            (.init(major: 27, minor: 2, patch: 1), [.worseQuery]),
            (.init(major: 27, minor: 2, patch: 2), []),
            (.init(major: 27, minor: 3, patch: 0), []),
            (.init(major: 28, minor: 0, patch: 0), [])
        ]
        for (version, engines) in cases {
            XCTAssertEqual(EnginePolicy.available(for: version), engines, version.text)
            if engines.isEmpty { XCTAssertThrowsError(try EnginePolicy.select(version), version.text) }
            else { XCTAssertEqual(try EnginePolicy.select(version), .worseQuery, version.text) }
        }
    }
    func testManualSelectionOnlyAllowsCompatibleEnginesWithoutSilentFallback() throws {
        let overlap = SystemVersion(major: 26, minor: 6, patch: 1)
        XCTAssertEqual(try EnginePolicy.select(overlap, preferred: .badQuery), .badQuery)
        XCTAssertEqual(try EnginePolicy.select(overlap, preferred: .worseQuery), .worseQuery)
        for version in [SystemVersion(major: 26, minor: 6, patch: 2), .init(major: 27, minor: 0, patch: 1), .init(major: 27, minor: 2, patch: 0)] {
            XCTAssertThrowsError(try EnginePolicy.select(version, preferred: .badQuery))
        }
    }
    func testBadQueryBeta4RequiresExactBuildRatherThanUserConfirmation() throws {
        let version = SystemVersion(major: 27, minor: 0, patch: 0)
        XCTAssertEqual(EnginePolicy.available(for: version, build: "24A5390f"), [.worseQuery, .badQuery, .airlift])
        XCTAssertEqual(try EnginePolicy.select(version, build: "24A5390f"), .worseQuery)
        XCTAssertEqual(try EnginePolicy.select(version, build: "24A5390f", preferred: .badQuery), .badQuery)
        for build in ["", "24A5390g", "24A5380h", "24A437", "24A5390f "] {
            XCTAssertThrowsError(try EnginePolicy.select(version, build: build, preferred: .badQuery), build)
        }
        XCTAssertThrowsError(try EnginePolicy.select(.init(major: 27, minor: 0, patch: 1), build: "24A5390f", preferred: .badQuery))
    }
    func testWorseQuery273Beta1DoesNotEnableOther273Builds() throws {
        let version = SystemVersion(major: 27, minor: 3, patch: 0)
        XCTAssertEqual(try EnginePolicy.select(version, build: "24C5037i"), .worseQuery)
        for build in ["", "24C5037I", "24C5038i", "24C5037i "] {
            XCTAssertThrowsError(try EnginePolicy.select(version, build: build), build)
        }
        XCTAssertThrowsError(try EnginePolicy.select(.init(major: 27, minor: 3, patch: 1), build: "24C5037i"))
        XCTAssertThrowsError(try EnginePolicy.select(version, build: "24C5037i", preferred: .badQuery))
    }
    func testSettingsPairingAvailabilityIsIndependentOfWallpaperCompatibility() {
        XCTAssertFalse(PairingPolicy.supportsOnDevice(.init(major: 26, minor: 7, patch: 2)))
        XCTAssertTrue(PairingPolicy.supportsOnDevice(.init(major: 27, minor: 0, patch: 0)))
        let unknown = SystemVersion(major: 27, minor: 3, patch: 0)
        XCTAssertTrue(PairingPolicy.supportsOnDevice(unknown))
        XCTAssertTrue(EnginePolicy.available(for: unknown).isEmpty)
    }
    func testAirliftOnlyEnablesListedTendiesVersionsAndExact272Betas() throws {
        let version = SystemVersion(major: 27, minor: 2, patch: 0)
        for build in ["24B5084k", "24B5089g"] {
            XCTAssertEqual(EnginePolicy.available(for: version, build: build), [.worseQuery, .airlift])
            XCTAssertEqual(try EnginePolicy.select(version, build: build), .worseQuery)
            XCTAssertEqual(try EnginePolicy.select(version, build: build, preferred: .airlift), .airlift)
        }
        for build in ["", "24B5099f", "24B5089G", "24B119"] {
            XCTAssertThrowsError(try EnginePolicy.select(version, build: build, preferred: .airlift))
        }
        for version in [SystemVersion(major: 26, minor: 6, patch: 2), .init(major: 27, minor: 1, patch: 0), .init(major: 27, minor: 2, patch: 1), .init(major: 27, minor: 3, patch: 0)] {
            XCTAssertThrowsError(try EnginePolicy.select(version, build: "24B5089g", preferred: .airlift))
        }
    }
    func testPocketTrashExtendsOlderVersionsWithoutAssumingFuturePatchSupport() throws {
        for version in [SystemVersion(major: 17, minor: 0, patch: 0), .init(major: 17, minor: 7, patch: 2),
                        .init(major: 18, minor: 0, patch: 0), .init(major: 18, minor: 7, patch: 2)] {
            XCTAssertEqual(EnginePolicy.available(for: version), [.pocketTrash])
            XCTAssertEqual(try EnginePolicy.select(version), .pocketTrash)
        }
        for version in [SystemVersion(major: 16, minor: 7, patch: 0), .init(major: 18, minor: 7, patch: 3),
                        .init(major: 18, minor: 7, patch: 5), .init(major: 19, minor: 0, patch: 0),
                        .init(major: 26, minor: 1, patch: 1), .init(major: 26, minor: 2, patch: 0), .init(major: 27, minor: 0, patch: 0)] {
            XCTAssertThrowsError(try EnginePolicy.select(version, preferred: .pocketTrash))
        }
        let overlap = SystemVersion(major: 26, minor: 1, patch: 0)
        XCTAssertEqual(try EnginePolicy.select(overlap), .worseQuery)
        XCTAssertEqual(try EnginePolicy.select(overlap, preferred: .pocketTrash), .pocketTrash)
        XCTAssertFalse(InjectionEngine.pocketTrash.requiresPairing)
        XCTAssertTrue(InjectionEngine.pocketTrash.isWriteOnly)
        XCTAssertFalse(PairingPolicy.supportsOnDevice(.init(major: 17, minor: 0, patch: 0)))
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
