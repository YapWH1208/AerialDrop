import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

private struct WriterPump: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderVideoCompositionOutput
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
}

/// Serializes the single-shot completion of the writer pump: resumes the
/// continuation at most once, and only from the writer queue.
private final class WriterPumpCompletion: @unchecked Sendable {
    private let queue: DispatchQueue
    private var finished = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func finish(with result: Result<Void, Error>, resuming continuation: CheckedContinuation<Void, Error>) {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            continuation.resume(with: result)
        }
    }
}

struct VideoProcessor: Sendable {
    private let nativeTargetDuration = CMTime(seconds: 80, preferredTimescale: 600)
    private let nativeFrameRate: Int32 = 30
    private let targetBitRate = 20_000_000
    private let nativeKeyFrameIntervalFrames = 57
    private let nativeKeyFrameIntervalDuration = 1.9

    func validate(source: URL) async throws {
        let ext = source.pathExtension.lowercased()
        guard ext == "mp4" || ext == "mov" else {
            throw AerialDropError.unsupportedFile
        }

        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw AerialDropError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0.25 else {
            throw AerialDropError.videoTooShort
        }

        let descriptions = try await track.load(.formatDescriptions)
        let codecs = descriptions.map { CMFormatDescriptionGetMediaSubType($0) }
        let supportedCodecs: Set<FourCharCode> = [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC]
        guard codecs.contains(where: supportedCodecs.contains) else {
            throw AerialDropError.incompatibleSourceCodec
        }
    }

    /// Encodes one normalized source loop, then repeats that already-encoded segment
    /// without re-encoding. The working Wallper asset uses this sample-table shape:
    /// regular 1.9-second closed GOPs plus a fresh sync sample at every loop boundary.
    func makeNativeMOV(from source: URL, destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)

        let sourceAsset = AVURLAsset(url: source)
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let sourceTrack = sourceTracks.first else {
            throw AerialDropError.noVideoTrack
        }

        let trackTimeRange = try await sourceTrack.load(.timeRange)
        let firstFrameTime = try firstRenderableSampleTime(asset: sourceAsset, track: sourceTrack)
        let loopStart = CMTimeMaximum(trackTimeRange.start, firstFrameTime)
        let availableDuration = CMTimeSubtract(trackTimeRange.end, loopStart)
        guard availableDuration.isNumeric, availableDuration.seconds > 0.20 else {
            throw AerialDropError.videoTooShort
        }

        // Snap to a whole number of 30 fps frames so the passthrough repeat keeps
        // every insertion on the sample grid; fractional lengths drift one frame
        // per repeat and the sync sample that should sit at each loop boundary
        // lands outside the validator's tolerance.
        let snapFrames = floor(
            CMTimeMinimum(availableDuration, nativeTargetDuration).seconds
                * Double(nativeFrameRate)
        )
        guard snapFrames >= 1 else {
            throw AerialDropError.videoTooShort
        }
        let segmentDuration = CMTime(
            seconds: snapFrames / Double(nativeFrameRate),
            preferredTimescale: 600
        )
        let segmentURL = destination.deletingLastPathComponent().appendingPathComponent(
            ".AerialDrop-\(UUID().uuidString)-segment.mov"
        )
        defer { try? FileManager.default.removeItem(at: segmentURL) }

        let segmentComposition = AVMutableComposition()
        guard let segmentTrack = segmentComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AerialDropError.exportSessionUnavailable
        }

        do {
            try segmentTrack.insertTimeRange(
                CMTimeRange(start: loopStart, duration: segmentDuration),
                of: sourceTrack,
                at: .zero
            )
        } catch {
            throw AerialDropError.exportFailed(error.localizedDescription)
        }

        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        segmentTrack.preferredTransform = preferredTransform

        let naturalSize = try await sourceTrack.load(.naturalSize)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = evenSize(
            CGSize(
                width: max(2, abs(transformedRect.width)),
                height: max(2, abs(transformedRect.height))
            )
        )

        let videoComposition = makeVideoComposition(
            track: segmentTrack,
            preferredTransform: preferredTransform,
            transformedRect: transformedRect,
            renderSize: renderSize,
            duration: segmentDuration
        )

        try await encodeMain10FullRange(
            composition: segmentComposition,
            track: segmentTrack,
            videoComposition: videoComposition,
            renderSize: renderSize,
            duration: segmentDuration,
            destination: segmentURL
        )

        if CMTimeCompare(segmentDuration, nativeTargetDuration) >= 0 {
            try FileManager.default.moveItem(at: segmentURL, to: destination)
        } else {
            try await repeatEncodedSegment(
                segmentURL: segmentURL,
                segmentDuration: segmentDuration,
                destination: destination
            )
        }

        try await validateInstalledVideo(destination, loopDuration: segmentDuration)
    }

    private func makeVideoComposition(
        track: AVCompositionTrack,
        preferredTransform: CGAffineTransform,
        transformedRect: CGRect,
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoComposition {
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        let normalizedTransform = preferredTransform.translatedBy(
            x: -transformedRect.minX,
            y: -transformedRect.minY
        )
        layerConfiguration.setTransform(normalizedTransform, at: .zero)

        var instructionConfiguration = AVVideoCompositionInstruction.Configuration()
        instructionConfiguration.timeRange = CMTimeRange(start: .zero, duration: duration)
        instructionConfiguration.layerInstructions = [
            AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        ]

        var configuration = AVVideoComposition.Configuration()
        configuration.renderSize = renderSize
        configuration.frameDuration = CMTime(value: 1, timescale: nativeFrameRate)
        configuration.instructions = [
            AVVideoCompositionInstruction(configuration: instructionConfiguration)
        ]
        return AVVideoComposition(configuration: configuration)
    }

    private func encodeMain10FullRange(
        composition: AVComposition,
        track: AVCompositionTrack,
        videoComposition: AVVideoComposition,
        renderSize: CGSize,
        duration: CMTime,
        destination: URL
    ) async throws {
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)

        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: readerSettings
        )
        output.alwaysCopiesSampleData = false
        output.videoComposition = videoComposition
        guard reader.canAdd(output) else {
            throw AerialDropError.exportFailed("AVAssetReader rejected the 10-bit video output.")
        }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitRate,
            AVVideoExpectedSourceFrameRateKey: Int(nativeFrameRate),
            AVVideoMaxKeyFrameIntervalKey: nativeKeyFrameIntervalFrames,
            AVVideoMaxKeyFrameIntervalDurationKey: nativeKeyFrameIntervalDuration,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoAllowFrameReorderingKey: true,
            kVTCompressionPropertyKey_AllowOpenGOP as String: false,
            kVTCompressionPropertyKey_AllowTemporalCompression as String: true,
            kVTCompressionPropertyKey_BaseLayerFrameRate as String: NSNumber(
                value: Double(nativeFrameRate) / 2.0
            )
        ]
        let colorProperties: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: colorProperties
        ]

        guard writer.canApply(outputSettings: writerSettings, forMediaType: .video) else {
            throw AerialDropError.main10EncodingUnavailable
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw AerialDropError.exportFailed("AVAssetWriter rejected the HEVC Main10 input.")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw AerialDropError.exportFailed(
                writer.error?.localizedDescription ?? "Could not start the native movie writer."
            )
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw AerialDropError.exportFailed(
                reader.error?.localizedDescription ?? "Could not start the native movie reader."
            )
        }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.yapwh.aerialdrop.main10-writer")
            let pump = WriterPump(reader: reader, output: output, writer: writer, input: input)
            let completion = WriterPumpCompletion(queue: queue)

            pump.input.requestMediaDataWhenReady(on: queue) {
                while pump.input.isReadyForMoreMediaData {
                    if let sample = pump.output.copyNextSampleBuffer() {
                        guard pump.input.append(sample) else {
                            pump.reader.cancelReading()
                            pump.writer.cancelWriting()
                            completion.finish(with: .failure(AerialDropError.exportFailed(
                                pump.writer.error?.localizedDescription
                                    ?? "The HEVC Main10 writer rejected a video sample."
                            )), resuming: continuation)
                            return
                        }
                        continue
                    }

                    if pump.reader.status == .failed {
                        pump.writer.cancelWriting()
                        completion.finish(with: .failure(AerialDropError.exportFailed(
                            pump.reader.error?.localizedDescription ?? "The 10-bit video reader failed."
                        )), resuming: continuation)
                        return
                    }

                    pump.input.markAsFinished()
                    pump.writer.endSession(atSourceTime: duration)
                    pump.writer.finishWriting {
                        switch pump.writer.status {
                        case .completed:
                            completion.finish(with: .success(()), resuming: continuation)
                        case .failed, .cancelled:
                            completion.finish(with: .failure(AerialDropError.exportFailed(
                                pump.writer.error?.localizedDescription
                                    ?? "The HEVC Main10 writer did not finish."
                            )), resuming: continuation)
                        default:
                            completion.finish(with: .failure(AerialDropError.exportFailed(
                                "Unexpected writer status: \(pump.writer.status.rawValue)"
                            )), resuming: continuation)
                        }
                    }
                    return
                }
            }
        }
    }

    private func repeatEncodedSegment(
        segmentURL: URL,
        segmentDuration: CMTime,
        destination: URL
    ) async throws {
        let encodedAsset = AVURLAsset(url: segmentURL)
        let tracks = try await encodedAsset.loadTracks(withMediaType: .video)
        guard let encodedTrack = tracks.first else {
            throw AerialDropError.noVideoTrack
        }

        let encodedTimeRange = try await encodedTrack.load(.timeRange)
        let usableDuration = CMTimeMinimum(segmentDuration, encodedTimeRange.duration)
        guard usableDuration.isNumeric, usableDuration.seconds > 0.20 else {
            throw AerialDropError.videoTooShort
        }

        let repeated = AVMutableComposition()
        guard let repeatedTrack = repeated.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AerialDropError.exportSessionUnavailable
        }
        repeatedTrack.preferredTransform = try await encodedTrack.load(.preferredTransform)

        var cursor = CMTime.zero
        while CMTimeCompare(cursor, nativeTargetDuration) < 0 {
            let remaining = CMTimeSubtract(nativeTargetDuration, cursor)
            let insertionDuration = CMTimeMinimum(usableDuration, remaining)
            do {
                try repeatedTrack.insertTimeRange(
                    CMTimeRange(start: encodedTimeRange.start, duration: insertionDuration),
                    of: encodedTrack,
                    at: cursor
                )
            } catch {
                throw AerialDropError.exportFailed(
                    "Could not repeat the encoded native segment: \(error.localizedDescription)"
                )
            }
            cursor = CMTimeAdd(cursor, insertionDuration)
        }

        guard let exporter = AVAssetExportSession(
            asset: repeated,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AerialDropError.passthroughUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mov) else {
            throw AerialDropError.passthroughUnavailable
        }

        try? FileManager.default.removeItem(at: destination)
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: nativeTargetDuration)

        do {
            try await exporter.export(to: destination, as: .mov)
        } catch {
            throw AerialDropError.exportFailed(
                error.localizedDescription
                    + " The encoded segment could not be repeated into the final MOV."
            )
        }
    }

    private func firstRenderableSampleTime(asset: AVAsset, track: AVAssetTrack) throws -> CMTime {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return .zero
        }
        reader.add(output)

        guard reader.startReading() else {
            return .zero
        }

        while let sample = output.copyNextSampleBuffer() {
            let duration = CMSampleBufferGetDuration(sample)
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            if presentationTime.isNumeric,
               (!duration.isNumeric || duration.seconds > 0) {
                reader.cancelReading()
                return presentationTime
            }
        }

        return .zero
    }

    private func validateInstalledVideo(_ url: URL, loopDuration: CMTime) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AerialDropError.installedFileMissing(url)
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 0 else {
            throw AerialDropError.exportFailed("The installed MOV is empty.")
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds >= 79.5 else {
            throw AerialDropError.nativeVideoTooShort(duration.seconds)
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw AerialDropError.noVideoTrack
        }

        let frameRate = try await track.load(.nominalFrameRate)
        guard abs(frameRate - 30) < 0.1 else {
            throw AerialDropError.nativeVideoWrongFrameRate(frameRate)
        }

        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_HEVC else {
            throw AerialDropError.incompatibleExportCodec
        }

        let bitsPerComponent = (
            CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_BitsPerComponent
            ) as? NSNumber
        )?.intValue ?? 0
        let fullRange = (
            CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_FullRangeVideo
            ) as? NSNumber
        )?.boolValue ?? false
        guard bitsPerComponent >= 10 else {
            throw AerialDropError.nativeVideoNotMain10(bitsPerComponent)
        }
        guard fullRange else {
            throw AerialDropError.nativeVideoNotFullRange
        }

        let firstFrame = try firstRenderableSampleTime(asset: asset, track: track)
        guard abs(firstFrame.seconds) < 0.002 else {
            throw AerialDropError.nativeVideoDoesNotStartAtZero(firstFrame.seconds)
        }

        try validateLoopBoundarySyncSamples(asset: asset, track: track, loopDuration: loopDuration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        do {
            _ = try await generator.image(at: .zero)
        } catch {
            throw AerialDropError.thumbnailFailed
        }
    }

    private func validateLoopBoundarySyncSamples(
        asset: AVAsset,
        track: AVAssetTrack,
        loopDuration: CMTime
    ) throws {
        let loopSeconds = loopDuration.seconds
        guard loopSeconds.isFinite,
              loopSeconds > 0.20,
              loopSeconds < nativeTargetDuration.seconds - 0.05 else {
            return
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AerialDropError.exportFailed("Could not inspect native loop sync samples.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AerialDropError.exportFailed(
                reader.error?.localizedDescription ?? "Could not read native loop sync samples."
            )
        }

        var syncPTS: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let duration = CMSampleBufferGetDuration(sample)
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard duration.isNumeric, duration.seconds > 0, pts.isNumeric else { continue }

            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sample,
                createIfNecessary: false
            ) as? [[CFString: Any]]
            let notSync = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
            if !notSync {
                syncPTS.append(pts.seconds)
            }
        }

        if reader.status == .failed {
            throw AerialDropError.exportFailed(
                reader.error?.localizedDescription ?? "Native loop sync-sample inspection failed."
            )
        }

        let tolerance = 1.5 / Double(nativeFrameRate)
        var boundary = loopSeconds
        while boundary < nativeTargetDuration.seconds - tolerance {
            guard syncPTS.contains(where: { abs($0 - boundary) <= tolerance }) else {
                throw AerialDropError.exportFailed(
                    "The final native MOV has no sync sample at loop boundary \(boundary.formatted(.number.precision(.fractionLength(3)))) seconds."
                )
            }
            boundary += loopSeconds
        }
    }

    /// Wallper's working custom preview is a HEIF image even though the catalogue path uses
    /// a `.png` suffix. Tahoe detects the image by its contents, so AerialDrop mirrors that.
    func generateThumbnail(from video: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = NSSize(width: 1920, height: 1080)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let image: CGImage
        do {
            image = try await generator.image(at: .zero).image
        } catch {
            throw AerialDropError.thumbnailFailed
        }

        let data = NSMutableData()
        guard let destinationWriter = CGImageDestinationCreateWithData(
            data,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw AerialDropError.thumbnailFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        CGImageDestinationAddImage(destinationWriter, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destinationWriter) else {
            throw AerialDropError.thumbnailFailed
        }

        try? FileManager.default.removeItem(at: destination)
        try (data as Data).write(to: destination, options: .atomic)
    }

    private func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, floor(size.width / 2) * 2),
            height: max(2, floor(size.height / 2) * 2)
        )
    }
}
