import XCTest
@testable import Pawster

final class NeoSpringControllerTests: XCTestCase {
    private func settings() -> (String, UserDefaults) {
        let name = "Pawster.NeoSpring.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }
    @MainActor
    func testAutomaticIsOptInAndPersistsUserChoice() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let first = NeoSpringController(defaults: defaults, isForeground: { true })
        XCTAssertFalse(first.automatic)
        first.requestAutomatic(true)
        XCTAssertFalse(first.automatic)
        XCTAssertFalse(first.confirmNotice(try XCTUnwrap(first.notice?.id)))
        XCTAssertTrue(first.automatic); XCTAssertNil(first.request)
        XCTAssertTrue(NeoSpringController(defaults: defaults, isForeground: { true }).automatic)
        first.requestAutomatic(false)
        XCTAssertFalse(NeoSpringController(defaults: defaults, isForeground: { true }).automatic)
    }
    @MainActor
    func testManualRefreshAlwaysNeedsConfirmationAndDoesNotStartAWebView() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        controller.requestManualRefresh()
        let id = try XCTUnwrap(controller.notice?.id)
        XCTAssertNil(controller.request)
        XCTAssertThrowsError(try controller.start { _ in XCTFail("Unconfirmed refresh must not start") })
        XCTAssertTrue(controller.confirmNotice(id))
        XCTAssertFalse(controller.confirmNotice(id))
        XCTAssertNil(controller.notice); XCTAssertFalse(controller.showingNotice)
        controller.requestManualRefresh(); XCTAssertNotNil(controller.notice)
    }
    @MainActor
    func testCancelledAutomaticNoticeCannotEnableRefreshLater() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        controller.requestAutomatic(true)
        let old = try XCTUnwrap(controller.notice?.id)
        controller.dismissNotice(); controller.requestAutomatic(true)
        XCTAssertFalse(controller.confirmNotice(old)); XCTAssertFalse(controller.automatic)
        controller.disableAutomatic(); XCTAssertNil(controller.notice)
        XCTAssertNil(defaults.string(forKey: "automaticNeoSpringNoticeVersion"))
    }
    @MainActor
    func testAcceptedAutomaticNoticeIsNotRepeatedAndLegacyChoiceRequiresNotice() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "automaticNeoSpring")
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        XCTAssertFalse(controller.automatic)
        controller.requestAutomatic(true)
        controller.confirmNotice(try XCTUnwrap(controller.notice?.id))
        controller.requestAutomatic(false); controller.requestAutomatic(true)
        XCTAssertTrue(controller.automatic); XCTAssertNil(controller.notice)
        defaults.set("old-version", forKey: "automaticNeoSpringNoticeVersion")
        XCTAssertFalse(NeoSpringController(defaults: defaults, isForeground: { true }).automatic)
    }
    @MainActor
    func testBackgroundDismissesPendingNoticeWithoutAccepting() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        controller.requestAutomatic(true); controller.didEnterBackground()
        XCTAssertFalse(controller.automatic); XCTAssertNil(controller.notice)
        XCTAssertFalse(controller.showingNotice)
    }
    @MainActor
    func testBackgroundRefusesToCreateSession() {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { false })
        var completed = false
        XCTAssertThrowsError(try controller.start { _ in completed = true })
        XCTAssertNil(controller.request); XCTAssertFalse(completed)
    }
    @MainActor
    func testDuplicateStartDoesNotReplaceCompletionAndCancelCompletesOnce() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        var outcomes: [NeoSpringOutcome] = []
        try controller.start { outcomes.append($0) }
        let id = try XCTUnwrap(controller.request?.id)
        XCTAssertThrowsError(try controller.start { _ in XCTFail("Duplicate start must not replace completion") })
        XCTAssertEqual(controller.request?.id, id)
        controller.cancel(); controller.cancel(); controller.complete(id, outcome: .ended)
        XCTAssertNil(controller.request); XCTAssertEqual(outcomes, [.cancelled])
    }
    @MainActor
    func testTimeoutEndsSessionWithoutRunningWebContent() async throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, timeout: .milliseconds(50), isForeground: { true })
        var outcomes: [NeoSpringOutcome] = []
        try controller.start { outcomes.append($0) }
        for _ in 0..<40 {
            if controller.request == nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(controller.request); XCTAssertEqual(outcomes, [.timedOut])
    }
    @MainActor
    func testOldCallbacksCannotEndNewSession() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, isForeground: { true })
        var outcomes: [NeoSpringOutcome] = []
        try controller.start { outcomes.append($0) }
        let old = try XCTUnwrap(controller.request?.id)
        controller.cancel()
        try controller.start { outcomes.append($0) }
        let current = try XCTUnwrap(controller.request?.id)
        controller.complete(old, outcome: .failed("late callback"))
        XCTAssertEqual(controller.request?.id, current)
        controller.complete(current, outcome: .ended)
        XCTAssertEqual(outcomes, [.cancelled, .ended])
    }
    @MainActor
    func testEnteringBackgroundCancelsPendingTimeout() async throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let controller = NeoSpringController(defaults: defaults, timeout: .milliseconds(50), isForeground: { true })
        var outcomes: [NeoSpringOutcome] = []
        try controller.start { outcomes.append($0) }
        controller.didEnterBackground()
        try await Task.sleep(for: .milliseconds(130))
        XCTAssertNil(controller.request); XCTAssertEqual(outcomes, [.interrupted])
    }
}
