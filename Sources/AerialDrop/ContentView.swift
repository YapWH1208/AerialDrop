import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: AppDestination? = .library
    @State private var preImportDestination: AppDestination?
    @State private var removeAllConfirmation = false
    @State private var alertPresented = false
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
            destinationView
        }
        .tint(AerialTheme.accent)
        .toolbar {
            primaryToolbarContent

            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Reload Catalogue", systemImage: "arrow.clockwise") {
                    Task { await model.reload() }
                }
                .disabled(model.isWorking)

                Button("Wallpaper Settings", systemImage: "gearshape") {
                    model.openWallpaperSettings()
                }

                maintenanceMenu
            }
        }
        .alert("AerialDrop", isPresented: $alertPresented) { } message: {
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
        .onChange(of: model.alertMessage) { _, newValue in
            if let newValue {
                alertMessage = newValue
                alertPresented = true
            }
        }
        .onChange(of: alertPresented) { _, presented in
            if !presented && model.alertMessage != nil {
                model.alertMessage = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !model.isWorking else { return }
            Task { await model.reload() }
        }
        .onChange(of: model.showingFileImporter) { _, showing in
            guard showing else { return }
            if destination != .importVideo {
                preImportDestination = destination
            }
            destination = .importVideo
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
                preImportDestination = nil
                if let url = urls.first { model.chooseVideo(url) }
            case .failure(let error):
                if (error as NSError).code == NSUserCancelledError {
                    if let preImportDestination {
                        destination = preImportDestination
                    }
                    preImportDestination = nil
                } else {
                    model.alertMessage = error.localizedDescription
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
            LibraryPane(onImport: beginImport)
                .navigationTitle("Library")
        case .importVideo:
            ImportPane(onViewLibrary: { destination = .library })
                .navigationTitle("Import Wallpaper")
        }
    }

    private func beginImport() {
        model.showingFileImporter = true
    }

    @ToolbarContentBuilder
    private var primaryToolbarContent: some ToolbarContent {
        if isImportInProgress {
            ToolbarItemGroup(placement: .primaryAction) {
                ProgressView(value: model.displayProgress)
                    .frame(width: 84)
                    .accessibilityLabel(model.stage.label)
                    .accessibilityValue(importProgressValue)
                    .help("\(model.stage.label) \(importProgressValue)")

                if model.isImportCancellable {
                    Button("Cancel Import", systemImage: "xmark") {
                        model.cancelImport()
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel before catalogue installation begins")
                }
            }
        } else if model.catalogueState == .ready {
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

    private var importProgressValue: String {
        "\(Int(model.displayProgress * 100)) percent"
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
            Button("Remove All AerialDrop Wallpapers", role: .destructive) {
                removeAllConfirmation = true
            }
            .disabled(
                model.wallpapers.isEmpty
                    || model.isWorking
                    || model.hasActiveManagedWallpaper
            )
            .help(removeAllHelp)
        }
        .labelStyle(.iconOnly)
        .help("Catalogue maintenance")
    }

    private var removeAllHelp: String {
        if model.hasActiveManagedWallpaper {
            return "Choose a different wallpaper before removing all AerialDrop wallpapers"
        }
        return "Remove every AerialDrop wallpaper"
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
