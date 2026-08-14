import SwiftUI

struct WallpaperPreviewView: View {
    let wallpaper: ManagedWallpaper
    let isActive: Bool
    let isWorking: Bool
    let onSetWallpaper: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            playerArea
            actionRow
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 780, minHeight: 460, idealHeight: 580)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(wallpaper.title)
                    .font(.title3)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let resolution = wallpaper.resolution {
                    Text("\(Int(resolution.width)) × \(Int(resolution.height)) · 80-second loop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Active wallpaper")
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        if FileManager.default.fileExists(atPath: wallpaper.videoURL.path) {
            LoopPlayerView(url: wallpaper.videoURL)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Looping preview of \(wallpaper.title)")
        } else {
            ContentUnavailableView {
                Label("Video Missing", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The installed video file could not be found on disk.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Reveal in Finder", systemImage: "folder", action: onReveal)
            Button("Rename…", systemImage: "pencil", action: onRename)
                .disabled(!actionAvailability.canRename)
                .help(actionAvailability.renameHelp)
            Button("Remove…", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(!actionAvailability.canRemove)
                .help(actionAvailability.removeHelp)

            Spacer()

            Button("Set as Wallpaper", systemImage: "desktopcomputer", action: onSetWallpaper)
                .buttonStyle(.borderedProminent)
                .disabled(!actionAvailability.canSetAsWallpaper)
                .help(actionAvailability.setWallpaperHelp)
        }
    }

    private var actionAvailability: WallpaperActionAvailability {
        WallpaperActionAvailability(
            wallpaper: wallpaper,
            isActive: isActive,
            isWorking: isWorking
        )
    }
}
