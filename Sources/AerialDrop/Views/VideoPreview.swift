import AppKit
import SwiftUI

struct VideoPreview: View {
    let url: URL
    var resolution: CGSize? = nil
    var cropOffset: Double? = nil
    var isDisabled = false
    let onReplace: () -> Void

    @State private var loader = VideoPreviewLoader()
    @State private var loadAttempt = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.6))

            switch loader.state {
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
            if resolution != nil || (loader.duration != nil && loader.fileSize != nil) {
                HStack(spacing: 6) {
                    if let resolution {
                        Label("\(Int(resolution.width))×\(Int(resolution.height))", systemImage: "rectangle.inset.filled")
                    }
                    if let duration = loader.duration, let fileSize = loader.fileSize {
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
            if case .ready = loader.state,
               let cropOffset, let resolution, hasCropWindow(resolution) {
                CropMask(cropOffset: cropOffset, resolution: resolution)
            }
        }
        .task(id: LoadRequest(url: url, attempt: loadAttempt)) {
            await loader.load(url: url)
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
    struct LoadRequest: Hashable {
        let url: URL
        let attempt: Int
    }
}
