import SwiftUI

struct StudioFooterView: View {
    static let homepage = URL(string: "https://www.xkstudio.org.cn")!

    var body: some View {
        Link(destination: Self.homepage) {
            VStack(spacing: 10) {
                Image("XKStudio")
                    .resizable().scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 56)
                    .accessibilityHidden(true)
                HStack(spacing: 5) {
                    Text("xkstudio.org.cn")
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("XK STUDIO")
        .accessibilityHint(L10n.text("about.studioWebsite"))
    }
}
