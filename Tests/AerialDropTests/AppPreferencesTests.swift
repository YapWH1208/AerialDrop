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

    func testLastConversionQualityRoundTrips() {
        XCTAssertNil(AppPreferences.lastConversionQuality(defaults: defaults))

        AppPreferences.setLastConversionQuality(.high, defaults: defaults)

        XCTAssertEqual(AppPreferences.lastConversionQuality(defaults: defaults), .high)
    }

    func testLastConversionQualityIgnoresUnknownRawValues() {
        defaults.set("ultra", forKey: AppPreferences.lastConversionQualityKey)

        XCTAssertNil(AppPreferences.lastConversionQuality(defaults: defaults))
    }

    func testLastOutputHeightCapRoundTrips() {
        XCTAssertNil(AppPreferences.lastOutputHeightCap(defaults: defaults))

        AppPreferences.setLastOutputHeightCap(1440, defaults: defaults)

        XCTAssertEqual(AppPreferences.lastOutputHeightCap(defaults: defaults), 1440)
    }

    func testLastOutputHeightCapClearsOnNil() {
        AppPreferences.setLastOutputHeightCap(1440, defaults: defaults)
        AppPreferences.setLastOutputHeightCap(nil, defaults: defaults)

        XCTAssertNil(AppPreferences.lastOutputHeightCap(defaults: defaults))
    }
}
