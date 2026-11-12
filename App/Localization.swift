import Foundation

struct LanguageManifest: Decodable {
    struct Pack: Decodable {
        let id: String
        let nativeName: String
        let file: String
        let aliases: [String]
        let documents: [String: String]
    }
    let schemaVersion: Int
    let fallback: String
    let chineseFallback: String
    let languageDefaults: [String: String]
    let languages: [Pack]
}

/// Immutable after launch: safe for UI, background file work, and PiP rendering.
struct LocalizationCatalog {
    let manifest: LanguageManifest
    let catalogs: [String: [String: String]]
    let language: String
    private let isChinese: Bool
    static func normalize(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-").lowercased()
    }
    init(manifest: LanguageManifest, catalogs: [String: [String: String]], preferredLanguages: [String]) {
        self.manifest = manifest; self.catalogs = catalogs
        // Use the first device language; an unsupported primary language falls back to English,
        // rather than unexpectedly adopting a secondary language from the preference list.
        let requested = Self.normalize(preferredLanguages.first ?? manifest.fallback)
        let base = String(requested.split(separator: "-").first ?? "")
        isChinese = base == "zh"
        let available = manifest.languages.filter { catalogs[$0.id] != nil }
        var candidate = requested
        var match: String?
        while !candidate.isEmpty {
            match = available.first { Self.normalize($0.id) == candidate }?.id ??
                available.first { $0.aliases.contains { Self.normalize($0) == candidate } }?.id
            if match != nil { break }
            guard let separator = candidate.lastIndex(of: "-") else { break }
            candidate = String(candidate[..<separator])
        }
        let defaultID = manifest.languageDefaults[base]
        if let match { language = match }
        else if let defaultID, catalogs[defaultID] != nil { language = defaultID }
        else if isChinese, catalogs[manifest.chineseFallback] != nil { language = manifest.chineseFallback }
        else { language = manifest.fallback }
    }
    private var fallbackOrder: [String] {
        var ids = [language]
        if isChinese { ids.append(manifest.chineseFallback) }
        ids.append(manifest.fallback)
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
    private static let placeholder = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
    static func placeholders(_ text: String) -> Set<String> {
        Set(placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            (text as NSString).substring(with: $0.range)
        })
    }
    func text(_ key: String, _ arguments: [String] = []) -> String {
        let baseline = catalogs[manifest.fallback]?[key]
        let expected = baseline.map(Self.placeholders)
        let template = fallbackOrder.compactMap { catalogs[$0]?[key] }.first {
            !$0.isEmpty && (expected == nil || Self.placeholders($0) == expected)
        } ?? baseline ?? key
        // Substitute once. A user filename containing "{1}" is data, never a new placeholder.
        let source = template as NSString
        let matches = Self.placeholder.matches(in: template, range: NSRange(location: 0, length: source.length))
        var result = ""; var cursor = 0
        for match in matches {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1))) ?? -1
            result += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        return result + source.substring(from: cursor)
    }
    func documentResources(_ name: String) -> [String] {
        fallbackOrder.compactMap { id in manifest.languages.first { $0.id == id }?.documents[name] }
    }
}

enum L10n {
    static let current: LocalizationCatalog = {
        let bundle = Bundle.main
        let manifest: LanguageManifest
        if let url = bundle.url(forResource: "LanguagePacks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(LanguageManifest.self, from: data), decoded.schemaVersion == 1 {
            manifest = decoded
        } else {
            // Keep a minimal safe fallback if packaging is damaged; the source validator rejects it.
            manifest = LanguageManifest(schemaVersion: 1, fallback: "en-US", chineseFallback: "zh-Hans",
                languageDefaults: ["en": "en-US", "zh": "zh-Hans"], languages: [
                    .init(id: "en-US", nativeName: "English (United States)", file: "en-US", aliases: ["en"],
                          documents: ["Terms": "Terms.en-US", "Privacy": "Privacy.en-US"]),
                    .init(id: "zh-Hans", nativeName: "Chinese (Simplified)", file: "zh-Hans", aliases: ["zh"],
                          documents: ["Terms": "Terms", "Privacy": "Privacy"])
                ])
        }
        var catalogs: [String: [String: String]] = [:]
        for pack in manifest.languages {
            guard safeResourceName(pack.file), let url = bundle.url(forResource: pack.file, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let values = try? JSONDecoder().decode([String: String].self, from: data), !values.isEmpty else { continue }
            catalogs[pack.id] = values
        }
        return LocalizationCatalog(manifest: manifest, catalogs: catalogs, preferredLanguages: Locale.preferredLanguages)
    }()
    static var locale: Locale { Locale(identifier: current.language) }
    static func text(_ key: String, _ arguments: [String] = []) -> String { current.text(key, arguments) }
    static func safeResourceName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
        }
    }
    static func documentURL(_ name: String, bundle: Bundle = .main) -> URL? {
        for resource in current.documentResources(name) where safeResourceName(resource) {
            if let url = bundle.url(forResource: resource, withExtension: "md") { return url }
        }
        return nil
    }
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }
}
