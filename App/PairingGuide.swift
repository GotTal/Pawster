import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo
import Combine

@MainActor
protocol PairingPictureInPicture: AnyObject {
    var isPictureInPictureActive: Bool { get }
    var isPictureInPictureSuspended: Bool { get }
    var isPictureInPicturePossible: Bool { get }
    var canStartPictureInPictureAutomaticallyFromInline: Bool { get set }
    func stopPictureInPicture()
    func invalidatePlaybackState()
    func endGuidePresentation()
}

extension AVPictureInPictureController: PairingPictureInPicture {
    func endGuidePresentation() {
        canStartPictureInPictureAutomaticallyFromInline = false
        stopPictureInPicture()
        contentSource = nil
    }
}

struct PairingGuideContent: Equatable {
    var title = L10n.text("guide.title")
    var instruction = L10n.text("guide.instructions")
    var code: String?
    var detail = L10n.text("guide.waitingCode")
    var footer = ""
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
              let buffer else { throw BridgeError.message(L10n.text("error.guideBuffer")) }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            throw BridgeError.message(L10n.text("error.guideBufferWrite"))
        }
        // Unlock before the caller enqueues this buffer for display.
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw BridgeError.message(L10n.text("error.guideDraw"))
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
        text(content.result ?? content.code ?? L10n.text("guide.codePlaceholder"), y: 218, height: 106,
             font: .monospacedDigitSystemFont(ofSize: content.code == nil ? 56 : 84, weight: .bold),
             color: content.succeeded ? .systemMint : .white)
        text(content.detail, y: 352, height: 88, font: .systemFont(ofSize: 27), color: .lightGray)
        text(content.footer, y: 474, height: 40, font: .systemFont(ofSize: 22), color: .lightGray)

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format) == noErr, let format else {
            throw BridgeError.message(L10n.text("error.guideFormat"))
        }
        // With no controlTimebase, AVFoundation uses the host clock, not a counter from zero.
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { throw BridgeError.message(L10n.text("error.guideSubmit")) }
        // Mutate the original CF attachment dictionary. A Swift bridged copy may discard this flag.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { throw BridgeError.message(L10n.text("error.guideAttachment")) }
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
    @Published private(set) var closing = false
    @Published private(set) var note = ""
    private(set) var content = PairingGuideContent()
    let layer = AVSampleBufferDisplayLayer()
    private var pip: PairingPictureInPicture?
    private var nativeController: AVPictureInPictureController? { pip as? AVPictureInPictureController }
    private let injectedPictureInPicture: PairingPictureInPicture?
    private let enablePictureInPicture: Bool
    private var timer: Timer?
    private var closeTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var completion: (() -> Void)?
    private var session = UUID()
    private let completionDelay: Duration
    private let stopCheckInterval: Duration
    private let maximumStopChecks: Int
    private let clock = ContinuousClock()
    private var terminalDeadline: ContinuousClock.Instant?
    private var starting = false
    private var stopping = false
    private var frameReady = false
    private var renderObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?
    private var activeObservation: NSKeyValueObservation?
    private var foregroundObservation: AnyCancellable?

    init(completionDelay: Duration = .seconds(3), enablePictureInPicture: Bool = true,
         pictureInPicture: PairingPictureInPicture? = nil,
         stopCheckInterval: Duration = .milliseconds(250), maximumStopChecks: Int = 16) {
        self.completionDelay = completionDelay
        self.enablePictureInPicture = enablePictureInPicture
        self.injectedPictureInPicture = pictureInPicture
        self.stopCheckInterval = stopCheckInterval
        self.maximumStopChecks = max(1, maximumStopChecks)
        super.init()
        layer.videoGravity = .resizeAspect
        layer.isOpaque = true
        layer.backgroundColor = UIColor.black.cgColor
        configurePictureInPicture()
        foregroundObservation = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.applicationDidBecomeActive() }
            }
    }

    private func configurePictureInPicture() {
        if let injectedPictureInPicture { pip = injectedPictureInPicture; return }
        if enablePictureInPicture && AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
            let controller = AVPictureInPictureController(contentSource: source)
            pip = controller
            controller.delegate = self
            controller.requiresLinearPlayback = true
            renderObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateAutomaticStart() }
            }
            possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateAutomaticStart() }
            }
            activeObservation = controller.observe(\.isPictureInPictureActive, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.active = self.pip?.isPictureInPictureActive == true
                    if self.closing { self.checkForStoppedPresentation() }
                }
            }
        } else { note = L10n.text("guide.unavailable") }
    }

    func begin() {
        stop()
        // Retire an old controller before a new session can accept callbacks from it.
        if closing {
            nativeController?.delegate = nil
            pip?.endGuidePresentation()
            completeStop()
        }
        if injectedPictureInPicture == nil {
            nativeController?.delegate = nil
            pip?.endGuidePresentation()
            renderObservation = nil; possibleObservation = nil; activeObservation = nil; pip = nil
            configurePictureInPicture()
        }
        starting = false; stopping = false
        session = UUID(); phase = .pairing; content = PairingGuideContent()
        render()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        updateAutomaticStart()
    }

    func update(pin: String?, status: String, seconds: Int) {
        guard phase == .pairing else { return }
        content.code = pin
        content.detail = L10n.text("guide.remaining", [String(describing: seconds), String(describing: status)])
        render()
    }

    func finish(succeeded: Bool, message: String, completion: @escaping () -> Void) {
        guard phase == .pairing else { completion(); return }
        phase = succeeded ? .succeeded : .failed
        self.completion = completion
        // Never leave the PIN in a terminal frame, including failures.
        content = PairingGuideContent(title: succeeded ? L10n.text("guide.successTitle") : L10n.text("guide.endedTitle"),
            instruction: succeeded ? "" : L10n.text("guide.returnDetails"), code: nil,
            detail: succeeded ? "" : message,
            footer: succeeded ? L10n.text("guide.returnQuery") : "",
            result: succeeded ? L10n.text("guide.success") : L10n.text("guide.failure"), succeeded: succeeded)
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        render(); pip?.invalidatePlaybackState()
        closeTask?.cancel()
        terminalDeadline = clock.now.advanced(by: completionDelay)
        let current = session; let delay = completionDelay
        closeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.session == current else { return }
            self.stop()
        }
    }

    func stop() {
        closeTask?.cancel(); closeTask = nil; terminalDeadline = nil
        timer?.invalidate(); timer = nil
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        closing = true
        if content.code != nil {
            content.code = nil
            content.result = L10n.text("guide.failure")
            render()
        }
        checkForStoppedPresentation()
        guard closing, stopTask == nil else { return }
        let current = session, interval = stopCheckInterval, checks = maximumStopChecks
        stopTask = Task { @MainActor [weak self] in
            for _ in 0..<checks {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.session == current, self.closing else { return }
                self.checkForStoppedPresentation()
                if !self.closing { return }
            }
            guard let self, self.session == current, self.closing else { return }
            // Bound teardown even if AVKit drops a callback or stays in a start transition.
            self.note = L10n.text("error.guideStop")
            self.pip?.endGuidePresentation()
            self.starting = false
            self.completeStop()
        }
    }

    private var nativePresentationExists: Bool {
        starting || stopping || pip?.isPictureInPictureActive == true || pip?.isPictureInPictureSuspended == true
    }

    private func checkForStoppedPresentation() {
        guard closing else { return }
        active = pip?.isPictureInPictureActive == true
        if nativePresentationExists { pip?.stopPictureInPicture() }
        else { completeStop() }
    }

    private func completeStop() {
        session = UUID(); closeTask?.cancel(); closeTask = nil; stopTask?.cancel(); stopTask = nil
        terminalDeadline = nil; timer?.invalidate(); timer = nil
        starting = false; stopping = false
        phase = .idle; closing = false; frameReady = false; content = PairingGuideContent()
        active = pip?.isPictureInPictureActive == true
        if !nativePresentationExists {
            nativeController?.contentSource = nil
            layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
        let callback = completion; completion = nil; callback?()
    }

    private func tick() {
        if let terminalDeadline, clock.now >= terminalDeadline { stop(); return }
        render()
    }

    func applicationDidBecomeActive() {
        // Foreground recovery must not depend on a delayed background Task getting CPU time.
        if phase == .succeeded || phase == .failed || closing || (phase == .idle && nativePresentationExists) {
            stop()
        }
    }

    func sourceDidLayout() {
        guard phase != .idle else { return }
        render(); updateAutomaticStart()
    }

    private func updateAutomaticStart() {
        let enabled = phase == .pairing && !closing && !stopping && frameReady && layer.isReadyForDisplay
        pip?.canStartPictureInPictureAutomaticallyFromInline = enabled
        if enabled, pip?.isPictureInPicturePossible == true {
            setNote("")
        }
    }

    private func setNote(_ value: String) { if note != value { note = value } }

    private func render() {
        guard phase != .idle else { return }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            note = L10n.text("error.guideDisplay", [String(describing: renderer.error?.localizedDescription ?? L10n.text("error.unknown"))])
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData else { return }
        do {
            let sample = try PairingGuideFrames.make(content)
            renderer.enqueue(sample); frameReady = true
            updateAutomaticStart()
        } catch { frameReady = false; note = L10n.text("error.guideFrame", [String(describing: error.localizedDescription)]) }
    }

    func presentationWillStart() {
        if phase != .idle || closing { starting = true }
    }
    func presentationWillStop() {
        guard phase != .idle || closing else { return }
        stopping = true; pip?.canStartPictureInPictureAutomaticallyFromInline = false
    }
    func presentationDidStart() {
        starting = false; active = pip?.isPictureInPictureActive == true
        if closing || phase == .idle { stop() }
        else { render() }
    }
    func presentationDidStop() {
        starting = false; stopping = false; active = pip?.isPictureInPictureActive == true
        if closing { checkForStoppedPresentation() }
        else if phase == .succeeded || phase == .failed || phase == .idle { stop() }
    }
    private enum PresentationEvent: Sendable { case willStart, didStart, willStop, didStop, failed(String) }
    nonisolated private func receive(_ event: PresentationEvent, from controller: AVPictureInPictureController) {
        let identity = ObjectIdentifier(controller)
        Task { @MainActor [weak self] in
            guard let self, let current = self.nativeController, ObjectIdentifier(current) == identity else { return }
            switch event {
            case .willStart: self.presentationWillStart()
            case .didStart: self.presentationDidStart()
            case .willStop: self.presentationWillStop()
            case .didStop: self.presentationDidStop()
            case .failed(let message):
                self.starting = false; self.stopping = false; self.active = false
                if self.phase != .idle || self.closing { self.note = L10n.text("error.guideStart", [String(describing: message)]) }
                if self.closing { self.checkForStoppedPresentation() }
            }
        }
    }
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) { receive(.willStart, from: controller) }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) { receive(.didStart, from: controller) }
    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) { receive(.willStop, from: controller) }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) { receive(.didStop, from: controller) }
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        receive(.failed(error.localizedDescription), from: controller)
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
    static func dismantleUIView(_ uiView: Surface, coordinator: ()) {
        if let guide = uiView.guide, guide.layer.superlayer === uiView.layer {
            guide.layer.removeFromSuperlayer()
        }
        uiView.guide = nil
    }
}
