import Foundation

/// Private formats are enabled only for native builds whose solar selection
/// contract has been observed. Add builds after verifying their native behavior.
enum DayNightWallpaperCapability {
    static let supportedAerialBuilds: Set<String> = ["313.0.4.401"]
    static let bundleInfoURL = URL(fileURLWithPath:
        "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Info.plist")

    static func validateCurrentSystem() throws {
        let info: [String: Any]
        do {
            let data = try Data(contentsOf: bundleInfoURL)
            guard let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw AerialDropError.dayNightUnavailable("The native Aerial format could not be checked.")
            }
            info = decoded
        } catch {
            throw AerialDropError.dayNightUnavailable("The native Aerial format could not be checked. Single wallpapers remain available.")
        }
        try validate(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, bundleInfo: info)
    }

    static func validate(osMajor: Int, bundleInfo: [String: Any]) throws {
        guard osMajor >= 27 else {
            throw AerialDropError.dayNightUnavailable("Day/Night wallpapers require macOS 27 or later. You can still apply a single wallpaper.")
        }
        guard bundleInfo["CFBundleIdentifier"] as? String == "com.apple.wallpaper.extension.aerials",
              let build = bundleInfo["CFBundleVersion"] as? String,
              supportedAerialBuilds.contains(build) else {
            throw AerialDropError.dayNightUnavailable("This macOS Aerial format has not been verified for Day/Night wallpapers. Single wallpapers remain available.")
        }
    }
}
