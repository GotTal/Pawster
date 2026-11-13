import XCTest
@testable import Pawster

final class LocalVPNTests: XCTestCase {
    private func interface(_ name: String = "utun3", _ ip: String = "10.7.0.2", active: Bool = true, peer: String? = nil) -> VPNInterface {
        .init(name: name, ip: ip, netmask: "255.255.255.0", destination: peer, active: active)
    }
    private func settings() -> (String, UserDefaults) {
        let name = "Pawster.VPN.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }
    func testOverrideAcceptsCanonicalPrivateIPv4AndBlank() throws {
        for ip in ["10.7.0.1", "172.16.0.1", "172.31.255.254", "192.168.3.1"] {
            XCTAssertEqual(try VPNAddress.normalizedPeer(" " + ip + "\n"), ip)
        }
        XCTAssertNil(try VPNAddress.normalizedPeer(" \n"))
        for ip in ["127.0.0.1", "0.0.0.0", "8.8.8.8", "172.32.0.1", "255.255.255.255", "::1", "10.7.0.1:80", "10.7.0.1/24", "10.07.0.1", "10.7.0.999", "10.7.0.-1", "10.7.0.+1"] {
            XCTAssertThrowsError(try VPNAddress.normalizedPeer(ip), ip)
        }
    }
    func testUnrelatedTunnelDoesNotProduceConnectedBadge() {
        let interfaces = [interface("utun1", "10.20.0.2"), interface("en0", "192.168.1.4")]
        let state = VPNInspection.summarize(interfaces: interfaces, peer: "10.7.0.1", routeSource: "192.168.1.4")
        XCTAssertEqual(state.state, .disconnected); XCTAssertNil(state.interfaceIP)
    }
    func testRouteMustUseAnActiveTunnel() {
        let interfaces = [interface(active: false), interface("en0", "192.168.1.4")]
        for source in ["10.7.0.2", "192.168.1.4", "10.0.0.9"] {
            XCTAssertEqual(VPNInspection.summarize(interfaces: interfaces, peer: "10.7.0.1", routeSource: source).state, .disconnected)
        }
    }
    func testConnectedSnapshotUsesTheRoutedInterface() {
        let state = VPNInspection.summarize(interfaces: [interface("utun2", "10.20.0.2"), interface()], peer: "10.7.0.1", routeSource: "10.7.0.2")
        XCTAssertEqual(state.state, .connected); XCTAssertEqual(state.interfaceIP, "10.7.0.2")
        XCTAssertEqual(state.peerIP, "10.7.0.1"); XCTAssertEqual(state.interfaceName, "utun3")
    }
    func testAutomaticPeerPrefersPointToPointDestinationAndNeverItself() {
        XCTAssertEqual(VPNInspection.automaticPeer(in: [interface(peer: "10.7.0.9")]), "10.7.0.9")
        XCTAssertEqual(VPNInspection.automaticPeer(in: [interface(peer: "10.7.0.2")]), "10.7.0.1")
        XCTAssertEqual(VPNInspection.automaticPeer(in: [interface("utun1", "10.7.0.1")]), "10.7.0.2")
        XCTAssertEqual(VPNInspection.automaticPeer(in: [interface("utun1", "10.20.0.2")]), "10.7.0.1")
    }
    @MainActor
    func testOverridePersistsAndResetDoesNotRestoreLegacyGateway() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("192.168.1.2", forKey: "gateway")
        let monitor = LocalVPNMonitor(defaults: defaults)
        XCTAssertEqual(monitor.peerIP, "192.168.1.2"); XCTAssertFalse(monitor.allowsFallbacks)
        try monitor.setOverride("10.7.0.1")
        XCTAssertFalse(LocalVPNMonitor(defaults: defaults).allowsFallbacks)
        try monitor.setOverride("")
        XCTAssertTrue(LocalVPNMonitor(defaults: defaults).allowsFallbacks)
        XCTAssertEqual(LocalVPNMonitor(defaults: defaults).peerIP, "10.7.0.1")
    }
    @MainActor
    func testInvalidOverrideDoesNotReplaceSavedTarget() throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let monitor = LocalVPNMonitor(defaults: defaults)
        try monitor.setOverride("192.168.2.1")
        XCTAssertThrowsError(try monitor.setOverride("8.8.8.8"))
        XCTAssertEqual(monitor.peerIP, "192.168.2.1")
    }
    @MainActor
    func testRefreshUsesSavedOverrideWithoutProbingARealNetwork() async throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let monitor = LocalVPNMonitor(defaults: defaults, inspect: { peer in
            .init(state: .connected, peerIP: peer ?? "10.7.0.1", interfaceIP: "10.7.0.2", interfaceName: "utun3")
        })
        try monitor.setOverride("10.7.0.9"); await monitor.refresh()
        XCTAssertEqual(monitor.snapshot.peerIP, "10.7.0.9"); XCTAssertEqual(monitor.snapshot.state, .connected)
        monitor.resetStatus(); XCTAssertEqual(monitor.snapshot.state, .unchecked)
    }
    @MainActor
    func testAnOldRefreshCannotOverwriteAChangedOverride() async throws {
        let (name, defaults) = settings(); defer { defaults.removePersistentDomain(forName: name) }
        let started = expectation(description: "The old refresh has started inspecting its captured peer")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let monitor = LocalVPNMonitor(defaults: defaults, inspect: { peer in
            started.fulfill(); _ = release.wait(timeout: .now() + 30)
            return .init(state: .connected, peerIP: peer ?? "10.7.0.1", interfaceIP: "10.7.0.2", interfaceName: "utun3")
        })
        let refresh = Task { await monitor.refresh() }
        // Wait for the actual inspection, rather than assuming a utility task starts within a second.
        await fulfillment(of: [started], timeout: 15)
        try monitor.setOverride("192.168.2.1"); release.signal(); await refresh.value
        XCTAssertEqual(monitor.peerIP, "192.168.2.1")
        XCTAssertEqual(monitor.snapshot.state, .unchecked)
    }
}
