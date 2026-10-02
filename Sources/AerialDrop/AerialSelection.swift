import Foundation

/// The observed native selection forms. Group membership belongs to the
/// manifest; this request describes only the selection plist identity/options.
enum AerialSelectionRequest: Equatable, Sendable {
    case single(assetID: String)
    case fixedVariant(assetID: String)
    case automatic(groupID: String)

    var assetID: String {
        switch self {
        case .single(let id), .fixedVariant(let id), .automatic(let id): id
        }
    }
}

enum AerialSelectionTarget: Equatable, Hashable, Sendable {
    case allSpacesAndDisplays
    case systemDefault
    case space(String)
}

struct AerialTargetSelection: Equatable, Sendable {
    let target: AerialSelectionTarget
    /// Every native Aerial configuration reference, even with unfamiliar options.
    let rawAssetIDs: Set<String>
    /// Nil for non-Aerial, shuffle, mixed, or unsupported native selections.
    let recognizedSelection: AerialSelectionRequest?
}

struct AerialSelectionInspection: Equatable, Sendable {
    let targets: [AerialTargetSelection]

    var rawAssetIDs: Set<String> {
        Set(targets.flatMap(\.rawAssetIDs))
    }

    func matches(_ selection: AerialSelectionRequest) -> Bool {
        !targets.isEmpty && targets.allSatisfy { $0.recognizedSelection == selection }
    }
}
