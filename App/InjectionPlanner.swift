import Foundation

enum InjectionPlanner {
    static func make(packs: [WallpaperPack], container: VerifiedContainer, engine: InjectionEngine,
                     receipts: [TransactionReceipt], source: (WallpaperPack, String) throws -> URL,
                     token: CancellationToken) throws -> InjectionPlan {
        guard !packs.isEmpty else { throw BridgeError.message(L10n.text("error.noWallpaperSelected")) }
        let prior = receipts.filter { $0.state != "rolledBack" && !$0.allowsUnverifiedRetry }
        guard !packs.contains(where: { pack in prior.contains { $0.container == container.path && $0.packHashes.contains(pack.hash) } }) else {
            throw BridgeError.message(L10n.text(engine.isWriteOnly ? "error.airliftPriorAttempt" : "error.packAlreadyInjected"))
        }
        let tx = UUID(); var items: [PlanItem] = []
        for pack in packs {
            for descriptor in pack.descriptors {
                try token.check()
                let hash = try FileDigest.tree(source(pack, descriptor))
                let destinationID = UUID()
                for ext in container.extensionIDs {
                    let parent = try ContainerPath.descriptorParent(version: container.storeVersion, extensionID: ext)
                    items.append(PlanItem(id: UUID(), packID: pack.id, sourceRelative: descriptor,
                        destinationRelative: "\(parent)/\(destinationID.uuidString)",
                        stagingRelative: "\(parent)/.posterbridge-\(tx.uuidString)-\(destinationID.uuidString)", expectedTreeHash: hash))
                }
            }
        }
        guard !items.isEmpty, items.count <= 30 else { throw BridgeError.message(L10n.text("error.targetCount")) }
        return InjectionPlan(id: tx, createdAt: Date(), engine: engine, container: container, packHashes: packs.map(\.hash), items: items)
    }
}
