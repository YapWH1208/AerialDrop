import CoreGraphics
import Foundation

struct LibrarySelectionState: Equatable {
    var selectedIDs: Set<String> = []
    var anchorID: String?
}

struct LibrarySelectionModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let command = LibrarySelectionModifiers(rawValue: 1 << 0)
    static let shift = LibrarySelectionModifiers(rawValue: 1 << 1)
}

/// Applies conventional macOS collection selection semantics in the current
/// visible order. Command toggles one item; Shift selects an inclusive range;
/// Command-Shift adds that range to the existing selection.
func updatingLibrarySelection(
    _ state: LibrarySelectionState,
    clickedID: String,
    visibleIDs: [String],
    modifiers: LibrarySelectionModifiers
) -> LibrarySelectionState {
    guard visibleIDs.contains(clickedID) else { return state }

    if modifiers.contains(.shift),
       let anchorID = state.anchorID,
       let anchorIndex = visibleIDs.firstIndex(of: anchorID),
       let clickedIndex = visibleIDs.firstIndex(of: clickedID) {
        let bounds = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
        let rangeIDs = Set(bounds.map { visibleIDs[$0] })
        let selectedIDs = modifiers.contains(.command)
            ? state.selectedIDs.union(rangeIDs)
            : rangeIDs
        return LibrarySelectionState(
            selectedIDs: selectedIDs,
            anchorID: anchorID
        )
    }

    if modifiers.contains(.command) {
        var selectedIDs = state.selectedIDs
        if selectedIDs.contains(clickedID) {
            selectedIDs.remove(clickedID)
        } else {
            selectedIDs.insert(clickedID)
        }
        return LibrarySelectionState(
            selectedIDs: selectedIDs,
            anchorID: clickedID
        )
    }

    return LibrarySelectionState(
        selectedIDs: [clickedID],
        anchorID: clickedID
    )
}

/// Removes selections that are no longer visible and clears an invalid or
/// deliberately reset anchor after filter/order changes.
func normalizingLibrarySelection(
    _ state: LibrarySelectionState,
    visibleIDs: [String],
    resetAnchor: Bool = false
) -> LibrarySelectionState {
    let visibleSet = Set(visibleIDs)
    return LibrarySelectionState(
        selectedIDs: state.selectedIDs.intersection(visibleSet),
        anchorID: resetAnchor || state.anchorID.map(visibleSet.contains) != true
            ? nil
            : state.anchorID
    )
}

enum LibraryMoveDirection: Sendable {
    case left
    case right
    case up
    case down
}

struct LibraryMoveResult: Equatable {
    let state: LibrarySelectionState
    /// The item that should receive keyboard focus after the move.
    let focusedID: String?
}

/// Moves keyboard selection one card in the requested direction within the
/// current visible order. Left/right always step ±1; up/down step ±`columns`
/// (the caller estimates the adaptive grid's column count). A move that would
/// leave the collection does nothing (no wrap-around), mirroring macOS
/// collection views. With `extending`, the range from the unchanged anchor to
/// the destination is added, mirroring shift-click.
func movingLibrarySelection(
    _ state: LibrarySelectionState,
    direction: LibraryMoveDirection,
    columns: Int,
    visibleIDs: [String],
    extending: Bool
) -> LibraryMoveResult? {
    guard !visibleIDs.isEmpty else { return nil }
    let columnStep = max(1, columns)
    let offset: Int
    switch direction {
    case .left: offset = -1
    case .right: offset = 1
    case .up: offset = -columnStep
    case .down: offset = columnStep
    }

    // Base index: the anchor when still visible, otherwise a sole selection,
    // otherwise the move starts from the nearest end.
    let baseIndex: Int?
    if let anchor = state.anchorID, let index = visibleIDs.firstIndex(of: anchor) {
        baseIndex = index
    } else if state.selectedIDs.count == 1,
              let only = state.selectedIDs.first,
              let index = visibleIDs.firstIndex(of: only) {
        baseIndex = index
    } else {
        baseIndex = nil
    }

    guard let base = baseIndex else {
        let targetIndex = offset > 0 ? 0 : visibleIDs.count - 1
        let target = visibleIDs[targetIndex]
        return LibraryMoveResult(
            state: LibrarySelectionState(selectedIDs: [target], anchorID: target),
            focusedID: target
        )
    }

    let newIndex = base + offset
    guard visibleIDs.indices.contains(newIndex) else { return nil }
    let destination = visibleIDs[newIndex]

    let newState: LibrarySelectionState
    if extending,
       let anchor = state.anchorID,
       let anchorIndex = visibleIDs.firstIndex(of: anchor) {
        let bounds = min(anchorIndex, newIndex)...max(anchorIndex, newIndex)
        newState = LibrarySelectionState(
            selectedIDs: state.selectedIDs.union(Set(bounds.map { visibleIDs[$0] })),
            anchorID: anchor
        )
    } else {
        newState = LibrarySelectionState(selectedIDs: [destination], anchorID: destination)
    }
    return LibraryMoveResult(state: newState, focusedID: destination)
}

/// Estimates the adaptive grid's column count for arrow-key vertical moves by
/// mirroring how an adaptive item list fits `minimumItemWidth`-wide cards with
/// `spacing` gaps inside `availableWidth`. An approximation is acceptable:
/// horizontal moves are exact single steps regardless of the estimate.
func libraryGridColumns(
    availableWidth: CGFloat,
    minimumItemWidth: CGFloat,
    spacing: CGFloat
) -> Int {
    guard availableWidth.isFinite, availableWidth > 0, minimumItemWidth > 0 else { return 1 }
    return max(1, Int((availableWidth + spacing) / (minimumItemWidth + spacing)))
}
