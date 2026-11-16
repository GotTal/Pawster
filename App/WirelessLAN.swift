import Foundation
import Network

enum WirelessLANState: Equatable, Sendable {
    case unchecked, connected, disconnected, unavailable
}

typealias WirelessLANUpdate = @MainActor @Sendable (WirelessLANState) -> Void

protocol WirelessLANObserving: AnyObject {
    func start(update: @escaping WirelessLANUpdate)
    func cancel()
}

/// Observe Wi-Fi independently of the default path, which may be a VPN tunnel.
/// This reads path availability only: no SSID, location, or internet probes.
final class WirelessLANPathObserver: WirelessLANObserving {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "org.xkstudio.Pawster.WirelessLAN", qos: .utility)

    func start(update: @escaping WirelessLANUpdate) {
        monitor.pathUpdateHandler = { path in
            let state: WirelessLANState
            switch path.status {
            case .satisfied: state = .connected
            case .requiresConnection: state = .disconnected
            case .unsatisfied:
                state = path.unsatisfiedReason == .wifiDenied || path.unsatisfiedReason == .localNetworkDenied ? .unavailable : .disconnected
            @unknown default: state = .unavailable
            }
            Task { @MainActor in update(state) }
        }
        monitor.start(queue: queue)
    }

    func cancel() { monitor.cancel() }
    deinit { monitor.cancel() }
}
