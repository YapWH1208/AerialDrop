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

    func testArrowRightMovesToNextCardAndUpdatesAnchor() {
        let result = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["B"], anchorID: "B"),
            direction: .right,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )

        XCTAssertEqual(result?.state.selectedIDs, ["C"])
        XCTAssertEqual(result?.state.anchorID, "C")
        XCTAssertEqual(result?.focusedID, "C")
    }

    func testHorizontalMovesAtTheEdgesDoNothing() {
        let atStart = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A"], anchorID: "A"),
            direction: .left,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertNil(atStart)

        let atEnd = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["E"], anchorID: "E"),
            direction: .right,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertNil(atEnd)
    }

    func testVerticalMovesStepByEstimatedColumns() {
        let down = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A"], anchorID: "A"),
            direction: .down,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertEqual(down?.focusedID, "D")

        let up = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["D"], anchorID: "D"),
            direction: .up,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertEqual(up?.focusedID, "A")

        // A vertical move that would leave the grid does nothing.
        let downPastEnd = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["D"], anchorID: "D"),
            direction: .down,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertNil(downPastEnd)
    }

    func testShiftArrowExtendsRangeFromUnchangedAnchor() {
        let result = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["A"], anchorID: "A"),
            direction: .down,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: true
        )

        XCTAssertEqual(result?.state.selectedIDs, ["A", "B", "C", "D"])
        XCTAssertEqual(result?.state.anchorID, "A")
        XCTAssertEqual(result?.focusedID, "D")
    }

    func testMoveWithoutAPositionSelectsTheNearestEnd() {
        let forward = movingLibrarySelection(
            LibrarySelectionState(),
            direction: .right,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertEqual(forward?.focusedID, "A")

        let backward = movingLibrarySelection(
            LibrarySelectionState(),
            direction: .left,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertEqual(backward?.focusedID, "E")
    }

    func testMoveWithStaleAnchorFallsBackToSoleSelection() {
        let result = movingLibrarySelection(
            LibrarySelectionState(selectedIDs: ["D"], anchorID: "MISSING"),
            direction: .right,
            columns: 3,
            visibleIDs: visibleIDs,
            extending: false
        )
        XCTAssertEqual(result?.focusedID, "E")
    }

    func testMovingInAnEmptyGridReturnsNil() {
        let result = movingLibrarySelection(
            LibrarySelectionState(),
            direction: .right,
            columns: 3,
            visibleIDs: [],
            extending: false
        )
        XCTAssertNil(result)
    }

    func testColumnEstimateMatchesAdaptiveFit() {
        // floor((760 + 20) / (220 + 20)) = 3 columns.
        XCTAssertEqual(libraryGridColumns(availableWidth: 760, minimumItemWidth: 220, spacing: 20), 3)
        // Narrow panes collapse to a single column; degenerate widths harden to 1.
        XCTAssertEqual(libraryGridColumns(availableWidth: 200, minimumItemWidth: 220, spacing: 20), 1)
        XCTAssertEqual(libraryGridColumns(availableWidth: 0, minimumItemWidth: 220, spacing: 20), 1)
    }
}
