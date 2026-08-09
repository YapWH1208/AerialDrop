import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: AppDestination? = .library
    @State private var removeAllConfirmation = false
    @State private var alertPresented = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $destination) {
                ForEach(AppDestination.allCases) { destination in
                    if destination == .library {
                        Label(destination.title, systemImage: destination.systemImage)
                            .badge(model.wallpapers.count)
                            .tag(destination)
                    } else {
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
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
            ToolbarItem(placement: .primaryAction) {
                Button("Import Wallpaper", systemImage: "plus") {
                    beginImport()
                }
                .buttonStyle(.borderedProminent)
                .help("Choose an MP4 or MOV to import")
            }

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
            guard phase == .active else { return }
            Task { await model.reload() }
        }
        .onChange(of: model.showingFileImporter) { _, showing in
            if showing {
                destination = .importVideo
            }
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

    @ViewBuilder
    private var destinationView: some View {
        switch destination ?? .library {
        case .library:
            LibraryPane(onImport: beginImport)
                .navigationTitle("Library")
        case .importVideo:
            ImportPane()
                .navigationTitle("Import Wallpaper")
        }
    }

    private func beginImport() {
        destination = .importVideo
        model.showingFileImporter = true
    }

    private var maintenanceMenu: some View {
        Menu("Maintenance", systemImage: "ellipsis.circle") {
            Button("Open Aerial Storage Folder") { model.openStorageFolder() }
            Button("Validate Current Catalogue") { model.validateCatalogue() }
            Divider()
            Button("Remove All AerialDrop Wallpapers", role: .destructive) {
                removeAllConfirmation = true
            }
            .disabled(model.wallpapers.isEmpty || model.isWorking)
        }
        .labelStyle(.iconOnly)
        .help("Catalogue maintenance")
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
