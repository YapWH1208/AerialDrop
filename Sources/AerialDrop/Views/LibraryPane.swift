import SwiftUI

struct LibraryPane: View {
    let onImport: () -> Void
    let onDropVideo: (URL) -> Void

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
    @State private var highlightTarget: String?
    @State private var dropTargeted = false

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
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(12)
                    .overlay {
                        Label("Drop to import as wallpaper", systemImage: "plus.circle")
                            .font(.headline)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.catalogueState == .ready, !model.isWorking, let first = urls.first else { return false }
            // Mirror VideoProcessor.validate: only movie files enter the import flow.
            let ext = first.pathExtension.lowercased()
            guard ext == "mp4" || ext == "mov" else { return false }
            onDropVideo(first)
            return true
        } isTargeted: { targeted in
            guard model.catalogueState == .ready, !model.isWorking else { return }
            dropTargeted = targeted
        }
        .onChange(of: model.operationLabel) { _, label in
            if let label {
                AccessibilityNotification.Announcement(label).post()
            }
        }
        .onAppear {
            applyPendingHighlight()
        }
        .onChange(of: model.pendingLibraryHighlightID) { _, _ in
            applyPendingHighlight()
        }
        .confirmationDialog(
            removeDialogTitle,
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { confirmRemoval() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the wallpaper and its copied video and thumbnail files. Your original source video is untouched — import it again to restore it. A catalogue backup is created first.")
        }
        .alert("Rename Wallpaper", isPresented: $showingRenameAlert) {
            TextField("Wallpaper name", text: $renameText)
                .disabled(model.isWorking)
            Button("Rename") { performRename() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRename)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This updates the name shown in System Settings and AerialDrop.")
        }
        .sheet(item: $previewWallpaper) { wallpaper in
            WallpaperPreviewView(
                wallpaper: wallpaper,
                isActive: model.activeAerialAssetIDs.contains(wallpaper.id),
                isWorking: model.isWorking,
                operationLabel: model.operationLabel,
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
        VStack(spacing: 12) {
            if let label = model.operationLabel {
                operationBanner(label)
            }

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
    }

    private func operationBanner(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private var wallpaperGrid: some View {
        ScrollViewReader { proxy in
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
                        .id(wallpaper.id)
                    }
                }
                .padding(24)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.wallpapers)
            }
            .onChange(of: highlightTarget) { _, target in
                guard let target else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                highlightTarget = nil
            }
        }
    }

    /// Selects and scrolls to the wallpaper whose import just completed,
    /// clearing the request so it is applied only once.
    private func applyPendingHighlight() {
        guard let id = model.pendingLibraryHighlightID,
              model.wallpapers.contains(where: { $0.id == id }) else { return }
        if !searchText.isEmpty {
            searchText = ""
        }
        selectedID = id
        highlightTarget = id
        model.pendingLibraryHighlightID = nil
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

    private var canRename: Bool {
        guard let renameTarget, !model.isWorking else { return false }
        let cleanTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanTitle.isEmpty && cleanTitle != renameTarget.title
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
