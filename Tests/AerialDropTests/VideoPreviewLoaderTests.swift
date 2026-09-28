import AppKit
import XCTest
@testable import AerialDrop

@MainActor
final class VideoPreviewLoaderTests: XCTestCase {
    private let oldURL = URL(fileURLWithPath: "/tmp/AerialDrop-old-preview.mov")
    private let newURL = URL(fileURLWithPath: "/tmp/AerialDrop-new-preview.mov")

    func testLateMetadataCannotReplaceANewerPreview() async throws {
        let metadataGate = PreviewReadGate<Double?>()
        let oldReader = FakeVideoPreviewReader(duration: 100, size: 100, metadataGate: metadataGate)
        let newReader = FakeVideoPreviewReader(duration: 20, size: 200, frames: [try image(bright: true)])
        var announcements = 0
        let loader = VideoPreviewLoader(
            makeReader: { $0 == self.oldURL ? oldReader : newReader },
            announceFailure: { announcements += 1 }
        )

        let oldTask = Task { await loader.load(url: oldURL) }
        await metadataGate.waitUntilRequested()
        await loader.load(url: newURL)
        let newState = loader.state
        metadataGate.resolve(100)
        await oldTask.value

        XCTAssertEqual(loader.state, newState)
        XCTAssertEqual(loader.duration, 20)
        XCTAssertEqual(loader.fileSize, 200)
        XCTAssertEqual(oldReader.fileSizeRequests, 0)
        XCTAssertTrue(oldReader.frameTimes.isEmpty)
        XCTAssertEqual(announcements, 0)
    }

    func testCancelledMetadataCannotPublishOrStartFrameLoading() async {
        let metadataGate = PreviewReadGate<Double?>()
        let reader = FakeVideoPreviewReader(duration: 100, size: 100, metadataGate: metadataGate)
        var announcements = 0
        let loader = VideoPreviewLoader(makeReader: { _ in reader }, announceFailure: { announcements += 1 })

        let task = Task { await loader.load(url: oldURL) }
        await metadataGate.waitUntilRequested()
        task.cancel()
        metadataGate.resolve(100)
        await task.value

        XCTAssertEqual(loader.state, .loading)
        XCTAssertNil(loader.duration)
        XCTAssertNil(loader.fileSize)
        XCTAssertEqual(reader.fileSizeRequests, 0)
        XCTAssertTrue(reader.frameTimes.isEmpty)
        XCTAssertEqual(announcements, 0)
    }

    func testObsoleteFrameCompletionCannotReplaceNewStateOrAnnounceFailure() async throws {
        for cancelOldRequest in [false, true] {
            for oldFrame in [try image(bright: true), nil] as [CGImage?] {
                let frameGate = PreviewReadGate<CGImage?>()
                let oldReader = FakeVideoPreviewReader(duration: 100, size: 100, frameGate: frameGate)
                let newReader = FakeVideoPreviewReader(duration: 20, size: 200, frames: [try image(bright: true)])
                var announcements = 0
                let loader = VideoPreviewLoader(
                    makeReader: { $0 == self.oldURL ? oldReader : newReader },
                    announceFailure: { announcements += 1 }
                )

                let oldTask = Task { await loader.load(url: oldURL) }
                await frameGate.waitUntilRequested()
                if cancelOldRequest { oldTask.cancel() }
                await loader.load(url: newURL)
                let newState = loader.state
                frameGate.resolve(oldFrame)
                await oldTask.value

                XCTAssertEqual(loader.state, newState)
                XCTAssertEqual(loader.duration, 20)
                XCTAssertEqual(loader.fileSize, 200)
                XCTAssertEqual(oldReader.frameTimes, [0.5])
                XCTAssertEqual(announcements, 0)
            }
        }
    }

    func testCancelledFrameCannotPublishWithoutAReplacementRequest() async throws {
        for frame in [try image(bright: true), nil] as [CGImage?] {
            let frameGate = PreviewReadGate<CGImage?>()
            let reader = FakeVideoPreviewReader(duration: 10, size: 100, frameGate: frameGate)
            var announcements = 0
            let loader = VideoPreviewLoader(makeReader: { _ in reader }, announceFailure: { announcements += 1 })

            let task = Task { await loader.load(url: oldURL) }
            await frameGate.waitUntilRequested()
            task.cancel()
            frameGate.resolve(frame)
            await task.value

            XCTAssertEqual(loader.state, .loading)
            XCTAssertEqual(loader.duration, 10)
            XCTAssertEqual(loader.fileSize, 100)
            XCTAssertEqual(reader.frameTimes, [0.5])
            XCTAssertEqual(announcements, 0)
        }
    }

    func testAlreadyCancelledRequestDoesNotResetAnExistingPreview() async throws {
        let reader = FakeVideoPreviewReader(duration: 20, size: 200, frames: [try image(bright: true)])
        var readerRequests = 0
        let loader = VideoPreviewLoader(makeReader: { _ in
            readerRequests += 1
            return reader
        }, announceFailure: {})
        await loader.load(url: newURL)
        let newState = loader.state
        let startGate = PreviewReadGate<Void>()
        let task = Task {
            await startGate.read()
            await loader.load(url: oldURL)
        }
        await startGate.waitUntilRequested()
        task.cancel()
        startGate.resolve(())
        await task.value

        XCTAssertEqual(loader.state, newState)
        XCTAssertEqual(loader.duration, 20)
        XCTAssertEqual(loader.fileSize, 200)
        XCTAssertEqual(readerRequests, 1)
    }

    func testSamplingPrefersFirstVisibleFrameAndRetainsDarkFallback() async throws {
        let dark = try image(bright: false)
        let bright = try image(bright: true)
        for hasBrightFrame in [true, false] {
            let reader = FakeVideoPreviewReader(
                duration: 6, size: 300,
                frames: hasBrightFrame ? [dark, bright] : [dark, dark, dark]
            )
            var announcements = 0
            let loader = VideoPreviewLoader(makeReader: { _ in reader }, announceFailure: { announcements += 1 })

            await loader.load(url: newURL)

            guard case .ready = loader.state else { return XCTFail("A generated frame should be displayed") }
            XCTAssertEqual(reader.frameTimes, hasBrightFrame ? [0.5, 2] : [0.5, 2, 5])
            XCTAssertEqual(loader.duration, 6)
            XCTAssertEqual(loader.fileSize, 300)
            XCTAssertEqual(announcements, 0)
        }
    }

    func testCurrentFailureAnnouncesOnceAndNonfiniteDurationStaysUnknown() async {
        let reader = FakeVideoPreviewReader(duration: .infinity, size: 300)
        var announcements = 0
        let loader = VideoPreviewLoader(makeReader: { _ in reader }, announceFailure: { announcements += 1 })

        await loader.load(url: newURL)

        XCTAssertEqual(loader.state, .failed)
        XCTAssertNil(loader.duration)
        XCTAssertEqual(loader.fileSize, 300)
        XCTAssertEqual(reader.frameTimes, [0.5])
        XCTAssertEqual(announcements, 1)
    }

    private func image(bright: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let value: CGFloat = bright ? 1 : 0
        context.setFillColor(CGColor(red: value, green: value, blue: value, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try XCTUnwrap(context.makeImage())
    }
}

/// Intentionally ignores Task cancellation, like an already-running AV callback.
@MainActor
private final class PreviewReadGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?

    func read() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func resolve(_ value: Value) {
        precondition(continuation != nil, "Wait for the request before resolving it")
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
private final class FakeVideoPreviewReader: VideoPreviewReading {
    let metadataDuration: Double?
    let size: Int64?
    let metadataGate: PreviewReadGate<Double?>?
    let frameGate: PreviewReadGate<CGImage?>?
    var frames: [CGImage?]
    private(set) var fileSizeRequests = 0
    private(set) var frameTimes: [Double] = []

    init(
        duration: Double?, size: Int64?, frames: [CGImage?] = [],
        metadataGate: PreviewReadGate<Double?>? = nil,
        frameGate: PreviewReadGate<CGImage?>? = nil
    ) {
        metadataDuration = duration
        self.size = size
        self.frames = frames
        self.metadataGate = metadataGate
        self.frameGate = frameGate
    }

    func duration() async -> Double? {
        if let metadataGate { return await metadataGate.read() }
        return metadataDuration
    }

    func fileSize() -> Int64? {
        fileSizeRequests += 1
        return size
    }

    func frame(at seconds: Double) async -> CGImage? {
        frameTimes.append(seconds)
        if let frameGate { return await frameGate.read() }
        return frames.isEmpty ? nil : frames.removeFirst()
    }
}
