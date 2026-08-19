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
