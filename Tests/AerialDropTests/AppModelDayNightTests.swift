import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class AppModelDayNightTests: XCTestCase {
    func testSavingRolesPersistsWithoutRegisteringOrActivating() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        await h.model.reload()
        let before = try Data(contentsOf: h.paths.manifest)
        h.choosePair()
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: h.defaults), h.model.dayNightDraft)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertTrue(h.service.typedRequests.isEmpty)
        let reopened = AppModel(paths: h.paths, systemService: h.service, automaticallyReload: false, preferencesDefaults: h.defaults)
        XCTAssertEqual(reopened.dayWallpaperID, h.dayID)
        XCTAssertEqual(reopened.nightWallpaperID, h.nightID)
    }

    func testApplyRegistersPairBeforeActivationAndClearsProtectionOnlyOnSuccess() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        await h.model.reload()
        h.choosePair()
        h.service.onTypedActivation = {
            XCTAssertEqual(try h.store.dayNightPair(), h.pair)
            XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs)
            XCTAssertTrue(h.model.isWorking)
            XCTAssertEqual(h.model.operationLabel, "Applying Day/Night wallpaper…")
        }
        await h.model.activateDayNightWallpaper()
        XCTAssertEqual(h.service.typedRequests, [.automatic(groupID: ManifestStore.dayNightSubcategoryID)])
        XCTAssertEqual(try h.store.dayNightPair(), h.pair)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertFalse(h.model.isDayNightRecoveryPending)
        XCTAssertEqual(h.model.dayNightStatusMessage, "Automatic is selected on all Spaces and displays.")
        XCTAssertFalse(h.model.isWorking)
        XCTAssertNil(h.model.activeAlert)
    }

    func testFailedApplyRetainsOldAndNewMembersAcrossRelaunch() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        await h.model.reload()
        h.model.dayWallpaperID = h.thirdID
        h.model.nightWallpaperID = h.nightID
        h.service.activationError = AerialDropError.nativeWallpaperRefreshFailed("simulated failure")
        await h.model.activateDayNightWallpaper()
        let protected: Set<String> = [h.dayID, h.nightID, h.thirdID]
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), protected)
        XCTAssertEqual(try h.store.dayNightPair()?.dayAssetID, h.thirdID)
        XCTAssertTrue(h.model.isDayNightRecoveryPending)
        XCTAssertEqual(h.model.activeAlert?.title, "Couldn’t Apply Day/Night Wallpaper")
        let reopened = AppModel(paths: h.paths, systemService: h.service, automaticallyReload: false, preferencesDefaults: h.defaults)
        await reopened.reload()
        XCTAssertTrue(reopened.isDayNightRecoveryPending)
        XCTAssertEqual(reopened.removalReadiness(for: [h.dayID]), .verifiedActive)
        await reopened.removeWallpaper(h.wallpaper(h.dayID), allowingUnverifiedSelection: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.dayID).path))
    }

    func testAutomaticAndFixedSelectionsProtectBothMembers() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        for selected in [ManifestStore.dayNightSubcategoryID, h.dayID, h.nightID] {
            h.service.activeIDs = [selected]
            await h.model.reload()
            XCTAssertEqual(h.model.removalReadiness(for: h.pair.memberAssetIDs), .verifiedActive)
            XCTAssertTrue(h.pair.memberAssetIDs.isSubset(of: h.model.activeAerialAssetIDs))
            let before = try Data(contentsOf: h.paths.manifest)
            await h.model.removeWallpaper(h.wallpaper(h.nightID), allowingUnverifiedSelection: true)
            XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        }
    }

    func testUnknownSelectionCannotRemovePairOrPendingVideosEvenWithAcknowledgement() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        h.service.selectionReadError = AerialDropError.wallpaperSelectionUnknownForRemoval
        await h.model.reload()
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.removeWallpaper(h.wallpaper(h.dayID), allowingUnverifiedSelection: true)
        await h.model.removeAllWallpapers(allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.dayID).path))
    }

    func testFreshSingleReplacesPairAndReleasesPendingProtection() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        try AppPreferences.protectDayNightAssetIDs(h.pair.memberAssetIDs, defaults: h.defaults)
        await h.model.reload()
        await h.model.activateWallpaper(h.wallpaper(h.thirdID))
        XCTAssertEqual(h.service.typedRequests, [.single(assetID: h.thirdID)])
        XCTAssertTrue(h.service.legacyRequests.isEmpty)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertEqual(h.model.removalReadiness(for: [h.dayID]), .verifiedInactive)
        await h.model.removeWallpaper(h.wallpaper(h.dayID))
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.dayID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.nightID).path))
    }

    func testPairedMemberManualActivationUsesFixedVariant() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        await h.model.reload()
        await h.model.activateWallpaper(h.wallpaper(h.nightID))
        XCTAssertEqual(h.service.typedRequests, [.fixedVariant(assetID: h.nightID)])
        XCTAssertEqual(h.service.verifyingPairs, [h.pair])
        XCTAssertEqual(h.model.dayNightStatusMessage, "Night is selected on all Spaces and displays. Automatic switching is off.")
    }

    func testPostImportSingleUsesFreshTransitionWhenPairExists() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        await h.model.reload()
        let result = await h.model.applyPostImportWallpaperSetting(to: h.wallpaper(h.thirdID), automaticallyActivate: true)
        XCTAssertEqual(result, .activatedEverywhere)
        XCTAssertEqual(h.service.typedRequests, [.single(assetID: h.thirdID)])
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
    }

    func testLegacySinglePathStaysAvailableWhenDayNightUnsupported() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        h.service.supportError = AerialDropError.dayNightUnavailable("macOS 26")
        await h.model.reload()
        h.choosePair()
        XCTAssertFalse(h.model.canApplyDayNightWallpaper)
        await h.model.activateDayNightWallpaper()
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertTrue(h.service.typedRequests.isEmpty)
        await h.model.activateWallpaper(h.wallpaper(h.dayID))
        XCTAssertEqual(h.service.legacyRequests, [h.dayID])
    }

    func testSameVideoAndMissingSavedVideoBlockApplyWithoutMutation() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        await h.model.reload()
        h.model.dayWallpaperID = h.dayID
        h.model.nightWallpaperID = h.dayID
        XCTAssertEqual(h.model.dayNightApplyBlockerMessage, "Choose different wallpapers for Day and Night.")
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.activateDayNightWallpaper()
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        h.model.nightWallpaperID = UUID().uuidString
        XCTAssertTrue(h.model.dayNightApplyBlockerMessage?.contains("saved Night wallpaper is missing") == true)
        XCTAssertNotNil(h.model.nightWallpaperID)
    }

    func testExternalSelectionRefreshDistinguishesSavedDraftFromActualMode() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        h.choosePair()
        h.service.selected = .automatic(groupID: ManifestStore.dayNightSubcategoryID)
        h.service.activeIDs = [ManifestStore.dayNightSubcategoryID]
        await h.model.reload()
        XCTAssertTrue(h.model.dayNightStatusMessage.hasPrefix("Automatic is selected"))
        h.model.dayWallpaperID = h.thirdID
        XCTAssertTrue(h.model.dayNightStatusMessage.contains("Apply your saved choices"))
        h.service.selected = .single(assetID: h.thirdID)
        h.service.activeIDs = [h.thirdID]
        await h.model.refreshCataloguePreservingContent()
        XCTAssertEqual(h.model.dayNightStatusMessage, "Choices are saved. Apply Day/Night to change the wallpaper.")
    }

    func testMalformedProtectionFailsClosedAndFreshSingleRecoversIt() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        h.defaults.set([42], forKey: AppPreferences.pendingDayNightAssetIDsKey)
        await h.model.reload()
        XCTAssertTrue(h.model.isDayNightRecoveryPending)
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.removeWallpaper(h.wallpaper(h.dayID), allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        await h.model.activateWallpaper(h.wallpaper(h.thirdID))
        XCTAssertEqual(h.service.typedRequests, [.single(assetID: h.thirdID)])
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertFalse(h.model.isDayNightRecoveryPending)
    }

    func testSelectedOrdinaryWallpaperCanRecoverPersistedProtectionAfterRelaunch() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.removeWallpaper(id: h.dayID)
        try h.store.removeWallpaper(id: h.nightID)
        try AppPreferences.protectDayNightAssetIDs(h.pair.memberAssetIDs, defaults: h.defaults)
        h.service.activeIDs = [h.thirdID]
        h.service.selected = .single(assetID: h.thirdID)
        let reopened = AppModel(paths: h.paths, systemService: h.service, automaticallyReload: false, preferencesDefaults: h.defaults)
        await reopened.reload()
        let wallpaper = h.wallpaper(h.thirdID)
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertEqual(try h.store.importedWallpapers().map(\.id), [h.thirdID])
        XCTAssertTrue(reopened.isDayNightRecoveryPending)
        XCTAssertNil(reopened.activationFailure)
        XCTAssertFalse(reopened.isWallpaperAlreadySelected(wallpaper))
        XCTAssertEqual(reopened.removalReadiness(for: [h.thirdID]), .verifiedActive)
        let before = try Data(contentsOf: h.paths.manifest)
        await reopened.removeWallpaper(wallpaper, allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wallpaper.videoURL.path))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs)
        await reopened.activateWallpaper(wallpaper)
        XCTAssertEqual(h.service.typedRequests, [.single(assetID: h.thirdID)])
        XCTAssertTrue(h.service.legacyRequests.isEmpty)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertFalse(reopened.isDayNightRecoveryPending)
        XCTAssertTrue(reopened.isWallpaperAlreadySelected(wallpaper))
        XCTAssertNil(reopened.activationFailure)
    }

    func testSelectedOrdinaryWallpaperCanRecoverMalformedProtectionAfterRelaunch() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.removeWallpaper(id: h.dayID)
        try h.store.removeWallpaper(id: h.nightID)
        h.defaults.set([42], forKey: AppPreferences.pendingDayNightAssetIDsKey)
        XCTAssertTrue(h.defaults.synchronize())
        h.service.activeIDs = [h.thirdID]
        h.service.selected = .single(assetID: h.thirdID)
        let reopened = AppModel(paths: h.paths, systemService: h.service, automaticallyReload: false, preferencesDefaults: h.defaults)
        await reopened.reload()
        let wallpaper = h.wallpaper(h.thirdID)
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertEqual(try h.store.importedWallpapers().map(\.id), [h.thirdID])
        XCTAssertTrue(reopened.isDayNightRecoveryPending)
        XCTAssertNil(reopened.activationFailure)
        XCTAssertFalse(reopened.isWallpaperAlreadySelected(wallpaper))
        XCTAssertEqual(reopened.removalReadiness(for: [h.thirdID]), .unknown)
        let before = try Data(contentsOf: h.paths.manifest)
        await reopened.removeWallpaper(wallpaper, allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wallpaper.videoURL.path))
        XCTAssertThrowsError(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults))
        await reopened.activateWallpaper(wallpaper)
        XCTAssertEqual(h.service.typedRequests, [.single(assetID: h.thirdID)])
        XCTAssertTrue(h.service.legacyRequests.isEmpty)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertFalse(reopened.isDayNightRecoveryPending)
        XCTAssertTrue(reopened.isWallpaperAlreadySelected(wallpaper))
        XCTAssertNil(reopened.activationFailure)
    }

    func testRestoreCannotRemovePreviouslyCachedPendingMember() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        let backup = try XCTUnwrap(h.store.latestBackup()) // before third import
        try AppPreferences.protectDayNightAssetIDs([h.thirdID], defaults: h.defaults)
        await h.model.reload()
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.restoreLatestBackup(backup)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertEqual(h.model.activeAlert?.title, "Restore Failed")
    }

    func testLatePairedRemovalKeepsBothFilesProtectedAcrossRelaunch() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        await h.model.reload()
        h.service.onSelectionRead = {
            if try !h.store.importedWallpapers().contains(where: { $0.id == h.dayID }) {
                h.service.activeIDs = [h.nightID]
                h.service.selected = .fixedVariant(assetID: h.nightID)
            }
        }
        await h.model.removeWallpapers([h.wallpaper(h.dayID)])
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertFalse(try h.store.importedWallpapers().contains(where: { $0.id == h.dayID }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.dayID).path))
        XCTAssertTrue(h.model.activeAlert?.message.contains("Removed 1 of 1") == true)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs)
        let reopened = AppModel(paths: h.paths, systemService: h.service, automaticallyReload: false, preferencesDefaults: h.defaults)
        await reopened.reload()
        XCTAssertTrue(reopened.isDayNightRecoveryPending)
        XCTAssertEqual(reopened.removalReadiness(for: [h.dayID]), .verifiedActive)
        await reopened.removeWallpaper(h.wallpaper(h.nightID), allowingUnverifiedSelection: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.nightID).path))
    }

    func testOrphanGroupCannotBeBypassedWithRemovalAcknowledgement() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        h.service.activeIDs = [ManifestStore.dayNightSubcategoryID]
        await h.model.reload()
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.removeWallpaper(h.wallpaper(h.dayID), allowingUnverifiedSelection: true)
        await h.model.removeAllWallpapers(allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
        XCTAssertTrue(h.model.isSelectionStatusUnknown)
    }

    func testLateOrphanGroupRetainsMediaAndBlocksFurtherRemoval() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        await h.model.reload()
        h.service.onSelectionRead = {
            if try !h.store.importedWallpapers().contains(where: { $0.id == h.dayID }) {
                h.service.activeIDs = [ManifestStore.dayNightSubcategoryID]
            }
        }
        await h.model.removeWallpaper(h.wallpaper(h.dayID), allowingUnverifiedSelection: true)
        XCTAssertFalse(try h.store.importedWallpapers().contains(where: { $0.id == h.dayID }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.paths.videoURL(for: h.dayID).path))
        XCTAssertTrue(h.model.isSelectionStatusUnknown)
        let before = try Data(contentsOf: h.paths.manifest)
        await h.model.removeWallpaper(h.wallpaper(h.nightID), allowingUnverifiedSelection: true)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), before)
    }

    func testFailedManualAndPostImportActivationKeepProtectionUntilRetry() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        await h.model.reload()
        h.service.activationError = AerialDropError.nativeWallpaperRefreshFailed("simulated failure")
        await h.model.activateWallpaper(h.wallpaper(h.nightID))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs)
        XCTAssertTrue(h.model.isDayNightRecoveryPending)
        XCTAssertNotNil(h.model.activationFailure)
        let result = await h.model.applyPostImportWallpaperSetting(to: h.wallpaper(h.thirdID), automaticallyActivate: true)
        XCTAssertEqual(result, .activationFailed)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs.union([h.thirdID]))
        h.service.activationError = nil
        await h.model.activateWallpaper(h.wallpaper(h.thirdID))
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults).isEmpty)
        XCTAssertFalse(h.model.isDayNightRecoveryPending)
    }

    func testConcurrentProtectionIsNotClearedAfterSuccessfulActivation() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        await h.model.reload()
        h.choosePair()
        h.service.onTypedActivation = {
            try AppPreferences.protectDayNightAssetIDs([h.thirdID], defaults: h.defaults)
        }
        await h.model.activateDayNightWallpaper()
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs.union([h.thirdID]))
        XCTAssertTrue(h.model.isDayNightRecoveryPending)
        XCTAssertEqual(h.model.activeAlert?.title, "Couldn’t Apply Day/Night Wallpaper")
    }

    func testMalformedRecoveryDoesNotClearNewProtectionDuringActivation() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        h.defaults.set([42], forKey: AppPreferences.pendingDayNightAssetIDsKey)
        await h.model.reload()
        h.service.onTypedActivation = {
            h.defaults.set([h.dayID], forKey: AppPreferences.pendingDayNightAssetIDsKey)
            XCTAssertTrue(h.defaults.synchronize())
        }
        await h.model.activateWallpaper(h.wallpaper(h.thirdID))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), [h.dayID])
        XCTAssertTrue(h.model.isDayNightRecoveryPending)
        XCTAssertNotNil(h.model.activationFailure)
    }

    func testLateRestoreRetainsPreviousPairProtectionAfterGroupDisappears() async throws {
        let h = try DayNightModelHarness()
        defer { h.cleanup() }
        try h.store.configureDayNightPair(h.pair)
        let backup = try XCTUnwrap(h.store.latestBackup()) // all assets, before group registration
        await h.model.reload()
        h.service.onSelectionRead = {
            if try h.store.dayNightPair() == nil {
                h.service.activeIDs = [h.dayID]
                h.service.selected = .fixedVariant(assetID: h.dayID)
            }
        }
        await h.model.restoreLatestBackup(backup)
        XCTAssertNil(try h.store.dayNightPair())
        XCTAssertEqual(h.model.activeAlert?.title, "Restore Needs Attention")
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: h.defaults), h.pair.memberAssetIDs)
        XCTAssertEqual(h.model.removalReadiness(for: [h.nightID]), .verifiedActive)
    }
}

@MainActor
private final class DayNightModelHarness {
    let dayID = "11111111-2222-4333-8444-555555555555"
    let nightID = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    let thirdID = "99999999-2222-4333-8444-555555555555"
    let home: URL
    let paths: WallpaperPaths
    let store: ManifestStore
    let defaults: UserDefaults
    let suite: String
    let service = DayNightFakeService()
    let model: AppModel
    var pair: DayNightWallpaperPair { .init(dayAssetID: dayID, nightAssetID: nightID) }

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "AerialDropDayNightModel-\(UUID().uuidString)")
        paths = WallpaperPaths(homeDirectory: home)
        store = ManifestStore(paths: paths)
        suite = "AerialDropDayNightModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try store.prepareDirectories()
        try JSONSerialization.data(withJSONObject: ["version": 1, "initialAssetCount": 0, "assets": [], "categories": []])
            .write(to: paths.manifest)
        for id in [dayID, nightID, thirdID] {
            try Data("video".utf8).write(to: paths.videoURL(for: id))
            try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: id))
            try store.addWallpaper(id: id, title: id)
        }
        model = AppModel(paths: paths, systemService: service, automaticallyReload: false, preferencesDefaults: defaults)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        _ = defaults.synchronize()
        try? FileManager.default.removeItem(at: home)
    }
    func choosePair() { model.dayWallpaperID = dayID; model.nightWallpaperID = nightID }
    func wallpaper(_ id: String) -> ManagedWallpaper {
        .init(id: id, title: id, videoURL: paths.videoURL(for: id), thumbnailURL: paths.thumbnailURL(for: id), resolution: nil)
    }
}

@MainActor
private final class DayNightFakeService: WallpaperServicing {
    var activeIDs: Set<String> = []
    var selected: AerialSelectionRequest?
    var typedRequests: [AerialSelectionRequest] = []
    var verifyingPairs: [DayNightWallpaperPair?] = []
    var legacyRequests: [String] = []
    var supportError: Error?
    var selectionReadError: Error?
    var activationError: Error?
    var onTypedActivation: (() throws -> Void)?
    var onSelectionRead: (() throws -> Void)?
    func activeAerialAssetIDs() throws -> Set<String> {
        try onSelectionRead?()
        if let selectionReadError { throw selectionReadError }
        return activeIDs
    }
    func inspectAerialSelections() throws -> AerialSelectionInspection {
        .init(targets: [.init(target: .allSpacesAndDisplays, rawAssetIDs: try activeAerialAssetIDs(), recognizedSelection: selected),
            .init(target: .systemDefault, rawAssetIDs: activeIDs, recognizedSelection: selected)])
    }
    func validateDayNightSupport() throws { if let supportError { throw supportError } }
    func activateAerial(assetID: String) async throws {
        legacyRequests.append(assetID)
        if let activationError { throw activationError }
        activeIDs = [assetID]; selected = .single(assetID: assetID)
    }
    func activateAerial(_ selection: AerialSelectionRequest, verifyingPair: DayNightWallpaperPair?) async throws {
        typedRequests.append(selection); verifyingPairs.append(verifyingPair)
        try onTypedActivation?()
        if let activationError { throw activationError }
        activeIDs = [selection.assetID]; selected = selection
    }
    func refresh() async { }
    func openWallpaperSettings() { }
    func openFolder(_: URL) { }
    func revealInFinder(_: URL) { }
}
