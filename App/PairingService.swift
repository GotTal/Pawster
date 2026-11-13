import Foundation
import AVFAudio
import Network
import Combine
import UIKit

@MainActor
final class PairingService: NSObject, ObservableObject {
    let guide: PairingGuide
    @Published private(set) var running = false
    @Published private(set) var pin: String?
    @Published private(set) var status = L10n.text("pairing.notStarted")
    @Published private(set) var remaining = 0
    @Published private(set) var credentialState: PairingCredentialState = .missing
    @Published private(set) var completedSuccessfully = false
    var hasCredentials: Bool { credentialState.hasCredentials }
    var supportsOnDevicePairing: Bool { PairingPolicy.supportsOnDevice(systemVersion) }
    private var initialStatus: String {
        !supportsOnDevicePairing && credentialState == .missing ? L10n.text("pairing.importRequired") : credentialState.initialStatus
    }
    var retainedCredentialsAfterAttempt: Bool { hasCredentials && attemptedPairing && !running && !completedSuccessfully }
    let hostName = "Pawster"
    private var service: NetService?
    private var operation: UInt64?
    private var countdown: Timer?
    private let keepAlive = PairingAudio()
    private var cancelled = false
    private var timedOut = false
    private var copiedPIN: String?
    private var attemptedPairing = false
    private let credentialsURL: URL
    private let systemVersion: SystemVersion
    private var allowCredentialInspection: Bool

    override convenience init() {
        self.init(credentialsURL: AppFiles.pairing, allowInspection: AppPreferences().hasPairingConsent)
    }
    init(credentialsURL: URL, enablePictureInPicture: Bool = true, allowInspection: Bool = true, systemVersion: SystemVersion = .current) {
        self.credentialsURL = credentialsURL
        self.systemVersion = systemVersion
        allowCredentialInspection = allowInspection
        guide = PairingGuide(enablePictureInPicture: enablePictureInPicture)
        super.init()
        credentialState = PairingCredentials.state(at: credentialsURL, allowInspection: allowInspection)
        status = initialStatus
    }
    func refreshCredentials(allowInspection: Bool) {
        allowCredentialInspection = allowInspection
        guard !running else { return }
        credentialState = PairingCredentials.state(at: credentialsURL, allowInspection: allowInspection)
        if !hasCredentials {
            completedSuccessfully = false; attemptedPairing = false; status = initialStatus
        } else if !completedSuccessfully && !attemptedPairing { status = initialStatus }
    }
    func importCredentials(_ source: URL) throws {
        guard !running else { throw BridgeError.message(L10n.text("error.pairingActive")) }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let data = try PairingCredentials.read(source)
        guard PairingCredentials.isSupported(data) else { throw BridgeError.message(L10n.text("error.pairingFileInvalid")) }
        try saveCredentials(data)
        credentialState = .ready; completedSuccessfully = false; attemptedPairing = false
        status = L10n.text("pairing.imported")
    }
    func start() {
        guard !running else { return }
        guard supportsOnDevicePairing else { status = L10n.text("pairing.importRequired"); return }
        completedSuccessfully = false; attemptedPairing = true
        do { try prepareStorage() } catch { status = error.localizedDescription; return }
        running = true; cancelled = false; timedOut = false; pin = nil; remaining = 180
        status = L10n.text("pairing.starting")
        guide.begin(); updateGuide()
        let id = pb_operation_new(); operation = id
        let output = credentialsURL.deletingLastPathComponent().appendingPathComponent("pairing-\(id).pending.plist")
        let name = hostName
        let irk = UserDefaults.standard.string(forKey: "hostAltIRK") ?? ""
        let contextAddress = UInt(bitPattern: Unmanaged.passRetained(self).toOpaque())
        keepAlive.start()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remaining = max(0, self.remaining - 1)
                if self.remaining == 0 { self.timedOut = true; self.cancel() }
                self.updateGuide()
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = UnsafeMutableRawPointer(bitPattern: contextAddress)!
            var result = PBPairResult()
            let rc = pb_pair(id, 180, name, output.path, irk, pairingReady, pairingPIN, ctx, &result)
            let error = result.error.map { String(cString: $0) }
            let returnedIRK = result.host_alt_irk_hex.map { String(cString: $0) }
            pb_pair_result_free(&result); pb_operation_free(id)
            DispatchQueue.main.async {
                let owner = Unmanaged<PairingService>.fromOpaque(UnsafeMutableRawPointer(bitPattern: contextAddress)!).takeRetainedValue()
                owner.finish(rc: rc, error: error, pending: output, irk: returnedIRK)
            }
        }
    }
    func cancel() {
        guard let operation else { return }
        cancelled = true; clearPIN(); service?.stop(); service = nil
        pb_operation_cancel(operation)
        status = L10n.text("pairing.cancelling")
        updateGuide()
        // Keep running true until Rust has dropped its listener and handshake future.
    }
    private func finish(rc: Int32, error: String?, pending: URL, irk: String?) {
        defer { try? FileManager.default.removeItem(at: pending) }
        operation = nil; service?.stop(); service = nil; countdown?.invalidate(); countdown = nil
        clearPIN(); running = false; remaining = 0
        var succeeded = false
        defer {
            guide.finish(succeeded: succeeded, message: status) { [weak self] in self?.keepAlive.stop() }
        }
        guard !cancelled else { status = timedOut ? L10n.text("pairing.timedOut") : L10n.text("pairing.cancelled"); return }
        guard rc == 0 else { status = error?.contains("timed out") == true ? L10n.text("pairing.timedOut") : L10n.text("pairing.failed", [String(describing: error ?? L10n.text("error.unknown"))]); return }
        do {
            let data = try PairingCredentials.read(pending)
            guard PairingCredentials.isSupported(data) else { throw BridgeError.message(L10n.text("error.pairingResultInvalid")) }
            try saveCredentials(data)
            if let irk { UserDefaults.standard.set(irk, forKey: "hostAltIRK") }
            credentialState = .ready; completedSuccessfully = true; succeeded = true
            status = L10n.text("pairing.success")
        } catch { status = error.localizedDescription }
    }
    fileprivate func advertise(id: String, port: Int32, txt: [String: Data]) {
        guard running, !cancelled else { return }
        service?.stop()
        let value = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: id, port: port)
        value.setTXTRecord(NetService.data(fromTXTRecord: txt)); value.publish(); service = value
        status = L10n.text("pairing.waiting")
        updateGuide()
    }
    fileprivate func showPIN(_ code: String) {
        guard running, !cancelled, code.count == 6, code.allSatisfy(\.isNumber) else { return }
        pin = code; status = L10n.text("pairing.enterCode")
        updateGuide()
    }
    private func updateGuide() { guide.update(pin: pin, status: status, seconds: remaining) }
    func copyPIN() {
        guard let pin else { return }
        copiedPIN = pin
        UIPasteboard.general.setItems([["public.utf8-plain-text": pin]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(TimeInterval(max(1, remaining)))])
    }
    func forgetCredentials() throws {
        guard !running else { throw BridgeError.message(L10n.text("error.pairingActive")) }
        guide.stop(); clearPIN()
        defer {
            credentialState = PairingCredentials.state(at: credentialsURL, allowInspection: allowCredentialInspection)
            if !hasCredentials { completedSuccessfully = false; attemptedPairing = false }
        }
        try PairingDataRemoval.remove(in: credentialsURL.deletingLastPathComponent())
        UserDefaults.standard.removeObject(forKey: "hostAltIRK")
        remaining = 0; status = L10n.text("pairing.removed")
    }
    private func clearPIN() {
        if let copiedPIN, UIPasteboard.general.string == copiedPIN { UIPasteboard.general.items = [] }
        copiedPIN = nil; pin = nil
    }
    private func saveCredentials(_ data: Data) throws {
        try prepareStorage()
        try data.write(to: credentialsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func prepareStorage() throws {
        if credentialsURL == AppFiles.pairing { try AppFiles.prepare() }
        else { try FileManager.default.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
    }
}

private let pairingReady: PBReadyCallback = { ctx, id, port, keys, values, count in
    guard let ctx, let id else { return }
    let owner = Unmanaged<PairingService>.fromOpaque(ctx).takeUnretainedValue()
    let serviceID = String(cString: id); var txt: [String: Data] = [:]
    if let keys, let values { for i in 0..<count { if let k = keys[i], let v = values[i] { txt[String(cString: k)] = Data(String(cString: v).utf8) } } }
    DispatchQueue.main.async { owner.advertise(id: serviceID, port: Int32(port), txt: txt) }
}
private let pairingPIN: PBPinCallback = { pin, ctx in
    guard let pin, let ctx else { return }
    let owner = Unmanaged<PairingService>.fromOpaque(ctx).takeUnretainedValue(); let code = String(cString: pin)
    DispatchQueue.main.async { owner.showPIN(code) }
}

@MainActor
private final class PairingAudio {
    private var player: AVAudioPlayer?
    func start() {
        // Bounded to the pairing session. Keeps Bonjour and the real-time PiP PIN updates alive.
        // 1 second mono PCM WAV, intentionally silent; no microphone access.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers]); try session.setActive(true)
            var data = Data("RIFF".utf8)
            func append<T: FixedWidthInteger>(_ value: T) { var x = value.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
            append(UInt32(16036)); data.append(Data("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
            append(UInt32(8000)); append(UInt32(16000)); append(UInt16(2)); append(UInt16(16)); data.append(Data("data".utf8)); append(UInt32(16000)); data.append(Data(repeating: 0, count: 16000))
            player = try AVAudioPlayer(data: data); player?.numberOfLoops = -1; player?.play()
        } catch { player = nil }
    }
    func stop() { player?.stop(); player = nil; try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
}

final class DeviceQuery: @unchecked Sendable {
    private let lock = NSLock(); private var active: UInt64?
    func cancel() { lock.lock(); defer { lock.unlock() }; if let active { pb_operation_cancel(active) } }
    func find(host: String, allowFallbacks: Bool = true, token: CancellationToken? = nil) throws -> String {
        let id = pb_operation_new()
        lock.lock(); active = id; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock(); pb_operation_free(id) }
        try token?.check()
        var output: UnsafeMutablePointer<CChar>?; var failure: UnsafeMutablePointer<CChar>?
        let rc = pb_find_container_with_policy(id, 35, AppFiles.pairing.path, host, allowFallbacks ? 1 : 0, &output, &failure)
        defer { pb_string_free(output); pb_string_free(failure) }
        guard rc == 0, let output else {
            let detail = failure.map { String(cString: $0) } ?? L10n.text("error.noDiagnostics")
            if detail == "Cancelled" { throw CancellationError() }
            throw BridgeError.message(L10n.text("error.pathQuery", [String(describing: detail)]))
        }
        return try ContainerPath.normalize(String(cString: output))
    }
}
