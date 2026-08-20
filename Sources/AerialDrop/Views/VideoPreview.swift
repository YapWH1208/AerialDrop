import AppKit
import AVFoundation
import SwiftUI

struct VideoPreview: View {
    let url: URL
    var resolution: CGSize? = nil
    var cropOffset: Double? = nil
    var isDisabled = false
    let onReplace: () -> Void

    @State private var state: PreviewState = .loading
    @State private var duration: Double?
    @State private var fileSize: Int64?
    @State private var loadAttempt = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.6))

            switch state {
            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .ready(let frame):
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFit()
            case .failed:
                ContentUnavailableView {
                    Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("AerialDrop couldn’t generate a still preview. You can still import the video after validation succeeds.")
                } actions: {
                    Button("Retry Preview", systemImage: "arrow.clockwise") {
                        loadAttempt += 1
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Replace Video…", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
                }
                .disabled(isDisabled)
            }
        }
        .background(Color.black)
        .overlay(alignment: .bottomTrailing) {
            if resolution != nil || (duration != nil && fileSize != nil) {
                HStack(spacing: 6) {
                    if let resolution {
                        Label("\(Int(resolution.width))×\(Int(resolution.height))", systemImage: "rectangle.inset.filled")
                    }
                    if let duration, let fileSize {
                        Label(timeString(duration), systemImage: "clock")
                        Label(fileSize.formatted(.byteCount(style: .file)), systemImage: "internaldrive")
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
            }
        }
        .overlay {
            if case .ready = state,
               let cropOffset, let resolution, hasCropWindow(resolution) {
                CropMask(cropOffset: cropOffset, resolution: resolution)
            }
        }
        .task(id: LoadRequest(url: url, attempt: loadAttempt)) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        state = .loading
        duration = nil
        fileSize = nil

        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            duration = seconds
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            fileSize = size.int64Value
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        // Sample a few early timestamps and prefer the first frame that is not
        // (nearly) black, so fade-in sources don't preview as a black box.
        let durationSeconds = duration ?? 1
        let candidates = [0.5, 2.0, 5.0].filter { $0 < durationSeconds }
        let times = candidates.isEmpty
            ? [min(max(durationSeconds, 0.05), 0.5)]
            : candidates
        var fallback: NSImage?
        for seconds in times {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let result = try? await generator.image(at: time) else { continue }
            let image = NSImage(cgImage: result.image, size: .zero)
            if Self.isMeaningfullyVisible(result.image) {
                state = .ready(image)
                return
            }
            if fallback == nil {
                fallback = image
            }
        }
        guard !Task.isCancelled else { return }
        if let fallback {
            state = .ready(fallback)
        } else {
            state = .failed
            AccessibilityNotification.Announcement(
                "Preview unavailable. Retry the preview or replace the video."
            ).post()
        }
    }

    /// True when a frame has enough non-dark pixels to represent the video
    /// (a fade-in-from-black or first-frame-black source fails this).
    nonisolated static func isMeaningfullyVisible(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let stepX = max(1, bitmap.pixelsWide / 10)
        let stepY = max(1, bitmap.pixelsHigh / 10)
        var bright = 0
        var sampled = 0
        var x = 0
        while x < bitmap.pixelsWide {
            var y = 0
            while y < bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y) {
                    let luminance =
                        0.299 * color.redComponent
                        + 0.587 * color.greenComponent
                        + 0.114 * color.blueComponent
                    if luminance > 0.12 {
                        bright += 1
                    }
                }
                sampled += 1
                y += stepY
            }
            x += stepX
        }
        return sampled > 0 && Double(bright) / Double(sampled) > 0.1
    }

    private func timeString(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}

private extension VideoPreview {
    enum PreviewState {
        case loading
        case ready(NSImage)
        case failed
    }

    struct LoadRequest: Hashable {
        let url: URL
        let attempt: Int
    }
}
