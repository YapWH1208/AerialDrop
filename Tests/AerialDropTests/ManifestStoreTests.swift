import Foundation
import XCTest
@testable import AerialDrop

final class ManifestStoreTests: XCTestCase {
    private var home: URL!
    private var paths: WallpaperPaths!
    private var store: ManifestStore!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AerialDropTests-\(UUID().uuidString)", isDirectory: true)
        paths = WallpaperPaths(homeDirectory: home)
        store = ManifestStore(paths: paths)
        try store.prepareDirectories()
        try fixtureData().write(to: paths.manifest, options: .atomic)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testImportMatchesCompleteCustomEntryShapeAndPreservesForeignData() throws {
        let original = try json(at: paths.manifest)
        let originalForeignAsset = try XCTUnwrap((original["assets"] as? [[String: Any]])?.first)
        let originalForeignCategory = try XCTUnwrap((original["categories"] as? [[String: Any]])?.first)

        let id = "11111111-2222-4333-8444-555555ABCDEF"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Test Wallpaper")

        let result = try json(at: paths.manifest)
        let assets = try XCTUnwrap(result["assets"] as? [[String: Any]])
        let categories = try XCTUnwrap(result["categories"] as? [[String: Any]])

        XCTAssertEqual(canonical(assets[0]), canonical(originalForeignAsset))
        XCTAssertEqual(canonical(categories[0]), canonical(originalForeignCategory))
        XCTAssertEqual(result["initialAssetCount"] as? Int, 2)
        XCTAssertEqual(result["version"] as? Int, 1)

        let asset = try XCTUnwrap(assets.first(where: { ($0["id"] as? String) == id }))
        XCTAssertEqual(asset["shotID"] as? String, "CUSTOM_11111111_2222_4333_8444_555555ABCDEF")
        XCTAssertEqual((asset["pointsOfInterest"] as? [String: String])?["0"], "CUSTOM_11111111_2222_4333_8444_555555ABCDEF_0")
        XCTAssertEqual(asset["categories"] as? [String], [ManifestStore.categoryID])
        XCTAssertEqual(asset["subcategories"] as? [String], [ManifestStore.subcategoryID])
        XCTAssertNotNil(asset["previewImage"] as? String)
        XCTAssertNotNil(asset["url-4K-SDR-240FPS"] as? String)

        let category = try XCTUnwrap(categories.first(where: { ($0["id"] as? String) == ManifestStore.categoryID }))
        XCTAssertEqual(category["representativeAssetID"] as? String, id)
        XCTAssertNotNil(category["previewImage"] as? String)
        let subcategories = try XCTUnwrap(category["subcategories"] as? [[String: Any]])
        let subcategory = try XCTUnwrap(subcategories.first)
        XCTAssertEqual(subcategory["representativeAssetID"] as? String, id)
        XCTAssertNotNil(subcategory["previewImage"] as? String)
        XCTAssertEqual(subcategory["preferredOrder"] as? Int, 0)
    }

    func testRemoveAllReturnsToOriginalSemanticCatalogue() throws {
        let original = try json(at: paths.manifest)
        let id = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEE123456"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))

        try store.addWallpaper(id: id, title: "Temporary")
        try store.removeAllManaged()

        let restored = try json(at: paths.manifest)
        XCTAssertEqual(canonical(restored), canonical(original))
    }

    func testRenameUpdatesTitleAndPreservesForeignData() throws {
        let id = "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFF1234"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Old Name")

        try store.renameWallpaper(id: id, title: "New Name")

        let result = try json(at: paths.manifest)
        let assets = try XCTUnwrap(result["assets"] as? [[String: Any]])
        let asset = try XCTUnwrap(assets.first(where: { ($0["id"] as? String) == id }))
        XCTAssertEqual(asset["localizedNameKey"] as? String, "New Name")
        XCTAssertEqual(asset["accessibilityLabel"] as? String, "New Name")

        let foreignAsset = try XCTUnwrap(
            assets.first { !(($0["categories"] as? [String]) ?? []).contains(ManifestStore.categoryID) }
        )
        XCTAssertEqual(foreignAsset["id"] as? String, "EC42DAD0-E8D4-4408-9CA3-3B4767783453")

        let wallpapers = try store.importedWallpapers()
        XCTAssertEqual(wallpapers.first { $0.id == id }?.title, "New Name")
    }

    func testRenameUnknownWallpaperThrows() throws {
        XCTAssertThrowsError(
            try store.renameWallpaper(id: "ZZZZZZZZ-ZZZZ-4ZZZ-8ZZZ-ZZZZZZZZZZZZ", title: "Ghost")
        ) { error in
            guard case AerialDropError.wallpaperNotFound = error else {
                return XCTFail("Expected wallpaperNotFound, got \(error)")
            }
        }
    }

    func testAddWallpaperPersistsResolutionAndDefaultEntriesReadNil() throws {
        let id = "CCCCCCCC-DDDD-4EEE-8FFF-000000000001"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Resolution Test", width: 3440, height: 1440)

        let result = try json(at: paths.manifest)
        let assets = try XCTUnwrap(result["assets"] as? [[String: Any]])
        let asset = try XCTUnwrap(assets.first(where: { ($0["id"] as? String) == id }))
        XCTAssertEqual(asset["width"] as? Int, 3440)
        XCTAssertEqual(asset["height"] as? Int, 1440)

        let wallpapers = try store.importedWallpapers()
        XCTAssertEqual(wallpapers.first { $0.id == id }?.resolution, CGSize(width: 3440, height: 1440))

        // An entry added without width/height (the legacy shape) reads back as nil.
        let legacyID = "DDDDDDDD-EEEE-4FFF-8AAA-111111111111"
        try Data("video".utf8).write(to: paths.videoURL(for: legacyID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: legacyID))
        try store.addWallpaper(id: legacyID, title: "Legacy")
        let legacyWallpapers = try store.importedWallpapers()
        XCTAssertNil(legacyWallpapers.first { $0.id == legacyID }?.resolution)
    }

    func testLatestBackupSelectsNewestBackupAndParsesMetadata() throws {
        let older = paths.backups.appending(path: "entries-20260801-100000-000-import.json")
        let newer = paths.backups.appending(path: "entries-20260809-181419-745-remove.json")
        try Data("{}".utf8).write(to: older)
        try Data("{}".utf8).write(to: newer)

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(info.url, newer)
        XCTAssertEqual(info.operation, "remove")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        XCTAssertEqual(info.date, formatter.date(from: "20260809-181419-745"))
    }

    func testLatestBackupParsesSuffixedOperationNames() throws {
        let backup = paths.backups.appending(path: "entries-20260809-181419-745-import-2.json")
        try Data("{}".utf8).write(to: backup)

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(info.operation, "import-2")
    }

    func testRestoreBackupReturnsManagedStateAndPreservesForeignData() throws {
        let firstID = "12121212-3434-4567-8AAA-999999999991"
        try Data("video".utf8).write(to: paths.videoURL(for: firstID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: firstID))
        try store.addWallpaper(id: firstID, title: "First")
        let secondID = "12121212-3434-4567-8AAA-999999999992"
        try Data("video".utf8).write(to: paths.videoURL(for: secondID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: secondID))
        try store.addWallpaper(id: secondID, title: "Second")
        try store.renameWallpaper(id: secondID, title: "Renamed")

        // Simulate an entry lost to a bad edit: drop the second wallpaper.
        var current = try json(at: paths.manifest)
        var assets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        assets.removeAll {
            (($0["categories"] as? [String]) ?? []).contains(ManifestStore.categoryID)
                && ($0["id"] as? String) == secondID
        }
        current["assets"] = assets
        current["initialAssetCount"] = assets.count
        try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted])
            .write(to: paths.manifest, options: .atomic)

        let info = try XCTUnwrap(store.latestBackup())
        try store.restoreBackup(info)

        let wallpapers = try store.importedWallpapers()
        XCTAssertEqual(Set(wallpapers.map(\.id)), Set([firstID, secondID]))
        XCTAssertEqual(wallpapers.first { $0.id == secondID }?.title, "Second")
        let restored = try json(at: paths.manifest)
        let foreignAssets = try XCTUnwrap(restored["assets"] as? [[String: Any]]).filter {
            !(($0["categories"] as? [String]) ?? []).contains(ManifestStore.categoryID)
        }
        XCTAssertEqual(foreignAssets.count, 1)
        XCTAssertEqual(restored["initialAssetCount"] as? Int, 3)
    }

    func testRestoreBackupToleratesMissingManagedVideoFiles() throws {
        let id = "12121212-3434-4567-8AAA-999999999993"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Missing Video")
        try store.renameWallpaper(id: id, title: "Renamed")
        try FileManager.default.removeItem(at: paths.videoURL(for: id))

        // Drop the entry as if a bad edit removed it.
        var current = try json(at: paths.manifest)
        var assets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        assets.removeAll {
            (($0["categories"] as? [String]) ?? []).contains(ManifestStore.categoryID)
        }
        current["assets"] = assets
        current["initialAssetCount"] = assets.count
        try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted])
            .write(to: paths.manifest, options: .atomic)

        let info = try XCTUnwrap(store.latestBackup())
        try store.restoreBackup(info)

        let wallpapers = try store.importedWallpapers()
        let restored = try XCTUnwrap(wallpapers.first { $0.id == id })
        XCTAssertFalse(restored.videoExists)
    }

    func testRestoreBackupRefusesWhenForeignDataChangedSinceBackup() throws {
        let id = "12121212-3434-4567-8AAA-999999999994"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "First")

        // Foreign change after the backup: retitle the foreign asset directly.
        var current = try json(at: paths.manifest)
        var assets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        assets[0]["accessibilityLabel"] = "Changed By Another Tool"
        current["assets"] = assets
        try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted])
            .write(to: paths.manifest, options: .atomic)

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertThrowsError(try store.restoreBackup(info)) { error in
            guard case AerialDropError.backupRestoreRejected = error else {
                return XCTFail("Expected backupRestoreRejected, got \(error)")
            }
        }
        let after = try json(at: paths.manifest)
        let afterAssets = try XCTUnwrap(after["assets"] as? [[String: Any]])
        XCTAssertEqual(afterAssets[0]["accessibilityLabel"] as? String, "Changed By Another Tool")
    }

    private func fixtureData() throws -> Data {
        let fixture: [String: Any] = [
            "version": 1,
            "localizationVersion": "fixture",
            "initialAssetCount": 1,
            "assets": [[
                "id": "EC42DAD0-E8D4-4408-9CA3-3B4767783453",
                "shotID": "CUSTOM_783453",
                "localizedNameKey": "Foreign Wallpaper",
                "accessibilityLabel": "Foreign Wallpaper",
                "includeInShuffle": true,
                "showInTopLevel": true,
                "preferredOrder": 0,
                "categories": ["BD000000-0000-4000-8000-000000000001"],
                "subcategories": ["BD000000-0000-4000-8000-000000000002"],
                "pointsOfInterest": ["0": "CUSTOM_783453_0"],
                "previewImage": "file:///foreign.png",
                "url-4K-SDR-240FPS": "file:///foreign.mov"
            ]],
            "categories": [[
                "id": "BD000000-0000-4000-8000-000000000001",
                "localizedNameKey": "Foreign",
                "localizedDescriptionKey": "Foreign",
                "preferredOrder": 0,
                "previewImage": "file:///foreign.png",
                "representativeAssetID": "EC42DAD0-E8D4-4408-9CA3-3B4767783453",
                "subcategories": [[
                    "id": "BD000000-0000-4000-8000-000000000002",
                    "localizedNameKey": "Foreign",
                    "localizedDescriptionKey": "Foreign",
                    "preferredOrder": 0,
                    "previewImage": "file:///foreign.png",
                    "representativeAssetID": "EC42DAD0-E8D4-4408-9CA3-3B4767783453"
                ]]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted])
    }

    private func json(at url: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func canonical(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testRenamePreservesResolution() throws {
        let id = "EEEEEEEE-FFFF-4AAA-8BBB-222222222222"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Before", width: 1920, height: 1080)

        try store.renameWallpaper(id: id, title: "After")

        let wallpapers = try store.importedWallpapers()
        XCTAssertEqual(wallpapers.first { $0.id == id }?.resolution, CGSize(width: 1920, height: 1080))
    }

    func testSecondImportPreservesFirstEntryResolution() throws {
        let firstID = "99999999-AAAA-4BBB-8CCC-333333333333"
        try Data("video".utf8).write(to: paths.videoURL(for: firstID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: firstID))
        try store.addWallpaper(id: firstID, title: "First", width: 3440, height: 1440)

        let secondID = "88888888-BBBB-4CCC-8DDD-444444444444"
        try Data("video".utf8).write(to: paths.videoURL(for: secondID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: secondID))
        try store.addWallpaper(id: secondID, title: "Second", width: 1920, height: 1080)

        let wallpapers = try store.importedWallpapers()
        XCTAssertEqual(wallpapers.first { $0.id == firstID }?.resolution, CGSize(width: 3440, height: 1440))
        XCTAssertEqual(wallpapers.first { $0.id == secondID }?.resolution, CGSize(width: 1920, height: 1080))
    }
}
