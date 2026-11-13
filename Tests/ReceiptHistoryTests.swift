import XCTest
@testable import Pawster

final class ReceiptHistoryTests: XCTestCase {
    private func entry(packID: UUID, name: String? = nil, source: String = "Contents/descriptor", state: String = "written") -> ReceiptEntry {
        ReceiptEntry(item: PlanItem(id: UUID(), packID: packID, sourceRelative: source,
            destinationRelative: "target/\(UUID().uuidString)", stagingRelative: "staging", expectedTreeHash: "tree-hash", packName: name), state: state)
    }
    private func receipt(_ entries: [ReceiptEntry]) -> TransactionReceipt {
        TransactionReceipt(id: UUID(), createdAt: Date(), engine: .worseQuery, container: "/test/container",
            packHashes: ["pack-hash"], entries: entries, state: "partial")
    }
    private func pack(id: UUID, name: String = "Local name", hash: String = "pack-hash") -> WallpaperPack {
        WallpaperPack(id: id, name: name, hash: hash, directory: "pack", descriptors: [], bytes: 0)
    }

    func testNameSnapshotSurvivesPersistenceAndPackRemovalOrRename() throws {
        let id = UUID()
        let original = receipt([entry(packID: id, name: "GBA Animated")])
        let restored = try JSONDecoder().decode(TransactionReceipt.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.wallpapers().first?.name, "GBA Animated")
        XCTAssertEqual(restored.wallpapers(availablePacks: [pack(id: id, name: "Renamed")]).first?.name, "GBA Animated")
    }

    func testLegacyReceiptsDecodeWithoutNamesAndOnlyUseMatchingLocalPacks() throws {
        let id = UUID()
        let data = try JSONEncoder().encode(receipt([entry(packID: id)]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        let item = try XCTUnwrap(entries.first?["item"] as? [String: Any])
        XCTAssertNil(item["packName"])
        let legacy = try JSONDecoder().decode(TransactionReceipt.self, from: data)
        XCTAssertNil(legacy.wallpapers().first?.name)
        XCTAssertEqual(legacy.wallpapers(availablePacks: [pack(id: id)]).first?.name, "Local name")
        XCTAssertNil(legacy.wallpapers(availablePacks: [pack(id: UUID())]).first?.name)
        XCTAssertNil(legacy.wallpapers(availablePacks: [pack(id: id, hash: "different-content")]).first?.name)
    }

    func testGroupingDistinguishesPackagesAndDescriptorCountFromWriteTargets() {
        let first = UUID(); let second = UUID()
        let record = receipt([entry(packID: first, name: "Same name"), entry(packID: first, name: "Same name"),
            entry(packID: first, name: "Same name", source: "Contents/another"), entry(packID: second, name: "Same name")])
        let groups = record.wallpapers()
        XCTAssertEqual(groups.map(\.id), [first, second])
        XCTAssertEqual(groups.map(\.descriptorCount), [2, 1])
        XCTAssertEqual(groups.map { $0.entries.count }, [3, 1])
    }

    func testPartialProgressPreservesPerPackageStatesInsteadOfClaimingAllWereWritten() {
        let id = UUID()
        let record = receipt([entry(packID: id, name: "Wallpaper", state: "written"),
            entry(packID: id, name: "Wallpaper", state: "planned"), entry(packID: id, name: "Wallpaper", state: "planned")])
        let counts = record.wallpapers().first?.stateCounts ?? []
        XCTAssertEqual(counts.map(\.state), ["written", "planned"])
        XCTAssertEqual(counts.map(\.count), [1, 2])
    }
}
