import XCTest
@testable import AerialDrop

final class VideoGeometryTests: XCTestCase {
    func testIdentityTransformKeepsSize() {
        let size = VideoGeometry.displaySize(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity
        )
        XCTAssertEqual(size.width, 1920, accuracy: 0.001)
        XCTAssertEqual(size.height, 1080, accuracy: 0.001)
    }

    func testQuarterTurnSwapsAxes() {
        // A 90° rotation maps (1920, 1080) onto (−1080, 1920): the display
        // size is the storage size with axes swapped, matching what the
        // encode pipeline renders for a portrait recording.
        let size = VideoGeometry.displaySize(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(size.width, 1080, accuracy: 0.001)
        XCTAssertEqual(size.height, 1920, accuracy: 0.001)
    }

    func testMirrorTransformKeepsDimensions() {
        // A mirror flips the sign but not the magnitude of each dimension.
        let size = VideoGeometry.displaySize(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(scaleX: -1, y: 1)
        )
        XCTAssertEqual(size.width, 1920, accuracy: 0.001)
        XCTAssertEqual(size.height, 1080, accuracy: 0.001)
    }

    func testTranslationDoesNotAffectDisplaySize() {
        // A translation shifts the transformed rect's origin, never its
        // dimensions — displaySize must stay origin-independent (the encode
        // pipeline separately consumes the origin for its crop transform).
        let size = VideoGeometry.displaySize(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(translationX: 100, y: -50)
        )
        XCTAssertEqual(size.width, 1920, accuracy: 0.001)
        XCTAssertEqual(size.height, 1080, accuracy: 0.001)
    }

    func testPortraitCropCoversRenderAreaForBothQuarterTurns() {
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let renderSize = CGSize(width: 1080, height: 606)
        let transforms = [
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)
        ]
        for preferredTransform in transforms {
            let rect = renderedRect(source, preferredTransform, renderSize)
            XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
            XCTAssertEqual(rect.minY, -657, accuracy: 0.001)
            XCTAssertEqual(rect.width, 1080, accuracy: 0.001)
            XCTAssertEqual(rect.height, 1920, accuracy: 0.001)
            XCTAssertTrue(rect.contains(CGRect(origin: .zero, size: renderSize)))
        }
    }

    func testUpsideDownSourceRemainsInsideDownscaledRenderArea() {
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let preferredTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)
        let renderSize = CGSize(width: 960, height: 540)
        let transform = VideoGeometry.renderTransform(
            preferredTransform: preferredTransform,
            transformedRect: source.applying(preferredTransform),
            renderSize: renderSize,
            pan: 0
        )
        XCTAssertEqual(source.applying(transform), CGRect(origin: .zero, size: renderSize))
        // Keep the source orientation while normalizing its bounds.
        XCTAssertEqual(CGPoint.zero.applying(transform), CGPoint(x: 960, y: 540))
        XCTAssertEqual(CGPoint(x: 1920, y: 1080).applying(transform), .zero)
    }

    func testMirroredTranslatedSourceKeepsOrientationAndNormalizesOrigin() {
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let preferredTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2200, ty: -80)
        let renderSize = CGSize(width: 960, height: 540)
        let transform = VideoGeometry.renderTransform(
            preferredTransform: preferredTransform,
            transformedRect: source.applying(preferredTransform),
            renderSize: renderSize,
            pan: 0
        )
        XCTAssertEqual(source.applying(transform), CGRect(origin: .zero, size: renderSize))
        XCTAssertEqual(CGPoint.zero.applying(transform), CGPoint(x: 960, y: 0))
        XCTAssertEqual(CGPoint(x: 1920, y: 1080).applying(transform), CGPoint(x: 0, y: 540))
    }

    func testUltrawidePanUsesOutputPixelsAfterScaling() {
        let source = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let renderSize = CGSize(width: 1920, height: 1080)
        for pan: CGFloat in [-330, 0, 330] {
            let rect = renderedRect(source, .identity, renderSize, pan: pan)
            XCTAssertEqual(rect.minX, -330 - pan, accuracy: 0.001)
            XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
            XCTAssertEqual(rect.width, 2580, accuracy: 0.001)
            XCTAssertEqual(rect.height, 1080, accuracy: 0.001)
            XCTAssertTrue(rect.contains(CGRect(origin: .zero, size: renderSize)))
        }
    }

    private func renderedRect(
        _ source: CGRect,
        _ preferredTransform: CGAffineTransform,
        _ renderSize: CGSize,
        pan: CGFloat = 0
    ) -> CGRect {
        source.applying(VideoGeometry.renderTransform(
            preferredTransform: preferredTransform,
            transformedRect: source.applying(preferredTransform),
            renderSize: renderSize,
            pan: pan
        ))
    }
}
