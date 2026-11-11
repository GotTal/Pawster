import SwiftUI

@main
struct PawsterApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var pairing = PairingService()
    @StateObject private var guide = PairingGuide()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model, pairing: pairing, guide: guide)
                .tint(.teal)
        }
    }
}
