import SwiftUI

struct ReceiptWallpapersView: View {
    let receipt: TransactionReceipt
    let availablePacks: [WallpaperPack]

    var body: some View {
        let wallpapers = receipt.wallpapers(availablePacks: availablePacks)
        ForEach(wallpapers) { wallpaper in
            VStack(alignment: .leading, spacing: 6) {
                Text(wallpaper.displayName).font(.headline).textSelection(.enabled)
                Text(L10n.text("history.wallpaperCounts", [String(wallpaper.descriptorCount), String(wallpaper.entries.count)]))
                    .font(.caption).foregroundStyle(.secondary)
                Text(wallpaper.stateCounts.map {
                    L10n.text("history.stateCount", [entryStateName($0.state), String($0.count)])
                }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        if wallpapers.contains(where: { $0.name == nil }) {
            Text(L10n.text("history.legacyNameHelp")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func entryStateName(_ state: String) -> String {
        switch state {
        case "planned": return L10n.text("history.entryPlanned")
        case "pending", "pocketCopying": return L10n.text("history.entryStaged")
        case "moving": return L10n.text("history.entryMoving")
        case "written": return L10n.text("history.entryWritten")
        case "rolledBack": return L10n.text("history.rolledBack")
        case "airliftSending", "pocketSending": return L10n.text("history.entrySending")
        case "airliftSent", "pocketSent": return L10n.text("history.entrySent")
        default: return L10n.text("history.entryUnknown")
        }
    }
}

struct ReceiptDetailsView: View {
    let receipt: TransactionReceipt

    var body: some View {
        DisclosureGroup(L10n.text("history.details")) {
            detail(L10n.text("history.recordID"), receipt.id.uuidString)
            detail(L10n.text("plan.container"), receipt.container)
            ForEach(receipt.entries, id: \.item.id) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("history.targetPath")).font(.caption).foregroundStyle(.secondary)
                    Text(entry.item.destinationRelative).font(.caption.monospaced()).textSelection(.enabled)
                    Text(L10n.text("history.sourceDescriptor")).font(.caption).foregroundStyle(.secondary)
                    Text(entry.item.sourceRelative).font(.caption.monospaced()).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }.padding(.vertical, 4)
    }
}
