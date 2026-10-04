import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: AppDestination? = .library
    @State private var preImportDestination: AppDestination?
    @State private var confirmation: ConfirmationKind?
    @State private var alertPresented = false
    @State private var alertTitle = "AerialDrop"
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $destination) {
                ForEach(AppDestination.allCases) { item in
                    if item == .library {
                        Label(item.title, systemImage: item.systemImage)
                            .badge(model.wallpapers.count)
                            .tag(item)
                    } else {
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("AerialDrop")
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                catalogueRefreshBanner
                if destination == .library && isImportInProgress {
                    LibraryImportStatusView(
                        stage: model.stage,
                        progress: model.displayProgress,
                        eta: model.encodeETA,
                        canCancel: model.isImportCancellable,
                        onCancel: model.cancelImport,
                        onViewImport: { destination = .importVideo }
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                destinationView
            }
        }
        .tint(AerialTheme.accent)
        .toolbar {
            primaryToolbarContent

            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Reload Catalogue", systemImage: "arrow.clockwise") {
                    Task { await model.refreshCataloguePreservingContent() }
                }
                .disabled(model.isWorking || model.catalogueRefreshState == .refreshing)

                Button("Wallpaper Settings", systemImage: "photo") {
                    model.openWallpaperSettings()
                }

                maintenanceMenu
            }
        }
        .alert(alertTitle, isPresented: $alertPresented) { } message: {
            Text(alertMessage ?? "")
        }
        .alert(
            "Couldn’t Set Wallpaper",
            isPresented: Binding(
                get: { model.activationFailure != nil },
                set: { if !$0 { model.dismissActivationFailure() } }
            )
        ) {
            Button("Try Again") { model.retryActivation() }
            Button("Open Wallpaper Settings") { model.openWallpaperSettings() }
            Button("Not Now", role: .cancel) { model.dismissActivationFailure() }
        } message: {
            let failureMessage = model.activationFailureMessage
                ?? "You can retry or choose it in System Settings."
            Text("AerialDrop kept its imported video and catalogue entry, but could not apply it as wallpaper. \(failureMessage)")
        }
        .onChange(of: model.activeAlert) { _, newValue in
            if let newValue {
                alertTitle = newValue.title
                alertMessage = newValue.message
                alertPresented = true
            }
        }
        .onChange(of: alertPresented) { _, presented in
            if !presented && model.activeAlert != nil {
                model.activeAlert = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !model.isWorking else { return }
            Task { await model.refreshCataloguePreservingContent() }
        }
        .onChange(of: model.catalogueRefreshState) { _, state in
            if case .failed = state {
                AccessibilityNotification.Announcement(
                    "Couldn’t refresh the catalogue. The last loaded wallpapers are still shown."
                ).post()
            }
        }
        .onChange(of: model.showingFileImporter) { _, showing in
            guard showing else { return }
            if destination != .importVideo {
                preImportDestination = destination
            }
            destination = .importVideo
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            switch confirmation {
            case .removeAll(let requiresAcknowledgement):
                if requiresAcknowledgement {
                    Button("Check Again") { retryRemoveAllPreparation() }
                    Button("Open Wallpaper Settings") {
                        confirmation = nil
                        model.openWallpaperSettings()
                    }
                    Button("Remove Anyway", role: .destructive) {
                        performConfirmation(allowingUnverifiedSelection: true)
                    }
                } else {
                    Button("Remove All", role: .destructive) { performConfirmation() }
                }
            case .restore:
                Button("Restore Backup") { performConfirmation() }
            case nil:
                EmptyView()
            }
            Button(confirmationCancelTitle, role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmationMessage)
        }
        .fileImporter(
            isPresented: $model.showingFileImporter,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                preImportDestination = nil
                if let url = urls.first { model.chooseVideo(url) }
            case .failure(let error):
                if (error as NSError).code == NSUserCancelledError {
                    if let preImportDestination {
                        destination = preImportDestination
                    }
                    preImportDestination = nil
                } else {
                    model.activeAlert = AppAlert(
                        title: "Couldn’t Choose a Video",
                        message: error.localizedDescription
                    )
                }
            }
        }
        .fileDialogMessage("Choose an MP4 or MOV video to turn into a native Aerial wallpaper.")
        .fileDialogConfirmationLabel("Choose Video")
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination ?? .library {
        case .library:
            LibraryPane(
                onImport: beginImport,
                onDropVideo: { url in
                    model.chooseVideo(url)
                    destination = .importVideo
                }
            )
            .navigationTitle("Library")
        case .importVideo:
            ImportPane(onViewLibrary: { destination = .library })
                .navigationTitle("Import Wallpaper")
        }
    }

    @ViewBuilder
    private var catalogueRefreshBanner: some View {
        switch model.catalogueRefreshState {
        case .idle:
            EmptyView()
        case .refreshing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing catalogue…")
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6))
            .accessibilityElement(children: .combine)
        case .failed(let message):
            HStack(spacing: 10) {
                Label("Couldn’t refresh catalogue", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(message)

                Spacer()

                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await model.refreshCataloguePreservingContent() }
                }
                .disabled(model.isWorking)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6))
            .accessibilityElement(children: .contain)
        }
    }

    private func beginImport() {
        guard !model.isWorking else { return }
        model.showingFileImporter = true
    }

    @ToolbarContentBuilder
    private var primaryToolbarContent: some ToolbarContent {
        if !isImportInProgress, model.catalogueState == .ready {
            if destination == .importVideo, model.selectedVideo != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Replace Video…", systemImage: "arrow.triangle.2.circlepath") {
                        beginImport()
                    }
                    .disabled(model.isWorking)
                    .help("Replace the selected source video")

                    Button("Import Wallpaper", systemImage: "square.and.arrow.down") {
                        model.importSelectedVideo()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canImport)
                    .help(importActionHelp)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button(primaryActionTitle, systemImage: primaryActionIcon) {
                        performPrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .help(primaryActionHelp)
                }
            }
        }
    }

    private var isImportInProgress: Bool {
        model.isWorking && model.stage != .idle && model.stage != .finished
    }

    private var primaryActionTitle: String {
        if destination == .library, model.selectedVideo != nil {
            return "Continue Import"
        }
        if model.importOutcome != nil {
            return "Import Another…"
        }
        return destination == .library ? "Import Wallpaper…" : "Choose Video…"
    }

    private var primaryActionIcon: String {
        destination == .library && model.selectedVideo != nil ? "arrow.right" : "plus"
    }

    private var primaryActionHelp: String {
        if destination == .library, model.selectedVideo != nil {
            return "Continue configuring the selected source video"
        }
        return "Choose an MP4 or MOV video"
    }

    private var importActionHelp: String {
        if !model.isSelectedVideoValid {
            return "Wait for video validation to finish"
        }
        if model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a wallpaper name before importing"
        }
        return "Import the selected video (⌘↩)"
    }

    private func performPrimaryAction() {
        if destination == .library, model.selectedVideo != nil {
            destination = .importVideo
        } else {
            beginImport()
        }
    }

    private var maintenanceMenu: some View {
        Menu("Maintenance", systemImage: "ellipsis.circle") {
            Button("Open Aerial Storage Folder") { model.openStorageFolder() }
            Button("Validate Current Catalogue") { model.validateCatalogue() }
            Divider()
            Button("Restore Latest Backup…") {
                if let info = model.latestBackupInfo() {
                    confirmation = .restore(info)
                } else {
                    model.activeAlert = AppAlert(
                        title: "No Backups Found",
                        message: "No AerialDrop backups were found."
                    )
                }
            }
            .disabled(model.isWorking)
            .help("Replace the current catalogue with the newest AerialDrop backup")
            Divider()
            Button("Remove All AerialDrop Wallpapers", role: .destructive) {
                requestRemoveAll()
            }
            .disabled(
                model.wallpapers.isEmpty
                    || model.isWorking
                    || (model.hasActiveManagedWallpaper && !model.isSelectionStatusUnknown)
            )
            .help(removeAllHelp)
        }
        .labelStyle(.iconOnly)
        .help("Catalogue maintenance")
    }

    private var removeAllHelp: String {
        if model.hasActiveManagedWallpaper && !model.isSelectionStatusUnknown {
            return "Choose a different wallpaper before removing all AerialDrop wallpapers"
        }
        if model.isSelectionStatusUnknown {
            return "Check the active wallpaper before removing every AerialDrop wallpaper"
        }
        return "Remove every AerialDrop wallpaper"
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .removeAll(let requiresAcknowledgement):
            requiresAcknowledgement
                ? "Remove without checking which wallpaper is active?"
                : "Remove every AerialDrop wallpaper?"
        case .restore(let info):
            "Restore the backup from \(info.date.formatted(date: .abbreviated, time: .shortened))?"
        case nil:
            ""
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .removeAll(let requiresAcknowledgement):
            if requiresAcknowledgement {
                "AerialDrop can’t verify which wallpaper is active. Removing an active wallpaper could leave macOS pointing to missing files. Check again, choose another wallpaper in Wallpaper Settings, or remove anyway."
            } else {
                "This removes every AerialDrop entry and its copied video and thumbnail files. Your original source videos are untouched — import them again to restore them. A catalogue backup is created first."
            }
        case .restore(let info):
            "This replaces the current Aerial catalogue with the backup from \(info.date.formatted(date: .abbreviated, time: .shortened)) (\(info.operation)). The current catalogue is backed up first. Restoring is refused if it would change newer Apple catalogue data or remove a currently active wallpaper. Active status must be verified before a restore can remove entries. Wallpapers whose video files were deleted since the backup will appear as “Video missing” and can be removed."
        case nil:
            ""
        }
    }

    private var confirmationCancelTitle: String {
        switch confirmation {
        case .removeAll: "Keep Wallpapers"
        case .restore: "Keep Current Catalogue"
        case nil: "Cancel"
        }
    }

    private func requestRemoveAll() {
        let ids = Set(model.wallpapers.map(\.id))
        switch model.removalReadiness(for: ids) {
        case .verifiedInactive:
            confirmation = .removeAll(requiresAcknowledgement: false)
        case .verifiedActive:
            confirmation = nil
            model.reportActiveWallpaperRemovalBlock()
        case .unknown:
            confirmation = .removeAll(requiresAcknowledgement: true)
        }
    }

    private func retryRemoveAllPreparation() {
        confirmation = nil
        Task {
            await Task.yield()
            requestRemoveAll()
        }
    }

    private func performConfirmation(allowingUnverifiedSelection: Bool = false) {
        switch confirmation {
        case .removeAll:
            model.removeAll(allowingUnverifiedSelection: allowingUnverifiedSelection)
        case .restore(let info):
            Task { await model.restoreLatestBackup(info) }
        case nil:
            break
        }
        confirmation = nil
    }
}

private struct LibraryImportStatusView: View {
    let stage: ImportStage
    let progress: Double
    let eta: TimeInterval?
    let canCancel: Bool
    let onCancel: () -> Void
    let onViewImport: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Label(stage.label, systemImage: stage.icon)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text("\(Int(progress * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                ProgressView(value: progress)
                    .accessibilityLabel("Import progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        supportingStatus(oneLine: true)
                        Spacer(minLength: 8)
                        actionButtons
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        supportingStatus(oneLine: false)
                        HStack(spacing: 8) {
                            Spacer()
                            actionButtons
                        }
                    }
                }
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import status")
    }

    private func supportingStatus(oneLine: Bool) -> some View {
        Text(supportingStatusLabel)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(oneLine ? 1 : nil)
            .fixedSize(horizontal: oneLine, vertical: false)
            .frame(maxWidth: oneLine ? nil : .infinity, alignment: .leading)
    }

    private var supportingStatusLabel: String {
        if let etaText { return etaText }
        if canCancel { return "The source video stays unchanged." }
        return "Finishing installation. This step can’t be cancelled."
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if canCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel before catalogue installation begins")
            }

            Button("View Import", systemImage: "arrow.right", action: onViewImport)
                .controlSize(.small)
        }
    }

    private var etaText: String? {
        guard let eta, eta > 5 else { return nil }
        if eta >= 60 {
            return "≈ \(Int(eta / 60)) min left"
        }
        return "≈ \(Int(eta)) s left"
    }
}

/// The single confirmation dialog covers the maintenance flows that need one.
private enum ConfirmationKind: Identifiable {
    case removeAll(requiresAcknowledgement: Bool)
    case restore(ManifestStore.BackupInfo)

    var id: String {
        switch self {
        case .removeAll: "removeAll"
        case .restore: "restore"
        }
    }
}

private enum AppDestination: String, CaseIterable, Identifiable {
    case library
    case importVideo

    var id: Self { self }

    var title: String {
        switch self {
        case .library: "Library"
        case .importVideo: "Import"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "photo.on.rectangle.angled"
        case .importVideo: "square.and.arrow.down"
        }
    }
}
