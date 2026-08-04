import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var removeAllConfirmation = false
    @State private var alertPresented = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var model = model
        HSplitView {
            ImportPane()
                .frame(minWidth: 420, maxWidth: 540)
            LibraryPane()
                .frame(minWidth: 470)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(AuroraBackground().ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text("AerialDrop")
                        .font(.system(size: 28, weight: .bold))
                    Text("v\(AppVersion.shortVersion)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
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
                Button("Reload Catalogue", systemImage: "arrow.clockwise") {
                    Task { await model.reload() }
                }
                .buttonStyle(.glass)
                .disabled(model.isWorking)
            }
            ToolbarItem(placement: .primaryAction) {
                maintenanceMenu
            }
        }
        .alert("AerialDrop", isPresented: $alertPresented) { } message: {
            Text(alertMessage ?? "")
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
        .background {
            Button("Choose Video") { model.showingFileImporter = true }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Toolbar

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
        .menuStyle(.button)
        .buttonStyle(.glass)
        .labelStyle(.iconOnly)
    }
}