// Interface and UDP route-source inspection adapted from AirCard-iOS NetworkStatus.swift,
// commit 40640c4d (MIT notice: ThirdParty/AirCard-MIT.txt; upstream notes SideInstaller ancestry).
// No probe packets are sent.
import Foundation
import Darwin
import Combine

enum VPNAddress {
    static let defaultPeer = "10.7.0.1"
    static func value(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = UInt8(part), String(number) == part else { return nil }
            result = result << 8 | UInt32(number)
        }
        return result
    }
    static func normalizedPeer(_ text: String) throws -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let ip = value(text),
              ip & 0xFF00_0000 == 0x0A00_0000 || ip & 0xFFF0_0000 == 0xAC10_0000 || ip & 0xFFFF_0000 == 0xC0A8_0000 else {
            throw BridgeError.message(L10n.text("vpn.invalidPeer"))
        }
        return text
    }
}

struct VPNInterface: Equatable, Sendable {
    let name: String
    let ip: String
    let netmask: String?
    let destination: String?
    let active: Bool
    var isTunnel: Bool { ["utun", "ipsec", "tap", "ppp"].contains { name.hasPrefix($0) } }
}

struct VPNStatusSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable { case unchecked, connected, disconnected, unavailable }
    let state: State
    let peerIP: String
    let interfaceIP: String?
    let interfaceName: String?
    static func unchecked(peer: String = VPNAddress.defaultPeer) -> Self {
        .init(state: .unchecked, peerIP: peer, interfaceIP: nil, interfaceName: nil)
    }
}

enum VPNInspection {
    static func automaticPeer(in interfaces: [VPNInterface]) -> String {
        let candidates = interfaces.filter { $0.active && $0.isTunnel && $0.ip.hasPrefix("10.7.0.") }.sorted { $0.name < $1.name }
        guard let local = candidates.first else { return VPNAddress.defaultPeer }
        if let peer = local.destination, peer != local.ip,
           let validated = try? VPNAddress.normalizedPeer(peer) { return validated }
        return local.ip == VPNAddress.defaultPeer ? "10.7.0.2" : VPNAddress.defaultPeer
    }
    static func summarize(interfaces: [VPNInterface], peer: String, routeSource: String?) -> VPNStatusSnapshot {
        // A corporate/ad-blocking utun alone is not evidence of a route to this peer.
        let match = interfaces.first { $0.active && $0.isTunnel && $0.ip == routeSource }
        return .init(state: match == nil ? .disconnected : .connected, peerIP: peer,
                     interfaceIP: match?.ip, interfaceName: match?.name)
    }
    static func read(override: String?) -> VPNStatusSnapshot {
        guard let interfaces = interfaces() else {
            return .init(state: .unavailable, peerIP: override ?? VPNAddress.defaultPeer, interfaceIP: nil, interfaceName: nil)
        }
        let peer = override ?? automaticPeer(in: interfaces)
        return summarize(interfaces: interfaces, peer: peer, routeSource: routeSource(to: peer))
    }
    private static func numericHost(_ address: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer,
                          socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer)
    }
    private static func interfaces() -> [VPNInterface]? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { if let list { freeifaddrs(list) } }
        var result: [VPNInterface] = []; var cursor = list
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let entry = item.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let ip = numericHost(UnsafePointer(address)) else { continue }
            let flags = entry.ifa_flags
            let destination = flags & UInt32(IFF_POINTOPOINT) != 0 ? entry.ifa_dstaddr.flatMap {
                $0.pointee.sa_family == sa_family_t(AF_INET) ? numericHost(UnsafePointer($0)) : nil
            } : nil
            result.append(.init(name: String(cString: entry.ifa_name), ip: ip,
                netmask: entry.ifa_netmask.flatMap { numericHost(UnsafePointer($0)) }, destination: destination,
                active: flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0))
        }
        return result
    }
    private static func routeSource(to peer: String) -> String? {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET); target.sin_port = UInt16(9).bigEndian
        guard peer.withCString({ inet_pton(AF_INET, $0, &target.sin_addr) }) == 1 else { return nil }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let result = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { return nil }
        var source = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &source) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0, source.sin_addr.s_addr != 0 else { return nil }
        return withUnsafePointer(to: &source) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1, numericHost) }
    }
}

@MainActor
final class LocalVPNMonitor: ObservableObject {
    @Published private(set) var snapshot = VPNStatusSnapshot.unchecked()
    @Published private(set) var overridePeerIP: String?
    private let defaults: UserDefaults
    private let inspect: @Sendable (String?) -> VPNStatusSnapshot
    private var generation = UUID()
    var peerIP: String { overridePeerIP ?? snapshot.peerIP }
    var allowsFallbacks: Bool { overridePeerIP == nil }
    init(defaults: UserDefaults = .standard, inspect: @escaping @Sendable (String?) -> VPNStatusSnapshot = VPNInspection.read) {
        self.defaults = defaults; self.inspect = inspect
        let saved = defaults.string(forKey: "overridePeerIP") ?? defaults.string(forKey: "gateway")
        // The previous default gateway represents automatic selection, not a user override.
        overridePeerIP = saved.flatMap { $0 == VPNAddress.defaultPeer ? nil : try? VPNAddress.normalizedPeer($0) }
        if let explicit = defaults.string(forKey: "overridePeerIP") {
            overridePeerIP = try? VPNAddress.normalizedPeer(explicit)
        }
        snapshot = .unchecked(peer: overridePeerIP ?? VPNAddress.defaultPeer)
    }
    func setOverride(_ text: String) throws {
        let value = try VPNAddress.normalizedPeer(text)
        generation = UUID(); overridePeerIP = value
        defaults.set(value ?? "", forKey: "overridePeerIP")
        snapshot = .unchecked(peer: value ?? VPNAddress.defaultPeer)
    }
    func resetStatus() { generation = UUID(); snapshot = .unchecked(peer: overridePeerIP ?? VPNAddress.defaultPeer) }
    func refresh() async {
        let id = UUID(); generation = id
        let selected = overridePeerIP; let inspect = inspect
        let result = await Task.detached(priority: .utility) { inspect(selected) }.value
        guard !Task.isCancelled, generation == id, overridePeerIP == selected else { return }
        snapshot = result
    }
}
