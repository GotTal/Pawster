import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo

struct PairingGuideContent: Equatable {
    var title = "Pawster · 配对引导"
    var instruction = "设置 → 隐私与安全性 → 开发者模式\n点击「与 Pawster 配对」"
    var code: String?
    var detail = "等待系统生成配对码"
    var footer = "离开 App 后自动显示小窗"
    var result: String?
    var succeeded = false
}

// CPU drawing into an IOSurface-backed BGRA buffer also works while Settings is foreground.
@MainActor
enum PairingGuideFrames {
    static let width = 960
    static let height = 540

    static func make(_ content: PairingGuideContent) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw BridgeError.message("无法创建小窗视频帧。") }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            throw BridgeError.message("无法写入小窗视频帧。")
        }
        // Unlock before the caller enqueues this buffer for display.
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw BridgeError.message("无法绘制小窗内容。")
        }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func text(_ value: String, y: CGFloat, height: CGFloat, font: UIFont, color: UIColor) {
            (value as NSString).draw(in: CGRect(x: 44, y: y, width: 872, height: height),
                                    withAttributes: [.font: font, .foregroundColor: color])
        }
        text(content.title, y: 28, height: 54, font: .boldSystemFont(ofSize: 36), color: .systemMint)
        text(content.instruction, y: 102, height: 92, font: .systemFont(ofSize: 30), color: .white)
        text(content.result ?? content.code ?? "等待配对码…", y: 218, height: 106,
             font: .monospacedDigitSystemFont(ofSize: content.code == nil ? 56 : 84, weight: .bold),
             color: content.succeeded ? .systemMint : .white)
        text(content.detail, y: 352, height: 88, font: .systemFont(ofSize: 27), color: .lightGray)
        text(content.footer, y: 474, height: 40, font: .systemFont(ofSize: 22), color: .lightGray)

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format) == noErr, let format else {
            throw BridgeError.message("无法创建小窗视频格式。")
        }
        // With no controlTimebase, AVFoundation uses the host clock, not a counter from zero.
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { throw BridgeError.message("无法提交小窗视频帧。") }
        // Mutate the original CF attachment dictionary. A Swift bridged copy may discard this flag.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { throw BridgeError.message("无法设置小窗显示标记。") }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        return sample
    }
}

@MainActor
final class PairingGuide: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    enum Phase: Equatable { case idle, pairing, succeeded, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var active = false
    @Published private(set) var note = "开始配对后，离开 App 将自动显示引导小窗。"
    private(set) var content = PairingGuideContent()
    let layer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    private var closeTask: Task<Void, Never>?
    private var completion: (() -> Void)?
    private var session = UUID()
    private let completionDelay: Duration
    private var frameReady = false
    private var renderObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?

    init(completionDelay: Duration = .seconds(3), enablePictureInPicture: Bool = true) {
        self.completionDelay = completionDelay
        super.init()
        layer.videoGravity = .resizeAspect
        layer.isOpaque = true
        layer.backgroundColor = UIColor.black.cgColor
        if enablePictureInPicture && AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
            pip = AVPictureInPictureController(contentSource: source)
            pip?.delegate = self
            pip?.requiresLinearPlayback = true
            renderObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateAutomaticStart() }
            }
            possibleObservation = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateAutomaticStart() }
            }
        } else { note = "此设备暂不支持自动小窗，请在应用内查看配对码。" }
    }

    func begin() {
        stop()
        session = UUID(); phase = .pairing; content = PairingGuideContent()
        render()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.render() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        updateAutomaticStart()
    }

    func update(pin: String?, status: String, seconds: Int) {
        guard phase == .pairing else { return }
        content.code = pin
        content.detail = "剩余 \(seconds) 秒 · \(status)"
        render()
    }

    func finish(succeeded: Bool, message: String, completion: @escaping () -> Void) {
        guard phase == .pairing else { completion(); return }
        phase = succeeded ? .succeeded : .failed
        self.completion = completion
        // Never leave the PIN in a terminal frame, including failures.
        content = PairingGuideContent(title: succeeded ? "Pawster · 配对完成" : "Pawster · 配对结束",
            instruction: succeeded ? "配对文件已安全保存" : "请返回 Pawster 检查配对结果", code: nil,
            detail: succeeded ? "3 秒后自动关闭小窗" : message,
            footer: succeeded ? "请返回 Pawster 查询壁纸路径" : "小窗即将自动关闭",
            result: succeeded ? "✓ 配对成功" : "配对未完成", succeeded: succeeded)
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        render(); pip?.invalidatePlaybackState()
        closeTask?.cancel()
        let current = session; let delay = completionDelay
        closeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.session == current else { return }
            self.stop()
        }
    }

    func stop() {
        session = UUID(); closeTask?.cancel(); closeTask = nil
        timer?.invalidate(); timer = nil
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        // Keep the last terminal frame until PiP has actually stopped; don't flush to black first.
        pip?.stopPictureInPicture()
        phase = .idle; active = false; frameReady = false; content = PairingGuideContent()
        let callback = completion; completion = nil; callback?()
    }

    func sourceDidLayout() {
        guard phase != .idle else { return }
        render(); updateAutomaticStart()
    }

    private func updateAutomaticStart() {
        let enabled = phase == .pairing && frameReady && layer.isReadyForDisplay
        pip?.canStartPictureInPictureAutomaticallyFromInline = enabled
        if enabled, pip?.isPictureInPicturePossible == true {
            setNote("引导画面已就绪，离开 App 后自动显示小窗；配对成功后显示 3 秒并自动关闭。")
        } else if phase == .pairing, pip != nil {
            setNote("正在准备自动小窗；若系统未弹出，请返回 App 查看配对码。")
        }
    }

    private func setNote(_ value: String) { if note != value { note = value } }

    private func render() {
        guard phase != .idle else { return }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            note = "小窗渲染曾失败：\(renderer.error?.localizedDescription ?? "未知错误")，正在恢复。"
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData else { return }
        do {
            let sample = try PairingGuideFrames.make(content)
            renderer.enqueue(sample); frameReady = true
            updateAutomaticStart()
        } catch { frameReady = false; note = "小窗画面生成失败：\(error.localizedDescription)" }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.phase == .idle { self.pip?.stopPictureInPicture(); return }
            self.active = true; self.render()
        }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.active = false
            if self.phase == .idle { self.layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil) }
        }
    }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.active = false; self?.note = "自动小窗未能启动，请返回 App 查看配对码：\(message)" }
    }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }
}

struct GuidePreview: UIViewRepresentable {
    let guide: PairingGuide
    final class Surface: UIView {
        weak var guide: PairingGuide?
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            guide?.layer.frame = bounds
            CATransaction.commit()
            if window != nil, !bounds.isEmpty { guide?.sourceDidLayout() }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface(); view.guide = guide
        view.layer.addSublayer(guide.layer); view.backgroundColor = .black
        return view
    }
    func updateUIView(_ uiView: Surface, context: Context) { uiView.setNeedsLayout() }
}
