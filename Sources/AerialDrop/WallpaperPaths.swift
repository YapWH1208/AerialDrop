import Foundation

struct WallpaperPaths {
    let wallpaperSupport: URL
    let base: URL
    let manifestDirectory: URL
    let manifest: URL
    let videos: URL
    let thumbnails: URL
    let backups: URL
    let selectionStoreDirectory: URL
    let selectionStore: URL
    let selectionBackups: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        wallpaperSupport = homeDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "com.apple.wallpaper", directoryHint: .isDirectory)
        base = wallpaperSupport.appending(path: "aerials", directoryHint: .isDirectory)
        manifestDirectory = base.appending(path: "manifest", directoryHint: .isDirectory)
        manifest = manifestDirectory.appending(path: "entries.json")
        videos = base.appending(path: "videos", directoryHint: .isDirectory)
        thumbnails = base.appending(path: "thumbnails", directoryHint: .isDirectory)
        backups = base.appending(path: "AerialDropBackups", directoryHint: .isDirectory)
        selectionStoreDirectory = wallpaperSupport.appending(path: "Store", directoryHint: .isDirectory)
        selectionStore = selectionStoreDirectory.appending(path: "Index.plist")
        selectionBackups = selectionStoreDirectory.appending(path: "AerialDropBackups", directoryHint: .isDirectory)
    }

    func videoURL(for id: String) -> URL {
        videos.appending(path: "\(id).mov")
    }

    func thumbnailURL(for id: String) -> URL {
        thumbnails.appending(path: "\(id).png")
    }
}
