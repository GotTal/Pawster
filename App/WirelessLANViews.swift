import SwiftUI

struct WirelessLANStatusRow: View {
    let state: WirelessLANState
    private var appearance: (key: String, symbol: String, color: Color) {
        switch state {
        case .connected: return ("wifi.connected", "wifi", .green)
        case .disconnected: return ("wifi.disconnected", "wifi.slash", .orange)
        case .unchecked: return ("wifi.unchecked", "ellipsis.circle", .secondary)
        case .unavailable: return ("wifi.unavailable", "questionmark.circle", .orange)
        }
    }
    var body: some View {
        HStack {
            Text(L10n.text("wifi.title"))
            Spacer()
            Label(L10n.text(appearance.key), systemImage: appearance.symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(appearance.color)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(appearance.color.opacity(0.12), in: Capsule())
        }
    }
}

struct WirelessLANRequirementNotice: View {
    let state: WirelessLANState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state == .disconnected || state == .unavailable {
                Label(L10n.text(state == .disconnected ? "wifi.connectRequired" : "wifi.checkSettings"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(L10n.text("wifi.requirement")).foregroundStyle(.secondary)
        }.font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
}
