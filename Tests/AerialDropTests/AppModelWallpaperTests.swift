import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class AppModelWallpaperTests: XCTestCase {
    func testImportRequiresAValidatedSelectedVideo() {
        let model = makeModel(service: FakeWallpaperService())
        model.catalogueState = .ready
        model.selectedVideo = URL(fileURLWithPath: "/tmp/source.mov")
        model.title = "Source"

        XCTAssertFalse(model.canImport)

        model.isSelectedVideoValid = true

        XCTAssertTrue(model.canImport)

        model.catalogueState = .unavailable("Set up Apple Aerials")

        XCTAssertFalse(model.canImport)
    }

    func testReloadReportsMissingCatalogueInsteadOfReadyEmpty() async {
        let model = makeModel(service: FakeWallpaperService())

        await model.reload()

        guard case .unavailable(let message) = model.catalogueState else {
            return XCTFail("Expected an unavailable catalogue state")
        }
        XCTAssertTrue(message.contains("Aerial manifest was not found"))
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testReloadReportsValidEmptyCatalogueAsReady() async throws {
        let home = makeTemporaryHome()
        try installEmptyManifest(in: home)
        let model = makeModel(service: FakeWallpaperService(), home: home)

        await model.reload()

        XCTAssertEqual(model.catalogueState, .ready)
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testReloadReportsMalformedCatalogueAsUnavailable() async throws {
        let home = makeTemporaryHome()
        let paths = WallpaperPaths(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: paths.manifestDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: paths.manifest)
        let model = makeModel(service: FakeWallpaperService(), home: home)

        await model.reload()

        guard case .unavailable(let message) = model.catalogueState else {
            return XCTFail("Expected an unavailable catalogue state")
        }
        XCTAssertTrue(message.contains("expected format"))
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testChoosingANewSourceReplacesTheNameWithTheNewFileStem() {
        let model = makeModel(service: FakeWallpaperService())
        model.title = "Custom Name"
        let url = URL(fileURLWithPath: "/tmp/beach.mp4")

        model.chooseVideo(url)

        XCTAssertEqual(model.title, "beach")
        XCTAssertEqual(model.selectedVideo, url)
    }

    func testChoosingANewSourceSeedsRememberedConversionChoices() throws {
        let suiteName = "AerialDropSeedingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppPreferences.setLastConversionQuality(.maximum, defaults: defaults)
        AppPreferences.setLastOutputHeightCap(1440, defaults: defaults)
        let model = makeModel(service: FakeWallpaperService(), preferencesDefaults: defaults)

        model.chooseVideo(URL(fileURLWithPath: "/tmp/beach.mp4"))

        XCTAssertEqual(model.conversionQuality, .maximum)
        XCTAssertEqual(model.outputHeightCap, 1440)
        // Crop stays per-video.
        XCTAssertEqual(model.cropOffset, 0.5)
    }

    func testChoosingANewSourceWithoutRememberedChoicesFallsBackToDefaults() {
        let model = makeModel(service: FakeWallpaperService())

        model.chooseVideo(URL(fileURLWithPath: "/tmp/beach.mp4"))

        XCTAssertEqual(model.conversionQuality, .standard)
        XCTAssertNil(model.outputHeightCap)
    }

    func testDisplayProgressIsMonotonicAcrossEveryStageTransition() {
        let model = makeModel(service: FakeWallpaperService())

        var previous = -1.0
        for stage in [
            ImportStage.validating,
            .preparingFolders,
            .processingVideo,
            .generatingThumbnail,
            .updatingManifest,
            .refreshingSystem,
            .finished
        ] {
            model.stage = stage
            for fraction in [0.0, 0.01, 0.5, 0.95] {
                model.importProgress = fraction
                let current = model.displayProgress
                XCTAssertGreaterThanOrEqual(
                    current, previous,
                    "Progress regressed at \(stage) with importProgress \(fraction): \(previous) -> \(current)"
                )
                previous = current
            }
        }
        XCTAssertEqual(model.displayProgress, 1)
    }

    func testImportCancellationAvailabilityStopsAtCatalogueCommitBoundary() {
        let model = makeModel(service: FakeWallpaperService())
        model.isWorking = true

        for stage in [
            ImportStage.validating,
            .preparingFolders,
            .processingVideo,
            .generatingThumbnail
        ] {
            model.stage = stage
            XCTAssertTrue(model.isImportCancellable, "Expected \(stage) to be cancellable")
        }

        for stage in [
            ImportStage.updatingManifest,
            .refreshingSystem,
            .finished
        ] {
            model.stage = stage
            XCTAssertFalse(model.isImportCancellable, "Expected \(stage) to be non-cancellable")
        }
    }

    func testManualActivationRefreshesTheActiveAerialID() async {
        let service = FakeWallpaperService()
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0001")

        await model.activateWallpaper(wallpaper)

        XCTAssertEqual(service.activatedAssetIDs, [wallpaper.id])
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.activeAlert)
    }

    func testActivationExposesOperationLabelWhileWorking() async throws {
        let service = FakeWallpaperService()
        let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()
        service.enteredContinuation = enteredContinuation
        service.releaseStream = releaseStream
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0012")

        let task = Task { await model.activateWallpaper(wallpaper) }

        var iterator = enteredStream.makeAsyncIterator()
        await iterator.next()
        XCTAssertEqual(model.operationLabel, "Applying “Test Aerial”…")
        XCTAssertTrue(model.isWorking)

        releaseContinuation.finish()
        await task.value

        XCTAssertNil(model.operationLabel)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
    }

    func testActivationFailureKeepsExistingActiveStateAndOffersRecovery() async {
        let service = FakeWallpaperService(activeIDs: ["CURRENT-AERIAL"])
        service.activationError = TestError.activationFailed
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0002")
        await model.reload()

        await model.activateWallpaper(wallpaper)

        XCTAssertEqual(service.activatedAssetIDs, ["C0D3X-0002"])
        XCTAssertEqual(model.activeAerialAssetIDs, Set(["CURRENT-AERIAL"]))
        XCTAssertEqual(model.activationFailure, wallpaper)
        XCTAssertEqual(model.activationFailureMessage, TestError.activationFailed.localizedDescription)
        XCTAssertNil(model.activeAlert)
        XCTAssertFalse(model.isWorking)
    }

    func testSuccessfulActivationClearsTheRetryTarget() async {
        let service = FakeWallpaperService()
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0003")
        model.activationFailure = wallpaper

        await model.activateWallpaper(wallpaper)

        XCTAssertNil(model.activationFailure)
        XCTAssertNil(model.activationFailureMessage)
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
    }

    func testEnabledPostImportSettingActivatesTheNewAerial() async {
        let service = FakeWallpaperService()
        let model = makeModel(service: service, automaticActivationEnabled: { true })
        let wallpaper = makeWallpaper(id: "C0D3X-0004")

        let result = await model.applyPostImportWallpaperSetting(to: wallpaper)

        XCTAssertEqual(result, .activatedEverywhere)
        XCTAssertEqual(
            model.importOutcome,
            ImportOutcome(wallpaper: wallpaper, activationResult: .activatedEverywhere)
        )
        XCTAssertEqual(service.activatedAssetIDs, [wallpaper.id])
        XCTAssertEqual(service.refreshCallCount, 0)
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
    }

    func testCompletedImportSetsPendingLibraryHighlight() async {
        let model = makeModel(service: FakeWallpaperService())
        let wallpaper = makeWallpaper(id: "C0D3X-0014")

        _ = await model.applyPostImportWallpaperSetting(to: wallpaper)

        XCTAssertEqual(model.pendingLibraryHighlightID, wallpaper.id)
    }

    func testRestoreLatestBackupBringsBackARemovedWallpaper() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0016")
        let service = FakeWallpaperService()
        let home = makeTemporaryHome()
        try! installManagedWallpaper(wallpaper, in: home)
        let model = makeModel(service: service, home: home)
        await model.reload()
        XCTAssertEqual(model.wallpapers.count, 1)

        await model.removeWallpaper(wallpaper)
        XCTAssertTrue(model.wallpapers.isEmpty)

        await model.restoreLatestBackup()

        XCTAssertEqual(model.wallpapers.count, 1)
        XCTAssertEqual(model.wallpapers.first?.id, wallpaper.id)
        // The video file was deleted by the removal, so the entry is degraded.
        XCTAssertEqual(model.wallpapers.first?.videoExists, false)
        XCTAssertEqual(model.activeAlert?.title, "Catalogue Restored")
        XCTAssertTrue(model.activeAlert?.message.contains("Restored") == true)
        XCTAssertFalse(model.isWorking)
    }

    func testRemovingTheHighlightedWallpaperClearsThePendingHighlight() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0015")
        let service = FakeWallpaperService()
        let home = makeTemporaryHome()
        try! installManagedWallpaper(wallpaper, in: home)
        let model = makeModel(service: service, home: home)
        model.pendingLibraryHighlightID = wallpaper.id

        await model.removeWallpaper(wallpaper)

        XCTAssertNil(model.pendingLibraryHighlightID)
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testDisabledPostImportSettingRefreshesWithoutChangingWallpaper() async {
        let service = FakeWallpaperService(activeIDs: ["CURRENT-AERIAL"])
        let model = makeModel(service: service, automaticActivationEnabled: { false })

        let wallpaper = makeWallpaper(id: "C0D3X-0005")
        let result = await model.applyPostImportWallpaperSetting(to: wallpaper)

        XCTAssertEqual(result, .installedOnly)
        XCTAssertEqual(
            model.importOutcome,
            ImportOutcome(wallpaper: wallpaper, activationResult: .installedOnly)
        )
        XCTAssertTrue(service.activatedAssetIDs.isEmpty)
        XCTAssertEqual(service.refreshCallCount, 1)
        XCTAssertEqual(model.activeAerialAssetIDs, Set(["CURRENT-AERIAL"]))
    }

    func testFailedPostImportActivationKeepsTheInstalledWallpaperRecoverable() async {
        let service = FakeWallpaperService(activeIDs: ["CURRENT-AERIAL"])
        service.activationError = TestError.activationFailed
        let model = makeModel(service: service, automaticActivationEnabled: { true })
        let wallpaper = makeWallpaper(id: "C0D3X-0009")

        let result = await model.applyPostImportWallpaperSetting(to: wallpaper)

        XCTAssertEqual(result, .activationFailed)
        XCTAssertEqual(
            model.importOutcome,
            ImportOutcome(wallpaper: wallpaper, activationResult: .activationFailed)
        )
        XCTAssertEqual(service.activatedAssetIDs, [wallpaper.id])
        XCTAssertEqual(model.activeAerialAssetIDs, Set(["CURRENT-AERIAL"]))
        XCTAssertEqual(model.activationFailure, wallpaper)
        XCTAssertEqual(model.activationFailureMessage, TestError.activationFailed.localizedDescription)
    }

    func testActiveWallpaperCannotBeRemoved() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0006")
        let service = FakeWallpaperService(activeIDs: [wallpaper.id])
        let model = makeModel(service: service)

        await model.removeWallpaper(wallpaper)

        XCTAssertEqual(model.activeAlert?.title, "Couldn’t Remove Wallpaper")
        XCTAssertEqual(model.activeAlert?.message, AerialDropError.activeWallpaperCannotBeRemoved.localizedDescription)
        XCTAssertEqual(service.refreshCallCount, 0)
    }

    func testActiveManagedWallpaperAvailabilityMatchesLoadedLibrary() {
        let wallpaper = makeWallpaper(id: "C0D3X-0011")
        let model = makeModel(service: FakeWallpaperService())
        model.wallpapers = [wallpaper]

        model.activeAerialAssetIDs = ["APPLE-AERIAL"]
        XCTAssertFalse(model.hasActiveManagedWallpaper)

        model.activeAerialAssetIDs = [wallpaper.id]
        XCTAssertTrue(model.hasActiveManagedWallpaper)
    }

    func testRemoveAllBlocksOnlyActiveManagedWallpapers() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0007")
        let service = FakeWallpaperService(activeIDs: [wallpaper.id])
        let home = makeTemporaryHome()
        try! installManagedWallpaper(wallpaper, in: home)
        let model = makeModel(service: service, home: home)

        await model.removeAllWallpapers()

        XCTAssertEqual(model.activeAlert?.title, "Couldn’t Remove Wallpapers")
        XCTAssertEqual(model.activeAlert?.message, AerialDropError.activeWallpaperCannotBeRemoved.localizedDescription)
        XCTAssertEqual(service.refreshCallCount, 0)
    }

    func testRemoveAllDoesNotTreatAnAppleAerialAsManaged() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0008")
        let service = FakeWallpaperService(activeIDs: ["APPLE-AERIAL"])
        let home = makeTemporaryHome()
        try! installManagedWallpaper(wallpaper, in: home)
        let model = makeModel(service: service, home: home)

        await model.removeAllWallpapers()

        XCTAssertNil(model.activeAlert)
        XCTAssertEqual(service.refreshCallCount, 1)
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testRemovalProceedsWhenTheSelectionStoreIsUnreadable() async {
        let wallpaper = makeWallpaper(id: "C0D3X-0010")
        let service = FakeWallpaperService(activeIDs: [wallpaper.id])
        service.selectionReadError = TestError.storeUnreadable
        let home = makeTemporaryHome()
        try! installManagedWallpaper(wallpaper, in: home)
        let model = makeModel(service: service, home: home)

        await model.removeWallpaper(wallpaper)

        XCTAssertNil(model.activeAlert)
        XCTAssertEqual(service.refreshCallCount, 1)
        XCTAssertTrue(model.wallpapers.isEmpty)
    }

    func testImportFailureProducesATitledAlert() async throws {
        let home = makeTemporaryHome()
        try installEmptyManifest(in: home)
        let suiteName = "AerialDropImportAlertTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = makeModel(
            service: FakeWallpaperService(),
            home: home,
            preferencesDefaults: defaults
        )
        model.catalogueState = .ready
        model.isSelectedVideoValid = true
        model.selectedVideo = URL(fileURLWithPath: "/tmp/aerialdrop-nothing-here.mov")
        model.title = "Ghost"

        model.importSelectedVideo()
        for _ in 0..<500 where model.activeAlert == nil {
            await Task.yield()
        }

        XCTAssertEqual(model.activeAlert?.title, "Couldn’t Import the Video")
        XCTAssertFalse(model.activeAlert?.message.isEmpty ?? true)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.stage, .idle)
    }

    func testValidateCatalogueFailureProducesATitledAlert() {
        let model = makeModel(service: FakeWallpaperService())

        model.validateCatalogue()

        XCTAssertEqual(model.activeAlert?.title, "Catalogue Problem")
        XCTAssertFalse(model.activeAlert?.message.isEmpty ?? true)
    }

    func testValidateCatalogueSuccessProducesATitledAlert() throws {
        let home = makeTemporaryHome()
        try installEmptyManifest(in: home)
        let model = makeModel(service: FakeWallpaperService(), home: home)

        model.validateCatalogue()

        XCTAssertEqual(model.activeAlert?.title, "Catalogue Valid")
    }

    private func makeModel(
        service: FakeWallpaperService,
        home: URL? = nil,
        automaticActivationEnabled: @escaping () -> Bool = { true },
        preferencesDefaults: UserDefaults = UserDefaults.standard
    ) -> AppModel {
        let temporaryHome = home ?? makeTemporaryHome()
        return AppModel(
            paths: WallpaperPaths(homeDirectory: temporaryHome),
            systemService: service,
            automaticallyReload: false,
            automaticActivationEnabled: automaticActivationEnabled,
            preferencesDefaults: preferencesDefaults
        )
    }

    private func makeTemporaryHome() -> URL {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "AerialDropAppModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        return temporaryHome
    }

    private func installManagedWallpaper(_ wallpaper: ManagedWallpaper, in home: URL) throws {
        let paths = WallpaperPaths(homeDirectory: home)
        let store = ManifestStore(paths: paths)
        try store.prepareDirectories()
        try installEmptyManifest(in: home)
        try Data("video".utf8).write(to: paths.videoURL(for: wallpaper.id))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: wallpaper.id))
        try store.addWallpaper(
            id: wallpaper.id,
            title: wallpaper.title,
            width: Int(wallpaper.resolution?.width ?? 0),
            height: Int(wallpaper.resolution?.height ?? 0)
        )
    }

    private func installEmptyManifest(in home: URL) throws {
        let paths = WallpaperPaths(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: paths.manifestDirectory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "version": 1,
            "initialAssetCount": 0,
            "assets": [],
            "categories": []
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: paths.manifest, options: .atomic)
    }

    private func makeWallpaper(id: String) -> ManagedWallpaper {
        ManagedWallpaper(
            id: id,
            title: "Test Aerial",
            videoURL: URL(fileURLWithPath: "/tmp/\(id).mov"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/\(id).png"),
            resolution: CGSize(width: 3_840, height: 2_160)
        )
    }
}

@MainActor
private final class FakeWallpaperService: WallpaperServicing {
    var activeIDs: Set<String>
    var activatedAssetIDs: [String] = []
    var refreshCallCount = 0
    var activationError: Error?

    var selectionReadError: Error?

    /// Optional test hooks: resumes a continuation as soon as activation starts,
    /// then blocks until the release stream finishes (see the operation-label test).
    var enteredContinuation: AsyncStream<Void>.Continuation?
    var releaseStream: AsyncStream<Void>?

    init(activeIDs: Set<String> = []) {
        self.activeIDs = activeIDs
    }

    func activeAerialAssetIDs() throws -> Set<String> {
        if let selectionReadError {
            throw selectionReadError
        }
        return activeIDs
    }

    func activateAerial(assetID: String) async throws {
        activatedAssetIDs.append(assetID)
        enteredContinuation?.yield()
        if let releaseStream {
            for await _ in releaseStream { break }
        }
        if let activationError {
            throw activationError
        }
        activeIDs = [assetID]
    }

    func refresh() async {
        refreshCallCount += 1
    }

    func openWallpaperSettings() { }

    func openFolder(_: URL) { }

    func revealInFinder(_: URL) { }
}

private enum TestError: LocalizedError {
    case activationFailed
    case storeUnreadable

    var errorDescription: String? {
        switch self {
        case .activationFailed:
            "The simulated wallpaper activation failed."
        case .storeUnreadable:
            "The simulated wallpaper selection store could not be read."
        }
    }
}
