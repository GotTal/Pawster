import XCTest
@testable import Pawster

final class TestWirelessLANObserver: WirelessLANObserving {
    private var update: WirelessLANUpdate?
    private(set) var starts = 0
    private(set) var cancellations = 0
    func start(update: @escaping WirelessLANUpdate) { starts += 1; self.update = update }
    // Retain the callback deliberately to exercise late system callbacks after cancellation.
    func cancel() { cancellations += 1 }
    @MainActor func emit(_ state: WirelessLANState) { update?(state) }
}

final class WirelessLANTests: XCTestCase {
    private func settings() -> (String, UserDefaults) {
        let name = "Pawster.WirelessLAN.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }
    private static let connectedVPN: @Sendable (String?) -> VPNStatusSnapshot = { peer in
        .init(state: .connected, peerIP: peer ?? "10.7.0.1", interfaceIP: "10.7.0.2", interfaceName: "utun3")
    }

    @MainActor
    func testObservationStartsOnlyOnRefreshAndIsReusedAcrossPolling() async {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let observer = TestWirelessLANObserver()
        let monitor = LocalVPNMonitor(defaults: defaults, inspect: Self.connectedVPN, makeWirelessObserver: { observer })
        XCTAssertEqual(observer.starts, 0); XCTAssertEqual(monitor.wirelessState, .unchecked)
        await monitor.refresh(); await monitor.refresh()
        XCTAssertEqual(observer.starts, 1)
        monitor.resetStatus()
        XCTAssertEqual(observer.cancellations, 1); XCTAssertEqual(monitor.wirelessState, .unchecked)
    }

    @MainActor
    func testVPNRouteDoesNotImplyWirelessLANAndPeerChangesPreserveWirelessState() async throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let observer = TestWirelessLANObserver()
        let monitor = LocalVPNMonitor(defaults: defaults, inspect: Self.connectedVPN, makeWirelessObserver: { observer })
        await monitor.refresh(); observer.emit(.disconnected)
        XCTAssertEqual(monitor.snapshot.state, .connected)
        XCTAssertEqual(monitor.wirelessState, .disconnected)
        observer.emit(.connected); try monitor.setOverride("192.168.2.1")
        XCTAssertEqual(monitor.snapshot.state, .unchecked)
        XCTAssertEqual(monitor.wirelessState, .connected)
    }

    @MainActor
    func testLateCallbacksCannotRestoreStatusAfterStoppingOrDuringANewSession() async {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let old = TestWirelessLANObserver(); let current = TestWirelessLANObserver()
        var next = old
        let monitor = LocalVPNMonitor(defaults: defaults, inspect: Self.connectedVPN, makeWirelessObserver: { next })
        await monitor.refresh(); old.emit(.connected)
        monitor.resetStatus(); old.emit(.connected)
        XCTAssertEqual(monitor.wirelessState, .unchecked)
        next = current; await monitor.refresh(); old.emit(.connected)
        XCTAssertEqual(monitor.wirelessState, .unchecked)
        current.emit(.unavailable)
        XCTAssertEqual(monitor.wirelessState, .unavailable)
        XCTAssertEqual(old.cancellations, 1); XCTAssertEqual(current.starts, 1)
    }
}
