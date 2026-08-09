import Foundation
import XCTest
@testable import AerialDrop

final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "AerialDropAppPreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    func testUnsetAutomaticActivationDefaultsToTrue() {
        XCTAssertNil(defaults.object(forKey: AppPreferences.setWallpaperAfterImportKey))
        XCTAssertTrue(AppPreferences.isSetWallpaperAfterImportEnabled(defaults: defaults))
    }

    func testPersistedFalseDisablesAutomaticActivation() {
        AppPreferences.setSetWallpaperAfterImportEnabled(false, defaults: defaults)

        XCTAssertFalse(AppPreferences.isSetWallpaperAfterImportEnabled(defaults: defaults))
    }

    func testPersistedTrueEnablesAutomaticActivation() {
        AppPreferences.setSetWallpaperAfterImportEnabled(true, defaults: defaults)

        XCTAssertTrue(AppPreferences.isSetWallpaperAfterImportEnabled(defaults: defaults))
    }
}
