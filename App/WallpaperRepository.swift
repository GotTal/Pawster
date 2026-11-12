import Foundation
import CryptoKit

enum FileDigest {
    struct Entry: Equatable {
        let kind: String
        let path: String
        let bytes: UInt64
        let digest: String
    }
    struct Snapshot {
        let entries: [Entry]
        let digest: String
        var fileCount: Int { entries.filter { $0.kind == "F" }.count }
        var byteCount: UInt64 { entries.reduce(0) { $0 + $1.bytes } }

        func differences(from actual: Snapshot) -> String {
            let expectedByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
            let actualByPath = Dictionary(uniqueKeysWithValues: actual.entries.map { ($0.path, $0) })
            var details: [String] = []
            for path in Set(expectedByPath.keys).union(actualByPath.keys).sorted() {
                if let expected = expectedByPath[path], let found = actualByPath[path] {
                    if expected.kind != found.kind { details.append(L10n.text("digest.typeMismatch", [String(describing: path)])) }
                    else if expected.bytes != found.bytes { details.append(L10n.text("digest.sizeMismatch", [String(describing: path), String(describing: expected.bytes), String(describing: found.bytes)])) }
                    else if expected.digest != found.digest { details.append(L10n.text("digest.contentMismatch", [String(describing: path)])) }
                } else if expectedByPath[path] != nil { details.append(L10n.text("digest.missing", [String(describing: path)])) }
                else { details.append(L10n.text("digest.extra", [String(describing: path)])) }
                if details.count == 3 { break }
            }
            let summary = L10n.text("digest.summary", [String(describing: fileCount), String(describing: byteCount), String(describing: actual.fileCount), String(describing: actual.byteCount)])
            return ([summary] + details + [L10n.text("digest.hashes", [digest, actual.digest])]).joined(separator: "\n")
        }
    }

    static func hash(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
        var digest = SHA256()
        while let data = try input.read(upToCount: 65536), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func tree(_ root: URL) throws -> String { try snapshot(root).digest }

    static func snapshot(_ root: URL) throws -> Snapshot {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: root.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw BridgeError.message(L10n.text("error.descriptorNotDirectory")) }
        var entries: [Entry] = []
        var pending: [(URL, String)] = [(root, "")]
        while let (directory, relativeParent) = pending.popLast() {
            // Use names returned by the directory, never offsets into an absolute URL path.
            // Foundation may represent /var and /private/var differently. A copied root also
            // has a different UUID/name. Neither may affect the descriptor's content digest.
            let names = try fm.contentsOfDirectory(atPath: directory.path)
            for name in names {
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
                    throw BridgeError.message(L10n.text("error.directoryName"))
                }
                let file = directory.appendingPathComponent(name)
                let relative = relativeParent.isEmpty ? name : relativeParent + "/" + name
                let attributes = try fm.attributesOfItem(atPath: file.path)
                let type = attributes[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeDirectory else { throw BridgeError.message(L10n.text("error.specialFile")) }
                if type == .typeDirectory {
                    entries.append(Entry(kind: "D", path: relative, bytes: 0, digest: ""))
                    pending.append((file, relative))
                } else {
                    let digest = try hash(file)
                    let after = try fm.attributesOfItem(atPath: file.path)
                    guard let bytes = (attributes[.size] as? NSNumber)?.uint64Value,
                          (after[.type] as? FileAttributeType) == .typeRegular,
                          bytes == (after[.size] as? NSNumber)?.uint64Value else {
                        throw BridgeError.message(L10n.text("error.fileChangedDuringHash", [String(describing: relative)]))
                    }
                    entries.append(Entry(kind: "F", path: relative, bytes: bytes, digest: digest))
                }
            }
        }
        entries.sort { $0.path < $1.path }
        // Keep the existing row format so stored plans/receipts retain their content-hash format.
        let rows = entries.map { [$0.kind, $0.path, $0.digest] }
        let data = try JSONSerialization.data(withJSONObject: rows)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Snapshot(entries: entries, digest: digest)
    }
}

final class WallpaperRepository {
    private let fm = FileManager.default
    func load() throws -> [WallpaperPack] {
        try AppFiles.prepare()
        return try fm.contentsOfDirectory(at: AppFiles.packs, includingPropertiesForKeys: nil).compactMap {
            guard let data = try? Data(contentsOf: $0.appendingPathComponent("pack.json")) else { return nil }
            return try? JSONDecoder().decode(WallpaperPack.self, from: data)
        }.sorted { $0.name < $1.name }
    }
    func remove(_ pack: WallpaperPack, from root: URL = AppFiles.packs) throws {
        guard UUID(uuidString: pack.directory) == pack.id else {
            throw BridgeError.message(L10n.text("error.packIndexInvalid"))
        }
        let directory = root.appendingPathComponent(pack.directory, isDirectory: true)
        let rootType = try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType
        let directoryType = try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType
        guard rootType == .typeDirectory, directoryType == .typeDirectory else {
            throw BridgeError.message(L10n.text("error.packDirectoryInvalid"))
        }
        let saved = try JSONDecoder().decode(WallpaperPack.self, from: Data(contentsOf: directory.appendingPathComponent("pack.json")))
        guard saved.id == pack.id, saved.directory == pack.directory, saved.hash == pack.hash else {
            throw BridgeError.message(L10n.text("error.packChanged"))
        }
        // The imported ZIP, extracted contents and preview are local copies in this one UUID folder.
        // PosterBoard descriptors and transaction receipts have separate roots and are not removed.
        try fm.removeItem(at: directory)
    }
    func importPack(_ source: URL, token: CancellationToken) throws -> WallpaperPack {
        try AppFiles.prepare(); try token.check()
        guard source.pathExtension.lowercased() == "tendies" else { throw BridgeError.message(L10n.text("error.tendiesRequired")) }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let id = UUID(); let dir = AppFiles.packs.appendingPathComponent(id.uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false)
        var keep = false; defer { if !keep { try? fm.removeItem(at: dir) } }
        let archive = dir.appendingPathComponent("source.tendies")
        try fm.copyItem(at: source, to: archive)
        var output: UnsafeMutablePointer<CChar>?; var failure: UnsafeMutablePointer<CChar>?
        let stage = dir.appendingPathComponent("Contents")
        let rc = pb_extract_zip(archive.path, stage.path, &output, &failure)
        defer { pb_string_free(output); pb_string_free(failure) }
        guard rc == 0, let output else { throw BridgeError.message(L10n.text("error.archiveRejected") + (failure.map { String(cString: $0) } ?? L10n.text("error.noDetails"))) }
        struct Report: Decodable { var files: [String]; var uncompressedBytes: UInt64; var sha256: String }
        let report = try JSONDecoder().decode(Report.self, from: Data(String(cString: output).utf8))
        try token.check()
        if try load().contains(where: { $0.hash == report.sha256 }) { throw BridgeError.message(L10n.text("error.packDuplicate")) }
        guard !report.files.contains(where: { $0.lowercased().contains("sqlite") || $0.split(separator: "/").contains(where: { $0.lowercased() == "container" }) }) else {
            throw BridgeError.message(L10n.text("error.wholeContainerPack"))
        }
        for file in report.files where file.hasSuffix(".plist") {
            let url = stage.appendingPathComponent(file)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard ((attrs[.size] as? NSNumber)?.uint64Value ?? .max) <= 16 * 1024 * 1024 else { throw BridgeError.message(L10n.text("error.wallpaperPlistLarge")) }
            let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            if url.lastPathComponent == "Wallpaper.plist" { try validateReferences(value, in: url.deletingLastPathComponent()) }
        }
        let parentPaths = DescriptorLocator.roots(in: report.files)
        var descriptors: [String] = []
        for path in parentPaths {
            let folder = stage.appendingPathComponent(path)
            let parts = path.split(separator: "/").map(String.init)
            if let extIndex = parts.firstIndex(of: "Extensions"), extIndex + 1 < parts.count,
               !ContainerPath.extensions.contains(parts[extIndex + 1]) { throw BridgeError.message(L10n.text("error.wallpaperType")) }
            let metadata = folder.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
            if let data = try? Data(contentsOf: metadata), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let objects = plist["$objects"] as? [Any] {
                let ids = objects.compactMap { $0 as? String }.filter { $0.hasPrefix("com.apple.") && $0.contains("Poster") }
                guard ids.allSatisfy({ ContainerPath.extensions.contains($0) || $0 == "com.apple.PosterBoard" }) else { throw BridgeError.message(L10n.text("error.wallpaperProvider")) }
            }
            let descriptorID = folder.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
            if let raw = try? String(contentsOf: descriptorID, encoding: .utf8), raw.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^v[0-9]+[.]", options: .regularExpression) != nil {
                throw BridgeError.message(L10n.text("error.mercury"))
            }
            if report.files.contains(where: { ($0.hasPrefix(path + "/") || path.isEmpty) && $0.split(separator: "/").contains("VideoCAML") }) {
                throw BridgeError.message(L10n.text("error.videoCAML"))
            }
            _ = try FileDigest.tree(folder)
            descriptors.append(path.isEmpty ? "Contents/" : "Contents/" + path)
        }
        guard !descriptors.isEmpty else { throw BridgeError.message(L10n.text("error.noCollections")) }
        let preview = report.files.filter { ["jpg", "jpeg", "png", "heic"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .sorted { ($0.lowercased().contains("preview") ? 0 : 1, $0) < ($1.lowercased().contains("preview") ? 0 : 1, $1) }.first
        let pack = WallpaperPack(id: id, name: source.deletingPathExtension().lastPathComponent, hash: report.sha256,
            directory: id.uuidString, descriptors: descriptors, bytes: report.uncompressedBytes, preview: preview.map { "Contents/" + $0 })
        try AppFiles.write(pack, to: dir.appendingPathComponent("pack.json")); keep = true
        return pack
    }
    private func validateReferences(_ value: Any, in base: URL) throws {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if (key.hasSuffix("FileName") || key.hasSuffix("FileNameKey")), let name = child as? String {
                    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains(":"), !name.contains("\\"),
                          !name.split(separator: "/").contains(".."), fm.fileExists(atPath: base.appendingPathComponent(name).path) else {
                        throw BridgeError.message(L10n.text("error.wallpaperReference", [String(describing: key)]))
                    }
                }
                try validateReferences(child, in: base)
            }
        } else if let array = value as? [Any] { for child in array { try validateReferences(child, in: base) } }
    }
    func source(pack: WallpaperPack, descriptor: String) throws -> URL {
        guard UUID(uuidString: pack.directory) == pack.id, descriptor.hasPrefix("Contents/"), !descriptor.split(separator: "/").contains("..") else { throw BridgeError.message(L10n.text("error.localIndex")) }
        return AppFiles.packs.appendingPathComponent(pack.directory).appendingPathComponent(descriptor)
    }
}
