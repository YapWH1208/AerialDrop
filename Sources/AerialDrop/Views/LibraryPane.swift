import SwiftUI

struct LibraryPane: View {
    let onImport: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var previewWallpaper: ManagedWallpaper?
    @State private var pendingRemoval: ManagedWallpaper?
    @State private var showingRemoveConfirmation = false
    @State private var renameTarget: ManagedWallpaper?
    @State private var renameText = ""
    @State private var showingRenameAlert = false

    private let wallpaperColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)
    ]

    private var filteredWallpapers: [ManagedWallpaper] {
        guard !searchText.isEmpty else { return model.wallpapers }
        return model.wallpapers.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        libraryState
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            removeDialogTitle,
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { confirmRemoval() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the wallpaper and its copied video and thumbnail files. A manifest backup is created first.")
        }
        .alert("Rename Wallpaper", isPresented: $showingRenameAlert) {
            TextField("Wallpaper name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This updates the name shown in System Settings and AerialDrop.")
        }
        .sheet(item: $previewWallpaper) { wallpaper in
            WallpaperPreviewView(
                wallpaper: wallpaper,
                isActive: model.activeAerialAssetIDs.contains(wallpaper.id),
                isWorking: model.isWorking,
                onSetWallpaper: { model.setWallpaper(wallpaper) },
                onRename: {
                    previewWallpaper = nil
                    DispatchQueue.main.async { beginRename(wallpaper) }
                },
                onRemove: {
                    previewWallpaper = nil
                    DispatchQueue.main.async { requestRemoval(wallpaper) }
                },
                onReveal: { model.revealInFinder(wallpaper) }
            )
        }
    }

    @ViewBuilder
    private var libraryState: some View {
        switch model.catalogueState {
        case .loading:
            CatalogueAccessView(
                state: model.catalogueState,
                onOpenSettings: model.openWallpaperSettings,
                onCheckAgain: { Task { await model.reload() } }
            )
        case .ready:
            readyLibrary
        case .unavailable:
            CatalogueAccessView(
                state: model.catalogueState,
                onOpenSettings: model.openWallpaperSettings,
                onCheckAgain: { Task { await model.reload() } }
            )
        }
    }

    @ViewBuilder
    private var readyLibrary: some View {
        if model.wallpapers.isEmpty {
            emptyLibrary
        } else {
            Group {
                if filteredWallpapers.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    wallpaperGrid
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search wallpapers")
        }
    }

    private var wallpaperGrid: some View {
        ScrollView {
            LazyVGrid(columns: wallpaperColumns, spacing: 20) {
                ForEach(filteredWallpapers) { wallpaper in
                    WallpaperCard(
                        wallpaper: wallpaper,
                        isSelected: selectedID == wallpaper.id,
                        isActive: model.activeAerialAssetIDs.contains(wallpaper.id),
                        isWorking: model.isWorking,
                        onSelect: {
                            guard !model.isWorking else { return }
                            selectedID = selectedID == wallpaper.id ? nil : wallpaper.id
                        },
                        onDoubleClick: { openPreview(wallpaper) },
                        onPreview: { openPreview(wallpaper) },
                        onSetWallpaper: { model.setWallpaper(wallpaper) },
                        onRename: { beginRename(wallpaper) },
                        onReveal: { model.revealInFinder(wallpaper) },
                        onRemove: { requestRemoval(wallpaper) }
                    )
                }
            }
            .padding(24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.wallpapers)
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No AerialDrop Wallpapers", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Import a video to add it to the native Aerial catalogue.")
        } actions: {
            Button("Import Wallpaper", systemImage: "plus", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }

    private var removeDialogTitle: String {
        if let name = pendingRemoval?.title {
            return "Remove “\(name)”?"
        }
        return "Remove this wallpaper?"
    }

    private func openPreview(_ wallpaper: ManagedWallpaper) {
        selectedID = wallpaper.id
        previewWallpaper = wallpaper
    }

    private func requestRemoval(_ wallpaper: ManagedWallpaper) {
        pendingRemoval = wallpaper
        showingRemoveConfirmation = true
    }

    private func confirmRemoval() {
        if let wallpaper = pendingRemoval {
            model.remove(wallpaper)
        }
        pendingRemoval = nil
    }

    private func beginRename(_ wallpaper: ManagedWallpaper) {
        renameTarget = wallpaper
        renameText = wallpaper.title
        showingRenameAlert = true
    }

    private func performRename() {
        if let target = renameTarget {
            model.rename(target, to: renameText)
        }
        renameTarget = nil
    }
}
