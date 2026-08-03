import Foundation

struct WallpaperPaths {
    let base: URL
    let manifestDirectory: URL
    let manifest: URL
    let videos: URL
    let thumbnails: URL
    let backups: URL
    let storeDirectory: URL
    let storeIndex: URL
    let storeBackups: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        base = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
        manifestDirectory = base.appendingPathComponent("manifest", isDirectory: true)
        manifest = manifestDirectory.appendingPathComponent("entries.json", isDirectory: false)
        videos = base.appendingPathComponent("videos", isDirectory: true)
        thumbnails = base.appendingPathComponent("thumbnails", isDirectory: true)
        backups = base.appendingPathComponent("AerialDropBackups", isDirectory: true)

        storeDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
        storeIndex = storeDirectory.appendingPathComponent("Index.plist", isDirectory: false)
        storeBackups = storeDirectory.appendingPathComponent("AerialDropBackups", isDirectory: true)
    }

    func videoURL(for id: String) -> URL {
        videos.appendingPathComponent("\(id).mov", isDirectory: false)
    }

    func thumbnailURL(for id: String) -> URL {
        thumbnails.appendingPathComponent("\(id).png", isDirectory: false)
    }
}
