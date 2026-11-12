import XCTest
@testable import Pawster

final class SetupProgressTests: XCTestCase {
    private func settings() -> UserDefaults {
        let name = "Pawster.Setup.Tests." + UUID().uuidString
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
    @MainActor
    func testNewUserStartsAtInstallationWithoutClaimingAnyPrerequisite() {
        let progress = SetupProgress(defaults: settings())
        XCTAssertEqual(progress.step, .install); XCTAssertTrue(progress.shouldAutoStart)
        XCTAssertFalse(progress.showing); XCTAssertFalse(progress.completed)
        XCTAssertFalse(progress.developerAcknowledged)
    }
    @MainActor
    func testVPNMustActuallyBeConnectedToAdvance() {
        let progress = SetupProgress(defaults: settings()); progress.start()
        XCTAssertTrue(progress.advance(vpnConnected: false))
        XCTAssertEqual(progress.step, .vpn)
        XCTAssertFalse(progress.advance(vpnConnected: false))
        XCTAssertEqual(progress.step, .vpn)
        XCTAssertTrue(progress.advance(vpnConnected: true))
        XCTAssertEqual(progress.step, .developer)
    }
    @MainActor
    func testDeveloperModeIsExplicitConfirmationNotAnAutomaticDetectionClaim() {
        let progress = SetupProgress(defaults: settings())
        progress.advance(vpnConnected: true); progress.advance(vpnConnected: true)
        XCTAssertFalse(progress.advance(vpnConnected: true)); XCTAssertEqual(progress.step, .developer)
        progress.acknowledgeDeveloper(true)
        XCTAssertTrue(progress.advance(vpnConnected: false))
        XCTAssertEqual(progress.step, .pairing, "A reboot can disconnect VPN; pairing completion rechecks it.")
    }
    @MainActor
    func testRestartRestoresStepAndAcknowledgementButNotAPresentedView() {
        let defaults = settings(), progress = SetupProgress(defaults: defaults)
        progress.start(); progress.advance(vpnConnected: true); progress.advance(vpnConnected: true)
        let beforeConfirmation = SetupProgress(defaults: defaults)
        XCTAssertEqual(beforeConfirmation.step, .developer); XCTAssertFalse(beforeConfirmation.developerAcknowledged)
        progress.acknowledgeDeveloper(true); progress.advance(vpnConnected: true)
        let restarted = SetupProgress(defaults: defaults)
        XCTAssertEqual(restarted.step, .pairing); XCTAssertTrue(restarted.developerAcknowledged)
        XCTAssertTrue(restarted.shouldAutoStart); XCTAssertFalse(restarted.showing)
    }
    @MainActor
    func testLaterSuppressesAutomaticPresentationAndManualEntryResumes() {
        let defaults = settings(), progress = SetupProgress(defaults: defaults)
        progress.start(); progress.advance(vpnConnected: false); progress.pause()
        let next = SetupProgress(defaults: defaults)
        XCTAssertFalse(next.shouldAutoStart); XCTAssertEqual(next.step, .vpn)
        next.start()
        XCTAssertTrue(next.showing); XCTAssertFalse(next.deferred); XCTAssertEqual(next.step, .vpn)
    }
    @MainActor
    func testCannotFinishWithoutCurrentVPNAndReadyCredentials() {
        let progress = SetupProgress(defaults: settings())
        progress.advance(vpnConnected: true); progress.advance(vpnConnected: true)
        progress.acknowledgeDeveloper(true); progress.advance(vpnConnected: true)
        XCTAssertFalse(progress.finish(vpnConnected: false, credentialReady: true))
        XCTAssertFalse(progress.finish(vpnConnected: true, credentialReady: false))
        XCTAssertFalse(progress.completed)
        XCTAssertTrue(progress.finish(vpnConnected: true, credentialReady: true))
    }
    @MainActor
    func testCannotSkipToCompletionFromAnotherStepOrWithoutAcknowledgement() {
        let defaults = settings(), progress = SetupProgress(defaults: defaults)
        XCTAssertFalse(progress.finish(vpnConnected: true, credentialReady: true))
        defaults.set("pairing", forKey: "setup.step")
        let restored = SetupProgress(defaults: defaults)
        XCTAssertFalse(restored.finish(vpnConnected: true, credentialReady: true))
    }
    @MainActor
    func testCompletionDoesNotReopenAutomaticallyAndGuideCanStillBeReviewed() {
        let defaults = settings(), progress = SetupProgress(defaults: defaults)
        progress.start(); progress.advance(vpnConnected: true); progress.advance(vpnConnected: true)
        progress.acknowledgeDeveloper(true); progress.advance(vpnConnected: true)
        XCTAssertTrue(progress.finish(vpnConnected: true, credentialReady: true))
        XCTAssertFalse(progress.showing)
        let next = SetupProgress(defaults: defaults)
        XCTAssertTrue(next.completed); XCTAssertFalse(next.shouldAutoStart)
        next.start(); XCTAssertTrue(next.showing)
        next.back(); XCTAssertEqual(next.step, .developer)
    }
    @MainActor
    func testInvalidSavedStepFallsBackAndBackCannotUnderflow() {
        let defaults = settings(); defaults.set("invalid", forKey: "setup.step")
        let progress = SetupProgress(defaults: defaults)
        XCTAssertEqual(progress.step, .install)
        progress.back(); XCTAssertEqual(progress.step.number, 1)
    }
    @MainActor
    func testGuideOnlyPersistsProgressFlagsAndDoesNotCreateConsentOrCredentials() {
        let defaults = settings(), progress = SetupProgress(defaults: defaults)
        progress.start(); progress.advance(vpnConnected: true); progress.pause()
        XCTAssertNil(defaults.object(forKey: "acceptedPolicyVersion"))
        XCTAssertNil(defaults.object(forKey: "pairingConsentVersion"))
        XCTAssertNil(defaults.object(forKey: "pin")); XCTAssertNil(defaults.object(forKey: "pairing.plist"))
        let keys = Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("setup.") })
        XCTAssertEqual(keys, ["setup.step", "setup.deferred"])
    }
    func testExternalLinksUseOfficialStoreIDAndOnlyOpenVPNWithoutEnablingIt() {
        XCTAssertEqual(SetupLinks.vpnStore.host, "apps.apple.com")
        XCTAssertEqual(SetupLinks.vpnStore.path, "/app/id6755608044")
        XCTAssertEqual(SetupLinks.vpnApp.scheme, "localdevvpn")
        XCTAssertTrue(SetupLinks.vpnApp.host?.isEmpty ?? true); XCTAssertNil(SetupLinks.vpnApp.query)
        XCTAssertEqual(SetupLinks.developerHelp.host, "developer.apple.com")
    }
}
