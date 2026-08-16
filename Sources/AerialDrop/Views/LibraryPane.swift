import AppKit
import SwiftUI

enum LibrarySortOrder: String, CaseIterable {
    case title
    case recentlyAdded
}

struct LibraryPane: View {
    static let sortOrderKey = "librarySortOrder"
    let onImport: () -> Void
    let onDropVideo: (URL) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIDs: Set<String> = []
    @State private var searchText = ""
    @State private var previewWallpaper: ManagedWallpaper?
    @State private var pendingRemoval: ManagedWallpaper?
    @State private var pendingBulkRemoval: [ManagedWallpaper] = []
    @State private var showingBulkRemoveConfirmation = false
    @State private var showingRemoveConfirmation = false
    @State private var renameTarget: ManagedWallpaper?
    @State private var renameText = ""
    @State private var showingRenameAlert = false
    @State private var highlightTarget: String?
    @State private var dropTargeted = false
    @AppStorage(LibraryPane.sortOrderKey) private var sortOrder = LibrarySortOrder.title

    private let wallpaperColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)
    ]

    private var filteredWallpapers: [ManagedWallpaper] {
        let base: [ManagedWallpaper]
        if searchText.isEmpty {
            base = model.wallpapers
        } else {
            base = model.wallpapers.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOrder {
        case .title:
            return base
        case .recentlyAdded:
            return base.sorted { lhs, rhs in
                let lhsOrder = lhs.preferredOrder ?? Int.min
                let rhsOrder = rhs.preferredOrder ?? Int.min
                if lhsOrder != rhsOrder {
                    return lhsOrder > rhsOrder
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
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
        .confirmationDialog(
            "Remove \(pendingBulkRemoval.count) wallpapers?",
            isPresented: $showingBulkRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(pendingBulkRemoval.count)", role: .destructive) { confirmBulkRemoval() }
            Button("Cancel", role: .cancel) { pendingBulkRemoval = [] }
        } message: {
            Text("This removes the selected wallpapers and their copied video and thumbnail files. Your original source videos are untouched — import them again to restore them. A catalogue backup is created first.")
        }
        .alert("Rename Wallpaper", isPresented: $showingRenameAlert) {
            TextField("Wallpaper name", text: $renameText)
                .disabled(model.isWorking)
            Button("Rename") { performRename() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRename)
            Button("Cancel", role: .cancel) { }
        } message: {
            renameMessage
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

            if selectedWallpapers.count > 1 {
                bulkSelectionBanner
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
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Picker("Sort", selection: $sortOrder) {
                            Text("Title").tag(LibrarySortOrder.title)
                            Text("Recently Added").tag(LibrarySortOrder.recentlyAdded)
                        }
                        .pickerStyle(.menu)
                        .disabled(model.wallpapers.count < 2)
                    }
                }
            }
        }
    }

    private var selectedWallpapers: [ManagedWallpaper] {
        model.wallpapers.filter { selectedIDs.contains($0.id) }
    }

    private var bulkSelectionBanner: some View {
        HStack(spacing: 10) {
            Text("\(selectedIDs.count) wallpapers selected")
                .font(.callout)
            Spacer()
            Button("Clear Selection") {
                selectedIDs = []
            }
            .disabled(model.isWorking)
            Button("Remove Selected…", role: .destructive) {
                requestBulkRemoval()
            }
            .disabled(!canBulkRemove)
            .help(bulkRemoveHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }

    private var canBulkRemove: Bool {
        !model.isWorking
            && !selectedWallpapers.contains { model.activeAerialAssetIDs.contains($0.id) }
    }

    private var bulkRemoveHelp: String {
        if model.isWorking {
            return "Wait for the current operation to finish"
        }
        if selectedWallpapers.contains(where: { model.activeAerialAssetIDs.contains($0.id) }) {
            return "One of the selected wallpapers is currently active — choose a different wallpaper first"
        }
        return "Remove the selected wallpapers"
    }

    private func requestBulkRemoval() {
        pendingBulkRemoval = selectedWallpapers
        showingBulkRemoveConfirmation = true
    }

    private func confirmBulkRemoval() {
        let wallpapers = pendingBulkRemoval
        pendingBulkRemoval = []
        selectedIDs = []
        guard !wallpapers.isEmpty else { return }
        model.remove(wallpapers)
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
                            isSelected: selectedIDs.contains(wallpaper.id),
                            isActive: model.activeAerialAssetIDs.contains(wallpaper.id),
                            isWorking: model.isWorking,
                            onSelect: {
                                guard !model.isWorking else { return }
                                select(wallpaper)
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
        selectedIDs = [id]
        highlightTarget = id
        model.pendingLibraryHighlightID = nil
    }

    /// Plain clicks keep single-selection semantics; Command- and Shift-click
    /// extend the selection so several wallpapers can be removed at once.
    private func select(_ wallpaper: ManagedWallpaper) {
        let modifiers = NSEvent.modifierFlags
        let extendsSelection = modifiers.contains(.command) || modifiers.contains(.shift)
        if extendsSelection {
            if selectedIDs.contains(wallpaper.id) {
                selectedIDs.remove(wallpaper.id)
            } else {
                selectedIDs.insert(wallpaper.id)
            }
        } else if selectedIDs == [wallpaper.id] {
            selectedIDs = []
        } else {
            selectedIDs = [wallpaper.id]
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

    private var canRename: Bool {
        guard let renameTarget, !model.isWorking else { return false }
        let cleanTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanTitle.isEmpty && cleanTitle != renameTarget.title
    }

    /// Mirrors the import pane's duplicate-name warning so both naming paths
    /// share one policy: warn, but permit.
    private var renameDuplicateTitle: String? {
        guard let target = renameTarget else { return nil }
        let clean = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let collides = model.wallpapers.contains {
            $0.id != target.id
                && $0.title.localizedCaseInsensitiveCompare(clean) == .orderedSame
        }
        return collides ? clean : nil
    }

    private var renameMessage: Text {
        var message = "This updates the name shown in System Settings and AerialDrop."
        if let duplicate = renameDuplicateTitle {
            message += "\n\nA wallpaper named “\(duplicate)” already exists."
        }
        return Text(message)
    }

    private func openPreview(_ wallpaper: ManagedWallpaper) {
        selectedIDs = [wallpaper.id]
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
