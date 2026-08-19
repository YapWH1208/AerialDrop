import AppKit
import SwiftUI

struct WallpaperCard: View {
    let wallpaper: ManagedWallpaper
    let isSelected: Bool
    let isActive: Bool
    let isSelectionStatusUnknown: Bool
    let isWorking: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onPreview: () -> Void
    let onSetWallpaper: () -> Void
    let onRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var hovering = false
    @FocusState private var selectFocused: Bool
    @FocusState private var previewFocused: Bool
    @FocusState private var moreFocused: Bool

    private var showsHoverControls: Bool {
        hovering || selectFocused || previewFocused || moreFocused
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                cardContent
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($selectFocused)
            .accessibilityLabel(wallpaper.title)
            .accessibilityValue(cardAccessibilityValue)
            .accessibilityHint("Select this wallpaper. Use the Preview button to play it.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .simultaneousGesture(
                TapGesture(count: 2).onEnded(onDoubleClick)
            )
            // Delete on the focused card opens the same confirmation as the
            // card menu; the responder chain keeps text fields (search) safe.
            .onDeleteCommand {
                if actionAvailability.canRemove {
                    onRemove()
                }
            }

            if showsHoverControls {
                hoverControls
                    .padding(14)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: borderWidth)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .contextMenu {
            cardMenu
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .contain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(wallpaper.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }

                if let resolution = wallpaper.resolution {
                    Text("\(Int(resolution.width)) × \(Int(resolution.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                statusLabel
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .contentShape(.rect)
    }

    private var thumbnail: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)

                Image(systemName: wallpaper.thumbnailExists ? "photo" : "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: wallpaper.id) {
            guard image == nil else { return }
            image = await Task.detached(priority: .utility) {
                NSImage(contentsOf: wallpaper.thumbnailURL)
            }.value
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if !wallpaper.videoExists {
            Label("Video missing", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel("Installed video is missing")
        } else if isActive {
            Label("Active", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.tint)
                .accessibilityLabel("Active wallpaper")
        } else {
            Label("Installed", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Wallpaper installed")
        }
    }

    private var hoverControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button("Preview", systemImage: "play.fill", action: onPreview)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .focused($previewFocused)
                    .help("Preview wallpaper")

                Menu {
                    cardMenu
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.small)
                .labelStyle(.iconOnly)
                .focused($moreFocused)
                .help("More actions")
            }
        }
    }

    @ViewBuilder
    private var cardMenu: some View {
        Button("Preview", systemImage: "play") { onPreview() }
        Button("Set as Wallpaper", systemImage: "desktopcomputer") { onSetWallpaper() }
            .disabled(!actionAvailability.canSetAsWallpaper)
            .help(actionAvailability.setWallpaperHelp)
        Divider()
        Button("Rename…", systemImage: "pencil") { onRename() }
            .disabled(!actionAvailability.canRename)
            .help(actionAvailability.renameHelp)
        Button("Reveal in Finder", systemImage: "folder") { onReveal() }
        Divider()
        Button("Remove Wallpaper…", systemImage: "trash", role: .destructive) { onRemove() }
            .disabled(!actionAvailability.canRemove)
            .help(actionAvailability.removeHelp)
    }

    private var actionAvailability: WallpaperActionAvailability {
        WallpaperActionAvailability(
            wallpaper: wallpaper,
            isActive: isActive,
            isSelectionStatusUnknown: isSelectionStatusUnknown,
            isWorking: isWorking
        )
    }

    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(colorSchemeContrast == .increased ? 0.2 : 0.12)
        }
        if hovering {
            return Color.primary.opacity(0.045)
        }
        return .clear
    }

    private var cardBorder: Color {
        if isSelected {
            return .accentColor
        }
        return Color(nsColor: .separatorColor)
    }

    private var borderWidth: CGFloat {
        if isSelected {
            return colorSchemeContrast == .increased ? 2 : 1.25
        }
        return 0.5
    }

    private var cardAccessibilityValue: String {
        if !wallpaper.videoExists {
            return "Installed video is missing"
        }
        if isActive {
            return "Active wallpaper"
        }
        return "Wallpaper installed"
    }
}
