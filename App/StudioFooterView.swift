import SwiftUI

struct StudioFooterView: View {
    static let homepage = URL(string: "https://www.xkstudio.org.cn")!

    var body: some View {
        Link(destination: Self.homepage) {
            Image("XKStudio")
                .resizable().scaledToFit()
                .frame(maxWidth: 208, maxHeight: 48)
                .accessibilityHidden(true)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("XK STUDIO")
        .accessibilityHint(L10n.text("about.studioWebsite"))
    }
}
