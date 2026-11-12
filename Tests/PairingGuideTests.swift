import XCTest
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
@testable import Pawster

final class PairingGuideTests: XCTestCase {
    @MainActor
    private final class Presentation: PairingPictureInPicture {
        var isPictureInPictureActive = false
        var isPictureInPictureSuspended = false
        var isPictureInPicturePossible = true
        var canStartPictureInPictureAutomaticallyFromInline = false
        private(set) var stopRequests = 0
        private(set) var forcedEnds = 0
        func stopPictureInPicture() { stopRequests += 1 }
        func invalidatePlaybackState() {}
        func endGuidePresentation() {
            forcedEnds += 1
            isPictureInPictureActive = false; isPictureInPictureSuspended = false
            canStartPictureInPictureAutomaticallyFromInline = false
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The guide did not reach the expected lifecycle state within one second.")
    }

    @MainActor
    func testFrameContainsVisibleTextAndUsesImmediateHostClockPresentation() throws {
        let before = CMClockGetTime(CMClockGetHostTimeClock())
        let sample = try PairingGuideFrames.make(PairingGuideContent(code: "123456"))
        let pixel = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixel), kCVPixelFormatType_32BGRA)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(pixel))
        XCTAssertEqual(CVPixelBufferGetWidth(pixel), 960)
        XCTAssertEqual(CVPixelBufferGetHeight(pixel), 540)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        XCTAssertGreaterThanOrEqual(CMTimeCompare(timestamp, before), 0)
        XCTAssertLessThan(CMTimeGetSeconds(CMTimeSubtract(timestamp, before)), 5)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)) as NSArray
        let flags = try XCTUnwrap(attachments.firstObject as? NSDictionary)
        XCTAssertEqual(flags[kCMSampleAttachmentKey_DisplayImmediately] as? Bool, true)

        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        var bright = 0
        for y in 0..<540 {
            for x in 0..<960 {
                let offset = y * stride + x * 4
                if bytes[offset] > 190 && bytes[offset + 1] > 190 && bytes[offset + 2] > 190 { bright += 1 }
            }
        }
        XCTAssertGreaterThan(bright, 5000, "A valid sample buffer must contain visible instructions and PIN pixels, not a black frame.")
        let image = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(CIImage(cvPixelBuffer: pixel), from: CGRect(x: 0, y: 0, width: 960, height: 540)))
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = "Pairing guide with synthetic PIN"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testDisplayLayerReceivesAVisibleFrame() async throws {
        let guide = PairingGuide(enablePictureInPicture: false)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.layer.addSublayer(guide.layer)
        guide.layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        window.isHidden = false
        defer { guide.stop(); guide.layer.removeFromSuperlayer(); window.isHidden = true }
        guide.begin(); CATransaction.flush()
        for _ in 0..<40 {
            if guide.layer.isReadyForDisplay { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(guide.layer.isReadyForDisplay, "The actual AVSampleBufferDisplayLayer must display the frame.")
        XCTAssertNotEqual(guide.layer.sampleBufferRenderer.status, .failed)
    }

    @MainActor
    func testSuccessClearsPINBeforeClosingAndReleasesKeepAliveOnce() async throws {
        let guide = PairingGuide(completionDelay: .milliseconds(80), enablePictureInPicture: false)
        var stopped = 0
        guide.begin(); guide.update(pin: "123456", status: "输入配对码", seconds: 100)
        guide.finish(succeeded: true, message: "配对成功") { stopped += 1 }
        XCTAssertEqual(guide.phase, .succeeded)
        XCTAssertNil(guide.content.code)
        XCTAssertEqual(guide.content.result, L10n.text("guide.success"))
        XCTAssertEqual(stopped, 0, "Keep-alive must continue while the terminal frame is displayed.")
        let attachment = try successAttachment(guide.content); add(attachment)
        for _ in 0..<40 {
            if guide.phase == .idle { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(stopped, 1)
        guide.stop(); XCTAssertEqual(stopped, 1)
    }

    @MainActor
    func testNewSessionCannotBeClosedByPreviousSuccessTimer() async throws {
        let guide = PairingGuide(completionDelay: .milliseconds(60), enablePictureInPicture: false)
        var oldStopped = 0
        guide.begin(); guide.finish(succeeded: true, message: "成功") { oldStopped += 1 }
        guide.begin(); guide.update(pin: "654321", status: "新的配对会话", seconds: 180)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(oldStopped, 1)
        XCTAssertEqual(guide.phase, .pairing); XCTAssertEqual(guide.content.code, "654321")
        guide.stop()
    }

    @MainActor
    func testFailureAlsoClearsPINAndEndsPresentation() async throws {
        let guide = PairingGuide(completionDelay: .milliseconds(50), enablePictureInPicture: false)
        var stopped = false
        guide.begin(); guide.update(pin: "123456", status: "等待", seconds: 1)
        guide.finish(succeeded: false, message: "配对超时") { stopped = true }
        XCTAssertNil(guide.content.code); XCTAssertEqual(guide.content.result, L10n.text("guide.failure"))
        XCTAssertFalse(guide.content.succeeded)
        for _ in 0..<40 {
            if stopped { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(stopped); XCTAssertEqual(guide.phase, .idle)
    }

    @MainActor
    func testCloseWaitsForNativeStopInsteadOfReportingIdleImmediately() async throws {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .milliseconds(20), pictureInPicture: presentation)
        var released = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.update(pin: "123456", status: "Waiting", seconds: 60)
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        try await waitUntil { guide.closing }
        XCTAssertEqual(guide.phase, .succeeded); XCTAssertTrue(guide.active)
        XCTAssertNil(guide.content.code); XCTAssertEqual(released, 0)
        XCTAssertGreaterThan(presentation.stopRequests, 0)
        XCTAssertFalse(presentation.canStartPictureInPictureAutomaticallyFromInline)
        presentation.isPictureInPictureActive = false; guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertFalse(guide.active); XCTAssertFalse(guide.closing)
        XCTAssertEqual(released, 1)
        guide.stop(); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testReturningToAppClosesCompletedGuideWithoutWaitingForBackgroundDelay() {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .seconds(60), pictureInPicture: presentation)
        var released = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        guide.applicationDidBecomeActive()
        XCTAssertTrue(guide.closing); XCTAssertGreaterThan(presentation.stopRequests, 0)
        presentation.isPictureInPictureActive = false; guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testInlineSourceSurvivesUntilStopAnimationAcknowledgement() {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .seconds(60), pictureInPicture: presentation)
        var released = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        guide.applicationDidBecomeActive(); guide.presentationWillStop()
        presentation.isPictureInPictureActive = false
        guide.stop()
        XCTAssertTrue(guide.closing); XCTAssertEqual(guide.phase, .succeeded)
        XCTAssertEqual(released, 0); XCTAssertEqual(guide.content.result, L10n.text("guide.success"))
        guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testReturningToAppDoesNotEndOngoingPairing() {
        let presentation = Presentation()
        let guide = PairingGuide(pictureInPicture: presentation)
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.update(pin: "123456", status: "Waiting", seconds: 60)
        guide.applicationDidBecomeActive()
        XCTAssertEqual(guide.phase, .pairing); XCTAssertEqual(guide.content.code, "123456")
        XCTAssertFalse(guide.closing); XCTAssertEqual(presentation.stopRequests, 0)
        presentation.isPictureInPictureActive = false; guide.stop()
    }

    @MainActor
    func testLateNativeStartAfterCompletionStillReceivesStop() async throws {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .milliseconds(10), pictureInPicture: presentation)
        var released = 0
        guide.begin(); guide.presentationWillStart()
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        try await waitUntil { guide.closing }
        XCTAssertEqual(released, 0)
        let requests = presentation.stopRequests
        presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        XCTAssertGreaterThan(presentation.stopRequests, requests)
        XCTAssertTrue(guide.closing); XCTAssertNil(guide.content.code)
        presentation.isPictureInPictureActive = false; guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testMissingStopCallbackHasBoundedFallbackAndReleasesKeepAliveOnce() async throws {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .milliseconds(10), pictureInPicture: presentation,
                                 stopCheckInterval: .milliseconds(10), maximumStopChecks: 3)
        var released = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        try await waitUntil { guide.phase == .idle }
        XCTAssertEqual(presentation.forcedEnds, 1); XCTAssertFalse(presentation.isPictureInPictureActive)
        XCTAssertEqual(guide.note, L10n.text("error.guideStop")); XCTAssertEqual(released, 1)
        guide.presentationDidStop(); guide.stop(); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testSuspendedNativeWindowIsAlsoEnded() {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .seconds(60), pictureInPicture: presentation)
        var released = 0
        guide.begin(); presentation.isPictureInPictureSuspended = true
        guide.finish(succeeded: false, message: "Timed out") { released += 1 }
        guide.applicationDidBecomeActive()
        XCTAssertTrue(guide.closing); XCTAssertGreaterThan(presentation.stopRequests, 0)
        XCTAssertEqual(released, 0)
        presentation.isPictureInPictureSuspended = false; guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(released, 1)
    }

    @MainActor
    func testManualNativeCloseDuringSuccessDwellClearsInlinePreviewToo() {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .seconds(60), pictureInPicture: presentation)
        var released = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.finish(succeeded: true, message: "Success") { released += 1 }
        presentation.isPictureInPictureActive = false; guide.presentationDidStop()
        XCTAssertEqual(guide.phase, .idle); XCTAssertEqual(released, 1)
        XCTAssertNil(guide.content.result)
    }

    @MainActor
    func testNewPairingDuringNativeTeardownCannotBeClosedByOldRetryTask() async throws {
        let presentation = Presentation()
        let guide = PairingGuide(completionDelay: .milliseconds(20), pictureInPicture: presentation,
                                 stopCheckInterval: .milliseconds(10), maximumStopChecks: 3)
        var oldReleased = 0
        guide.begin(); presentation.isPictureInPictureActive = true; guide.presentationDidStart()
        guide.finish(succeeded: true, message: "Success") { oldReleased += 1 }
        guide.applicationDidBecomeActive(); XCTAssertTrue(guide.closing)
        guide.begin(); guide.update(pin: "654321", status: "New session", seconds: 180)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(guide.phase, .pairing); XCTAssertFalse(guide.closing)
        XCTAssertEqual(guide.content.code, "654321"); XCTAssertEqual(oldReleased, 1)
        guide.stop()
    }

    @MainActor
    private func successAttachment(_ content: PairingGuideContent) throws -> XCTAttachment {
        let sample = try PairingGuideFrames.make(content)
        let pixel = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        let cg = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(CIImage(cvPixelBuffer: pixel), from: CGRect(x: 0, y: 0, width: 960, height: 540)))
        let attachment = XCTAttachment(image: UIImage(cgImage: cg))
        attachment.name = "Pairing succeeded before automatic close"; attachment.lifetime = .keepAlways
        return attachment
    }
}
