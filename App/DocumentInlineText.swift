import Foundation

enum DocumentInlineText {
    // Explicit links/autolinks and code spans already have author-defined boundaries.
    private static let protected = try! NSRegularExpression(
        pattern: #"(`+)[\s\S]*?\1|\[[^\]\n]*\]\([^\n]*?\)|<[^>\n]+>"#)
    private static let webAddress = try! NSRegularExpression(
        pattern: #"https?://[A-Za-z0-9\[][A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]*"#,
        options: .caseInsensitive)
    private static let emailAddress = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}"#)

    static func boundedMarkdown(_ source: String) -> String {
        let original = source as NSString
        let full = NSRange(location: 0, length: original.length)
        let protectedRanges = protected.matches(in: source, range: full).map(\.range)
        let webMatches = webAddress.matches(in: source, range: full).map(\.range)
        let emails = emailAddress.matches(in: source, range: full).map(\.range).filter { email in
            !webMatches.contains { NSIntersectionRange($0, email).length > 0 }
        }
        var replacements: [(NSRange, String)] = []
        for match in webMatches + emails {
            guard !protectedRanges.contains(where: { NSIntersectionRange($0, match).length > 0 }) else { continue }
            let raw = original.substring(with: match)
            let address = trimmedAddress(raw)
            guard !address.isEmpty else { continue }
            let isWeb = address.lowercased().hasPrefix("http")
            let target = isWeb ? address : "mailto:" + address
            guard let url = URL(string: target), !isWeb || url.host?.isEmpty == false else { continue }
            let range = NSRange(location: match.location, length: (address as NSString).length)
            replacements.append((range, "<" + address + ">"))
        }
        let result = NSMutableString(string: source)
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: value)
        }
        return result as String
    }
    private static func trimmedAddress(_ input: String) -> String {
        var value = input
        while let last = value.last {
            if ".,;:!?'*".contains(last) { value.removeLast(); continue }
            if last == ")", value.filter({ $0 == ")" }).count > value.filter({ $0 == "(" }).count {
                value.removeLast(); continue
            }
            if last == "]", value.filter({ $0 == "]" }).count > value.filter({ $0 == "[" }).count {
                value.removeLast(); continue
            }
            break
        }
        return value
    }
    static func render(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: boundedMarkdown(source),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
