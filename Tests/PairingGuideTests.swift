import XCTest
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
@testable import Pawster

final class PairingGuideTests: XCTestCase {
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
        XCTAssertEqual(guide.content.result, "✓ 配对成功")
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
        XCTAssertNil(guide.content.code); XCTAssertEqual(guide.content.result, "配对未完成")
        XCTAssertFalse(guide.content.succeeded)
        for _ in 0..<40 {
            if stopped { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(stopped); XCTAssertEqual(guide.phase, .idle)
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
