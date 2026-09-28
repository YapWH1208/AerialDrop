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
    var catalogueState: CatalogueState = .loading
    var catalogueRefreshState: CatalogueRefreshState = .idle
    var stage: ImportStage = .idle
    var isWorking = false
    var activeAlert: AppAlert?
    var showingFileImporter = false
    var importProgress: Double = 0
    var importOutcome: ImportOutcome?
    var isSelectedVideoValid = false
    var cropOffset: Double = 0.5
    var conversionQuality: ConversionOptions.Quality = .standard
    var outputHeightCap: Int? = nil
    var sourceResolution: CGSize?
    var sourceDuration: Double?
    var activeAerialAssetIDs: Set<String> = []
    /// True when the wallpaper selection store could not be read, so Active
    /// badges may be out of date. Destructive actions require an explicit
    /// acknowledgement while this is true.
    var isSelectionStatusUnknown = false
    var activationFailure: ManagedWallpaper?
    var activationFailureMessage: String?
    /// Human-readable label of the Library operation currently in progress
    /// (activation, removal, remove-all, restore), shown as busy feedback.
    /// Nil while idle or during an import, which has its own progress UI.
    private(set) var operationLabel: String?
    /// ID of the most recently completed import; the Library selects and
    /// scrolls to this wallpaper when it appears. Cleared once applied.
    var pendingLibraryHighlightID: String?

    private var selectionVersion = 0
    private var importTask: Task<Void, Never>?
    private var importGeneration = 0
    private var encodeStartedAt: Date?

    private let paths: WallpaperPaths
    private let manifestStore: ManifestStore
    private let videoProcessor: any VideoProcessing
    private let systemService: any WallpaperServicing
    private let automaticActivationEnabled: () -> Bool
    private let preferencesDefaults: UserDefaults
    private let availableCapacityProvider: (URL) -> Int64?

    init(
        paths: WallpaperPaths = WallpaperPaths(),
        systemService: (any WallpaperServicing)? = nil,
        videoProcessor: any VideoProcessing = VideoProcessor(),
        automaticallyReload: Bool = true,
        automaticActivationEnabled: @escaping () -> Bool = {
            AppPreferences.isSetWallpaperAfterImportEnabled()
        },
        preferencesDefaults: UserDefaults = .standard,
        availableCapacityProvider: @escaping (URL) -> Int64? = { url in
            let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            if let important = values?.volumeAvailableCapacityForImportantUsage {
                return important
            }
            if let available = values?.volumeAvailableCapacity {
                return Int64(available)
            }
            return nil
        }
    ) {
        self.paths = paths
        manifestStore = ManifestStore(paths: paths)
        self.systemService = systemService ?? SystemWallpaperService(
            selectionStore: WallpaperSelectionStore(paths: paths)
        )
        self.videoProcessor = videoProcessor
        self.automaticActivationEnabled = automaticActivationEnabled
        self.preferencesDefaults = preferencesDefaults
        self.availableCapacityProvider = availableCapacityProvider
        if automaticallyReload {
            Task { await reload() }
        }
    }

    /// Form-level import prerequisites, shared by `canImport` and
    /// `importBlockerMessage` so the gating and its inline explanation
    /// cannot drift apart.
    private enum ImportReadiness {
        case ready
        case missingVideo
        case validating
        case missingTitle
    }

    private var importReadiness: ImportReadiness {
        if selectedVideo == nil { return .missingVideo }
        if !isSelectedVideoValid { return .validating }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingTitle }
        return .ready
    }

    var canImport: Bool {
        catalogueState == .ready && !isWorking && importReadiness == .ready
    }

    /// The current reason Import cannot run, for inline display next to the
    /// form instead of hover-only toolbar help. Nil exactly when importing
    /// may proceed, or while another surface (catalogue gate, progress UI)
    /// already explains the wait.
    var importBlockerMessage: String? {
        guard catalogueState == .ready, !isWorking else { return nil }
        switch importReadiness {
        case .ready: return nil
        case .missingVideo: return "Choose a video to configure."
        case .validating: return "Validating the selected video…"
        case .missingTitle: return "Enter a wallpaper name to enable Import."
        }
    }

    var hasActiveManagedWallpaper: Bool {
        wallpapers.contains { activeAerialAssetIDs.contains($0.id) }
    }

    var isImportCancellable: Bool {
        isWorking && stage.allowsCancellation
    }

    /// Maps the real encode fraction into the progress band occupied by the
    /// video-processing stage; other stages use their fixed milestones. The
    /// encode band starts at the preparing-folders milestone (0.3) and ends
    /// below the thumbnail milestone (0.7), so the bar never moves backward
    /// across stage transitions.
    var displayProgress: Double {
        if stage == .processingVideo {
            return 0.3 + min(importProgress, 0.95) * 0.4
        }
        return stage.progress
    }

    /// The encode ETA extrapolates from the throttled 1% progress steps, so a
    /// stalled encoder would otherwise present an absurd, ever-growing
    /// countdown. No credible encode of an 80-second segment exceeds this.
    static let maxEncodeETA: TimeInterval = 1800

    /// Estimated seconds remaining in the encode stage, derived from the
    /// progress rate observed since encoding started. Nil outside the encode
    /// stage or while the estimate is not yet meaningful.
    var encodeETA: TimeInterval? {
        guard stage == .processingVideo,
              let start = encodeStartedAt,
              importProgress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 3 else { return nil }
        let fraction = min(max(importProgress, 0.01), 0.95)
        let eta = elapsed * (1 - fraction) / fraction
        return min(eta, Self.maxEncodeETA)
    }

    func chooseVideo(_ url: URL) {
        guard !isWorking else { return }
        selectionVersion += 1
        let version = selectionVersion
        // Always follow the chosen file: a name left over from a previously
        // selected source is confusing when the source is replaced.
        title = url.deletingPathExtension().lastPathComponent
        selectedVideo = url
        importOutcome = nil
        cropOffset = 0.5
        // Seed from the most recent import so repeated importers keep their
        // quality/resolution choices; crop stays per-video (content-specific).
        conversionQuality = AppPreferences.lastConversionQuality(defaults: preferencesDefaults) ?? .standard
        outputHeightCap = AppPreferences.lastOutputHeightCap(defaults: preferencesDefaults)
        sourceResolution = nil
        sourceDuration = nil
        isSelectedVideoValid = false
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            do {
                try await videoProcessor.validate(source: url)
            } catch {
                guard version == selectionVersion else { return }
                activeAlert = AppAlert(
                    title: "Couldn’t Use This Video",
                    message: error.localizedDescription
                )
                selectedVideo = nil
                title = ""
                isSelectedVideoValid = false
                return
            }

            guard version == selectionVersion else { return }
            isSelectedVideoValid = true

            // Best-effort metadata for the resolution badge, crop bands and
            // height caps. A failure here must not reject a file that passed
            // validation — the import pipeline loads the same track metadata
            // again and surfaces its own errors there.
            let asset = AVURLAsset(url: url)
            // Prefer the duration the encoder can actually use (skipping
            // leading unrenderable samples) so the Loop row states the same
            // trim-versus-repeat decision the encode will make.
            let effective = await videoProcessor.effectiveSourceDuration(for: url)
            let fallback = try? await asset.load(.duration).seconds
            let seconds = effective ?? fallback
            if let seconds, seconds.isFinite, seconds > 0 {
                guard version == selectionVersion else { return }
                sourceDuration = seconds
            }
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
                // A remembered cap that this source would not downscale shows
                // no picker selection; fall back to Original for it.
                outputHeightCap = applicableHeightCap(outputHeightCap, sourceSize: transformedSize)
            }
        }
    }

    func cancelImport() {
        guard isImportCancellable else { return }
        importTask?.cancel()
    }

    func importSelectedVideo() {
        guard !isWorking, catalogueState == .ready,
              isSelectedVideoValid, let source = selectedVideo else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            activeAlert = AppAlert(
                title: "Couldn’t Import the Video",
                message: AerialDropError.invalidTitle.localizedDescription
            )
            return
        }

        // Remember the choices this import commits to, so the next video
        // starts from them.
        AppPreferences.setLastConversionQuality(conversionQuality, defaults: preferencesDefaults)
        AppPreferences.setLastOutputHeightCap(outputHeightCap, defaults: preferencesDefaults)
        let options = ConversionOptions(
            cropOffset: cropOffset,
            outputHeightCap: outputHeightCap,
            quality: conversionQuality
        )
        let selectedSourceResolution = sourceResolution
        let shouldActivate = automaticActivationEnabled()

        // Reserve the operation before scheduling its task, and invalidate any late
        // metadata work still associated with the editable source selection.
        selectionVersion += 1
        importGeneration += 1
        let generation = importGeneration
        isWorking = true
        stage = .validating
        importProgress = 0
        importOutcome = nil
        encodeStartedAt = nil
        operationLabel = nil
        showingFileImporter = false
        dismissActivationFailure()
        importTask = Task {
            defer {
                if generation == importGeneration {
                    isWorking = false
                    importTask = nil
                    encodeStartedAt = nil
                }
            }

            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            let id = UUID().uuidString.uppercased()
            let videoDestination = paths.videoURL(for: id)
            let thumbnailDestination = paths.thumbnailURL(for: id)
            var manifestInstalled = false

            do {
                try Task.checkCancellation()
                try requireTahoe()
                stage = .validating
                try await videoProcessor.validate(source: source)
                try Task.checkCancellation()

                stage = .preparingFolders
                try manifestStore.requireManifest()
                try manifestStore.prepareDirectories()

                let importSourceSize: CGSize
                if let selectedSourceResolution {
                    importSourceSize = selectedSourceResolution
                } else {
                    importSourceSize = try await videoProcessor.sourceDisplaySize(for: source)
                }
                try Task.checkCancellation()
                try requireImportStorageCapacity(
                    sourceSize: importSourceSize,
                    options: options
                )

                stage = .processingVideo
                encodeStartedAt = Date()
                let encodedSize = try await videoProcessor.makeNativeMOV(
                    from: source,
                    destination: videoDestination,
                    options: options
                ) { fraction in
                    Task { @MainActor in
                        guard generation == self.importGeneration,
                              self.isWorking, self.stage == .processingVideo,
                              self.importTask?.isCancelled == false,
                              fraction.isFinite else { return }
                        self.importProgress = max(self.importProgress, min(max(fraction, 0), 0.95))
                    }
                }
                try Task.checkCancellation()

                stage = .generatingThumbnail
                try await videoProcessor.generateThumbnail(from: videoDestination, destination: thumbnailDestination)

                try Task.checkCancellation()
                stage = .updatingManifest
                try manifestStore.addWallpaper(
                    id: id,
                    title: cleanTitle,
                    width: Int(encodedSize.width),
                    height: Int(encodedSize.height)
                )
                manifestInstalled = true

                await applyPostImportWallpaperSetting(
                    to: ManagedWallpaper(
                        id: id,
                        title: cleanTitle,
                        videoURL: videoDestination,
                        thumbnailURL: thumbnailDestination,
                        resolution: encodedSize
                    ),
                    automaticallyActivate: shouldActivate
                )

                guard generation == importGeneration else { return }
                stage = .finished
                selectedVideo = nil
                title = ""
                isSelectedVideoValid = false
                sourceResolution = nil
                sourceDuration = nil
            } catch {
                if !manifestInstalled {
                    try? FileManager.default.removeItem(at: videoDestination)
                    try? FileManager.default.removeItem(at: thumbnailDestination)
                }
                guard generation == importGeneration else { return }
                stage = .idle
                importProgress = 0
                guard !Task.isCancelled else { return }
                activeAlert = AppAlert(
                    title: "Couldn’t Import the Video",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Fails before encoding when the destination volume cannot hold the
    /// pipeline's conservative peak working set. If macOS cannot report a
    /// capacity value, import proceeds and the encoder retains its existing
    /// actionable failure path.
    func requireImportStorageCapacity(
        sourceSize: CGSize,
        options: ConversionOptions
    ) throws {
        let requiredBytes = requiredImportStorageBytes(
            sourceSize: sourceSize,
            options: options
        )
        guard let availableBytes = availableCapacityProvider(paths.videos) else {
            return
        }
        guard availableBytes >= requiredBytes else {
            throw AerialDropError.insufficientImportStorage(
                requiredBytes: requiredBytes,
                availableBytes: max(0, availableBytes)
            )
        }
    }

    func rename(_ wallpaper: ManagedWallpaper, to newTitle: String) {
        guard !isWorking else { return }
        let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle != wallpaper.title else { return }
        isWorking = true
        operationLabel = "Renaming “\(wallpaper.title)”…"
        Task {
            defer {
                isWorking = false
                operationLabel = nil
            }
            do {
                try manifestStore.renameWallpaper(id: wallpaper.id, title: cleanTitle)
                await reload()
            } catch {
                activeAlert = AppAlert(
                    title: "Couldn’t Rename Wallpaper",
                    message: error.localizedDescription
                )
            }
        }
    }

    func remove(
        _ wallpaper: ManagedWallpaper,
        allowingUnverifiedSelection: Bool = false
    ) {
        guard !isWorking else { return }
        Task {
            await removeWallpaper(
                wallpaper,
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
        }
    }

    func remove(
        _ wallpapers: [ManagedWallpaper],
        allowingUnverifiedSelection: Bool = false
    ) {
        guard !isWorking else { return }
        Task {
            await removeWallpapers(
                wallpapers,
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
        }
    }

    func removeWallpaper(
        _ wallpaper: ManagedWallpaper,
        allowingUnverifiedSelection: Bool = false
    ) async {
        guard !isWorking else { return }
        isWorking = true
        operationLabel = "Removing “\(wallpaper.title)”…"
        defer {
            isWorking = false
            operationLabel = nil
        }
        do {
            try requireRemovalReadiness(
                for: [wallpaper.id],
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
            if pendingLibraryHighlightID == wallpaper.id {
                pendingLibraryHighlightID = nil
            }
            try manifestStore.removeWallpaper(id: wallpaper.id)
            await systemService.refresh()
            await reload()
        } catch {
            activeAlert = AppAlert(
                title: "Couldn’t Remove Wallpaper",
                message: error.localizedDescription
            )
        }
    }

    func removeAll(allowingUnverifiedSelection: Bool = false) {
        guard !isWorking else { return }
        Task {
            await removeAllWallpapers(
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
        }
    }

    /// Removes several wallpapers in one confirmed operation. Each removal is
    /// its own backed-up manifest mutation; a failure partway through keeps
    /// the already-removed items removed and still refreshes the catalogue.
    func removeWallpapers(
        _ wallpapers: [ManagedWallpaper],
        allowingUnverifiedSelection: Bool = false
    ) async {
        guard !isWorking else { return }
        let ids = Set(wallpapers.map(\.id))
        guard !ids.isEmpty else { return }
        isWorking = true
        operationLabel = "Removing \(ids.count) wallpapers…"
        defer {
            isWorking = false
            operationLabel = nil
        }
        do {
            try requireRemovalReadiness(
                for: ids,
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
            var firstError: Error?
            var removedCount = 0
            for id in ids.sorted() {
                do {
                    try manifestStore.removeWallpaper(id: id)
                    removedCount += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let highlight = pendingLibraryHighlightID, ids.contains(highlight) {
                pendingLibraryHighlightID = nil
            }
            await systemService.refresh()
            await reload()
            if let firstError {
                // State exactly how far the bulk removal got so the outcome
                // never contradicts the confirmed "Remove N" promise.
                activeAlert = AppAlert(
                    title: "Couldn’t Remove Wallpapers",
                    message: "Removed \(removedCount) of \(ids.count) wallpapers. \(firstError.localizedDescription)"
                )
            }
        } catch {
            activeAlert = AppAlert(
                title: "Couldn’t Remove Wallpapers",
                message: error.localizedDescription
            )
        }
    }

    func removeAllWallpapers(
        allowingUnverifiedSelection: Bool = false
    ) async {
        guard !isWorking else { return }
        isWorking = true
        operationLabel = "Removing all AerialDrop wallpapers…"
        defer {
            isWorking = false
            operationLabel = nil
        }
        do {
            let managedIDs = Set(try manifestStore.importedWallpapers().map(\.id))
            try requireRemovalReadiness(
                for: managedIDs,
                allowingUnverifiedSelection: allowingUnverifiedSelection
            )
            pendingLibraryHighlightID = nil
            try manifestStore.removeAllManaged()
            await systemService.refresh()
            await reload()
        } catch {
            activeAlert = AppAlert(
                title: "Couldn’t Remove Wallpapers",
                message: error.localizedDescription
            )
        }
    }

    func reload() async {
        sweepOrphanedTempSegments()
        catalogueRefreshState = .idle
        catalogueState = .loading
        do {
            try manifestStore.requireManifest()
            wallpapers = try manifestStore.importedWallpapers()
            catalogueState = .ready
        } catch {
            wallpapers = []
            catalogueState = .unavailable(error.localizedDescription)
        }
        do {
            try refreshActiveSelection()
            isSelectionStatusUnknown = false
        } catch {
            isSelectionStatusUnknown = true
        }
    }

    /// Refreshes a catalogue that is already on screen without replacing it
    /// with the blocking loading or unavailable states. A failed foreground
    /// read keeps the last known content and exposes a retryable status.
    func refreshCataloguePreservingContent() async {
        guard !isWorking else { return }
        guard catalogueRefreshState != .refreshing else { return }
        guard catalogueState == .ready else {
            await reload()
            return
        }

        sweepOrphanedTempSegments()
        catalogueRefreshState = .refreshing
        // Give SwiftUI a render opportunity before the small synchronous
        // private-catalogue read so progress is perceptible on slower disks.
        await Task.yield()
        guard catalogueRefreshState == .refreshing else { return }

        let refreshError: Error?
        do {
            try manifestStore.requireManifest()
            let refreshedWallpapers = try manifestStore.importedWallpapers()
            wallpapers = refreshedWallpapers
            refreshError = nil
        } catch {
            refreshError = error
        }

        do {
            try refreshActiveSelection()
            isSelectionStatusUnknown = false
        } catch {
            isSelectionStatusUnknown = true
        }

        if let refreshError {
            catalogueRefreshState = .failed(refreshError.localizedDescription)
        } else {
            catalogueRefreshState = .idle
        }
    }

    /// Removes leftover AerialDrop encode temp files (e.g. after the app was
    /// quit mid-import). Only touches files matching AerialDrop's own temp
    /// naming, never other apps' catalogue files.
    private func sweepOrphanedTempSegments() {
        guard !isWorking else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: paths.videos.path) else { return }
        for name in files where name.hasPrefix(".AerialDrop-") && name.hasSuffix(".mov") {
            try? FileManager.default.removeItem(at: paths.videos.appending(path: name))
        }
    }

    func setWallpaper(_ wallpaper: ManagedWallpaper) {
        guard !isWorking else { return }
        Task {
            await activateWallpaper(wallpaper)
        }
    }

    /// The awaited counterpart to `setWallpaper`, kept internal for focused
    /// model tests while UI callers retain the non-blocking action method.
    func activateWallpaper(_ wallpaper: ManagedWallpaper) async {
        guard !isWorking else { return }
        isWorking = true
        operationLabel = "Applying “\(wallpaper.title)”…"
        defer {
            isWorking = false
            operationLabel = nil
        }
        do {
            try await systemService.activateAerial(assetID: wallpaper.id)
            dismissActivationFailure()
            if importOutcome?.wallpaper.id == wallpaper.id {
                importOutcome = ImportOutcome(
                    wallpaper: wallpaper,
                    activationResult: .activatedEverywhere
                )
            }
            await reload()
        } catch {
            recordActivationFailure(for: wallpaper, error: error)
        }
    }

    func retryActivation() {
        guard !isWorking, let wallpaper = activationFailure else { return }
        dismissActivationFailure()
        setWallpaper(wallpaper)
    }

    /// Applies the default-on post-import choice independently of media work,
    /// making a failed activation recoverable without rolling back installation.
    @discardableResult
    func applyPostImportWallpaperSetting(
        to wallpaper: ManagedWallpaper,
        automaticallyActivate: Bool? = nil
    ) async -> ImportActivationResult {
        stage = .refreshingSystem
        let activationResult: ImportActivationResult
        if automaticallyActivate ?? automaticActivationEnabled() {
            do {
                try await systemService.activateAerial(assetID: wallpaper.id)
                dismissActivationFailure()
                activationResult = .activatedEverywhere
            } catch {
                recordActivationFailure(for: wallpaper, error: error)
                activationResult = .activationFailed
            }
        } else {
            await systemService.refresh()
            activationResult = .installedOnly
        }
        await reload()
        importOutcome = ImportOutcome(
            wallpaper: wallpaper,
            activationResult: activationResult
        )
        pendingLibraryHighlightID = wallpaper.id
        return activationResult
    }

    private func refreshActiveSelection() throws {
        activeAerialAssetIDs = try systemService.activeAerialAssetIDs()
    }

    /// Refreshes the selection immediately before removal UI is presented.
    /// Callers use the result to distinguish a safe confirmation from the
    /// stronger acknowledgement required when the private store is unreadable.
    func removalReadiness(for wallpaperIDs: Set<String>) -> RemovalReadiness {
        do {
            try refreshActiveSelection()
            isSelectionStatusUnknown = false
            return activeAerialAssetIDs.isDisjoint(with: wallpaperIDs)
                ? .verifiedInactive
                : .verifiedActive
        } catch {
            isSelectionStatusUnknown = true
            return .unknown
        }
    }

    func reportActiveWallpaperRemovalBlock() {
        activeAlert = AppAlert(
            title: "Can’t Remove Active Wallpaper",
            message: AerialDropError.activeWallpaperCannotBeRemoved.localizedDescription
        )
    }

    /// Rechecks at execution time so a selection change between presentation
    /// and confirmation cannot bypass the active-wallpaper guard.
    private func requireRemovalReadiness(
        for wallpaperIDs: Set<String>,
        allowingUnverifiedSelection: Bool
    ) throws {
        switch removalReadiness(for: wallpaperIDs) {
        case .verifiedInactive:
            return
        case .verifiedActive:
            throw AerialDropError.activeWallpaperCannotBeRemoved
        case .unknown:
            guard allowingUnverifiedSelection else {
                throw AerialDropError.wallpaperSelectionUnknownForRemoval
            }
        }
    }

    func dismissActivationFailure() {
        activationFailure = nil
        activationFailureMessage = nil
    }

    private func recordActivationFailure(for wallpaper: ManagedWallpaper, error: Error) {
        activationFailure = wallpaper
        activationFailureMessage = error.localizedDescription
    }

    func validateCatalogue() {
        do {
            try manifestStore.validateCurrentManifest()
            activeAlert = AppAlert(
                title: "Catalogue Valid",
                message: "The current Aerial catalogue is valid and ready to use."
            )
        } catch {
            activeAlert = AppAlert(
                title: "Catalogue Problem",
                message: error.localizedDescription
            )
        }
    }

    func openWallpaperSettings() {
        systemService.openWallpaperSettings()
    }

    /// The newest AerialDrop catalogue backup, for the restore confirmation.
    func latestBackupInfo() -> ManifestStore.BackupInfo? {
        manifestStore.latestBackup()
    }

    /// Replaces the current catalogue with the newest AerialDrop backup. The
    /// restore is refused (with nothing changed) if foreign catalogue data
    /// changed since the backup.
    func restoreLatestBackup(_ confirmedBackup: ManifestStore.BackupInfo? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        operationLabel = "Restoring catalogue backup…"
        defer {
            isWorking = false
            operationLabel = nil
        }
        do {
            guard let info = confirmedBackup ?? manifestStore.latestBackup() else {
                activeAlert = AppAlert(
                    title: "No Backups Found",
                    message: "No AerialDrop backups were found."
                )
                return
            }
            let activeIDs: Set<String>?
            do {
                try refreshActiveSelection()
                isSelectionStatusUnknown = false
                activeIDs = activeAerialAssetIDs
            } catch {
                isSelectionStatusUnknown = true
                activeIDs = nil
            }
            try manifestStore.restoreBackup(info, protectingActiveAssetIDs: activeIDs)
            await systemService.refresh()
            await reload()
            activeAlert = AppAlert(
                title: "Catalogue Restored",
                message: "Restored the Aerial catalogue backup from \(info.date.formatted(date: .abbreviated, time: .shortened)) (\(info.operation))."
            )
        } catch {
            activeAlert = AppAlert(
                title: "Restore Failed",
                message: error.localizedDescription
            )
        }
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
