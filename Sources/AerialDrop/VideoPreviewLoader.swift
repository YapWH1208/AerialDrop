import AppKit
import AVFoundation
import Observation
import SwiftUI

@MainActor
protocol VideoPreviewReading {
    func duration() async -> Double?
    func fileSize() -> Int64?
    func frame(at seconds: Double) async -> CGImage?
}

/// Keeps an obsolete preview request from publishing after a replacement or retry.
@MainActor
@Observable
final class VideoPreviewLoader {
    enum State: Equatable {
        case loading
        case ready(NSImage)
        case failed
    }

    private(set) var state: State = .loading
    private(set) var duration: Double?
    private(set) var fileSize: Int64?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let makeReader: @MainActor (URL) -> any VideoPreviewReading
    @ObservationIgnored private let announceFailure: @MainActor () -> Void

    init(
        makeReader: @escaping @MainActor (URL) -> any VideoPreviewReading = { AVVideoPreviewReader(url: $0) },
        announceFailure: @escaping @MainActor () -> Void = {
            AccessibilityNotification.Announcement(
                "Preview unavailable. Retry the preview or replace the video."
            ).post()
        }
    ) {
        self.makeReader = makeReader
        self.announceFailure = announceFailure
    }

    func load(url: URL) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        state = .loading
        duration = nil
        fileSize = nil

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let reader = makeReader(url)
        let loadedDuration = await reader.duration()
        guard isCurrent(request) else { return }
        let finiteDuration = loadedDuration.flatMap { $0.isFinite ? $0 : nil }
        duration = finiteDuration
        fileSize = reader.fileSize()

        // Preserve the existing fade-in sampling and first-frame fallback.
        let durationSeconds = finiteDuration ?? 1
        let candidates = [0.5, 2.0, 5.0].filter { $0 < durationSeconds }
        let times = candidates.isEmpty
            ? [min(max(durationSeconds, 0.05), 0.5)]
            : candidates
        var fallback: NSImage?
        for seconds in times {
            let frame = await reader.frame(at: seconds)
            guard isCurrent(request) else { return }
            guard let frame else { continue }
            let image = NSImage(cgImage: frame, size: .zero)
            if VideoPreview.isMeaningfullyVisible(frame) {
                state = .ready(image)
                return
            }
            if fallback == nil {
                fallback = image
            }
        }
        guard isCurrent(request) else { return }
        if let fallback {
            state = .ready(fallback)
        } else {
            state = .failed
            announceFailure()
        }
    }

    private func isCurrent(_ request: Int) -> Bool {
        generation == request && !Task.isCancelled
    }
}

@MainActor
private final class AVVideoPreviewReader: VideoPreviewReading {
    private let url: URL
    private let asset: AVURLAsset

    init(url: URL) {
        self.url = url
        asset = AVURLAsset(url: url)
    }

    func duration() async -> Double? {
        try? await asset.load(.duration).seconds
    }

    func fileSize() -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    func frame(at seconds: Double) async -> CGImage? {
        // Keep the non-Sendable generator local to this operation rather than
        // sending a MainActor-owned instance to AVFoundation's async method.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
