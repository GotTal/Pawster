import Foundation
import AVFAudio
import Network
import Combine
import UIKit

@MainActor
final class PairingService: NSObject, ObservableObject {
    let guide = PairingGuide()
    @Published private(set) var running = false
    @Published private(set) var pin: String?
    @Published private(set) var status = "尚未开始配对"
    @Published private(set) var remaining = 0
    @Published private(set) var hasCredentials = false
    let hostName = "Pawster"
    private var service: NetService?
    private var operation: UInt64?
    private var countdown: Timer?
    private let keepAlive = PairingAudio()
    private var cancelled = false
    private var timedOut = false
    private var copiedPIN: String?

    override init() { super.init(); hasCredentials = FileManager.default.fileExists(atPath: AppFiles.pairing.path) }
    func importCredentials(_ source: URL) throws {
        guard !running else { throw BridgeError.message("请先结束当前配对。") }
        try AppFiles.prepare()
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard !data.isEmpty, data.count <= 1024 * 1024,
              (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else { throw BridgeError.message("配对文件为空、过大或不是有效 plist。") }
        try saveCredentials(data)
        hasCredentials = true; status = "已导入；请通过路径查询验证凭据和 VPN。"
    }
    func start() {
        guard !running else { return }
        guard SystemVersion.current.major >= 27 else { status = "旧版系统请导入 SideStore 等工具导出的配对文件。"; return }
        do { try AppFiles.prepare() } catch { status = error.localizedDescription; return }
        running = true; cancelled = false; timedOut = false; pin = nil; remaining = 180
        status = "正在启动；若弹出本地网络权限，请允许。"
        guide.begin(); updateGuide()
        let id = pb_operation_new(); operation = id
        let output = AppFiles.root.appendingPathComponent("pairing-\(id).pending.plist")
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
        status = "正在取消配对…"
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
        guard !cancelled else { status = timedOut ? "配对超时，请重试或导入现有配对文件。" : "配对已取消"; return }
        guard rc == 0 else { status = error?.contains("timed out") == true ? "配对超时，请重试或导入现有配对文件。" : "配对失败：\(error ?? "未知错误")"; return }
        do {
            let data = try Data(contentsOf: pending)
            guard !data.isEmpty, data.count <= 1024 * 1024 else { throw BridgeError.message("返回的配对文件无效。") }
            try saveCredentials(data)
            if let irk { UserDefaults.standard.set(irk, forKey: "hostAltIRK") }
            hasCredentials = true; succeeded = true; status = "配对成功，请返回 App 查询壁纸路径。"
        } catch { status = error.localizedDescription }
    }
    fileprivate func advertise(id: String, port: Int32, txt: [String: Data]) {
        guard running, !cancelled else { return }
        service?.stop()
        let value = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: id, port: port)
        value.setTXTRecord(NetService.data(fromTXTRecord: txt)); value.publish(); service = value
        status = "前往 设置 → 隐私与安全性 → 开发者模式，选择与 Pawster 配对。"
        updateGuide()
    }
    fileprivate func showPIN(_ code: String) {
        guard running, !cancelled, code.count == 6, code.allSatisfy(\.isNumber) else { return }
        pin = code; status = "请在系统配对页面输入小窗中的六位配对码。"
        updateGuide()
    }
    private func updateGuide() { guide.update(pin: pin, status: status, seconds: remaining) }
    func copyPIN() {
        guard let pin else { return }
        copiedPIN = pin
        UIPasteboard.general.setItems([["public.utf8-plain-text": pin]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(TimeInterval(max(1, remaining)))])
    }
    private func clearPIN() {
        if let copiedPIN, UIPasteboard.general.string == copiedPIN { UIPasteboard.general.items = [] }
        copiedPIN = nil; pin = nil
    }
    private func saveCredentials(_ data: Data) throws {
        try data.write(to: AppFiles.pairing, options: .atomic)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: AppFiles.pairing.path)
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
    func find(host: String, token: CancellationToken? = nil) throws -> String {
        let id = pb_operation_new()
        lock.lock(); active = id; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock(); pb_operation_free(id) }
        try token?.check()
        var output: UnsafeMutablePointer<CChar>?; var failure: UnsafeMutablePointer<CChar>?
        let rc = pb_find_container(id, 35, AppFiles.pairing.path, host, &output, &failure)
        defer { pb_string_free(output); pb_string_free(failure) }
        guard rc == 0, let output else {
            let detail = failure.map { String(cString: $0) } ?? "未返回诊断信息。"
            if detail == "Cancelled" { throw CancellationError() }
            throw BridgeError.message("未能查询壁纸路径，请检查配对文件、LocalDevVPN 和设备解锁状态。\n诊断：\(detail)")
        }
        return try ContainerPath.normalize(String(cString: output))
    }
}
