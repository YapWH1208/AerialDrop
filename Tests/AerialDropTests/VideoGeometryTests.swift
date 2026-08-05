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
}
