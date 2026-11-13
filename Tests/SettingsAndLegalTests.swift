import XCTest
@testable import Pawster

final class SettingsAndLegalTests: XCTestCase {
    private func settings() -> (String, UserDefaults) {
        let name = "Pawster.Settings.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }
    @MainActor
    func testNoConsentOrOptionalDiagnosticLoggingByDefault() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
        XCTAssertNil(preferences.acceptedAt); XCTAssertEqual(preferences.effectiveLogLimit, 0)
        preferences.acceptPairingConsent()
        XCTAssertFalse(preferences.hasPairingConsent)
    }
    @MainActor
    func testConsentPersistsAndPairingIsSeparate() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let first = AppPreferences(defaults: defaults)
        first.acceptPolicies(risksAcknowledged: true)
        let second = AppPreferences(defaults: defaults)
        XCTAssertTrue(second.hasConsent); XCTAssertNotNil(second.acceptedAt)
        XCTAssertFalse(second.hasPairingConsent)
        second.acceptPairingConsent()
        XCTAssertTrue(AppPreferences(defaults: defaults).hasPairingConsent)
        second.withdrawPairingConsent()
        XCTAssertTrue(second.hasConsent)
        XCTAssertFalse(AppPreferences(defaults: defaults).hasPairingConsent)
    }
    @MainActor
    func testWithdrawalClearsBothConsentRecords() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let first = AppPreferences(defaults: defaults)
        first.acceptPolicies(risksAcknowledged: true); first.acceptPairingConsent(); first.withdrawConsent()
        let next = AppPreferences(defaults: defaults)
        XCTAssertFalse(next.hasConsent); XCTAssertFalse(next.hasPairingConsent)
        XCTAssertNil(next.acceptedAt)
        XCTAssertNil(defaults.object(forKey: "acceptedPolicyVersion"))
        XCTAssertNil(defaults.object(forKey: "acknowledgedRiskPolicyVersion"))
        XCTAssertNil(defaults.object(forKey: "pairingConsentVersion"))
    }
    @MainActor
    func testNewPolicyVersionRequiresRenewalWithoutSilentlyAccepting() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("older-policy", forKey: "acceptedPolicyVersion")
        defaults.set("older-policy", forKey: "pairingConsentVersion")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
        preferences.acceptPolicies(risksAcknowledged: true)
        XCTAssertTrue(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
    }
    @MainActor
    func testUncheckedRiskCannotGrantOrPersistConsent() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.acceptPolicies(risksAcknowledged: false))
        preferences.acceptPairingConsent()
        XCTAssertFalse(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
        XCTAssertNil(preferences.acceptedAt)
        for key in ["acceptedPolicyVersion", "acknowledgedRiskPolicyVersion", "acceptedPolicyAt", "pairingConsentVersion"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        XCTAssertFalse(AppPreferences(defaults: defaults).hasConsent)
    }
    @MainActor
    func testMatchingPolicyWithoutRiskAcknowledgementStaysLocked() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(AppPreferences.policyVersion, forKey: "acceptedPolicyVersion")
        defaults.set(AppPreferences.policyVersion, forKey: "pairingConsentVersion")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
        XCTAssertTrue(preferences.acceptPolicies(risksAcknowledged: true))
        XCTAssertTrue(AppPreferences(defaults: defaults).hasConsent)
        XCTAssertFalse(preferences.hasPairingConsent)
    }
    @MainActor
    func testOlderConsentRequiresNewExplicitRiskAcknowledgement() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        for key in ["acceptedPolicyVersion", "acknowledgedRiskPolicyVersion", "pairingConsentVersion"] {
            defaults.set("2026-11-12.2", forKey: key)
        }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasConsent); XCTAssertFalse(preferences.hasPairingConsent)
        XCTAssertFalse(preferences.acceptPolicies(risksAcknowledged: false))
        XCTAssertTrue(preferences.acceptPolicies(risksAcknowledged: true))
        let restored = AppPreferences(defaults: defaults)
        XCTAssertTrue(restored.hasConsent)
        XCTAssertEqual(restored.acknowledgedRiskPolicyVersion, AppPreferences.policyVersion)
        XCTAssertFalse(restored.hasPairingConsent)
    }
    @MainActor
    func testRiskAcknowledgementAloneCannotEnableOperations() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(AppPreferences.policyVersion, forKey: "acknowledgedRiskPolicyVersion")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasConsent); XCTAssertNil(preferences.acceptedAt)
        preferences.acceptPairingConsent()
        XCTAssertFalse(preferences.hasPairingConsent)
    }
    @MainActor
    func testInvalidPreferencesFallBackAndValidChoicesPersist() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(-1, forKey: "diagnosticLogLimit"); defaults.set("unsupported", forKey: "appearance")
        let first = AppPreferences(defaults: defaults)
        XCTAssertEqual(first.effectiveLogLimit, 0); XCTAssertEqual(first.appearance, .system)
        first.logLimit = 100; first.appearance = .dark
        let second = AppPreferences(defaults: defaults)
        XCTAssertEqual(second.effectiveLogLimit, 100); XCTAssertEqual(second.appearance, .dark)
    }
    func testCredentialCleanupPreservesWallpaperReceiptsAndUnrelatedFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let removed = ["pairing.plist", "pairing-1.pending.plist", "pairing-18446744073709551615.pending.plist"]
        let preserved = ["pack.json", "receipt.json", "source.tendies", "pairing-custom.pending.plist", "pairing-01.pending.plist", "pairing-1.pending.plist.backup"]
        for name in removed + preserved { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        try PairingDataRemoval.remove(in: root)
        for name in removed { XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(name).path)) }
        for name in preserved { XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8), name) }
        try PairingDataRemoval.remove(in: root)
    }
    func testCredentialCleanupRefusesToRecursivelyRemoveUnexpectedDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = root.appendingPathComponent("pairing.plist/keep")
        try fm.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: child)
        defer { try? fm.removeItem(at: root) }
        XCTAssertThrowsError(try PairingDataRemoval.remove(in: root))
        XCTAssertEqual(try String(contentsOf: child, encoding: .utf8), "keep")
    }
    @MainActor
    func testOfflinePolicyAndLicenseResourcesAreBundled() throws {
        for name in ["Terms", "Privacy", "OpenSourceNotices", "ThirdPartySources", "RustDependencies"] {
            let text = try XCTUnwrap(LegalDocuments.load(name), "Missing bundled document: " + name)
            XCTAssertFalse(text.isEmpty)
        }
        for name in ["Terms", "Privacy"] {
            let text = try XCTUnwrap(LegalDocuments.load(name))
            XCTAssertTrue(text.contains(AppPreferences.policyVersion))
            XCTAssertTrue(text.contains(AppInformation.contact))
        }
        for name in ["GPL-3.0", "AirCard-MIT", "RustLicenseNotices"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "txt"), "Missing license: " + name)
        }
    }
    func testLongLicenseChunkingPreservesEveryCharacter() {
        let content = String(repeating: "许可 👩🏽‍💻\nCopyright\n\n", count: 1200)
        let chunks = LegalDocuments.chunks(content, maximum: 97)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 97 })
        XCTAssertEqual(chunks.joined(), content)
        XCTAssertEqual(LegalDocuments.chunks(""), [])
    }
}
