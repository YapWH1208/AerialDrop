import SwiftUI

struct LibraryPane: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var searchText = ""
    @Namespace private var glass

    @State private var previewWallpaper: ManagedWallpaper?
    @State private var pendingRemoval: ManagedWallpaper?
    @State private var showingRemoveConfirmation = false
    @State private var renameTarget: ManagedWallpaper?
    @State private var renameText = ""
    @State private var showingRenameAlert = false

    private let wallpaperColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    private var filteredWallpapers: [ManagedWallpaper] {
        guard !searchText.isEmpty else { return model.wallpapers }
        return model.wallpapers.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    SectionHeader(title: "Imported Wallpapers", systemImage: "photo.stack")
                    Text("\(model.wallpapers.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: model.wallpapers.count)
                    Spacer()
                }

                if model.wallpapers.isEmpty {
                    emptyLibrary
                } else if filteredWallpapers.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 380)
                } else {
                    LazyVGrid(columns: wallpaperColumns, spacing: 16) {
                        ForEach(filteredWallpapers) { wallpaper in
                            WallpaperCard(
                                wallpaper: wallpaper,
                                isSelected: selectedID == wallpaper.id,
                                isActive: model.activeAerialAssetIDs.contains(wallpaper.id),
                                namespace: glass,
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
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: model.wallpapers)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search wallpapers")
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

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No AerialDrop Wallpapers", systemImage: "rectangle.stack.badge.plus")
                .symbolEffect(.bounce, options: .repeat(1))
        } description: {
            Text("Imported videos will appear here and under the AerialDrop section in System Settings.")
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .rect(cornerRadius: 22))
    }
}
