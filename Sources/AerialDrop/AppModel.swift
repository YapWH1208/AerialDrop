import AppKit
import AVFoundation
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
    var importProgress: Double = 0
    var importSucceeded = false
    var cropOffset: Double = 0.5
    var conversionQuality: ConversionOptions.Quality = .standard
    var outputHeightCap: Int? = nil
    var sourceResolution: CGSize?
    var activeAerialAssetIDs: Set<String> = []
    var activationFailure: ManagedWallpaper?

    private var selectionVersion = 0
    private var importTask: Task<Void, Never>?
    private var importGeneration = 0

    private let paths: WallpaperPaths
    private let manifestStore: ManifestStore
    private let videoProcessor = VideoProcessor()
    private let systemService: any WallpaperServicing

    init(
        paths: WallpaperPaths = WallpaperPaths(),
        systemService: (any WallpaperServicing)? = nil,
        automaticallyReload: Bool = true
    ) {
        self.paths = paths
        manifestStore = ManifestStore(paths: paths)
        self.systemService = systemService ?? SystemWallpaperService(
            selectionStore: WallpaperSelectionStore(paths: paths)
        )
        if automaticallyReload {
            Task { await reload() }
        }
    }

    var canImport: Bool {
        selectedVideo != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    /// Maps the real encode fraction into the progress band occupied by the
    /// video-processing stage; other stages use their fixed milestones.
    var displayProgress: Double {
        if stage == .processingVideo && importProgress > 0 {
            return 0.15 + importProgress * 0.6
        }
        return stage.progress
    }

    func chooseVideo(_ url: URL) {
        selectionVersion += 1
        let version = selectionVersion
        let previousTitle = selectedVideo.map { $0.deletingPathExtension().lastPathComponent }
        if title.isEmpty || title == previousTitle {
            title = url.deletingPathExtension().lastPathComponent
        }
        selectedVideo = url
        cropOffset = 0.5
        conversionQuality = .standard
        outputHeightCap = nil
        sourceResolution = nil
        Task {
            do {
                try await videoProcessor.validate(source: url)
            } catch {
                guard version == selectionVersion else { return }
                alertMessage = error.localizedDescription
                selectedVideo = nil
                title = ""
                return
            }

            // Best-effort metadata for the resolution badge, crop bands and
            // height caps. A failure here must not reject a file that passed
            // validation — the import pipeline loads the same track metadata
            // again and surfaces its own errors there.
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            guard let naturalSize = try? await track.load(.naturalSize) else { return }
            guard let preferredTransform = try? await track.load(.preferredTransform) else { return }
            // Mirror VideoProcessor: apply the track transform so the UI
            // (crop bands, height caps, resolution badge) matches the
            // encode window for rotated sources.
            let transformedSize = VideoGeometry.displaySize(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            )
            guard version == selectionVersion else { return }
            if transformedSize.width.isFinite, transformedSize.height.isFinite,
               transformedSize.width > 0, transformedSize.height > 0 {
                sourceResolution = transformedSize
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func importSelectedVideo() {
        guard let source = selectedVideo else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            alertMessage = AerialDropError.invalidTitle.localizedDescription
            return
        }

        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        importTask = Task {
            isWorking = true
            importProgress = 0
            importSucceeded = false
            defer { isWorking = false }

            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            let id = UUID().uuidString.uppercased()
            let videoDestination = paths.videoURL(for: id)
            let thumbnailDestination = paths.thumbnailURL(for: id)
            var manifestInstalled = false

            do {
                try requireTahoe()
                stage = .validating
                try await videoProcessor.validate(source: source)

                stage = .preparingFolders
                try manifestStore.requireManifest()
                try manifestStore.prepareDirectories()

                stage = .processingVideo
                let encodedSize = try await videoProcessor.makeNativeMOV(
                    from: source,
                    destination: videoDestination,
                    options: ConversionOptions(
                        cropOffset: cropOffset,
                        outputHeightCap: outputHeightCap,
                        quality: conversionQuality
                    )
                ) { fraction in
                    Task { @MainActor in
                        self.importProgress = fraction
                    }
                }

                stage = .generatingThumbnail
                try await videoProcessor.generateThumbnail(from: videoDestination, destination: thumbnailDestination)

                stage = .updatingManifest
                try manifestStore.addWallpaper(
                    id: id,
                    title: cleanTitle,
                    width: Int(encodedSize.width),
                    height: Int(encodedSize.height)
                )
                manifestInstalled = true

                stage = .refreshingSystem
                if AppPreferences.isSetWallpaperAfterImportEnabled() {
                    do {
                        try await systemService.activateAerial(assetID: id)
                    } catch {
                        stage = .finished
                        selectedVideo = nil
                        title = ""
                        await reload()
                        importSucceeded = true
                        activationFailure = ManagedWallpaper(
                            id: id,
                            title: cleanTitle,
                            videoURL: videoDestination,
                            thumbnailURL: thumbnailDestination,
                            resolution: encodedSize
                        )
                        return
                    }
                } else {
                    await systemService.refresh()
                }

                stage = .finished
                selectedVideo = nil
                title = ""
                await reload()
                importSucceeded = true
            } catch {
                if !manifestInstalled {
                    try? FileManager.default.removeItem(at: videoDestination)
                    try? FileManager.default.removeItem(at: thumbnailDestination)
                }
                guard generation == importGeneration else { return }
                stage = .idle
                importProgress = 0
                guard !Task.isCancelled else { return }
                alertMessage = error.localizedDescription
            }
        }
    }

    func rename(_ wallpaper: ManagedWallpaper, to newTitle: String) {
        let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle != wallpaper.title else { return }
        Task {
            do {
                try manifestStore.renameWallpaper(id: wallpaper.id, title: cleanTitle)
                await reload()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func remove(_ wallpaper: ManagedWallpaper) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try refreshActiveSelection()
                guard !activeAerialAssetIDs.contains(wallpaper.id) else {
                    throw AerialDropError.activeWallpaperCannotBeRemoved
                }
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
                try refreshActiveSelection()
                guard activeAerialAssetIDs.isEmpty else {
                    throw AerialDropError.activeWallpaperCannotBeRemoved
                }
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
        try? refreshActiveSelection()
    }

    func setWallpaper(_ wallpaper: ManagedWallpaper) {
        Task {
            await activateWallpaper(wallpaper)
        }
    }

    /// The awaited counterpart to `setWallpaper`, kept internal for focused
    /// model tests while UI callers retain the non-blocking action method.
    func activateWallpaper(_ wallpaper: ManagedWallpaper) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await systemService.activateAerial(assetID: wallpaper.id)
            activationFailure = nil
            await reload()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func retryActivation() {
        if let activationFailure { setWallpaper(activationFailure) }
    }

    private func refreshActiveSelection() throws {
        activeAerialAssetIDs = try systemService.activeAerialAssetIDs()
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

    func revealInFinder(_ wallpaper: ManagedWallpaper) {
        systemService.revealInFinder(wallpaper.videoURL)
    }

    private func requireTahoe() throws {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            throw AerialDropError.unsupportedOS
        }
    }
}
