import XCTest
@testable import AerialDrop

final class WallpaperPresentationStateTests: XCTestCase {
    private let dayID = "DAY-ASSET"
    private let nightID = "NIGHT-ASSET"
    private let otherID = "OTHER-ASSET"

    private var pair: DayNightWallpaperPair {
        DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
    }

    func testAutomaticSelectionReportsBothRegisteredRolesInRotation() {
        let inspection = inspection(.automatic(groupID: ManifestStore.dayNightSubcategoryID))
        let day = resolve(dayID, inspection: inspection)
        let night = resolve(nightID, inspection: inspection)

        XCTAssertEqual(day.assignment, .dayNight(role: .day))
        XCTAssertEqual(night.assignment, .dayNight(role: .night))
        XCTAssertEqual(day.selection, .automatic)
        XCTAssertEqual(night.selection, .automatic)
        XCTAssertEqual(day.statusLabel, "Day · In rotation")
        XCTAssertEqual(night.statusLabel, "Night · In rotation")
        XCTAssertTrue(day.accessibilityDescription.contains("macOS chooses which member to show"))
        XCTAssertEqual(day.activationTitle, "Use Day only")
        XCTAssertEqual(night.activationTitle, "Use Night only")
    }

    func testFixedDayIdentityIsSharedByBothPairMembers() {
        let inspection = inspection(.fixedVariant(assetID: dayID))

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .fixedVariant(.day))
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .fixedVariant(.day))
    }

    func testFixedNightIdentityIsSharedByBothPairMembers() {
        let inspection = inspection(.fixedVariant(assetID: nightID))

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .fixedVariant(.night))
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .fixedVariant(.night))
    }

    func testFixedModeMarksOnlyTheMemberWhoseRoleIsSelected() {
        let fixedDay = inspection(.fixedVariant(assetID: dayID))
        let day = resolve(dayID, inspection: fixedDay)
        let night = resolve(nightID, inspection: fixedDay)

        XCTAssertEqual(day.selectedRoleMatchesAssignment, true)
        XCTAssertEqual(night.selectedRoleMatchesAssignment, false)
        XCTAssertEqual(day.statusLabel, "Day selected · Automatic off")
        XCTAssertEqual(night.statusLabel, "Night member · Day selected")

        let fixedNight = inspection(.fixedVariant(assetID: nightID))
        XCTAssertEqual(resolve(dayID, inspection: fixedNight).selectedRoleMatchesAssignment, false)
        XCTAssertEqual(resolve(nightID, inspection: fixedNight).selectedRoleMatchesAssignment, true)
    }

    func testUnknownStatusDominatesPreviouslyVerifiedAutomaticSelection() {
        let inspection = inspection(.automatic(groupID: ManifestStore.dayNightSubcategoryID))

        XCTAssertEqual(resolve(dayID, inspection: inspection, unknown: true).selection, .unknown)
        XCTAssertEqual(resolve(nightID, inspection: inspection, unknown: true).selection, .unknown)
    }

    func testUnknownStatusDominatesPreviouslyVerifiedOrdinarySelection() {
        let state = resolve(otherID, inspection: inspection(.single(assetID: otherID)), unknown: true)

        XCTAssertEqual(state.assignment, .single)
        XCTAssertEqual(state.selection, .unknown)
    }

    func testDifferentRecognizedTargetSelectionsReportMixedPairState() {
        let inspection = inspection(
            .automatic(groupID: ManifestStore.dayNightSubcategoryID),
            .fixedVariant(assetID: dayID)
        )

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .mixedTargets)
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .mixedTargets)
    }

    func testUnsupportedTargetsDoNotImplyARecognizedPairMismatch() {
        let inspection = inspection(.fixedVariant(assetID: nightID), nil)

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .unknown)
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .selectedWithUnknownScope)
    }

    func testOrdinarySelectionWithUnsupportedTargetsReportsOnlyWhatIsKnown() {
        let matchingAndUnsupported = inspection(.single(assetID: otherID), nil)
        let elsewhereAndUnsupported = inspection(.single(assetID: dayID), nil)
        let knownDifferenceAndUnsupported = inspection(.single(assetID: otherID), .single(assetID: dayID), nil)

        XCTAssertEqual(resolve(otherID, inspection: matchingAndUnsupported).selection, .selectedWithUnknownScope)
        XCTAssertEqual(resolve(otherID, inspection: elsewhereAndUnsupported).selection, .unknown)
        XCTAssertEqual(resolve(otherID, inspection: knownDifferenceAndUnsupported).selection, .mixedTargets)
    }

    func testKnownPairMismatchRemainsMixedWhenAnotherTargetIsUnsupported() {
        let inspection = inspection(
            .automatic(groupID: ManifestStore.dayNightSubcategoryID),
            .fixedVariant(assetID: dayID),
            nil
        )

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .mixedTargets)
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .mixedTargets)
    }

    func testRawGroupMembershipWithoutTypedInspectionCannotProveAutomaticSelection() {
        let state = resolve(dayID, rawIDs: [ManifestStore.dayNightSubcategoryID])

        XCTAssertEqual(state.assignment, .dayNight(role: .day))
        XCTAssertEqual(state.selection, .unknown)
    }

    func testRawOrdinarySelectionWithoutTypedInspectionDoesNotClaimEveryTarget() {
        XCTAssertEqual(resolve(otherID, rawIDs: [otherID]).selection, .selectedWithUnknownScope)
        XCTAssertEqual(resolve(otherID).selection, .notSelected)
    }

    func testPendingVerificationDominatesStaleInspectionAndUnknownStatus() {
        let state = resolve(
            dayID,
            inspection: inspection(.fixedVariant(assetID: dayID)),
            unknown: true,
            pendingIDs: [otherID]
        )

        XCTAssertEqual(state.assignment, .dayNight(role: .day))
        XCTAssertEqual(state.selection, .pendingVerification)
    }

    func testUnreadablePendingProtectionAndRecoveryEachPreventVerifiedClaims() {
        let inspection = inspection(.single(assetID: otherID))

        XCTAssertEqual(resolve(otherID, inspection: inspection, pendingIDs: nil).selection, .pendingVerification)
        XCTAssertEqual(resolve(otherID, inspection: inspection, recoveryPending: true).selection, .pendingVerification)
    }

    func testOrdinarySelectionRequiresEveryTargetForUniversalActiveState() {
        let everywhere = resolve(otherID, inspection: inspection(.single(assetID: otherID), .single(assetID: otherID)))
        let partial = resolve(otherID, inspection: inspection(.single(assetID: otherID), .fixedVariant(assetID: dayID)))
        let elsewhere = resolve(otherID, inspection: inspection(.fixedVariant(assetID: nightID)))

        XCTAssertEqual(everywhere.assignment, .single)
        XCTAssertEqual(everywhere.selection, .selectedEverywhere)
        XCTAssertEqual(partial.selection, .selectedOnSomeTargets)
        XCTAssertEqual(elsewhere.selection, .notSelected)
    }

    func testUniformOtherSelectionLeavesRegisteredRolesWithoutActiveClaim() {
        let inspection = inspection(.single(assetID: otherID))

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .notSelected)
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .notSelected)
    }

    func testRegisteredMemberSelectedAsSingleIsNotDescribedAsAutomatic() {
        let day = resolve(dayID, inspection: inspection(.single(assetID: dayID)))

        XCTAssertEqual(day.selection, .selectedEverywhere)
        XCTAssertEqual(day.statusLabel, "Day selected · Automatic off")
        XCTAssertTrue(day.accessibilityDescription.contains("Day/Night Automatic switching is off"))
    }

    func testSamePairMemberAcrossSingleAndFixedModesIsNotReportedPartial() {
        let inspection = inspection(.single(assetID: dayID), .fixedVariant(assetID: dayID))

        XCTAssertEqual(resolve(dayID, inspection: inspection).selection, .selectedEverywhere)
        XCTAssertEqual(resolve(nightID, inspection: inspection).selection, .notSelected)
    }

    private func resolve(
        _ wallpaperID: String,
        rawIDs: Set<String> = [],
        inspection: AerialSelectionInspection? = nil,
        unknown: Bool = false,
        pendingIDs: Set<String>? = [],
        recoveryPending: Bool = false
    ) -> WallpaperPresentationState {
        WallpaperPresentationState.resolve(
            wallpaperID: wallpaperID,
            pair: pair,
            rawSelectionAssetIDs: rawIDs,
            inspection: inspection,
            selectionStatusUnknown: unknown,
            pendingAssetIDs: pendingIDs,
            recoveryPending: recoveryPending
        )
    }

    private func inspection(_ selections: AerialSelectionRequest?...) -> AerialSelectionInspection {
        AerialSelectionInspection(targets: selections.enumerated().map { index, selection in
            AerialTargetSelection(
                target: index == 0 ? .allSpacesAndDisplays : .space("SPACE-\(index)"),
                rawAssetIDs: selection.map { [$0.assetID] } ?? [],
                recognizedSelection: selection
            )
        })
    }
}
