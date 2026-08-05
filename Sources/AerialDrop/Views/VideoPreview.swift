import AppKit
import AVFoundation
import SwiftUI

struct VideoPreview: View {
    let url: URL
    var resolution: CGSize? = nil
    var cropOffset: Double? = nil

    @State private var frame: NSImage?
    @State private var duration: Double?
    @State private var fileSize: Int64?

    var body: some View {
        ZStack {
            if let frame {
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(.quaternary.opacity(0.6))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .background(Color.black)
        .overlay(alignment: .bottomTrailing) {
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
        .overlay {
            if let cropOffset, let resolution, hasCropWindow(resolution) {
                cropBands(cropOffset: cropOffset, resolution: resolution)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
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
        let target = min(max(duration ?? 0.5, 0.05), 0.5)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        if let result = try? await generator.image(at: time) {
            frame = NSImage(cgImage: result.image, size: .zero)
        }
    }

    /// Dims the parts of the preview box that the chosen crop window cuts away.
    /// The box shows the entire source fitted (scaledToFit), so the bands darken
    /// everything outside the chosen 16:9 window: left/right for ultrawide
    /// sources, top/bottom for portrait and 4:3 sources.
    private func cropBands(cropOffset: Double, resolution: CGSize) -> some View {
        GeometryReader { geo in
            let horizontal = cropBandFractions(cropOffset: cropOffset, sourceSize: resolution)
            let vertical = verticalCropBandFractions(sourceSize: resolution)
            ZStack {
                if horizontal.left > 0 || horizontal.right > 0 {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(width: geo.size.width * horizontal.left)
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(width: geo.size.width * horizontal.right)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                if vertical.top > 0 || vertical.bottom > 0 {
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(height: geo.size.height * vertical.top)
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(height: geo.size.height * vertical.bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func timeString(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
