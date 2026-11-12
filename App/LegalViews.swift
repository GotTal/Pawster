import SwiftUI

enum LegalDocuments {
    static func load(_ resource: String, bundle: Bundle = .main) -> String? {
        guard let url = L10n.documentURL(resource, bundle: bundle) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    static var policiesAvailable: Bool { load("Terms") != nil && load("Privacy") != nil }
    static func chunks(_ content: String, maximum: Int = 6000) -> [String] {
        var result: [String] = []; var start = content.startIndex
        while start < content.endIndex {
            let limit = content.index(start, offsetBy: max(1, maximum), limitedBy: content.endIndex) ?? content.endIndex
            let end = limit == content.endIndex ? limit :
                content[start..<limit].lastIndex(of: "\n").map { content.index(after: $0) } ?? limit
            result.append(String(content[start..<end])); start = end
        }
        return result
    }
}

struct BundledDocumentView: View {
    let title: String
    let resource: String
    private var paragraphs: [String] {
        guard let content = LegalDocuments.load(resource) else { return [] }
        return content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if paragraphs.isEmpty {
                    Text(L10n.text("legal.documentUnavailable")).foregroundStyle(.secondary)
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("# ") {
                        Text(String(paragraph.dropFirst(2))).font(.title2.bold())
                    } else if paragraph.hasPrefix("## ") {
                        Text(String(paragraph.dropFirst(3))).font(.headline)
                    } else {
                        Text((try? AttributedString(markdown: paragraph,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct PlainLicenseView: View {
    let title: String
    let resource: String
    @State private var chunks: [String] = []
    @State private var unavailable = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if unavailable { Text(L10n.text("legal.licenseUnavailable")) }
                else if chunks.isEmpty { ProgressView() }
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    Text(chunk).font(.footnote.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding().textSelection(.enabled)
        }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task(id: resource) {
                let name = resource
                let loaded = await Task.detached(priority: .userInitiated) { () -> [String]? in
                    guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                          let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else { return nil }
                    return LegalDocuments.chunks(content)
                }.value
                guard !Task.isCancelled else { return }
                unavailable = loaded == nil; chunks = loaded ?? []
            }
    }
}

struct OpenSourceNoticesView: View {
    var body: some View {
        List {
            NavigationLink(L10n.text("legal.openSourceNotices")) { BundledDocumentView(title: L10n.text("legal.openSourceNotices"), resource: "OpenSourceNotices") }
            NavigationLink(L10n.text("legal.gplFull")) { PlainLicenseView(title: "GPL-3.0", resource: "GPL-3.0") }
            NavigationLink(L10n.text("legal.airCardMIT")) { PlainLicenseView(title: "AirCard MIT", resource: "AirCard-MIT") }
            NavigationLink(L10n.text("legal.sources")) { BundledDocumentView(title: L10n.text("legal.sources"), resource: "ThirdPartySources") }
            NavigationLink(L10n.text("legal.rustInventory")) { BundledDocumentView(title: L10n.text("legal.rustInventory"), resource: "RustDependencies") }
            NavigationLink(L10n.text("legal.rustTexts")) { PlainLicenseView(title: L10n.text("legal.rustNotices"), resource: "RustLicenseNotices") }
        }.navigationTitle(L10n.text("legal.openSourceTitle"))
    }
}

struct PolicyNoticeView: View {
    let alreadyAccepted: Bool
    let accept: () -> Void
    let decline: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text("consent.welcome")).font(.title2.bold())
                    Text(L10n.text("consent.introduction"))
                }
                Section {
                    NavigationLink(L10n.text("legal.terms")) { BundledDocumentView(title: L10n.text("legal.terms"), resource: "Terms") }
                    NavigationLink(L10n.text("legal.privacy")) { BundledDocumentView(title: L10n.text("legal.privacy"), resource: "Privacy") }
                    LabeledContent(L10n.text("about.developer"), value: AppInformation.developer)
                    Link(AppInformation.contact, destination: AppInformation.email)
                }
                Section {
                    if alreadyAccepted {
                        Button(L10n.text("action.done"), action: decline)
                    } else {
                        Button(L10n.text("consent.acceptAction"), action: accept)
                            .buttonStyle(.borderedProminent).disabled(!LegalDocuments.policiesAvailable)
                        Button(L10n.text("consent.declineAction"), action: decline)
                    }
                    if !LegalDocuments.policiesAvailable { Text(L10n.text("legal.policiesUnavailable")).foregroundStyle(.secondary) }
                }
            }.navigationTitle(L10n.text("consent.title"))
        }.interactiveDismissDisabled()
    }
}
