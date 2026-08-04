import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var removeAllConfirmation = false
    @State private var hoveringDropZone = false

    private let wallpaperColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        HSplitView {
            importerPane
                .frame(minWidth: 420, maxWidth: 540)
            libraryPane
                .frame(minWidth: 470)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text("AerialDrop")
                        .font(.system(size: 24, weight: .bold))
                    Text("v\(AppVersion.shortVersion)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.openWallpaperSettings()
                } label: {
                    Label("Wallpaper Settings", systemImage: "gearshape")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .help("Reload catalogue")
                .disabled(model.isWorking)
            }
            ToolbarItem(placement: .primaryAction) {
                maintenanceMenu
            }
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

    // MARK: - Toolbar

    private var maintenanceMenu: some View {
        Menu {
            Button("Open Aerial Storage Folder") { model.openStorageFolder() }
            Button("Validate Current Catalogue") { model.validateCatalogue() }
            Divider()
            Button("Remove All AerialDrop Wallpapers", role: .destructive) {
                removeAllConfirmation = true
            }
            .disabled(model.wallpapers.isEmpty || model.isWorking)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .labelStyle(.iconOnly)
        .help("Maintenance")
    }

    // MARK: - Import

    private var importerPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Import a Video", systemImage: "square.and.arrow.down")

                dropZone

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallpaper name")
                        .font(.callout.weight(.medium))
                    TextField("Example: Yoimiya 4K", text: $model.title)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                if model.isWorking {
                    progressCard
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }

                Button {
                    model.importSelectedVideo()
                } label: {
                    Label {
                        Text("Import into Aerials")
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .symbolEffect(.pulse, options: .repeating, isActive: model.isWorking)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.canImport)

                whatHappensCard

                Spacer(minLength: 8)

                Text("After importing, select the new item in System Settings → Wallpaper; macOS applies it to Desktop, Lock Screen and Screen Saver natively. You may quit AerialDrop after setup; macOS handles playback natively.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(importPaneBackground)
        .scrollIndicators(.hidden)
    }

    private var importPaneBackground: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0.00, 0.00), SIMD2(0.50, 0.02), SIMD2(1.00, 0.00),
                SIMD2(0.02, 0.50), SIMD2(0.50, 0.50), SIMD2(0.98, 0.50),
                SIMD2(0.00, 1.00), SIMD2(0.50, 0.98), SIMD2(1.00, 1.00)
            ],
            colors: [
                Color(red: 0.22, green: 0.24, blue: 0.48), Color(red: 0.10, green: 0.55, blue: 0.55), Color(red: 0.22, green: 0.24, blue: 0.48),
                Color(red: 0.12, green: 0.30, blue: 0.55), Color(red: 0.42, green: 0.30, blue: 0.62), Color(red: 0.12, green: 0.30, blue: 0.55),
                Color(red: 0.22, green: 0.24, blue: 0.48), Color(red: 0.06, green: 0.46, blue: 0.52), Color(red: 0.22, green: 0.24, blue: 0.48)
            ],
            smoothsColors: true
        )
        .opacity(0.4)
        .allowsHitTesting(false)
    }

    private var dropZone: some View {
        Button {
            model.showingFileImporter = true
        } label: {
            VStack(spacing: 12) {
                if let url = model.selectedVideo {
                    Image(systemName: "film.fill")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Click to choose another file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 30, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .padding(18)
                        .glassEffect(.regular, in: Circle())
                        .symbolEffect(.pulse, isActive: hoveringDropZone)
                    Text("Choose or drop a video")
                        .font(.headline)
                    Text("MP4 or MOV · The source file is not modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(16)
            .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundStyle(hoveringDropZone ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.quaternary))
            }
            .scaleEffect(hoveringDropZone ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hoveringDropZone = $0 }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: hoveringDropZone)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            model.chooseVideo(first)
            return true
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: model.stage.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: model.stage != .finished)
                    .foregroundStyle(.tint)
                Text(model.stage.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ProgressView(value: model.stage.progress)
                .tint(.accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var whatHappensCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happens")
                .font(.callout.weight(.semibold))
            ForEach(whatHappensRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26, height: 26)
                        .background(.tint.opacity(0.14), in: Circle())
                    Text(row.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private struct WhatHappensRow: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private let whatHappensRows: [WhatHappensRow] = [
        WhatHappensRow(icon: "film", text: "Builds an 80-second, 30 fps HEVC Main10 stream with native temporal sub-layers"),
        WhatHappensRow(icon: "photo", text: "Normalizes timestamp zero and creates a Tahoe-compatible HEIF preview"),
        WhatHappensRow(icon: "doc.badge.gearshape", text: "Backs up entries.json and preserves other apps’ entries"),
        WhatHappensRow(icon: "rectangle.stack", text: "Adds a complete Tahoe Aerial catalogue entry")
    ]

    // MARK: - Library

    private var libraryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    sectionHeader("Imported Wallpapers", systemImage: "photo.stack")
                    Text("\(model.wallpapers.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }

                if model.wallpapers.isEmpty {
                    emptyLibrary
                } else {
                    LazyVGrid(columns: wallpaperColumns, spacing: 16) {
                        ForEach(model.wallpapers) { wallpaper in
                            WallpaperCard(wallpaper: wallpaper) {
                                model.remove(wallpaper)
                            }
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: model.wallpapers)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .scrollIndicators(.hidden)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No AerialDrop Wallpapers", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Imported videos will appear here and under the AerialDrop section in System Settings.")
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

// MARK: - Wallpaper card

private struct WallpaperCard: View {
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
