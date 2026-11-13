import Foundation
import Darwin

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum InjectionEngine: String, Codable, CaseIterable, Hashable {
    case badQuery = "bad_query", worseQuery = "worse_query"
    case airlift = "airlift"
    case pocketTrash = "pocket_trash"
    var title: String {
        switch self { case .airlift: return "AirTraffic / Airlift"; case .pocketTrash: return "Pocket Poster / Trash"; default: return rawValue }
    }
    var isWriteOnly: Bool { self == .airlift || self == .pocketTrash }
    var requiresPairing: Bool { self != .pocketTrash }
}

struct SystemVersion: Comparable, Codable {
    var major: Int; var minor: Int; var patch: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
    }
    static var current: Self {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return Self(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }
    static let currentBuild: String = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1, size < 256 else { return "" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }()
    var text: String { "\(major).\(minor).\(patch)" }
}

enum EnginePolicy {
    // README ranges concern file access, not device acceptance or Settings pairing.
    // Keep named beta exceptions tied to their complete kernel build identifiers.
    static func available(for version: SystemVersion, build: String = "") -> [InjectionEngine] {
        var result: [InjectionEngine] = []
        if (version >= .init(major: 26, minor: 0, patch: 0) && version <= .init(major: 26, minor: 7, patch: 2)) ||
            (version >= .init(major: 27, minor: 0, patch: 0) && version <= .init(major: 27, minor: 2, patch: 1)) ||
            (version == .init(major: 27, minor: 3, patch: 0) && build == "24C5037i") {
            result.append(.worseQuery)
        }
        if (version >= .init(major: 26, minor: 0, patch: 0) && version <= .init(major: 26, minor: 6, patch: 1)) ||
            (version == .init(major: 27, minor: 0, patch: 0) && build == "24A5390f") {
            result.append(.badQuery)
        }
        if (version == .init(major: 27, minor: 0, patch: 0) || version == .init(major: 27, minor: 0, patch: 1)) ||
            (version == .init(major: 27, minor: 2, patch: 0) && ["24B5084k", "24B5089g"].contains(build)) {
            result.append(.airlift)
        }
        // Upstream's older-system route; conservatively stop the 18.x branch at
        // the community guide's 18.7.2 boundary rather than enabling later backports.
        if (version >= .init(major: 17, minor: 0, patch: 0) && version <= .init(major: 18, minor: 7, patch: 2)) ||
            (version >= .init(major: 26, minor: 0, patch: 0) && version <= .init(major: 26, minor: 1, patch: 0)) {
            result.append(.pocketTrash)
        }
        return result
    }
    static func select(_ version: SystemVersion, build: String = "", preferred: InjectionEngine? = nil) throws -> InjectionEngine {
        let engines = available(for: version, build: build)
        if let preferred {
            guard engines.contains(preferred) else {
                throw BridgeError.message(L10n.text("error.engineUnsupported", [preferred.rawValue, version.text, build]))
            }
            return preferred
        }
        if let first = engines.first { return first }
        throw BridgeError.message(L10n.text("error.systemUnsupported", [String(describing: version.text)]))
    }
}

enum PairingPolicy {
    static func supportsOnDevice(_ version: SystemVersion) -> Bool { version.major >= 27 }
}

enum ContainerPath {
    static let base = "/var/mobile/Containers/Data/Application"
    static func normalize(_ input: String) throws -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("/private/var/") { s.removeFirst(8) }
        while s.hasSuffix("/") { s.removeLast() }
        let components = s.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("."), !s.contains("\0"),
              URL(fileURLWithPath: s).deletingLastPathComponent().path == base,
              UUID(uuidString: URL(fileURLWithPath: s).lastPathComponent) != nil,
              s == URL(fileURLWithPath: s).standardizedFileURL.path else {
            throw BridgeError.message(L10n.text("error.containerPath", [String(describing: base)]))
        }
        return s
    }
    static let extensions = ["com.apple.WallpaperKit.CollectionsPoster", "com.apple.Posters.CollectionsPosterApp"]
    static let store = "Library/Application Support/PRBPosterExtensionDataStore"
    static func descriptorParent(version: String, extensionID: String) throws -> String {
        guard !version.isEmpty, version.allSatisfy(\.isNumber), extensions.contains(extensionID) else {
            throw BridgeError.message(L10n.text("error.storeUnsupported"))
        }
        return "\(store)/\(version)/Extensions/\(extensionID)/descriptors"
    }
    static func isManagedDescriptor(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 8, parts[0...2].joined(separator: "/") == store,
              parts[3].allSatisfy(\.isNumber), !parts[3].isEmpty,
              parts[4] == "Extensions", extensions.contains(parts[5]), parts[6] == "descriptors",
              UUID(uuidString: parts[7]) != nil else { return false }
        return true
    }
}

enum DescriptorLocator {
    static func roots(in files: [String]) -> [String] {
        let markers = ["Wallpaper.plist", "com.apple.posterkit.provider.descriptor.identifier", "providerInfo.plist", "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist"]
        var candidates: Set<String> = []
        for file in files {
            let parts = file.split(separator: "/").map(String.init)
            guard let name = parts.last, markers.contains(name), !parts.contains("__MACOSX") else { continue }
            let parent = Array(parts.dropLast())
            if let i = parent.firstIndex(where: { ["descriptors", "ordered-descriptors"].contains($0.lowercased()) }), i + 1 < parent.count {
                candidates.insert(parent[...(i + 1)].joined(separator: "/"))
            } else if let i = parent.firstIndex(of: "versions") {
                candidates.insert(parent.prefix(i).joined(separator: "/"))
            } else { candidates.insert(parent.joined(separator: "/")) }
        }
        var result: [String] = []
        for path in candidates.sorted(by: { ($0.count, $0) < ($1.count, $1) }) {
            if !result.contains(where: { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }) { result.append(path) }
        }
        return result
    }
}

struct WallpaperPack: Identifiable, Codable {
    var id: UUID; var name: String; var hash: String; var directory: String
    var descriptors: [String]; var bytes: UInt64; var preview: String?
}

struct VerifiedContainer: Codable {
    var path: String; var source: String; var checkedAt: Date; var storeVersion: String
    var extensionIDs: [String]; var identity: String?; var diagnostics: [String]
    var knownExtensionIDs: [String] = []
}

struct PlanItem: Identifiable, Codable {
    var id: UUID; var packID: UUID; var sourceRelative: String; var destinationRelative: String
    var stagingRelative: String; var expectedTreeHash: String
}

struct InjectionPlan: Identifiable, Codable {
    var id: UUID; var createdAt: Date; var engine: InjectionEngine; var container: VerifiedContainer
    var packHashes: [String]; var items: [PlanItem]
}

struct ReceiptEntry: Codable {
    var item: PlanItem; var state: String
}
struct RefreshRecord: Codable {
    var existed: Bool; var beforeHash: String?; var afterHash: String
    var state = "pending"
}
struct TransactionReceipt: Identifiable, Codable {
    var id: UUID; var createdAt: Date; var engine: InjectionEngine; var container: String
    var packHashes: [String]; var entries: [ReceiptEntry]; var state: String; var failure: String?
    var refresh: RefreshRecord?
    var airliftRecoveryCompleted: Bool? = nil
    var airliftRetryAcknowledged: Bool? = nil
    var pocketCleanupCompleted: Bool? = nil
    var pocketRetryAcknowledged: Bool? = nil
    var allowsUnverifiedRetry: Bool { engine.isWriteOnly && (airliftRetryAcknowledged == true || pocketRetryAcknowledged == true) }
}

final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func check() throws { lock.lock(); let cancelled = value; lock.unlock(); if cancelled { throw CancellationError() } }
}

enum AppFiles {
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pawster", isDirectory: true) }
    static var packs: URL { root.appendingPathComponent("Packs", isDirectory: true) }
    static var transactions: URL { root.appendingPathComponent("Transactions", isDirectory: true) }
    static var pairing: URL { root.appendingPathComponent("pairing.plist") }
    static var diagnosticExport: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Pawster-Diagnostics.txt") }
    static func prepare() throws {
        for dir in [root, packs, transactions] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var url = dir; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
        #endif
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
