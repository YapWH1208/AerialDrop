import Foundation

enum DayNightRole: Equatable, Hashable, Sendable {
    case day
    case night

    var title: String {
        switch self {
        case .day: "Day"
        case .night: "Night"
        }
    }

}

/// Read-only presentation of a wallpaper's registered role and verified
/// native selection. This deliberately does not drive removal protection.
struct WallpaperPresentationState: Equatable, Sendable {
    enum Assignment: Equatable, Sendable {
        case single
        case dayNight(role: DayNightRole)
    }

    enum Selection: Equatable, Sendable {
        case selectedEverywhere
        case selectedOnSomeTargets
        case selectedWithUnknownScope
        case notSelected
        case automatic
        case fixedVariant(DayNightRole)
        case mixedTargets
        case unknown
        case pendingVerification
    }

    let assignment: Assignment
    let selection: Selection

    /// Whether this card's assigned Day/Night role is the selected member when
    /// the pair is in fixed mode. Nil outside that specific presentation.
    var selectedRoleMatchesAssignment: Bool? {
        guard case .dayNight(let role) = assignment,
              case .fixedVariant(let selectedRole) = selection else { return nil }
        return role == selectedRole
    }

    static func resolve(
        wallpaperID: String,
        pair: DayNightWallpaperPair?,
        rawSelectionAssetIDs: Set<String>,
        inspection: AerialSelectionInspection?,
        selectionStatusUnknown: Bool,
        pendingAssetIDs: Set<String>?,
        recoveryPending: Bool
    ) -> Self {
        let role: DayNightRole?
        if let pair, pair.dayAssetID == wallpaperID {
            role = .day
        } else if let pair, pair.nightAssetID == wallpaperID {
            role = .night
        } else {
            role = nil
        }

        let assignment: Assignment = role.map(Assignment.dayNight(role:)) ?? .single

        if recoveryPending || pendingAssetIDs == nil || !(pendingAssetIDs?.isEmpty ?? true) {
            return Self(assignment: assignment, selection: .pendingVerification)
        }
        if selectionStatusUnknown {
            return Self(assignment: assignment, selection: .unknown)
        }
        guard let inspection, !inspection.targets.isEmpty else {
            // The legacy service can report which IDs occur, but without
            // target records it cannot prove that a selection is universal.
            if role == nil {
                return Self(
                    assignment: assignment,
                    selection: rawSelectionAssetIDs.contains(wallpaperID) ? .selectedWithUnknownScope : .notSelected
                )
            }
            return Self(assignment: assignment, selection: .unknown)
        }

        let selections = inspection.targets.compactMap(\.recognizedSelection)
        let hasDifferentSelections = selections.dropFirst().contains { $0 != selections[0] }
        let hasUnrecognizedTarget = selections.count != inspection.targets.count

        if role != nil, let pair {
            if inspection.matches(.automatic(groupID: ManifestStore.dayNightSubcategoryID)) {
                return Self(assignment: assignment, selection: .automatic)
            }
            if inspection.matches(.fixedVariant(assetID: pair.dayAssetID)) {
                return Self(assignment: assignment, selection: .fixedVariant(.day))
            }
            if inspection.matches(.fixedVariant(assetID: pair.nightAssetID)) {
                return Self(assignment: assignment, selection: .fixedVariant(.night))
            }
            let memberSelections = inspection.targets.compactMap { target -> String? in
                guard let selection = target.recognizedSelection else { return nil }
                switch selection {
                case .single(let assetID), .fixedVariant(let assetID):
                    return pair.memberAssetIDs.contains(assetID) ? assetID : nil
                case .automatic:
                    return nil
                }
            }
            if memberSelections.count == inspection.targets.count,
               Set(memberSelections).count == 1,
               let selectedMember = memberSelections.first {
                return Self(
                    assignment: assignment,
                    selection: selectedMember == wallpaperID ? .selectedEverywhere : .notSelected
                )
            }
            let memberMatches = memberSelections.filter { $0 == wallpaperID }
            if !memberMatches.isEmpty {
                if hasDifferentSelections {
                    return Self(assignment: assignment, selection: .mixedTargets)
                }
                if hasUnrecognizedTarget {
                    return Self(assignment: assignment, selection: .selectedWithUnknownScope)
                }
                return Self(assignment: assignment, selection: .selectedOnSomeTargets)
            }
            if hasDifferentSelections {
                return Self(assignment: assignment, selection: .mixedTargets)
            }
            if hasUnrecognizedTarget || selections.isEmpty {
                return Self(assignment: assignment, selection: .unknown)
            }
            // A uniformly recognized selection of another wallpaper means
            // this pair remains registered but is not the current selection.
            return Self(assignment: assignment, selection: .notSelected)
        }

        let matchingTargets = inspection.targets.filter {
            $0.recognizedSelection == .single(assetID: wallpaperID)
                || $0.recognizedSelection == .fixedVariant(assetID: wallpaperID)
        }
        if matchingTargets.count == inspection.targets.count {
            return Self(assignment: assignment, selection: .selectedEverywhere)
        }
        if !matchingTargets.isEmpty {
            if hasUnrecognizedTarget, !hasDifferentSelections {
                return Self(assignment: assignment, selection: .selectedWithUnknownScope)
            }
            if hasUnrecognizedTarget, hasDifferentSelections {
                return Self(assignment: assignment, selection: .mixedTargets)
            }
            return Self(assignment: assignment, selection: .selectedOnSomeTargets)
        }
        if hasDifferentSelections {
            return Self(assignment: assignment, selection: .mixedTargets)
        }
        if hasUnrecognizedTarget || selections.isEmpty {
            return Self(assignment: assignment, selection: .unknown)
        }
        return Self(assignment: assignment, selection: .notSelected)
    }

    var statusLabel: String {
        switch (assignment, selection) {
        case (.single, .selectedEverywhere):
            "Active"
        case (.single, .selectedOnSomeTargets):
            "Active on some targets"
        case (.single, .selectedWithUnknownScope):
            "Active · Scope unknown"
        case (.single, .notSelected):
            "Installed"
        case (.dayNight(let role), .automatic):
            "\(role.title) · In rotation"
        case (.dayNight(let role), .fixedVariant(let selectedRole)) where role == selectedRole:
            "\(role.title) selected · Automatic off"
        case (.dayNight(let role), .fixedVariant(let selectedRole)):
            "\(role.title) member · \(selectedRole.title) selected"
        case (.dayNight(let role), .notSelected):
            "\(role.title) member · Not selected"
        case (.dayNight(let role), .mixedTargets):
            "\(role.title) member · Selection varies"
        case (_, .mixedTargets):
            "Selection varies"
        case (.dayNight(let role), .unknown):
            "\(role.title) member · Selection unknown"
        case (.single, .unknown):
            "Selection unknown"
        case (.dayNight(let role), .pendingVerification):
            "\(role.title) member · Verification pending"
        case (.single, .pendingVerification):
            "Verification pending"
        case (.single, .automatic):
            "Automatic selection"
        case (.single, .fixedVariant(let role)):
            "\(role.title) variant selected"
        case (.dayNight(let role), .selectedEverywhere):
            "\(role.title) selected · Automatic off"
        case (.dayNight(let role), .selectedOnSomeTargets):
            "\(role.title) selected on some targets"
        case (.dayNight(let role), .selectedWithUnknownScope):
            "\(role.title) selected · Scope unknown"
        }
    }

    var accessibilityDescription: String {
        switch (assignment, selection) {
        case (.single, .selectedEverywhere):
            "Active wallpaper across all Spaces and displays."
        case (.single, .selectedOnSomeTargets):
            "Selected on some Spaces or displays."
        case (.single, .selectedWithUnknownScope):
            "This wallpaper appears in the native selection, but its Spaces and display coverage could not be verified."
        case (.single, .notSelected):
            "Installed, but not selected."
        case (.dayNight(let role), .automatic):
            "Registered \(role.title) member of the Day/Night pair. Automatic switching is selected across all Spaces and displays; macOS chooses which member to show based on the sun’s position."
        case (.dayNight(let role), .fixedVariant(let selectedRole)) where role == selectedRole:
            "Registered \(role.title) member is selected across all Spaces and displays. Automatic switching is off."
        case (.dayNight(let role), .fixedVariant(let selectedRole)):
            "Registered \(role.title) member of the Day/Night pair. The fixed \(selectedRole.title) variant is selected; Automatic switching is off."
        case (.dayNight(let role), .notSelected):
            "Registered \(role.title) member of the Day/Night pair. Another wallpaper is selected."
        case (_, .mixedTargets):
            "The wallpaper selection differs across Spaces or displays."
        case (_, .unknown):
            "The current wallpaper selection could not be verified."
        case (_, .pendingVerification):
            "A wallpaper change is waiting for verification."
        case (.single, .automatic):
            "An Automatic Aerial selection is active."
        case (.single, .fixedVariant(let role)):
            "The fixed \(role.title) variant is selected."
        case (.dayNight(let role), .selectedEverywhere):
            "The registered \(role.title) member is selected across all Spaces and displays. Day/Night Automatic switching is off."
        case (.dayNight(let role), .selectedOnSomeTargets):
            "The registered \(role.title) member is selected on some Spaces or displays."
        case (.dayNight(let role), .selectedWithUnknownScope):
            "The registered \(role.title) member appears in the native selection, but its Spaces and display coverage could not be verified."
        }
    }

    var activationTitle: String {
        switch assignment {
        case .single: "Set as Wallpaper"
        case .dayNight(let role): "Use \(role.title) only"
        }
    }

    var activationHelp: String {
        switch assignment {
        case .single:
            return "Apply this wallpaper across all Spaces and displays"
        case .dayNight(let role):
            if selection == .fixedVariant(role) {
                return "\(role.title) is selected across all Spaces and displays. Automatic switching is off."
            }
            return "Select only the \(role.title) variant across all Spaces and displays. Automatic switching will be off."
        }
    }
}
