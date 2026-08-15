import Foundation

/// Single source of truth for the marketing version and build number.
/// Scripts/build-app.sh reads these values to generate Info.plist.
enum AppVersion {
    static let shortVersion = "1.1.4"
    static let buildNumber = "19"
}
