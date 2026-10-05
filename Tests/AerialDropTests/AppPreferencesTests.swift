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

    func testDayNightSectionExpansionPreferenceDefaultsToAutomatic() {
        XCTAssertNil(defaults.object(forKey: AppPreferences.dayNightSectionExpansionPreferenceKey))
        XCTAssertEqual(
            AppPreferences.dayNightSectionExpansionPreference(defaults: defaults),
            DayNightSectionExpansionPreference()
        )
    }

    func testDayNightSectionExpansionPreferenceRoundTripsModeAndAttentionToken() throws {
        let preferences = [
            DayNightSectionExpansionPreference(mode: .automatic),
            DayNightSectionExpansionPreference(mode: .expanded, dismissedAttentionToken: "attention-1"),
            DayNightSectionExpansionPreference(mode: .collapsed, dismissedAttentionToken: "attention-2")
        ]

        for preference in preferences {
            AppPreferences.setDayNightSectionExpansionPreference(preference, defaults: defaults)
            let reread = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            XCTAssertEqual(
                AppPreferences.dayNightSectionExpansionPreference(defaults: reread),
                preference
            )
        }
    }

    func testMalformedDayNightSectionExpansionPreferenceFallsBackToAutomatic() {
        let malformedValues: [Any] = [
            "invalid",
            ["mode": "unknown"],
            ["mode": 42],
            ["mode": "expanded", "dismissedAttentionToken": 42],
            ["mode": "collapsed", "future-key": true],
            ["dismissedAttentionToken": "attention-1"]
        ]

        for value in malformedValues {
            defaults.set(value, forKey: AppPreferences.dayNightSectionExpansionPreferenceKey)
            XCTAssertEqual(
                AppPreferences.dayNightSectionExpansionPreference(defaults: defaults),
                DayNightSectionExpansionPreference(),
                String(describing: value)
            )
        }
    }

    private let dayID = "11111111-2222-4333-8444-555555555555"
    private let nightID = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    private let priorID = "BBBBBBBB-BBBB-4CCC-8DDD-EEEEEEEEEEEE"

    func testDayNightDraftDefaultsToEmptyAndPersistsPartialAndCompleteRoles() throws {
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), DayNightWallpaperDraft())
        for draft in [
            DayNightWallpaperDraft(dayAssetID: dayID),
            DayNightWallpaperDraft(nightAssetID: nightID),
            DayNightWallpaperDraft(dayAssetID: dayID, nightAssetID: nightID),
            DayNightWallpaperDraft()
        ] {
            try AppPreferences.setDayNightDraft(draft, defaults: defaults)
            let reread = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: reread), draft)
        }
    }

    func testDraftSavingKeepsUninstalledIDsAndOtherPreferences() throws {
        AppPreferences.setSetWallpaperAfterImportEnabled(false, defaults: defaults)
        AppPreferences.setLastConversionQuality(.high, defaults: defaults)
        AppPreferences.setLastOutputHeightCap(1440, defaults: defaults)
        let draft = DayNightWallpaperDraft(dayAssetID: dayID, nightAssetID: nightID)
        try AppPreferences.setDayNightDraft(draft, defaults: defaults)
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), draft)
        XCTAssertFalse(AppPreferences.isSetWallpaperAfterImportEnabled(defaults: defaults))
        XCTAssertEqual(AppPreferences.lastConversionQuality(defaults: defaults), .high)
        XCTAssertEqual(AppPreferences.lastOutputHeightCap(defaults: defaults), 1440)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults).isEmpty)
    }

    func testMalformedDraftsFailClosedOnRead() throws {
        let badValues: [Any] = [
            "invalid", [dayID], ["dayAssetID": 42], ["nightAssetID": "invalid"],
            ["future-key": dayID], ["dayAssetID": true]
        ]
        for value in badValues {
            defaults.set(value, forKey: AppPreferences.dayNightDraftKey)
            XCTAssertThrowsError(try AppPreferences.dayNightDraft(defaults: defaults), String(describing: value)) { error in
                self.assertPreferenceError(error, invalid: true)
            }
            XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults).isEmpty)
        }
    }

    func testExplicitDraftSaveRepairsMalformedPriorValueAndFailureRestoresExactRawValue() throws {
        let malformed: [String: Any] = ["dayAssetID": [true, 42]]
        let replacement = DayNightWallpaperDraft(dayAssetID: dayID, nightAssetID: nightID)
        defaults.set(malformed, forKey: AppPreferences.dayNightDraftKey)
        XCTAssertThrowsError(try AppPreferences.dayNightDraft(defaults: defaults))
        XCTAssertThrowsError(try AppPreferences.setDayNightDraft(replacement, defaults: defaults, flush: { _ in false }))
        XCTAssertEqual(defaults.object(forKey: AppPreferences.dayNightDraftKey) as? NSDictionary, malformed as NSDictionary)
        try AppPreferences.setDayNightDraft(replacement, defaults: defaults)
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), replacement)
    }

    func testInvalidDraftInputDoesNotReplaceValidSavedChoices() throws {
        let original = DayNightWallpaperDraft(dayAssetID: dayID, nightAssetID: nightID)
        try AppPreferences.setDayNightDraft(original, defaults: defaults)
        XCTAssertThrowsError(try AppPreferences.setDayNightDraft(DayNightWallpaperDraft(dayAssetID: "invalid"), defaults: defaults))
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), original)
    }

    func testDraftFlushAndReadbackFailuresRestorePreviousChoices() throws {
        let original = DayNightWallpaperDraft(dayAssetID: dayID)
        let replacement = DayNightWallpaperDraft(nightAssetID: nightID)
        try AppPreferences.setDayNightDraft(original, defaults: defaults)
        XCTAssertThrowsError(try AppPreferences.setDayNightDraft(replacement, defaults: defaults, flush: { _ in false })) { error in
            self.assertPreferenceError(error, invalid: false)
        }
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), original)
        XCTAssertThrowsError(try AppPreferences.setDayNightDraft(replacement, defaults: defaults, flush: { store in
            store.set("corrupted", forKey: AppPreferences.dayNightDraftKey)
            return true
        }))
        XCTAssertEqual(try AppPreferences.dayNightDraft(defaults: defaults), original)
    }

    func testPendingProtectionUnionsPriorMembersAndPersistsAcrossDefaultsInstances() throws {
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults).isEmpty)
        try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
        try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults)
        let reread = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: reread), [priorID, dayID, nightID])
        try AppPreferences.protectDayNightAssetIDs([], defaults: defaults)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [priorID, dayID, nightID])
    }

    func testMalformedPendingProtectionNeverBecomesEmptyDuringReadOrProtection() throws {
        let badValues: [Any] = ["invalid", 42, ["id": dayID], ["invalid"], [dayID, 42], [true]]
        for value in badValues {
            defaults.set(value, forKey: AppPreferences.pendingDayNightAssetIDsKey)
            XCTAssertThrowsError(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults)) { error in
                self.assertPreferenceError(error, invalid: true)
            }
            XCTAssertThrowsError(try AppPreferences.protectDayNightAssetIDs([nightID], defaults: defaults))
            XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSObject, value as? NSObject)
        }
    }

    func testInvalidPendingInputDoesNotReplaceExistingProtection() throws {
        try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
        XCTAssertThrowsError(try AppPreferences.protectDayNightAssetIDs(["invalid"], defaults: defaults))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [priorID])
    }

    func testProtectionFlushFailureRetainsUnionAndStopsBeforeCatalogueCallback() throws {
        try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
        var catalogueWriteCalled = false
        do {
            try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults, flush: { _ in false })
            catalogueWriteCalled = true
            XCTFail("A failed durable guard must stop catalogue registration")
        } catch { assertPreferenceError(error, invalid: false) }
        XCTAssertFalse(catalogueWriteCalled)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [priorID, dayID, nightID])
    }

    func testProtectionReadbackFailureRetainsUnionEvenIfRetryFlushChangesStoredValue() throws {
        try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
        XCTAssertThrowsError(try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults, flush: { store in
            store.removeObject(forKey: AppPreferences.pendingDayNightAssetIDsKey)
            return true
        }))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [priorID, dayID, nightID])
    }

    func testProtectionFailureKeepsMalformedValueIntroducedDuringEitherFlushAttempt() throws {
        let malformed: [String: Any] = ["unknown-member": true]
        for malformedAttempt in [1, 2] {
            defaults.removeObject(forKey: AppPreferences.pendingDayNightAssetIDsKey)
            try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
            var calls = 0
            XCTAssertThrowsError(try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults, flush: { store in
                calls += 1
                if calls == malformedAttempt {
                    store.set(malformed, forKey: AppPreferences.pendingDayNightAssetIDsKey)
                } else {
                    store.set([self.dayID], forKey: AppPreferences.pendingDayNightAssetIDsKey)
                }
                return false
            }))
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSDictionary, malformed as NSDictionary)
            XCTAssertThrowsError(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults))
        }
    }

    func testProtectionFailureRetainsValidConcurrentMembersFromBothFlushAttempts() throws {
        try AppPreferences.protectDayNightAssetIDs([priorID], defaults: defaults)
        let concurrentID = "CCCCCCCC-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        var calls = 0
        XCTAssertThrowsError(try AppPreferences.protectDayNightAssetIDs([dayID], defaults: defaults, flush: { store in
            calls += 1
            store.set([calls == 1 ? self.nightID : concurrentID], forKey: AppPreferences.pendingDayNightAssetIDsKey)
            return false
        }))
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [priorID, dayID, nightID, concurrentID])
    }

    func testClearingPendingProtectionPersistsAndClearFailureRestoresAllMembers() throws {
        try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults)
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults, flush: { _ in false })) { error in
            self.assertPreferenceError(error, invalid: false)
        }
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [dayID, nightID])
        try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults)
        let reread = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: reread).isEmpty)
    }

    func testVerifiedSingleRecoveryCanClearMalformedPendingProtection() throws {
        defaults.set(["unexpected": true], forKey: AppPreferences.pendingDayNightAssetIDsKey)
        try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey))
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults).isEmpty)
    }

    func testFailedMalformedProtectionClearRestoresExactOriginalObject() throws {
        let original: [String: Any] = ["unexpected": [true, 42, "invalid"]]
        defaults.set(original, forKey: AppPreferences.pendingDayNightAssetIDsKey)
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults, flush: { store in
            store.removeObject(forKey: AppPreferences.pendingDayNightAssetIDsKey)
            return false
        }))
        XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSDictionary, original as NSDictionary)
        XCTAssertThrowsError(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults))
    }

    func testFailedClearRetainsNewProtectionAddedDuringBothFlushAttempts() throws {
        try AppPreferences.protectDayNightAssetIDs([dayID], defaults: defaults)
        var calls = 0
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults, flush: { store in
            calls += 1
            store.set([calls == 1 ? self.nightID : self.priorID], forKey: AppPreferences.pendingDayNightAssetIDsKey)
            return true
        }))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [dayID, nightID, priorID])
    }

    func testFailedClearPreservesMalformedNewProtectionInsteadOfAssumingEmpty() throws {
        try AppPreferences.protectDayNightAssetIDs([dayID], defaults: defaults)
        let unknown: [String: Any] = ["unknown": true]
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(defaults: defaults, flush: { store in
            store.set(unknown, forKey: AppPreferences.pendingDayNightAssetIDsKey)
            return true
        }))
        XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSDictionary, unknown as NSDictionary)
        XCTAssertThrowsError(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults))
    }

    func testExpectedProtectionMismatchRefusesClearBeforeAnyWriteOrFlush() throws {
        try AppPreferences.protectDayNightAssetIDs([dayID, nightID], defaults: defaults)
        let original = defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSArray
        var flushCalls = 0
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(expectingAssetIDs: [dayID], defaults: defaults, flush: { _ in
            flushCalls += 1
            return true
        }))
        XCTAssertEqual(flushCalls, 0)
        XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSArray, original)
        try AppPreferences.clearPendingDayNightAssetIDs(expectingAssetIDs: [dayID, nightID], defaults: defaults)
        XCTAssertTrue(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults).isEmpty)
    }

    func testMalformedSnapshotCannotClearNewValidDifferentMalformedOrMissingProtection() throws {
        let original: NSDictionary = ["unknown": true]
        let changedMalformed: NSDictionary = ["different-unknown": true]
        for replacement: Any? in [[dayID, nightID], changedMalformed, nil] {
            if let replacement { defaults.set(replacement, forKey: AppPreferences.pendingDayNightAssetIDsKey) }
            else { defaults.removeObject(forKey: AppPreferences.pendingDayNightAssetIDsKey) }
            let before = defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSObject
            var flushCalls = 0
            XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(expectingMalformedValue: original, defaults: defaults, flush: { _ in
                flushCalls += 1
                return true
            }))
            XCTAssertEqual(flushCalls, 0)
            XCTAssertEqual(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSObject, before)
        }
    }

    func testUnchangedMalformedSnapshotCanRecoverAfterVerifiedTypedActivation() throws {
        let original: NSDictionary = ["unknown": [true, 42, "invalid"]]
        defaults.set(original, forKey: AppPreferences.pendingDayNightAssetIDsKey)
        let snapshot = try XCTUnwrap(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey) as? NSObject)
        try AppPreferences.clearPendingDayNightAssetIDs(expectingMalformedValue: snapshot, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: AppPreferences.pendingDayNightAssetIDsKey))
    }

    func testMalformedSnapshotArgumentMustActuallyBeMalformed() throws {
        try AppPreferences.protectDayNightAssetIDs([dayID], defaults: defaults)
        let valid: NSArray = [dayID]
        var flushCalls = 0
        XCTAssertThrowsError(try AppPreferences.clearPendingDayNightAssetIDs(expectingMalformedValue: valid, defaults: defaults, flush: { _ in
            flushCalls += 1
            return true
        })) { error in
            self.assertPreferenceError(error, invalid: true)
        }
        XCTAssertEqual(flushCalls, 0)
        XCTAssertEqual(try AppPreferences.pendingDayNightAssetIDs(defaults: defaults), [dayID])
    }

    private func assertPreferenceError(_ error: Error, invalid: Bool, file: StaticString = #filePath, line: UInt = #line) {
        if invalid {
            guard case AerialDropError.dayNightPreferencesInvalid = error else {
                return XCTFail("Expected invalid Day/Night preferences, got \(error)", file: file, line: line)
            }
        } else {
            guard case AerialDropError.dayNightPreferencesWriteFailed = error else {
                return XCTFail("Expected failed Day/Night preference write, got \(error)", file: file, line: line)
            }
        }
    }

}
