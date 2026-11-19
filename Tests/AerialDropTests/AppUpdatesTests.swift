import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class AppUpdatesTests: XCTestCase {
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
