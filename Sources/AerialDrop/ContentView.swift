import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var removeAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
            Divider()
            HSplitView {
                importerPane
                    .frame(minWidth: 390, maxHeight: .infinity)
                libraryPane
                    .frame(minWidth: 300, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .alert("AerialDrop", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .confirmationDialog(
            "Remove every AerialDrop wallpaper?",
            isPresented: $removeAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) { model.removeAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes AerialDrop entries and their copied video and thumbnail files. A manifest backup is created first.")
        }
        .fileImporter(
            isPresented: $model.showingFileImporter,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.chooseVideo(url) }
            case .failure(let error):
                model.alertMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AerialDrop")
                        .font(.title2.bold())
                    Text("v0.5.5")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Text("Import a native 10-bit Aerial and link the same asset to Desktop, Lock Screen and Screen Saver")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Wallpaper Settings") { model.openWallpaperSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
    }

    private var importerPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import")
                .font(.headline)

            dropZone

            VStack(alignment: .leading, spacing: 6) {
                Text("Wallpaper name")
                    .font(.subheadline.weight(.medium))
                TextField("Example: Yoimiya 4K", text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            if model.isWorking {
                ProgressView()
                Text(model.stage.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.importSelectedVideo()
            } label: {
                Label("Import into Aerials", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canImport)

            GroupBox("What happens") {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Encodes one closed-GOP HEVC Main10 source loop", systemImage: "film")
                    Label("Repeats the encoded loop to 80 seconds without re-encoding", systemImage: "repeat")
                    Label("Normalizes timestamp zero and creates a Tahoe-compatible HEIF preview", systemImage: "photo")
                    Label("Backs up entries.json and preserves other apps’ entries", systemImage: "doc.badge.gearshape")
                    Label("Adds a complete Tahoe Aerial catalogue entry", systemImage: "rectangle.stack")
                    Label("Updates Tahoe’s visible asset count", systemImage: "number")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()

            Text("After importing, select the new item in Wallpaper settings, close System Settings, then click Finish Native Setup. You may quit AerialDrop after setup; macOS handles playback natively.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var dropZone: some View {
        Button {
            model.showingFileImporter = true
        } label: {
            VStack(spacing: 10) {
                if let url = model.selectedVideo {
                    Image(systemName: "film.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Text("Click to choose another file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Choose an MP4 or MOV video")
                        .font(.headline)
                    Text("The source file is not modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            model.chooseVideo(first)
            return true
        }
    }

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Imported Wallpapers")
                    .font(.headline)
                Text("\(model.wallpapers.count)")
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button("Open Aerial Storage Folder") { model.openStorageFolder() }
                    Button("Validate Current Catalogue") { model.validateCatalogue() }
                    Button("Repair Catalogue Registration") { model.repairCatalogueRegistration() }
                        .disabled(model.wallpapers.isEmpty || model.isWorking)
                    Button("Restore Latest Manifest Backup") { model.restoreLatestBackup() }
                        .disabled(model.isWorking)
                    Button("Restore Latest Selection Backup") { model.restoreLatestSelectionBackup() }
                        .disabled(model.isWorking)
                    Divider()
                    Button("Remove All AerialDrop Wallpapers", role: .destructive) {
                        removeAllConfirmation = true
                    }
                    .disabled(model.wallpapers.isEmpty || model.isWorking)
                } label: {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload catalogue")
                .disabled(model.isWorking)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)

            if !model.wallpapers.isEmpty {
                GroupBox("Complete Native Setup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("""
                        1. Select the AerialDrop item in System Settings → Wallpaper.
                        2. Close System Settings.
                        3. Click the button below to use that exact asset for both Desktop and Screen Saver.
                        """)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            model.finishNativeSetup()
                        } label: {
                            Label("Finish Native Setup", systemImage: "rectangle.2.swap")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isWorking)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
            }

            if model.wallpapers.isEmpty {
                ContentUnavailableView(
                    "No AerialDrop Wallpapers",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Imported videos will appear here and under the AerialDrop section in System Settings.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.wallpapers) { wallpaper in
                    WallpaperRow(wallpaper: wallpaper) {
                        model.remove(wallpaper)
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }
        }
        .padding(20)
    }
}

private struct WallpaperRow: View {
    let wallpaper: ManagedWallpaper
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = NSImage(contentsOf: wallpaper.thumbnailURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 55)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text(wallpaper.title)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: wallpaper.videoExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Text(wallpaper.videoExists ? "Video installed" : "Video missing")
                }
                .font(.caption)
                .foregroundColor(wallpaper.videoExists ? .secondary : .orange)
            }

            Spacer()

            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this wallpaper")
        }
        .padding(.vertical, 4)
    }
}
