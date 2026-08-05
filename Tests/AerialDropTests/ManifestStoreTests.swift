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
}
