import Foundation
import CryptoKit

enum FileDigest {
    static func hash(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
        var digest = SHA256()
        while let data = try input.read(upToCount: 65536), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func tree(_ root: URL) throws -> String {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: root.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw BridgeError.message("描述文件目标不是目录。") }
        var traversalError: Error?
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in traversalError = error; return false }) else { throw BridgeError.message("无法读取目录。") }
        var rows: [[String]] = []
        for case let file as URL in walker {
            let attrs = try fm.attributesOfItem(atPath: file.path)
            let type = attrs[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeDirectory else { throw BridgeError.message("目录中含有链接或特殊文件。") }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            rows.append([type == .typeDirectory ? "D" : "F", relative, type == .typeDirectory ? "" : try hash(file)])
        }
        if let traversalError { throw traversalError }
        let data = try JSONSerialization.data(withJSONObject: rows.sorted { $0[1] < $1[1] })
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
    func importPack(_ source: URL, token: CancellationToken) throws -> WallpaperPack {
        try AppFiles.prepare(); try token.check()
        guard source.pathExtension.lowercased() == "tendies" else { throw BridgeError.message("首版仅导入 .tendies 壁纸包。") }
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
        guard rc == 0, let output else { throw BridgeError.message("壁纸包解压或安全检查未通过。\n诊断：" + (failure.map { String(cString: $0) } ?? "未返回详细信息。")) }
        struct Report: Decodable { var files: [String]; var uncompressedBytes: UInt64; var sha256: String }
        let report = try JSONDecoder().decode(Report.self, from: Data(String(cString: output).utf8))
        try token.check()
        if try load().contains(where: { $0.hash == report.sha256 }) { throw BridgeError.message("这个壁纸包已经导入，无需重复添加。") }
        guard !report.files.contains(where: { $0.lowercased().contains("sqlite") || $0.split(separator: "/").contains(where: { $0.lowercased() == "container" }) }) else {
            throw BridgeError.message("首版不接受整容器或数据库壁纸包。")
        }
        for file in report.files where file.hasSuffix(".plist") {
            let url = stage.appendingPathComponent(file)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard ((attrs[.size] as? NSNumber)?.uint64Value ?? .max) <= 16 * 1024 * 1024 else { throw BridgeError.message("壁纸 plist 超过 16 MiB。") }
            let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            if url.lastPathComponent == "Wallpaper.plist" { try validateReferences(value, in: url.deletingLastPathComponent()) }
        }
        let parentPaths = DescriptorLocator.roots(in: report.files)
        var descriptors: [String] = []
        for path in parentPaths {
            let folder = stage.appendingPathComponent(path)
            let parts = path.split(separator: "/").map(String.init)
            if let extIndex = parts.firstIndex(of: "Extensions"), extIndex + 1 < parts.count,
               !ContainerPath.extensions.contains(parts[extIndex + 1]) { throw BridgeError.message("此包包含首版未支持的壁纸扩展。") }
            let metadata = folder.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
            if let data = try? Data(contentsOf: metadata), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let objects = plist["$objects"] as? [Any] {
                let ids = objects.compactMap { $0 as? String }.filter { $0.hasPrefix("com.apple.") && $0.contains("Poster") }
                guard ids.allSatisfy({ ContainerPath.extensions.contains($0) || $0 == "com.apple.PosterBoard" }) else { throw BridgeError.message("注册元数据包含未支持的壁纸提供组件。") }
            }
            let descriptorID = folder.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
            if let raw = try? String(contentsOf: descriptorID, encoding: .utf8), raw.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^v[0-9]+[.]", options: .regularExpression) != nil {
                throw BridgeError.message("此包可能是 Mercury 壁纸，首版仅支持 Collections。")
            }
            if report.files.contains(where: { ($0.hasPrefix(path + "/") || path.isEmpty) && $0.split(separator: "/").contains("VideoCAML") }) {
                throw BridgeError.message("首版暂不支持 VideoCAML 视频壁纸。")
            }
            _ = try FileDigest.tree(folder)
            descriptors.append(path.isEmpty ? "Contents/" : "Contents/" + path)
        }
        guard !descriptors.isEmpty else { throw BridgeError.message("未找到可识别的 Collections 描述文件；不会把整个压缩包作为描述文件注入。") }
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
                        throw BridgeError.message("Wallpaper.plist 引用的资源不存在或路径异常：\(key)。")
                    }
                }
                try validateReferences(child, in: base)
            }
        } else if let array = value as? [Any] { for child in array { try validateReferences(child, in: base) } }
    }
    func source(pack: WallpaperPack, descriptor: String) throws -> URL {
        guard UUID(uuidString: pack.directory) == pack.id, descriptor.hasPrefix("Contents/"), !descriptor.split(separator: "/").contains("..") else { throw BridgeError.message("本地壁纸索引损坏。") }
        return AppFiles.packs.appendingPathComponent(pack.directory).appendingPathComponent(descriptor)
    }
}
