import AppKit
import SwiftUI

struct WallpaperCard: View {
    let wallpaper: ManagedWallpaper
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onPreview: () -> Void
    let onRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 9) {
                    thumbnail

                    HStack(spacing: 5) {
                        Text(wallpaper.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        statusIcon
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassEffect(.regular.tint(isSelected ? .accentColor.opacity(0.2) : .white.opacity(0.05)), in: .rect(cornerRadius: 16))
        .glassEffectID(isSelected ? wallpaper.id : nil, in: namespace)
        .glassEffectTransition(.materialize)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.separator),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .overlay(alignment: .topTrailing) {
            topTrailingBadge
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                previewChip
                    .padding(.bottom, 6)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded(onDoubleClick)
        )
        .contextMenu {
            Button("Preview") { onPreview() }
            Button("Rename…") { onRename() }
            Button("Reveal in Finder") { onReveal() }
            Divider()
            Button("Remove Wallpaper…", role: .destructive) { onRemove() }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: hovering)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: isSelected)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if wallpaper.videoExists {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityLabel("Video installed")
                .help("Video installed")
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Video missing")
                .help("Video missing")
        }
    }

    private var previewChip: some View {
        Button(action: onPreview) {
            Label("Preview", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Preview the wallpaper motion")
    }

    private var topTrailingBadge: some View {
        Group {
            if hovering {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(7)
                        .background(.regularMaterial, in: Circle())
                        .glassEffectUnion(id: wallpaper.id, namespace: namespace)
                }
                .buttonStyle(.plain)
                .help("Remove this wallpaper")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(7)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.4)), in: Circle())
                    .glassEffectUnion(id: wallpaper.id, namespace: namespace)
                    .accessibilityLabel("Selected")
                    .help("Selected")
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(8)
    }

    private var thumbnail: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(hovering ? 1.05 : 1)
            } else {
                Rectangle().fill(.quaternary.opacity(0.6))
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: wallpaper.id) {
            guard image == nil else { return }
            image = await Task.detached(priority: .utility) {
                NSImage(contentsOf: wallpaper.thumbnailURL)
            }.value
        }
    }
}