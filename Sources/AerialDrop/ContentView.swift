import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var removeAllConfirmation = false

    var body: some View {
        HSplitView {
            ImportPane()
                .frame(minWidth: 420, maxWidth: 540)
            LibraryPane()
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
}