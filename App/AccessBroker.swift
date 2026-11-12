import Foundation
import Darwin

protocol ScopedAccess {
    func withAccess<T>(_ path: String, engine: InjectionEngine, readOnly: Bool, operation: () throws -> T) throws -> T
}
extension ScopedAccess {
    func withAccess<T>(_ path: String, engine: InjectionEngine, operation: () throws -> T) throws -> T {
        try withAccess(path, engine: engine, readOnly: false, operation: operation)
    }
}
final class AccessBroker: ScopedAccess, @unchecked Sendable {
    static let shared = AccessBroker()
    // worse_query temporarily changes this app's dedicated App Group Caches link.
    // Serialize acquisition AND the scoped operation, including nested reads.
    private let lock = NSRecursiveLock()
    var availableGroup: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String] else { return nil }
        return groups.first { $0.contains("Pawster.WQ") && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }
    func withAccess<T>(_ path: String, engine: InjectionEngine, readOnly: Bool = false, operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if readOnly && FileManager.default.isReadableFile(atPath: path) {
            do { return try operation() }
            catch {
                let e = error as NSError
                let permission = (e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError) ||
                    (e.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(e.code))
                if !permission { throw error }
                // A positive access() result is not proof that this sandbox can read the directory.
            }
        }
        let handle: Int64
        switch engine {
        case .worseQuery:
            guard let group = availableGroup else { throw BridgeError.message(L10n.text("access.groupMissing")) }
            handle = worse_query(path, group, false, false)
        case .badQuery:
            handle = path.withCString { p in bad_query(UnsafeMutablePointer(mutating: p), false, nil, false) }
        }
        guard handle >= 0 else { throw BridgeError.message(L10n.text("access.denied", [String(describing: engine.rawValue), String(describing: handle), String(describing: path)])) }
        defer {
            if engine == .worseQuery { worse_query_release(handle) } else { bad_query_release(handle) }
        }
        return try operation()
    }
}

struct ContainerInspector {
    private let fm = FileManager.default
    func inspect(path: String, authoritative: Bool, engine: InjectionEngine) throws -> VerifiedContainer {
        let path = try ContainerPath.normalize(path)
        return try AccessBroker.shared.withAccess(path, engine: engine, readOnly: true) {
            var diagnostics: [String] = []
            var identities: [String] = []
            let attr = "com.apple.containermanager.identifier"
            let size = getxattr(path, attr, nil, 0, 0, 0)
            if size > 0 && size <= 65536 {
                var bytes = [UInt8](repeating: 0, count: size)
                let read = getxattr(path, attr, &bytes, bytes.count, 0, 0)
                if read < 0 { let code = errno; diagnostics.append(L10n.text("diagnostics.xattrRead", [String(describing: code)])) }
                else if let id = String(bytes: bytes.prefix(read).prefix { $0 != 0 }, encoding: .utf8), !id.isEmpty {
                    identities.append(id); diagnostics.append(L10n.text("diagnostics.xattrIdentifier", [String(describing: id)]))
                } else { diagnostics.append(L10n.text("diagnostics.xattrInvalid")) }
            } else if size < 0 {
                let code = errno
                diagnostics.append(code == ENOATTR ? L10n.text("diagnostics.xattrMissing") : L10n.text("diagnostics.xattrQuery", [String(describing: code)]))
            } else { diagnostics.append(L10n.text("diagnostics.xattrSize")) }
            let namesSize = listxattr(path, nil, 0, 0)
            if namesSize < 0 { let code = errno; diagnostics.append(L10n.text("diagnostics.listXattrQuery", [String(describing: code)])) }
            else if namesSize > 65536 { diagnostics.append(L10n.text("diagnostics.xattrListLarge")) }
            else {
                var bytes = [UInt8](repeating: 0, count: max(1, namesSize))
                let n = listxattr(path, &bytes, bytes.count, 0)
                if n >= 0 { diagnostics.append(L10n.text("diagnostics.xattrVisible") + bytes.prefix(n).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }.joined(separator: ", ")) }
                else { let code = errno; diagnostics.append(L10n.text("diagnostics.listXattrRead", [String(describing: code)])) }
            }
            for name in [".com.apple.mobile_container_manager.metadata.plist", "com.apple.mobile_container_manager.metadata.plist"] {
                let url = URL(fileURLWithPath: path).appendingPathComponent(name)
                do {
                    let id: String? = try AccessBroker.shared.withAccess(url.path, engine: engine, readOnly: true) {
                        let attrs = try fm.attributesOfItem(atPath: url.path)
                        guard ((attrs[.size] as? NSNumber)?.uint64Value ?? .max) <= 1024 * 1024 else { throw BridgeError.message(L10n.text("error.metadataLarge")) }
                        let data = try Data(contentsOf: url)
                        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                        return plist?["MCMMetadataIdentifier"] as? String
                    }
                    if let id { identities.append(id); diagnostics.append(L10n.text("diagnostics.mcmIdentifier", [String(describing: id)])) }
                } catch { diagnostics.append(L10n.text("diagnostics.unreadable", [String(describing: name)])) }
            }
            guard !identities.contains(where: { $0 != "com.apple.PosterBoard" }) else { throw BridgeError.message(L10n.text("error.containerConflict") + diagnostics.joined(separator: "\n")) }
            guard authoritative || identities.contains("com.apple.PosterBoard") else { throw BridgeError.message(L10n.text("error.containerUnknown") + diagnostics.joined(separator: "\n")) }
            let store = URL(fileURLWithPath: path).appendingPathComponent(ContainerPath.store)
            let versions = try fm.contentsOfDirectory(at: store, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { !$0.lastPathComponent.isEmpty && $0.lastPathComponent.allSatisfy(\.isNumber) && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            // No blind selection if multiple schema versions coexist.
            let usable = versions.filter { version in
                ContainerPath.extensions.contains { fm.fileExists(atPath: version.appendingPathComponent("Extensions/\($0)/descriptors").path) }
            }
            guard usable.count == 1, let version = usable.first else { throw BridgeError.message(L10n.text("error.storeAmbiguous", [String(describing: usable.count)])) }
            let ids = ContainerPath.extensions.filter { fm.fileExists(atPath: version.appendingPathComponent("Extensions/\($0)/descriptors").path) }
            let knownIDs = try fm.contentsOfDirectory(atPath: version.appendingPathComponent("Extensions").path)
                .filter { $0.hasPrefix("com.apple.") && !$0.contains("/") }.sorted()
            diagnostics.append(L10n.text("diagnostics.store", [String(describing: version.lastPathComponent), String(describing: ids.count)]))
            return VerifiedContainer(path: path, source: authoritative ? "InstallationProxy" : "MCM/xattr", checkedAt: Date(), storeVersion: version.lastPathComponent, extensionIDs: ids, identity: identities.first, diagnostics: diagnostics, knownExtensionIDs: knownIDs)
        }
    }
}
