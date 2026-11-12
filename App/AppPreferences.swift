import SwiftUI

@MainActor
final class AppPreferences: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self { case .system: return L10n.text("appearance.system"); case .light: return L10n.text("appearance.light"); case .dark: return L10n.text("appearance.dark") }
        }
        var colorScheme: ColorScheme? {
            switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
        }
    }
    static let policyVersion = "2026-11-12.1"
    static let logLimits = [0, 100, 300, 1000]
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var logLimit: Int { didSet { defaults.set(logLimit, forKey: "diagnosticLogLimit") } }
    @Published private(set) var acceptedPolicyVersion: String?
    @Published private(set) var acceptedAt: Date?
    @Published private(set) var pairingConsentVersion: String?
    var hasConsent: Bool { acceptedPolicyVersion == Self.policyVersion }
    var hasPairingConsent: Bool { hasConsent && pairingConsentVersion == Self.policyVersion }
    var effectiveLogLimit: Int { Self.logLimits.contains(logLimit) ? logLimit : 0 }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        let saved = defaults.object(forKey: "diagnosticLogLimit") as? Int ?? 0
        logLimit = Self.logLimits.contains(saved) ? saved : 0
        acceptedPolicyVersion = defaults.string(forKey: "acceptedPolicyVersion")
        acceptedAt = defaults.object(forKey: "acceptedPolicyAt") as? Date
        pairingConsentVersion = defaults.string(forKey: "pairingConsentVersion")
    }
    func acceptPolicies() {
        let now = Date()
        defaults.set(Self.policyVersion, forKey: "acceptedPolicyVersion")
        defaults.set(now, forKey: "acceptedPolicyAt")
        acceptedAt = now; acceptedPolicyVersion = Self.policyVersion
    }
    func withdrawConsent() {
        defaults.removeObject(forKey: "acceptedPolicyVersion")
        defaults.removeObject(forKey: "acceptedPolicyAt")
        acceptedAt = nil; acceptedPolicyVersion = nil
        withdrawPairingConsent()
    }
    func acceptPairingConsent() {
        guard hasConsent else { return }
        defaults.set(Self.policyVersion, forKey: "pairingConsentVersion")
        pairingConsentVersion = Self.policyVersion
    }
    func withdrawPairingConsent() {
        defaults.removeObject(forKey: "pairingConsentVersion"); pairingConsentVersion = nil
    }
}

enum AppInformation {
    static let name = L10n.text("app.name")
    static let developer = "GotTal"
    static let contact = "xkstudio@icloud.com"
    static let repository = URL(string: "https://github.com/GotTal/Pawster")!
    static let feedback = URL(string: "https://github.com/GotTal/Pawster/issues")!
    static let email = URL(string: "mailto:xkstudio@icloud.com")!
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? L10n.text("app.developmentVersion")
        let build = info["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : L10n.text("app.versionAndBuild", [version, build])
    }
    static var channel: String? {
        guard let channel = Bundle.main.object(forInfoDictionaryKey: "PawsterBuildChannel") as? String else { return nil }
        return channel == "test" ? L10n.text("app.testBuild") : L10n.text("app.releaseBuild")
    }
    static var revision: String? {
        (Bundle.main.object(forInfoDictionaryKey: "PawsterSourceRevision") as? String).map { String($0.prefix(7)) }
    }
}

enum PairingDataRemoval {
    static func remove(in root: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files {
            let name = file.lastPathComponent
            let pendingID = name.hasPrefix("pairing-") && name.hasSuffix(".pending.plist") ?
                UInt64(name.dropFirst(8).dropLast(14)) : nil
            let pending = pendingID.map { name == "pairing-\($0).pending.plist" } ?? false
            if name == "pairing.plist" || pending {
                let type = try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeSymbolicLink else {
                    throw BridgeError.message(L10n.text("error.credentialType"))
                }
                try fm.removeItem(at: file)
            }
        }
    }
}
