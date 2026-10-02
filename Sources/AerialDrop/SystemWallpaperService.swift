import AppKit
import Foundation

@MainActor
protocol WallpaperServicing {
    func activeAerialAssetIDs() throws -> Set<String>
    func inspectAerialSelections() throws -> AerialSelectionInspection
    func validateDayNightSupport() throws
    func activateAerial(assetID: String) async throws
    func activateAerial(_ selection: AerialSelectionRequest, verifyingPair: DayNightWallpaperPair?) async throws
    func refresh() async
    func openWallpaperSettings()
    func openFolder(_ url: URL)
    func revealInFinder(_ url: URL)
}

extension WallpaperServicing {
    func inspectAerialSelections() throws -> AerialSelectionInspection {
        throw AerialDropError.dayNightUnavailable("Native wallpaper selection cannot be inspected.")
    }

    func validateDayNightSupport() throws {
        throw AerialDropError.dayNightUnavailable("Day/Night wallpapers are unavailable on this system.")
    }

    func activateAerial(_ selection: AerialSelectionRequest, verifyingPair: DayNightWallpaperPair?) async throws {
        // Implementations must provide a verified fresh reload before callers
        // can release pending protection. Legacy services cannot infer this.
        throw AerialDropError.dayNightUnavailable("A native wallpaper reload cannot be verified.")
    }
}

@MainActor
final class SystemWallpaperService: WallpaperServicing {
    private let selectionStore: WallpaperSelectionStore
    private let manifestStore: ManifestStore
    private let processController: WallpaperProcessController
    private let validateCapability: () throws -> Void
    private var isActivating = false

    init(
        selectionStore: WallpaperSelectionStore = WallpaperSelectionStore(),
        manifestStore: ManifestStore? = nil,
        processController: WallpaperProcessController = WallpaperProcessController(),
        validateCapability: @escaping () throws -> Void = DayNightWallpaperCapability.validateCurrentSystem
    ) {
        self.selectionStore = selectionStore
        self.manifestStore = manifestStore ?? ManifestStore(paths: selectionStore.paths)
        self.processController = processController
        self.validateCapability = validateCapability
    }

    func activeAerialAssetIDs() throws -> Set<String> {
        try selectionStore.activeAerialAssetIDs()
    }

    func inspectAerialSelections() throws -> AerialSelectionInspection {
        try selectionStore.inspectAerialSelections()
    }

    /// Checks both private formats without changing either store. Current
    /// selections may belong to another native provider.
    func validateDayNightSupport() throws {
        try validateCapability()
        try manifestStore.validateCurrentManifest()
        try selectionStore.validateForApplying(.automatic(groupID: ManifestStore.dayNightSubcategoryID))
        try processController.validateCurrentAgent()
    }

    func activateAerial(assetID: String) async throws {
        guard !isActivating else { throw AerialDropError.wallpaperActivationInProgress }
        isActivating = true
        defer { isActivating = false }
        let requiredSpaceIDs = try selectionStore.apply(assetID: assetID)
        await bestEffortRefresh()
        try selectionStore.verifyAerialSelection(assetID: assetID, requiringSpaceIDs: requiredSpaceIDs)
    }

    /// Successful return establishes a fresh native generation and stable
    /// catalogue/selection identity. It is the only activation path that may
    /// release durable protection for previously cached Day/Night members.
    func activateAerial(
        _ selection: AerialSelectionRequest,
        verifyingPair pair: DayNightWallpaperPair?
    ) async throws {
        guard !isActivating else { throw AerialDropError.wallpaperActivationInProgress }
        isActivating = true
        defer { isActivating = false }
        if case .automatic = selection { try validateDayNightSupport() }
        if case .fixedVariant = selection { try validateDayNightSupport() }
        try verifyCatalogue(selection, pair: pair)
        try processController.validateCurrentAgent()
        let requiredSpaceIDs = try selectionStore.apply(selection)
        let freshAgent = try await processController.restartAndProveFreshAgent()
        for pass in 0..<2 {
            if pass > 0 { try await processController.settle() }
            try Task.checkCancellation()
            try processController.verifyFreshAgent(freshAgent)
            try verifyCatalogue(selection, pair: pair)
            try selectionStore.verifySelection(selection, requiringSpaceIDs: requiredSpaceIDs)
            try processController.verifyFreshAgent(freshAgent)
        }
    }

    private func verifyCatalogue(_ selection: AerialSelectionRequest, pair: DayNightWallpaperPair?) throws {
        try manifestStore.validateCurrentManifest()
        switch selection {
        case .automatic(let groupID):
            guard groupID == ManifestStore.dayNightSubcategoryID, let pair,
                  try manifestStore.dayNightPair() == pair else {
                throw AerialDropError.dayNightUnavailable("The Day/Night videos changed. Check both choices and apply again.")
            }
        case .fixedVariant(let assetID):
            guard let pair, pair.memberAssetIDs.contains(assetID), try manifestStore.dayNightPair() == pair else {
                throw AerialDropError.dayNightUnavailable("The Day/Night videos changed. Check the Library and apply again.")
            }
        case .single(let assetID):
            guard pair == nil else {
                throw AerialDropError.dayNightUnavailable("A single wallpaper cannot use a Day/Night role mapping.")
            }
            guard try manifestStore.dayNightPair()?.memberAssetIDs.contains(assetID) != true else {
                throw AerialDropError.dayNightUnavailable("This wallpaper belongs to the Day/Night pair. Apply its Day or Night variant instead.")
            }
        }
        let assets = try manifestStore.importedWallpapers()
        let requiredIDs = pair?.memberAssetIDs ?? [selection.assetID]
        let members = assets.filter { requiredIDs.contains($0.id) }
        guard Set(members.map(\.id)) == requiredIDs else { throw AerialDropError.wallpaperNotFound }
        for member in members {
            guard member.videoExists else { throw AerialDropError.installedFileMissing(member.videoURL) }
            guard member.thumbnailExists else { throw AerialDropError.installedFileMissing(member.thumbnailURL) }
        }
    }

    /// Reloads the Aerial catalogue after a manifest update.
    func refresh() async {
        guard !isActivating else { return }
        await bestEffortRefresh()
    }

    private func bestEffortRefresh() async {
        await terminateProcess(named: "WallpaperAerialsExtension", signal: nil)
        await terminateProcess(named: "WallpaperAgent", signal: nil)
        try? await Task.sleep(for: .seconds(1))
    }

    private func terminateProcess(named name: String, signal: String?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            if let signal {
                process.arguments = [signal, name]
            } else {
                process.arguments = [name]
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }

            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
    }

    func openWallpaperSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
