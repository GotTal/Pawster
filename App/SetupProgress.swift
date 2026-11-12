import Foundation
import Combine

@MainActor
final class SetupProgress: ObservableObject {
    enum Step: String, CaseIterable, Identifiable {
        case install, vpn, developer, pairing
        var id: Self { self }
        var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
        var title: String {
            switch self {
            case .install: return L10n.text("onboarding.installTitle")
            case .vpn: return L10n.text("onboarding.vpnTitle")
            case .developer: return L10n.text("onboarding.developerTitle")
            case .pairing: return L10n.text("onboarding.pairingTitle")
            }
        }
    }
    @Published private(set) var showing = false
    @Published private(set) var step: Step
    @Published private(set) var completed: Bool
    @Published private(set) var deferred: Bool
    @Published private(set) var developerAcknowledged: Bool
    var shouldAutoStart: Bool { !completed && !deferred }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = defaults.string(forKey: "setup.step").flatMap(Step.init(rawValue:)) ?? .install
        completed = defaults.bool(forKey: "setup.completed")
        deferred = defaults.bool(forKey: "setup.deferred")
        developerAcknowledged = defaults.bool(forKey: "setup.developerAcknowledged")
    }
    func start() {
        showing = true; deferred = false; defaults.set(false, forKey: "setup.deferred")
    }
    func pause() {
        showing = false; deferred = true; defaults.set(true, forKey: "setup.deferred")
    }
    func acknowledgeDeveloper(_ value: Bool) {
        developerAcknowledged = value; defaults.set(value, forKey: "setup.developerAcknowledged")
    }
    @discardableResult
    func advance(vpnConnected: Bool) -> Bool {
        switch step {
        case .install: setStep(.vpn)
        case .vpn:
            guard vpnConnected else { return false }; setStep(.developer)
        case .developer:
            guard developerAcknowledged else { return false }; setStep(.pairing)
        case .pairing: return false
        }
        return true
    }
    func back() {
        guard let index = Step.allCases.firstIndex(of: step), index > 0 else { return }
        setStep(Step.allCases[index - 1])
    }
    @discardableResult
    func finish(vpnConnected: Bool, credentialReady: Bool) -> Bool {
        guard step == .pairing, developerAcknowledged, vpnConnected, credentialReady else { return false }
        completed = true; showing = false; deferred = false
        defaults.set(true, forKey: "setup.completed"); defaults.set(false, forKey: "setup.deferred")
        return true
    }
    private func setStep(_ value: Step) { step = value; defaults.set(value.rawValue, forKey: "setup.step") }
}

enum SetupLinks {
    static let vpnStore = URL(string: "https://apps.apple.com/app/id6755608044")!
    static let vpnProject = URL(string: "https://github.com/jkcoxson/LocalDevVPN")!
    // Open the app only. The user chooses Connect and approves the VPN configuration.
    static let vpnApp = URL(string: "localdevvpn://")!
    static let developerHelp = URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")!
}
