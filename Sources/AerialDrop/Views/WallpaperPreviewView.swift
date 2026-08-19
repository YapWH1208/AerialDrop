import SwiftUI

struct WallpaperPreviewView: View {
    let wallpaper: ManagedWallpaper
    let isActive: Bool
    let isSelectionStatusUnknown: Bool
    let isWorking: Bool
    let operationLabel: String?
    let onSetWallpaper: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaying = false
    @State private var wasPlayingBeforeReduceMotion = false
    @State private var playbackState: LoopPlaybackState = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            playerArea
            actionRow
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 780, minHeight: 460, idealHeight: 580)
        .onAppear {
            isPlaying = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                wasPlayingBeforeReduceMotion = isPlaying
                isPlaying = false
            } else {
                isPlaying = wasPlayingBeforeReduceMotion || isPlaying
            }
        }
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
        if !FileManager.default.fileExists(atPath: wallpaper.videoURL.path) {
            ContentUnavailableView {
                Label("Video Missing", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The installed video file could not be found on disk.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if playbackState == .failed {
            ContentUnavailableView {
                Label("Couldn’t Play Preview", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The installed video could not be played. It may have been moved, deleted, or damaged — the catalogue entry is untouched.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .bottomLeading) {
                LoopPlayerView(url: wallpaper.videoURL, isPlaying: isPlaying) { state in
                    playbackState = state
                }
                .accessibilityLabel(previewAccessibilityLabel)

                if playbackState == .loading {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading preview…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button(
                    isPlaying ? "Pause Preview" : "Play Preview",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                ) {
                    wasPlayingBeforeReduceMotion = false
                    isPlaying.toggle()
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(isPlaying ? "Pause the looping preview" : "Play the looping preview")
                .padding(12)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
    }

    private var previewAccessibilityLabel: String {
        "\(isPlaying ? "Playing" : "Paused") looping preview of \(wallpaper.title)"
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let operationLabel {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operationLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

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
            isSelectionStatusUnknown: isSelectionStatusUnknown,
            isWorking: isWorking
        )
    }
}
