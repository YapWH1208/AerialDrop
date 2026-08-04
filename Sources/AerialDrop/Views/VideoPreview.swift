import AppKit
import AVFoundation
import SwiftUI

struct VideoPreview: View {
    let url: URL

    @State private var frame: NSImage?
    @State private var duration: Double?
    @State private var fileSize: Int64?

    var body: some View {
        ZStack {
            if let frame {
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary.opacity(0.6))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let duration, let fileSize {
                HStack(spacing: 6) {
                    Label(timeString(duration), systemImage: "clock")
                    Label(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file), systemImage: "internaldrive")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, !seconds.isNaN {
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
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}