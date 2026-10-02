import Foundation

/// Saved Library choices. Saving a draft never registers or activates a pair.
/// Missing installed members remain visible so the user can choose replacements.
struct DayNightWallpaperDraft: Equatable, Sendable {
    var dayAssetID: String?
    var nightAssetID: String?

    init(dayAssetID: String? = nil, nightAssetID: String? = nil) {
        self.dayAssetID = dayAssetID
        self.nightAssetID = nightAssetID
    }
}
