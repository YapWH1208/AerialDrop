import Foundation

enum AppPreferences {
    static let setWallpaperAfterImportKey = "setWallpaperAfterImport"
    static let lastConversionQualityKey = "lastConversionQuality"
    static let lastOutputHeightCapKey = "lastOutputHeightCap"

    static func isSetWallpaperAfterImportEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: setWallpaperAfterImportKey) != nil else {
            return true
        }
        return defaults.bool(forKey: setWallpaperAfterImportKey)
    }

    static func setSetWallpaperAfterImportEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: setWallpaperAfterImportKey)
    }

    /// The quality preset used by the most recent import, if any. Seeds the
    /// Import pane so repeated importers do not re-pick it for every video.
    static func lastConversionQuality(defaults: UserDefaults = .standard) -> ConversionOptions.Quality? {
        guard let raw = defaults.string(forKey: lastConversionQualityKey) else { return nil }
        return ConversionOptions.Quality(rawValue: raw)
    }

    static func setLastConversionQuality(_ quality: ConversionOptions.Quality, defaults: UserDefaults = .standard) {
        defaults.set(quality.rawValue, forKey: lastConversionQualityKey)
    }

    /// The output-height cap used by the most recent import, if any. Stored
    /// only when the user actually chose one (nil means "Original").
    static func lastOutputHeightCap(defaults: UserDefaults = .standard) -> Int? {
        let value = defaults.integer(forKey: lastOutputHeightCapKey)
        guard value > 0 else { return nil }
        return value
    }

    static func setLastOutputHeightCap(_ cap: Int?, defaults: UserDefaults = .standard) {
        if let cap {
            defaults.set(cap, forKey: lastOutputHeightCapKey)
        } else {
            defaults.removeObject(forKey: lastOutputHeightCapKey)
        }
    }
}
