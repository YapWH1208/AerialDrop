import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var selectedVideo: URL?
    var title = ""
    var wallpapers: [ManagedWallpaper] = []
    var stage: ImportStage = .idle
    var isWorking = false
    var alertMessage: String?
    var showingFileImporter = false

    private let paths = WallpaperPaths()
    private let manifestStore: ManifestStore
    private let videoProcessor = VideoProcessor()
    private let systemService = SystemWallpaperService()

    init() {
        manifestStore = ManifestStore(paths: paths)
        Task { await reload() }
    }

    var canImport: Bool {
        selectedVideo != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    func chooseVideo(_ url: URL) {
        selectedVideo = url
        title = url.deletingPathExtension().lastPathComponent
    }

    func importSelectedVideo() {
        guard let source = selectedVideo else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            alertMessage = AerialDropError.invalidTitle.localizedDescription
            return
        }

        Task {
            isWorking = true
            defer { isWorking = false }

            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            let id = UUID().uuidString.uppercased()
            let videoDestination = paths.videoURL(for: id)
            let thumbnailDestination = paths.thumbnailURL(for: id)

            do {
                try requireTahoe()
                stage = .validating
                try await videoProcessor.validate(source: source)

                stage = .preparingFolders
                try manifestStore.requireManifest()
                try manifestStore.prepareDirectories()

                stage = .processingVideo
                try await videoProcessor.makeNativeMOV(from: source, destination: videoDestination)

                stage = .generatingThumbnail
                try await videoProcessor.generateThumbnail(from: videoDestination, destination: thumbnailDestination)

                stage = .updatingManifest
                try manifestStore.addWallpaper(id: id, title: cleanTitle)

                stage = .refreshingSystem
                await systemService.refresh()
                systemService.openWallpaperSettings()

                stage = .finished
                selectedVideo = nil
                title = ""
                await reload()
                alertMessage = "Import completed. Select the new AerialDrop item in System Settings → Wallpaper and apply it as you would any Aerial; macOS links Desktop, Lock Screen and Screen Saver natively. You may quit AerialDrop."
            } catch {
                try? FileManager.default.removeItem(at: videoDestination)
                try? FileManager.default.removeItem(at: thumbnailDestination)
                stage = .idle
                alertMessage = error.localizedDescription
            }
        }
    }

    func remove(_ wallpaper: ManagedWallpaper) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try manifestStore.removeWallpaper(id: wallpaper.id)
                await systemService.refresh()
                await reload()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func removeAll() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try manifestStore.removeAllManaged()
                await systemService.refresh()
                await reload()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func reload() async {
        do {
            wallpapers = try manifestStore.importedWallpapers()
        } catch {
            wallpapers = []
        }
    }

    func validateCatalogue() {
        do {
            try manifestStore.validateCurrentManifest()
            alertMessage = "The current Aerial catalogue passed AerialDrop’s structural and preservation checks."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func openWallpaperSettings() {
        systemService.openWallpaperSettings()
    }

    func openStorageFolder() {
        systemService.openFolder(paths.base)
    }

    private func requireTahoe() throws {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            throw AerialDropError.unsupportedOS
        }
    }
}
