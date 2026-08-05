import XCTest
@testable import AerialDrop

final class ConversionOptionsTests: XCTestCase {
    func testCropPanCenterIsZero() {
        XCTAssertEqual(
            cropPan(cropOffset: 0.5, sourceSize: CGSize(width: 3440, height: 1440), renderSize: CGSize(width: 1920, height: 1080)),
            0, accuracy: 0.001
        )
    }

    func testCropPanLeftAndRightClampToHalfTheExcess() {
        // scale = 1080/1440 = 0.75; excess = 3440*0.75 - 1920 = 660; half = 330
        let source = CGSize(width: 3440, height: 1440)
        let render = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: 0, sourceSize: source, renderSize: render), -330, accuracy: 0.001)
        XCTAssertEqual(cropPan(cropOffset: 1, sourceSize: source, renderSize: render), 330, accuracy: 0.001)
    }

    func testCropPanNonWideSourceIsZero() {
        let square = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: 0, sourceSize: square, renderSize: square), 0)
        XCTAssertEqual(cropPan(cropOffset: 1, sourceSize: square, renderSize: square), 0)
        XCTAssertEqual(cropPan(cropOffset: 0.5, sourceSize: square, renderSize: square), 0)
    }

    func testCropPanClampsOutOfRangeInput() {
        let source = CGSize(width: 3440, height: 1440)
        let render = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: -1, sourceSize: source, renderSize: render), -330, accuracy: 0.001)
        XCTAssertEqual(cropPan(cropOffset: 2, sourceSize: source, renderSize: render), 330, accuracy: 0.001)
    }

    func testBitrateBucketsByRenderHeightAndQuality() {
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1080), 8_000_000)
        XCTAssertEqual(bitrateBps(quality: .maximum, renderHeight: 1080), 18_000_000)
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1440), 12_000_000)
        XCTAssertEqual(bitrateBps(quality: .high, renderHeight: 1440), 18_000_000)
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 2160), 20_000_000)
        XCTAssertEqual(bitrateBps(quality: .maximum, renderHeight: 2160), 48_000_000)
        XCTAssertEqual(bitrateBps(quality: .high, renderHeight: 1600), 32_000_000) // ≥1600 → 2160 row
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1199), 8_000_000) // <1200 → 1080 row
    }

    func testClampedOutputHeightNeverUpscales() {
        XCTAssertEqual(clampedOutputHeight(nil, sourceHeight: 1440), 1440)
        XCTAssertEqual(clampedOutputHeight(nil, sourceHeight: 4320), 2160) // existing 4K cap
        XCTAssertEqual(clampedOutputHeight(1080, sourceHeight: 1440), 1080)
        XCTAssertEqual(clampedOutputHeight(2160, sourceHeight: 1080), 1080)
    }

    func testIsWiderThan16By9() {
        XCTAssertTrue(isWiderThan16By9(CGSize(width: 3440, height: 1440)))
        XCTAssertTrue(isWiderThan16By9(CGSize(width: 7680, height: 2160)))
        XCTAssertFalse(isWiderThan16By9(CGSize(width: 1920, height: 1080)))
        XCTAssertFalse(isWiderThan16By9(CGSize(width: 1000, height: 1000)))
    }

    func testNearestCropPreset() {
        XCTAssertEqual(nearestCropPreset(0), 0)
        XCTAssertEqual(nearestCropPreset(0.24), 0)
        XCTAssertEqual(nearestCropPreset(0.25), 0.5)
        XCTAssertEqual(nearestCropPreset(0.5), 0.5)
        XCTAssertEqual(nearestCropPreset(0.75), 0.5)
        XCTAssertEqual(nearestCropPreset(0.76), 1)
        XCTAssertEqual(nearestCropPreset(1), 1)
    }

    func testCropBandFractionsMatchEncodeWindow() {
        // 3440×1440: f = (16/9)/2.3889 = 0.7443
        let ultrawide = CGSize(width: 3440, height: 1440)
        // Center preset: box already shows the encode window -> no bands.
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).left, 0, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).right, 0, accuracy: 0.001)
        // Left preset: encode window [0, 0.744]; box [0.128, 0.872] -> right band 0.172.
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).left, 0, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).right, 0.172, accuracy: 0.001)
        // Right preset: left band 0.172.
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).left, 0.172, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).right, 0, accuracy: 0.001)
        // Quarter offset: window [0.064, 0.808] -> right band (0.872-0.808)/0.744 = 0.086.
        XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).left, 0, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).right, 0.086, accuracy: 0.001)
        // Out-of-range offsets clamp like cropPan.
        XCTAssertEqual(cropBandFractions(cropOffset: -1, sourceSize: ultrawide).right, 0.172, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 2, sourceSize: ultrawide).left, 0.172, accuracy: 0.001)
        // 32:9: f = 0.5; Left -> right band (0.75-0.5)/0.5 = 0.5 (half the box darkened).
        let superUltrawide = CGSize(width: 7680, height: 2160)
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: superUltrawide).right, 0.5, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: superUltrawide).left, 0.5, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: superUltrawide).left, 0, accuracy: 0.001)
        // Non-wide sources: no bands.
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: CGSize(width: 1920, height: 1080)).left, 0)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: CGSize(width: 1920, height: 1080)).right, 0)
    }
}
