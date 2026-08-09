import Foundation

enum AppPreferences {
    static let setWallpaperAfterImportKey = "setWallpaperAfterImport"

    static func isSetWallpaperAfterImportEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: setWallpaperAfterImportKey) != nil else {
            return true
        }
        return defaults.bool(forKey: setWallpaperAfterImportKey)
    }

    static func setSetWallpaperAfterImportEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: setWallpaperAfterImportKey)
    }
}
