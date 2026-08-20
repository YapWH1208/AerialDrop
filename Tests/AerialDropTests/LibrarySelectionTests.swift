import XCTest
@testable import AerialDrop

final class LibrarySelectionTests: XCTestCase {
    private let visibleIDs = ["A", "B", "C", "D", "E"]

    func testPlainClickReplacesSelectionAndSetsAnchor() {
        let result = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A", "B"], anchorID: "A"),
            clickedID: "D",
            visibleIDs: visibleIDs,
            modifiers: []
        )

        XCTAssertEqual(result.selectedIDs, ["D"])
        XCTAssertEqual(result.anchorID, "D")
    }

    func testCommandClickTogglesOneItemAndMovesAnchor() {
        let added = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A"], anchorID: "A"),
            clickedID: "C",
            visibleIDs: visibleIDs,
            modifiers: .command
        )
        XCTAssertEqual(added.selectedIDs, ["A", "C"])
        XCTAssertEqual(added.anchorID, "C")

        let removed = updatingLibrarySelection(
            added,
            clickedID: "C",
            visibleIDs: visibleIDs,
            modifiers: .command
        )
        XCTAssertEqual(removed.selectedIDs, ["A"])
        XCTAssertEqual(removed.anchorID, "C")
    }

    func testShiftClickSelectsInclusiveRangeInEitherDirection() {
        let forward = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["B"], anchorID: "B"),
            clickedID: "D",
            visibleIDs: visibleIDs,
            modifiers: .shift
        )
        XCTAssertEqual(forward.selectedIDs, ["B", "C", "D"])
        XCTAssertEqual(forward.anchorID, "B")

        let backward = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["D"], anchorID: "D"),
            clickedID: "B",
            visibleIDs: visibleIDs,
            modifiers: .shift
        )
        XCTAssertEqual(backward.selectedIDs, ["B", "C", "D"])
        XCTAssertEqual(backward.anchorID, "D")
    }

    func testCommandShiftClickAddsRangeToExistingSelection() {
        let result = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A", "C"], anchorID: "C"),
            clickedID: "E",
            visibleIDs: visibleIDs,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(result.selectedIDs, ["A", "C", "D", "E"])
        XCTAssertEqual(result.anchorID, "C")
    }

    func testShiftClickWithoutAVisibleAnchorFallsBackToPlainSelection() {
        let result = updatingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A"], anchorID: "MISSING"),
            clickedID: "D",
            visibleIDs: visibleIDs,
            modifiers: .shift
        )

        XCTAssertEqual(result.selectedIDs, ["D"])
        XCTAssertEqual(result.anchorID, "D")
    }

    func testNormalizationRemovesHiddenSelectionsAndResetsAnchor() {
        let filtered = normalizingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A", "B", "D"], anchorID: "B"),
            visibleIDs: ["A", "D"]
        )
        XCTAssertEqual(filtered.selectedIDs, ["A", "D"])
        XCTAssertNil(filtered.anchorID)

        let reordered = normalizingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A", "D"], anchorID: "D"),
            visibleIDs: ["D", "A"],
            resetAnchor: true
        )
        XCTAssertEqual(reordered.selectedIDs, ["A", "D"])
        XCTAssertNil(reordered.anchorID)
    }
}
