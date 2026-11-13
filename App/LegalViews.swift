import SwiftUI

enum LegalDocuments {
    static func load(_ resource: String, bundle: Bundle = .main) -> String? {
        guard let url = L10n.documentURL(resource, bundle: bundle) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    static var policiesAvailable: Bool {
        ["Terms", "Privacy"].allSatisfy { resource in
            guard let text = load(resource) else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
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
                        Text(DocumentInlineText.render(paragraph))
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
            NavigationLink(L10n.text("pocket.license")) { PlainLicenseView(title: "Pocket Poster · GPL-3.0", resource: "Pocket-Poster-GPL-3.0") }
            NavigationLink(L10n.text("legal.sources")) { BundledDocumentView(title: L10n.text("legal.sources"), resource: "ThirdPartySources") }
            NavigationLink(L10n.text("legal.rustInventory")) { BundledDocumentView(title: L10n.text("legal.rustInventory"), resource: "RustDependencies") }
            NavigationLink(L10n.text("legal.rustTexts")) { PlainLicenseView(title: L10n.text("legal.rustNotices"), resource: "RustLicenseNotices") }
        }.navigationTitle(L10n.text("legal.openSourceTitle"))
    }
}

struct FreeUseNoticeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("freeUse.message"))
            Text(L10n.text("freeUse.paidChannel"))
                .font(.footnote).foregroundStyle(.secondary)
            Link(L10n.text("freeUse.download"), destination: AppInformation.latestRelease)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PolicyNoticeView: View {
    let alreadyAccepted: Bool
    let accept: (Bool) -> Void
    let decline: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var risksAcknowledged = false
    private var canAccept: Bool { risksAcknowledged && LegalDocuments.policiesAvailable }
    private var warningColor: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.48, blue: 0.46) : Color(red: 0.72, green: 0.08, blue: 0.12)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text("consent.welcome")).font(.title2.bold())
                    Text(L10n.text("consent.introduction"))
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.text("consent.riskTitle"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(L10n.text("consent.riskDamage")).fontWeight(.semibold)
                        Text(L10n.text("consent.riskRecovery"))
                        Text(L10n.text("consent.riskBackup"))
                        Text(L10n.text("consent.riskMechanism")).font(.footnote)
                    }
                    .foregroundStyle(warningColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section(L10n.text("freeUse.title")) { FreeUseNoticeView() }
                Section {
                    NavigationLink(L10n.text("legal.terms")) { BundledDocumentView(title: L10n.text("legal.terms"), resource: "Terms") }
                    NavigationLink(L10n.text("legal.privacy")) { BundledDocumentView(title: L10n.text("legal.privacy"), resource: "Privacy") }
                    LabeledContent(L10n.text("about.developer"), value: AppInformation.developer)
                    Link(AppInformation.contact, destination: AppInformation.email)
                }
                if !alreadyAccepted {
                    Section {
                        Toggle(L10n.text("consent.riskAcknowledgement"), isOn: $risksAcknowledged)
                            .toggleStyle(CheckboxToggleStyle())
                            .accessibilityHint(L10n.text("consent.riskAcknowledgementHint"))
                        Text(L10n.text("consent.enableRequirement"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    VStack(spacing: 12) {
                        if alreadyAccepted {
                            Button(action: decline) {
                                Text(L10n.text("action.done"))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(.tint)
                        } else {
                            Button {
                                guard canAccept else { return }
                                accept(risksAcknowledged)
                            } label: {
                                Text(L10n.text("consent.acceptAction"))
                                    .font(.headline).multilineTextAlignment(.center)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
                                    .foregroundStyle(.white)
                                    .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                                    .opacity(canAccept ? 1 : 0.45)
                            }
                            .buttonStyle(.plain).disabled(!canAccept)
                            Button(action: decline) {
                                Text(L10n.text("consent.declineAction"))
                                    .foregroundStyle(.red).multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if !LegalDocuments.policiesAvailable {
                            Text(L10n.text("legal.policiesUnavailable")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }.navigationTitle(L10n.text("consent.title"))
        }
        .interactiveDismissDisabled()
        .onAppear { risksAcknowledged = false }
    }
}
