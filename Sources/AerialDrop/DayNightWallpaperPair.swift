import Foundation

/// The two imported AerialDrop assets registered as one native solar group.
/// Draft Day/Night choices live outside the manifest; this value describes only
/// the pair currently registered with the native Aerial catalogue.
struct DayNightWallpaperPair: Equatable, Sendable {
    let dayAssetID: String
    let nightAssetID: String

    var memberAssetIDs: Set<String> {
        [dayAssetID, nightAssetID]
    }
}
