import Foundation
import Sparkle
import XCTest
@testable import AerialDrop

@MainActor
final class AppUpdatesTests: XCTestCase {
    func testAutomaticAndManualChecksRevealOffersWithoutAuthorizingInstallation() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()

        XCTAssertNil(interaction.offer)
        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true }))
        XCTAssertEqual(interaction.offer, offer)

        interaction.beginCheck()
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, fromSignedAppcast: true, canInstallInPlace: { true }))
        interaction.finish()
        XCTAssertEqual(interaction.offer, offer)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testOneClickAuthorizesOnlyTheSameOfferAndClearsWhenTheCycleEnds() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(offer, userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true })

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true }))
        XCTAssertTrue(interaction.discovered(offer, userInitiated: true, fromSignedAppcast: true, canInstallInPlace: { true }))
        interaction.advance(to: .waitingForWork)
        XCTAssertEqual(interaction.activity, .installing(.waitingForWork))
        XCTAssertTrue(interaction.installAuthorized)

        interaction.finish(failed: true)
        XCTAssertFalse(interaction.installAuthorized)
        XCTAssertEqual(interaction.feedback, .installFailed)
        XCTAssertEqual(interaction.offer, offer)
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, fromSignedAppcast: true, canInstallInPlace: { true }))
    }

    func testChangedOfferRequiresANewClick() {
        let old = makeOffer(build: "26")
        let new = makeOffer(build: "27")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(old, userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true })

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(new, userInitiated: true, fromSignedAppcast: true, canInstallInPlace: { true }))
        interaction.finish()
        XCTAssertEqual(interaction.offer, new)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testMissingAndFailedBackgroundChecksRemainQuiet() {
        var interaction = UpdateInteraction()
        _ = interaction.discovered(makeOffer(build: "26"), userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true })

        interaction.finish(failed: true)
        XCTAssertNotNil(interaction.offer)
        XCTAssertNil(interaction.feedback)
        interaction.reportedMissingUpdate(userInitiated: false, fromSignedAppcast: true)
        XCTAssertNil(interaction.offer)
        XCTAssertNil(interaction.feedback)

        interaction.beginCheck()
        interaction.reportedMissingUpdate(userInitiated: true, fromSignedAppcast: true)
        interaction.finish()
        XCTAssertEqual(interaction.feedback, .noCompatibleUpdate)
    }

    func testInstallInAProtectedLocationReportsInlineAndDoesNotAuthorize() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(offer, userInitiated: false, fromSignedAppcast: true, canInstallInPlace: { true })

        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: false))
        XCTAssertEqual(interaction.feedback, .needsWritableLocation)
        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, fromSignedAppcast: true, canInstallInPlace: { false }))
        interaction.finish()
        XCTAssertFalse(interaction.installAuthorized)
        XCTAssertEqual(interaction.feedback, .needsWritableLocation)
    }

    func testCanceledInstallerOfferRoundTripsAcrossLaunchesWithoutAuthorization() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let offer = makeOffer(build: "26")
        let updates = AppUpdates(model: try makeModel(), defaults: defaults)
        XCTAssertEqual(updates.choiceForPreparedInstaller(recovering: offer), .skip)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        let recovered = AppPreferences.recoveredUpdateOffer(defaults: reopened)
        var newSession = UpdateInteraction(recoveredOffer: recovered)
        XCTAssertEqual(newSession.offer, offer)
        XCTAssertNil(newSession.activity)
        XCTAssertFalse(newSession.installAuthorized)

        newSession.finishedInstalling()
        AppPreferences.setRecoveredUpdateOffer(newSession.recoveredOffer, defaults: reopened)
        XCTAssertNil(AppPreferences.recoveredUpdateOffer(defaults: defaults))
    }

    func testPreparedInstallerWithoutAnEligibleOfferIsStillCanceled() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let updates = AppUpdates(model: try makeModel(), defaults: defaults)

        XCTAssertEqual(updates.choiceForPreparedInstaller(recovering: nil), .skip)
        XCTAssertNil(AppPreferences.recoveredUpdateOffer(defaults: defaults))
    }

    func testLaunchDiscardsARecoveredOfferForTheBuildAlreadyInstalled() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AppPreferences.setRecoveredUpdateOffer(makeOffer(build: AppVersion.buildNumber), defaults: defaults)

        _ = AppUpdates(model: try makeModel(), defaults: defaults)

        XCTAssertNil(AppPreferences.recoveredUpdateOffer(defaults: defaults))
    }

    func testSparkleDelegateReceivesFreshAppcastCallback() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let updates = AppUpdates(model: try makeModel(), defaults: defaults)
        XCTAssertTrue(updates.responds(to: #selector(SPUUpdaterDelegate.updater(_:didFinishLoading:))))
    }

    func testRecoveredOfferSurvivesBackgroundMissAndLowerFallback() {
        let recovered = makeOffer(build: "27")
        let fallback = makeOffer(build: "26")
        var interaction = UpdateInteraction(recoveredOffer: recovered)

        interaction.reportedMissingUpdate(userInitiated: false, fromSignedAppcast: true)
        interaction.finish()
        XCTAssertEqual(interaction.offer, recovered)
        XCTAssertEqual(interaction.recoveredOffer, recovered)
        XCTAssertNil(interaction.feedback)

        XCTAssertFalse(interaction.discovered(fallback, userInitiated: false, fromSignedAppcast: true) { true })
        XCTAssertEqual(interaction.offer, recovered)
        XCTAssertEqual(interaction.recoveredOffer, recovered)
        XCTAssertNil(interaction.feedback)
        XCTAssertFalse(interaction.installAuthorized)

        let newer = makeOffer(build: "28")
        XCTAssertFalse(interaction.discovered(newer, userInitiated: false, fromSignedAppcast: true) { true })
        XCTAssertEqual(interaction.offer, newer)
        XCTAssertNil(interaction.recoveredOffer)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testOnlySignedManualMissClearsARecoveredOffer() {
        let recovered = makeOffer(build: "26")
        var interaction = UpdateInteraction(recoveredOffer: recovered)

        interaction.beginCheck()
        interaction.reportedMissingUpdate(userInitiated: true, fromSignedAppcast: false)
        interaction.finish()
        XCTAssertEqual(interaction.offer, recovered)
        XCTAssertEqual(interaction.recoveredOffer, recovered)
        XCTAssertEqual(interaction.feedback, .checkFailed)

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        interaction.reportedMissingUpdate(userInitiated: true, fromSignedAppcast: true)
        interaction.finish()
        XCTAssertNil(interaction.offer)
        XCTAssertNil(interaction.recoveredOffer)
        XCTAssertEqual(interaction.feedback, .noCompatibleUpdate)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testChangedArchiveForRecoveredBuildRequiresAnotherExplicitInstall() {
        let recovered = makeOffer(build: "26")
        let replacement = UpdateInteraction.Offer(
            version: recovered.version,
            build: recovered.build,
            archiveURL: recovered.archiveURL.appending(queryItems: [.init(name: "revision", value: "2")])
        )
        var interaction = UpdateInteraction(recoveredOffer: recovered)

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(replacement, userInitiated: true, fromSignedAppcast: true) { true })
        interaction.finish()
        XCTAssertEqual(interaction.offer, replacement)
        XCTAssertNil(interaction.recoveredOffer)
        XCTAssertFalse(interaction.installAuthorized)

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertTrue(interaction.discovered(replacement, userInitiated: true, fromSignedAppcast: true) { true })
    }

    func testRecoveredInstallRequiresAnExplicitClickAndAFreshSignedMatch() {
        let recovered = makeOffer(build: "26")
        var interaction = UpdateInteraction(recoveredOffer: recovered)

        interaction.beginCheck()
        XCTAssertFalse(interaction.discovered(recovered, userInitiated: true, fromSignedAppcast: true) { true })
        interaction.finish()
        XCTAssertFalse(interaction.installAuthorized)

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        interaction.recoverInstallerOffer(recovered)
        XCTAssertFalse(interaction.installAuthorized)
        XCTAssertFalse(interaction.discovered(recovered, userInitiated: true, fromSignedAppcast: false) { true })
        interaction.finish()
        XCTAssertEqual(interaction.feedback, .installFailed)
        XCTAssertEqual(interaction.offer, recovered)
        XCTAssertFalse(interaction.installAuthorized)

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertTrue(interaction.discovered(recovered, userInitiated: true, fromSignedAppcast: true) { true })
        XCTAssertTrue(interaction.installAuthorized)
    }

    func testIdleAppLetsSparkleProceedImmediately() throws {
        let model = try makeModel()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let updates = AppUpdates(model: model, defaults: defaults)

        XCTAssertFalse(updates.deferRelaunchIfBusy {
            XCTFail("Sparkle should retain control when the app is idle")
        })
    }

    func testRelaunchWaitsForAnImportAndTheFollowingCatalogueRefresh() async throws {
        let model = try makeModel()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let updates = AppUpdates(model: model, defaults: defaults)
        let resumed = expectation(description: "Authorized update resumes when idle")
        model.isWorking = true

        XCTAssertTrue(updates.deferRelaunchIfBusy {
            XCTAssertFalse(model.isWorking)
            XCTAssertNotEqual(model.catalogueRefreshState, .refreshing)
            resumed.fulfill()
        })

        model.catalogueRefreshState = .refreshing
        model.isWorking = false
        await Task.yield()
        model.catalogueRefreshState = .idle

        let outcome = await XCTWaiter.fulfillment(of: [resumed], timeout: 2)
        XCTAssertEqual(outcome, .completed)
    }

    private func makeOffer(build: String) -> UpdateInteraction.Offer {
        UpdateInteraction.Offer(
            version: "1.2.0",
            build: build,
            archiveURL: URL(string: "https://example.com/AerialDrop-\(build).zip")!
        )
    }

    private func makeModel() throws -> AppModel {
        let id = UUID().uuidString
        let home = FileManager.default.temporaryDirectory.appending(path: id, directoryHint: .isDirectory)
        return AppModel(
            paths: WallpaperPaths(homeDirectory: home),
            automaticallyReload: false,
            preferencesDefaults: try XCTUnwrap(UserDefaults(suiteName: id))
        )
    }
}
