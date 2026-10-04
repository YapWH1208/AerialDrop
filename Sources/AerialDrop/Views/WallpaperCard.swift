import AppKit
import SwiftUI

struct WallpaperCard: View {
    let wallpaper: ManagedWallpaper
    let isSelected: Bool
    let isActive: Bool
    let isAlreadySelected: Bool
    let isSelectionStatusUnknown: Bool
    let presentationState: WallpaperPresentationState
    let isWorking: Bool
    let onSelect: () -> Void
    let onNavigate: (LibraryMoveDirection) -> Void
    let onDoubleClick: () -> Void
    let onPreview: () -> Void
    let onSetWallpaper: () -> Void
    let onRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    /// Parent-owned selection focus so arrow-key navigation can move keyboard
    /// focus across cards in one shared namespace.
    @FocusState.Binding var selectionFocus: String?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var hovering = false
    @FocusState private var setWallpaperFocused: Bool
    @FocusState private var previewFocused: Bool
    @FocusState private var moreFocused: Bool

    private var showsHoverControls: Bool {
        isSelected || hovering || selectionFocus == wallpaper.id || setWallpaperFocused || previewFocused || moreFocused
    }

    /// Split out of `body` so its long modifier chain type-checks quickly.
    private var selectionButton: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($selectionFocus, equals: wallpaper.id)
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
        .onMoveCommand { direction in
            switch direction {
            case .left: onNavigate(.left)
            case .right: onNavigate(.right)
            case .up: onNavigate(.up)
            case .down: onNavigate(.down)
            @unknown default: break
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            selectionButton

            cardControls
                .padding(14)
                .transition(.opacity)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
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
                        .help(wallpaper.title)

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
        } else {
            Label(presentationState.statusLabel, systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
                .accessibilityLabel(presentationState.accessibilityDescription)
        }
    }

    private var cardControls: some View {
        HStack(alignment: .top) {
            Button(action: onPreview) {
                Label("Preview", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .focused($previewFocused)
            .accessibilityLabel("Preview \(wallpaper.title)")
            .help("Preview wallpaper")

            Spacer(minLength: 8)

            if showsHoverControls {
                actionControls
            }
        }
    }

    private var actionControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button(action: onSetWallpaper) {
                    Label(presentationState.activationTitle, systemImage: "desktopcomputer")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .focused($setWallpaperFocused)
                .disabled(!actionAvailability.canSetAsWallpaper)
                .accessibilityLabel(presentationState.activationTitle)
                .help(activationHelp)

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
        Button(presentationState.activationTitle, systemImage: "desktopcomputer") { onSetWallpaper() }
            .disabled(!actionAvailability.canSetAsWallpaper)
            .help(activationHelp)
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
            isAlreadySelected: isAlreadySelected,
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
        return presentationState.accessibilityDescription
    }

    private var activationHelp: String {
        if presentationState.assignment != .single {
            return presentationState.activationHelp
        }
        return actionAvailability.setWallpaperHelp
    }

    private var statusSymbol: String {
        switch presentationState.selection {
        case .selectedEverywhere:
            "checkmark.seal.fill"
        case .fixedVariant:
            presentationState.selectedRoleMatchesAssignment == false ? "circle" : "checkmark.seal.fill"
        case .selectedOnSomeTargets, .automatic:
            "arrow.triangle.2.circlepath"
        case .selectedWithUnknownScope:
            "questionmark.circle"
        case .notSelected:
            "checkmark.circle"
        case .mixedTargets, .unknown:
            "questionmark.circle"
        case .pendingVerification:
            "clock"
        }
    }

    private var statusColor: Color {
        switch presentationState.selection {
        case .selectedEverywhere, .automatic:
            .accentColor
        case .fixedVariant:
            if presentationState.selectedRoleMatchesAssignment == false {
                Color(nsColor: .secondaryLabelColor)
            } else {
                .accentColor
            }
        case .selectedOnSomeTargets, .selectedWithUnknownScope, .mixedTargets, .unknown, .pendingVerification, .notSelected:
            Color(nsColor: .secondaryLabelColor)
        }
    }
}
