import XCTest
@testable import AerialDrop

final class DayNightSectionExpansionStateTests: XCTestCase {
    func testAutomaticPreferenceOpensForSetupAndCollapsesOnceUserDismissesIt() {
        var preference = DayNightSectionExpansionPreference()

        XCTAssertFalse(DayNightSectionExpansionState.reconcile(attentionToken: nil, preference: &preference))
        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: "setup:-:-", preference: &preference))

        DayNightSectionExpansionState.recordUserChoice(
            expanded: false,
            attentionToken: "setup:-:-",
            preference: &preference
        )

        XCTAssertFalse(DayNightSectionExpansionState.reconcile(attentionToken: "setup:-:-", preference: &preference))
    }

    func testDismissedTokenStaysCollapsedAcrossPaneRecreationAndResolvesForLaterRetry() {
        var saved = DayNightSectionExpansionPreference()
        DayNightSectionExpansionState.recordUserChoice(
            expanded: false,
            attentionToken: "recovery:old",
            preference: &saved
        )

        var reopenedPane = saved
        XCTAssertFalse(DayNightSectionExpansionState.reconcile(attentionToken: "recovery:old", preference: &reopenedPane))
        XCTAssertEqual(reopenedPane, saved)

        XCTAssertFalse(DayNightSectionExpansionState.reconcile(attentionToken: nil, preference: &reopenedPane))
        XCTAssertNil(reopenedPane.dismissedAttentionToken)
        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: "recovery:old", preference: &reopenedPane))
    }

    func testNewDraftOrRecoveryTokenOpensAfterAnOlderTokenWasDismissed() {
        var preference = DayNightSectionExpansionPreference(mode: .collapsed, dismissedAttentionToken: "draft:old")

        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: "draft:new", preference: &preference))
        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: "recovery:new-id", preference: &preference))
    }

    func testExplicitExpansionPersistsThroughHealthyState() {
        var preference = DayNightSectionExpansionPreference()
        DayNightSectionExpansionState.recordUserChoice(expanded: true, attentionToken: nil, preference: &preference)

        XCTAssertEqual(preference.mode, .expanded)
        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: nil, preference: &preference))
        XCTAssertTrue(DayNightSectionExpansionState.reconcile(attentionToken: "setup:changed", preference: &preference))
    }

    func testUnavailableWithoutRecoveryStaysCompactInAutomaticMode() {
        var preference = DayNightSectionExpansionPreference()

        XCTAssertFalse(DayNightSectionExpansionState.reconcile(attentionToken: nil, preference: &preference))
    }
}
