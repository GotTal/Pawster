import SwiftUI

@main
struct PawsterApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var pairing = PairingService()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model, pairing: pairing, guide: pairing.guide)
                .tint(.teal)
        }
    }
}
