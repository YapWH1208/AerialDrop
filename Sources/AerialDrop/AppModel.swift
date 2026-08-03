import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedVideo: URL?
    @Published var title = ""
    @Published var wallpapers: [ManagedWallpaper] = []
    @Published var stage: ImportStage = .idle
    @Published var isWorking = false
    @Published var alertMessage: String?
    @Published var showingFileImporter = false

    private let paths = WallpaperPaths()
    private lazy var manifestStore = ManifestStore(paths: paths)
    private lazy var selectionStore = WallpaperSelectionStore(paths: paths)
    private let videoProcessor = VideoProcessor()
    private let systemService = SystemWallpaperService()

    init() {
        Task { await reload() }
    }

    var canImport: Bool {
        selectedVideo != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    func chooseVideo(_ url: URL) {
        selectedVideo = url
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
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
                alertMessage = "Import completed. Select the new AerialDrop item in System Settings, close System Settings, then return here and click Finish Native Setup so the same asset is used for Desktop, Lock Screen and Screen Saver."
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

    func repairCatalogueRegistration() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try manifestStore.repairCatalogueRegistration()
                await systemService.refresh()
                await reload()
                alertMessage = "Catalogue registration repaired. Close and reopen Wallpaper settings; the AerialDrop section should now be visible."
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func restoreLatestBackup() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try manifestStore.restoreLatestBackup()
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



    func finishNativeSetup() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let managedIDs = Set(wallpapers.map(\.id))
                var linkedID: String?
                var lastError: Error?

                // WallpaperAgent may race one store update while it still holds an older
                // individual selection in memory. Force-reload and verify the on-disk linked
                // representation; retry once only when that verification fails.
                for attempt in 0..<2 {
                    do {
                        let candidateID = try selectionStore.linkSelectedManagedWallpaper(managedIDs: managedIDs)
                        await systemService.reloadPersistedSelection()
                        try selectionStore.validatePersistedNativeLink(managedID: candidateID)
                        linkedID = candidateID
                        break
                    } catch {
                        lastError = error
                        if attempt == 0 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                    }
                }

                guard let linkedID else {
                    throw lastError ?? AerialDropError.wallpaperStoreChangedDuringOperation
                }

                let name = wallpapers.first(where: { $0.id == linkedID })?.title ?? linkedID
                alertMessage = "Native setup completed for \(name). Tahoe retained a linked useAsBoth wallpaper record after WallpaperAgent restarted. Quit AerialDrop and test several lock/unlock cycles."
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func restoreLatestSelectionBackup() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try selectionStore.restoreLatestBackup()
                await systemService.refresh()
                alertMessage = "The latest AerialDrop wallpaper-selection backup was restored."
            } catch {
                alertMessage = error.localizedDescription
            }
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
