import AppKit
import XCTest
@testable import AerialDrop

final class VideoPreviewTests: XCTestCase {
    private func makeImage(color: NSColor, size: Int = 64) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    func testNearlyBlackFrameIsNotMeaningfullyVisible() {
        let image = makeImage(color: NSColor(calibratedWhite: 0.05, alpha: 1))
        XCTAssertFalse(VideoPreview.isMeaningfullyVisible(image))
    }

    func testBrightFrameIsMeaningfullyVisible() {
        let image = makeImage(color: .white)
        XCTAssertTrue(VideoPreview.isMeaningfullyVisible(image))
    }

    func testMixedFrameWithEnoughBrightContentIsMeaningfullyVisible() {
        // Left half dark, right half bright: ~50% bright pixels.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSColor.white.setFill()
        NSRect(x: 32, y: 0, width: 32, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        XCTAssertTrue(VideoPreview.isMeaningfullyVisible(rep.cgImage!))
    }

    func testMostlyDarkFrameIsNotMeaningfullyVisible() {
        // Tiny bright patch on black: ~1.5% bright pixels.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSColor.white.setFill()
        NSRect(x: 30, y: 30, width: 4, height: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        XCTAssertFalse(VideoPreview.isMeaningfullyVisible(rep.cgImage!))
    }
}
