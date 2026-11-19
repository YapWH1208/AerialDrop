import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class AppUpdatesTests: XCTestCase {
    func testAutomaticAndManualChecksRevealOffersWithoutAuthorizingInstallation() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()

        XCTAssertNil(interaction.offer)
        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: false, canInstallInPlace: { true }))
        XCTAssertEqual(interaction.offer, offer)

        interaction.beginCheck()
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, canInstallInPlace: { true }))
        interaction.finish()
        XCTAssertEqual(interaction.offer, offer)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testOneClickAuthorizesOnlyTheSameOfferAndClearsWhenTheCycleEnds() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(offer, userInitiated: false, canInstallInPlace: { true })

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: false, canInstallInPlace: { true }))
        XCTAssertTrue(interaction.discovered(offer, userInitiated: true, canInstallInPlace: { true }))
        interaction.advance(to: .waitingForWork)
        XCTAssertEqual(interaction.activity, .installing(.waitingForWork))
        XCTAssertTrue(interaction.installAuthorized)

        interaction.finish(failed: true)
        XCTAssertFalse(interaction.installAuthorized)
        XCTAssertEqual(interaction.feedback, .installFailed)
        XCTAssertEqual(interaction.offer, offer)
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, canInstallInPlace: { true }))
    }

    func testChangedOfferRequiresANewClick() {
        let old = makeOffer(build: "26")
        let new = makeOffer(build: "27")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(old, userInitiated: false, canInstallInPlace: { true })

        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(new, userInitiated: true, canInstallInPlace: { true }))
        interaction.finish()
        XCTAssertEqual(interaction.offer, new)
        XCTAssertFalse(interaction.installAuthorized)
    }

    func testMissingAndFailedBackgroundChecksRemainQuiet() {
        var interaction = UpdateInteraction()
        _ = interaction.discovered(makeOffer(build: "26"), userInitiated: false, canInstallInPlace: { true })

        interaction.finish(failed: true)
        XCTAssertNotNil(interaction.offer)
        XCTAssertNil(interaction.feedback)
        interaction.reportedMissingUpdate()
        XCTAssertNil(interaction.offer)
        XCTAssertNil(interaction.feedback)

        interaction.beginCheck()
        interaction.reportedMissingUpdate()
        interaction.finish()
        XCTAssertEqual(interaction.feedback, .noCompatibleUpdate)
    }

    func testInstallInAProtectedLocationReportsInlineAndDoesNotAuthorize() {
        let offer = makeOffer(build: "26")
        var interaction = UpdateInteraction()
        _ = interaction.discovered(offer, userInitiated: false, canInstallInPlace: { true })

        XCTAssertFalse(interaction.beginInstall(canInstallInPlace: false))
        XCTAssertEqual(interaction.feedback, .needsWritableLocation)
        XCTAssertTrue(interaction.beginInstall(canInstallInPlace: true))
        XCTAssertFalse(interaction.discovered(offer, userInitiated: true, canInstallInPlace: { false }))
        interaction.finish()
        XCTAssertFalse(interaction.installAuthorized)
        XCTAssertEqual(interaction.feedback, .needsWritableLocation)
    }

    func testIdleAppLetsSparkleProceedImmediately() throws {
        let model = try makeModel()
        let updates = AppUpdates(model: model)

        XCTAssertFalse(updates.deferRelaunchIfBusy {
            XCTFail("Sparkle should retain control when the app is idle")
        })
    }

    func testRelaunchWaitsForAnImportAndTheFollowingCatalogueRefresh() async throws {
        let model = try makeModel()
        let updates = AppUpdates(model: model)
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
