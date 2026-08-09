import AppKit
import SwiftUI

struct WallpaperPreviewView: View {
    let wallpaper: ManagedWallpaper
    let isActive: Bool
    let onSetWallpaper: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(wallpaper.title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let resolution = wallpaper.resolution {
                    Text("\(Int(resolution.width))×\(Int(resolution.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            playerArea

            Text("80-second looping preview — this is how macOS plays it as a wallpaper.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onReveal()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button {
                    onRename()
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button {
                    onSetWallpaper()
                } label: {
                    Label("Set as Wallpaper", systemImage: "desktopcomputer")
                }
                .buttonStyle(.glassProminent)
                .disabled(isActive)
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove…", systemImage: "trash")
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var playerArea: some View {
        if FileManager.default.fileExists(atPath: wallpaper.videoURL.path) {
            LoopPlayerView(url: wallpaper.videoURL)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.34), location: 0),
                            .init(color: .clear, location: 0.55)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 76)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Looping preview of \(wallpaper.title)")
        } else {
            ContentUnavailableView {
                Label("Video Missing", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The installed video file could not be found on disk.")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }
}
