import AppKit
import SwiftUI

struct WallpaperCard: View {
    let wallpaper: ManagedWallpaper
    let remove: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail

            HStack(spacing: 5) {
                Text(wallpaper.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if wallpaper.videoExists {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .help("Video installed")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Video missing")
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(7)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Remove this wallpaper")
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: hovering)
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