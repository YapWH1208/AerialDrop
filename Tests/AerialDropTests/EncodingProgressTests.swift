import XCTest
@testable import AerialDrop

final class EncodingProgressTests: XCTestCase {
    func testProgressAccumulatesAcrossReadinessBatches() {
        var progress = EncodingProgress()
        var reports: [Double] = []
        var batchEndpoints: [Double] = []
        // The writer can yield and invoke its readiness callback again. Each
        // callback uses the same tracker, including its reporting throttle.
        for _ in 0..<3 {
            for _ in 0..<50 {
                if let value = progress.recordWrittenFrame(totalFrames: 300) {
                    reports.append(value)
                }
            }
            batchEndpoints.append(reports.last!)
        }
        XCTAssertEqual(progress.writtenFrames, 150)
        XCTAssertEqual(batchEndpoints[0], 1.0 / 6, accuracy: 0.011)
        XCTAssertEqual(batchEndpoints[1], 1.0 / 3, accuracy: 0.011)
        XCTAssertEqual(batchEndpoints[2], 0.5, accuracy: 0.011)
        XCTAssertTrue(zip(reports, reports.dropFirst()).allSatisfy { $0 < $1 })
    }

    func testProgressKeepsEncodingCapAndDoesNotRepeatCappedReports() {
        var progress = EncodingProgress()
        var reports: [Double] = []
        for _ in 0..<200 {
            if let value = progress.recordWrittenFrame(totalFrames: 100) {
                reports.append(value)
            }
        }
        XCTAssertTrue(reports.allSatisfy { $0 > 0 && $0 <= 0.95 })
        XCTAssertEqual(reports.last!, 0.95, accuracy: 0.011)
        XCTAssertNil(progress.recordWrittenFrame(totalFrames: 100))
    }

    func testZeroFrameEstimateStillProducesFiniteCappedProgress() {
        var progress = EncodingProgress()
        XCTAssertEqual(progress.recordWrittenFrame(totalFrames: 0), 0.95)
        XCTAssertNil(progress.recordWrittenFrame(totalFrames: 0))
    }
}
