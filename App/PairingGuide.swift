import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo

@MainActor
final class PairingGuide: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    @Published private(set) var active = false
    @Published private(set) var note = "小窗需在实机上验证；若无法开启，可在 App 内查看相同步骤。"
    let layer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    private var lines: [String] = ["设置 → 隐私与安全性", "开发者模式 → 与 Pawster 配对", "等待系统开始配对…"]
    private var frame: Int64 = 0
    private var wanted = false
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
            pip = AVPictureInPictureController(contentSource: source); pip?.delegate = self
            pip?.requiresLinearPlayback = true
            observation = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.startIfReady() }
            }
        } else { note = "此设备暂不支持画中画引导，请使用应用内步骤。" }
    }
    func update(pin: String?, status: String, seconds: Int) {
        lines = ["设置 → 隐私与安全性 → 开发者模式", "点击「与 Pawster 配对」", pin.map { "配对码  \($0)" } ?? "等待系统生成配对码", "剩余 \(seconds) 秒 · \(status)"]
        render()
    }
    func prepare() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.render() } }
        RunLoop.main.add(timer!, forMode: .common); render()
    }
    func start() { prepare(); wanted = true; startIfReady() }
    private func startIfReady() {
        guard wanted, let pip else { return }
        if pip.isPictureInPicturePossible { wanted = false; pip.startPictureInPicture() }
        else { note = "正在准备小窗；请保持引导卡片可见。如未出现，可返回 App 查看配对码。" }
    }
    func stop() {
        wanted = false; pip?.stopPictureInPicture(); timer?.invalidate(); timer = nil; active = false
        lines = ["配对会话已结束", "配对码已清除", "请返回 Pawster 查看结果"]
        layer.flushAndRemoveImage()
        render()
    }
    private func render() {
        let width = 960, height = 540
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ("Pawster · 配对引导" as NSString).draw(at: CGPoint(x: 44, y: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.systemMint])
            for (index, line) in lines.enumerated() {
                let isCode = index == 2
                (line as NSString).draw(in: CGRect(x: 44, y: 110 + index * 95, width: 872, height: 85), withAttributes: [
                    .font: isCode ? UIFont.monospacedDigitSystemFont(ofSize: 62, weight: .bold) : UIFont.systemFont(ofSize: index == 3 ? 24 : 32),
                    .foregroundColor: isCode ? UIColor.white : UIColor.lightGray])
            }
        }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel) == kCVReturnSuccess,
              let pixel, let cgImage = image.cgImage else { return }
        CVPixelBufferLockBaseAddress(pixel, []); defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format) == noErr, let format else { return }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2), presentationTimeStamp: CMTime(value: frame, timescale: 2), decodeTimeStamp: .invalid)
        frame += 1
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary], let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = kCFBooleanTrue
        }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sample)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { active = true; note = "小窗已开启，可前往系统设置。" }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { active = false }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) { active = false; wanted = false; note = "小窗未能启动，请使用应用内步骤：\(error.localizedDescription)" }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }
}

struct GuidePreview: UIViewRepresentable {
    let guide: PairingGuide
    final class Surface: UIView {
        var display: AVSampleBufferDisplayLayer?
        override func layoutSubviews() { super.layoutSubviews(); display?.frame = bounds }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface(); view.display = guide.layer; view.layer.addSublayer(guide.layer); guide.prepare(); return view
    }
    func updateUIView(_ uiView: Surface, context: Context) { uiView.setNeedsLayout() }
}
