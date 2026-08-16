import XCTest
@testable import AerialDrop

final class ConversionOptionsTests: XCTestCase {
    func testLoopDescriptionStatesTrimForLongSources() {
        XCTAssertEqual(loopDescription(sourceDuration: 300), "First 1:20 of the source, looped")
        XCTAssertEqual(loopDescription(sourceDuration: 80), "First 1:20 of the source, looped")
    }

    func testLoopDescriptionStatesRepeatForShortSources() {
        XCTAssertEqual(loopDescription(sourceDuration: 12), "Whole video, repeated to fill 1:20")
        XCTAssertEqual(loopDescription(sourceDuration: 79.9), "Whole video, repeated to fill 1:20")
    }

    func testLoopDescriptionFallsBackWithoutADuration() {
        XCTAssertEqual(loopDescription(sourceDuration: nil), "80-second loop")
        XCTAssertEqual(loopDescription(sourceDuration: 0), "80-second loop")
        XCTAssertEqual(loopDescription(sourceDuration: .nan), "80-second loop")
    }

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

    func testEncodedOutputSizeMatchesTheNative16By9Contract() {
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: 3440, height: 1440), outputHeightCap: nil),
            CGSize(width: 2560, height: 1440)
        )
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: 3440, height: 1440), outputHeightCap: 1080),
            CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: 2160, height: 3840), outputHeightCap: nil),
            CGSize(width: 2160, height: 1214)
        )
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: 7680, height: 4320), outputHeightCap: nil),
            CGSize(width: 3840, height: 2160)
        )
    }

    func testEncodedOutputSizeHardensInvalidInputToMinimumEvenDimensions() {
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: 0, height: 1080), outputHeightCap: nil),
            CGSize(width: 2, height: 2)
        )
        XCTAssertEqual(
            encodedOutputSize(sourceSize: CGSize(width: CGFloat.infinity, height: 1080), outputHeightCap: nil),
            CGSize(width: 2, height: 2)
        )
    }

    func testIsUltrawide() {
        XCTAssertTrue(isUltrawide(CGSize(width: 3440, height: 1440)))
        XCTAssertTrue(isUltrawide(CGSize(width: 2560, height: 1080)))
        XCTAssertTrue(isUltrawide(CGSize(width: 5120, height: 2160)))
        XCTAssertTrue(isUltrawide(CGSize(width: 2100, height: 900))) // exact 21:9
        XCTAssertFalse(isUltrawide(CGSize(width: 1920, height: 1080)))
        XCTAssertFalse(isUltrawide(CGSize(width: 2048, height: 1152)))
        XCTAssertFalse(isUltrawide(CGSize(width: 3440, height: 1720))) // 2:1
        XCTAssertFalse(isUltrawide(CGSize(width: 1000, height: 1000)))
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

    func testCropBandFractionsDarkenOutsideWindowInFullFrame() {
        // 3440×1440: f = (16/9)/2.3889 = 0.7442, 1-f = 0.2558
        let ultrawide = CGSize(width: 3440, height: 1440)
        // Center preset: equal bands on both sides (half the trimmed width each).
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).left, 0.128, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).right, 0.128, accuracy: 0.001)
        // Left preset: window [0, 0.744] -> right band 0.256.
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).left, 0, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).right, 0.256, accuracy: 0.001)
        // Right preset: left band 0.256.
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).left, 0.256, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).right, 0, accuracy: 0.001)
        // Quarter offset: left 0.064, right 0.192.
        XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).left, 0.064, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).right, 0.192, accuracy: 0.001)
        // Out-of-range offsets clamp like cropPan.
        XCTAssertEqual(cropBandFractions(cropOffset: -1, sourceSize: ultrawide).right, 0.256, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 2, sourceSize: ultrawide).left, 0.256, accuracy: 0.001)
        // 32:9: f = 0.5; Left darkens the right half, Center darkens a quarter on each side.
        let superUltrawide = CGSize(width: 7680, height: 2160)
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: superUltrawide).right, 0.5, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: superUltrawide).left, 0.5, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: superUltrawide).left, 0.25, accuracy: 0.001)
        XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: superUltrawide).right, 0.25, accuracy: 0.001)
        // Non-wide sources: no bands.
        XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: CGSize(width: 1920, height: 1080)).left, 0)
        XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: CGSize(width: 1920, height: 1080)).right, 0)
    }

    func testNonFiniteAndDegenerateInputsAreHardened() {
        let source = CGSize(width: 3440, height: 1440)
        let render = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: .nan, sourceSize: source, renderSize: render), 0)
        XCTAssertEqual(cropPan(cropOffset: .infinity, sourceSize: source, renderSize: render), 0)
        let bands = cropBandFractions(cropOffset: .nan, sourceSize: source)
        XCTAssertEqual(bands.left, 0)
        XCTAssertEqual(bands.right, 0)
        let infiniteBands = cropBandFractions(cropOffset: .infinity, sourceSize: source)
        XCTAssertEqual(infiniteBands.left, 0)
        XCTAssertEqual(infiniteBands.right, 0)
        // Degenerate source dims: non-finite aspect yields no bands.
        let zeroHeightBands = cropBandFractions(cropOffset: 0.5, sourceSize: CGSize(width: 1920, height: 0))
        XCTAssertEqual(zeroHeightBands.left, 0)
        XCTAssertEqual(zeroHeightBands.right, 0)
        let infiniteWidthBands = cropBandFractions(cropOffset: 0.5, sourceSize: CGSize(width: CGFloat.infinity, height: 1080))
        XCTAssertEqual(infiniteWidthBands.left, 0)
        XCTAssertEqual(infiniteWidthBands.right, 0)
        // Degenerate cap is floored at 2 (matching evenSize's minimum render dimension).
        XCTAssertEqual(clampedOutputHeight(0, sourceHeight: 1080), 2)
        XCTAssertEqual(clampedOutputHeight(-5, sourceHeight: 1080), 2)
    }

    func testIsUltrawideRejectsNonFiniteAndDegenerateInputs() {
        XCTAssertFalse(isUltrawide(CGSize(width: CGFloat.nan, height: 1080)))
        XCTAssertFalse(isUltrawide(CGSize(width: 0, height: 1080)))
        XCTAssertFalse(isUltrawide(CGSize(width: 1920, height: 0)))
        XCTAssertFalse(isUltrawide(CGSize(width: CGFloat.infinity, height: 1080)))
    }

    func testIsNarrowerThan16By9() {
        XCTAssertTrue(isNarrowerThan16By9(CGSize(width: 1080, height: 1920)))
        XCTAssertTrue(isNarrowerThan16By9(CGSize(width: 1440, height: 1080))) // 4:3
        XCTAssertFalse(isNarrowerThan16By9(CGSize(width: 1920, height: 1080)))
        XCTAssertFalse(isNarrowerThan16By9(CGSize(width: 3440, height: 1440)))
        XCTAssertFalse(isNarrowerThan16By9(CGSize(width: CGFloat.nan, height: 1080)))
        XCTAssertFalse(isNarrowerThan16By9(CGSize(width: 1920, height: 0)))
    }

    func testHasCropWindow() {
        XCTAssertTrue(hasCropWindow(CGSize(width: 3440, height: 1440))) // ultrawide
        XCTAssertTrue(hasCropWindow(CGSize(width: 1080, height: 1920))) // portrait
        XCTAssertTrue(hasCropWindow(CGSize(width: 1440, height: 1080))) // 4:3
        XCTAssertFalse(hasCropWindow(CGSize(width: 1920, height: 1080))) // exact 16:9
        XCTAssertFalse(hasCropWindow(CGSize(width: 0, height: 1080)))
    }

    func testNaturalWindowHeight() {
        // 16:9 and wide sources: the full source height.
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: 3840, height: 2160)), 2160, accuracy: 0.001)
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: 3440, height: 1440)), 1440, accuracy: 0.001)
        // Portrait: the vertical-center-crop window (width × 9/16).
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: 2160, height: 3840)), 1215, accuracy: 0.001)
        // 4:3: 1440 × 9/16 = 810.
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: 1440, height: 1080)), 810, accuracy: 0.001)
        // Degenerate inputs are hardened.
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: 0, height: 1080)), 0)
        XCTAssertEqual(naturalWindowHeight(sourceSize: CGSize(width: CGFloat.infinity, height: 1080)), 0)
    }

    func testVerticalCropBandFractionsDarkenTopAndBottomForNarrowSources() {
        // 1080×1920 portrait: f = 0.5625/1.7778 = 0.3164; each band (1-f)/2 = 0.342.
        let portrait = CGSize(width: 1080, height: 1920)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: portrait).top, 0.3418, accuracy: 0.001)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: portrait).bottom, 0.3418, accuracy: 0.001)
        // 1440×1080 (4:3): f = 0.75; each band 0.125.
        let fourByThree = CGSize(width: 1440, height: 1080)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: fourByThree).top, 0.125, accuracy: 0.001)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: fourByThree).bottom, 0.125, accuracy: 0.001)
        // 16:9 and ultrawide sources: no vertical bands.
        XCTAssertEqual(verticalCropBandFractions(sourceSize: CGSize(width: 1920, height: 1080)).top, 0)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: CGSize(width: 3440, height: 1440)).top, 0)
        // Degenerate inputs are hardened.
        XCTAssertEqual(verticalCropBandFractions(sourceSize: CGSize(width: 1920, height: 0)).top, 0)
        XCTAssertEqual(verticalCropBandFractions(sourceSize: CGSize(width: CGFloat.nan, height: 1080)).top, 0)
    }
}
