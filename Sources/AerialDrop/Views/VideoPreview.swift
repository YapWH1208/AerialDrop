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
                CropMask(cropOffset: cropOffset, resolution: resolution)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        frame = nil
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
        let target = min(max(duration ?? 0.5, 0.05), 0.5)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        if let result = try? await generator.image(at: time) {
            frame = NSImage(cgImage: result.image, size: .zero)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
