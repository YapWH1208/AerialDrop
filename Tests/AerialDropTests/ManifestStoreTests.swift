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

    func testLatestBackupOrdersSameMillisecondBackupsByWriteOrder() throws {
        let timestamp = "20260809-181419-745"
        let importBackup = paths.backups.appending(path: "entries-\(timestamp)-import.json")
        let renameBackup = paths.backups.appending(path: "entries-\(timestamp)-rename.json")
        try Data("{}".utf8).write(to: importBackup)
        try Data("{}".utf8).write(to: renameBackup)

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(info.url, renameBackup)
    }

    func testLatestBackupFallsBackToNameOrderWhenModificationTimesMatch() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let importBackup = paths.backups.appending(path: "entries-20260809-181419-745-import.json")
        let renameBackup = paths.backups.appending(path: "entries-20260809-181419-745-rename.json")
        try Data("{}".utf8).write(to: importBackup)
        try Data("{}".utf8).write(to: renameBackup)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: importBackup.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: renameBackup.path
        )

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(info.url, renameBackup)
    }

    func testRestoreBackupWrapsMissingManifestAsRejected() throws {
        let backup = paths.backups.appending(path: "entries-20260809-181419-745-import.json")
        try fixtureData().write(to: backup)
        try FileManager.default.removeItem(at: paths.manifest)

        let info = try XCTUnwrap(store.latestBackup())
        XCTAssertThrowsError(try store.restoreBackup(info)) { error in
            guard case AerialDropError.backupRestoreRejected = error else {
                return XCTFail("Expected backupRestoreRejected, got \(error)")
            }
        }
    }

    func testImportedWallpapersExposeImportOrder() throws {
        let firstID = "12121212-3434-4567-8AAA-9999999999A1"
        try Data("video".utf8).write(to: paths.videoURL(for: firstID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: firstID))
        try store.addWallpaper(id: firstID, title: "First")
        let secondID = "12121212-3434-4567-8AAA-9999999999A2"
        try Data("video".utf8).write(to: paths.videoURL(for: secondID))
        try Data("png".utf8).write(to: paths.thumbnailURL(for: secondID))
        try store.addWallpaper(id: secondID, title: "Second")

        let wallpapers = try store.importedWallpapers()

        XCTAssertEqual(wallpapers.first { $0.id == firstID }?.preferredOrder, 0)
        XCTAssertEqual(wallpapers.first { $0.id == secondID }?.preferredOrder, 1)
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

    func testRestoreRejectsChangedConfirmedBackupBeforeWritingCatalogueOrBackup() throws {
        try installFixtureWallpaper(id: "confirmed-target", title: "Current")
        let confirmed = try XCTUnwrap(store.latestBackup())
        let currentData = try Data(contentsOf: paths.manifest)
        // Replace the exact confirmed filename with a different valid snapshot. Without
        // content identity this would be an otherwise safe, foreign-preserving restore.
        try currentData.write(to: confirmed.url, options: .atomic)
        let backupsBefore = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)

        XCTAssertThrowsError(try store.restoreBackup(confirmed)) { error in
            guard case AerialDropError.backupRestoreRejected(let reason) = error else {
                return XCTFail("Expected backupRestoreRejected, got \(error)")
            }
            XCTAssertTrue(reason.contains("changed after confirmation"))
        }

        XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
        XCTAssertEqual(try Data(contentsOf: confirmed.url), currentData)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)), Set(backupsBefore))
    }

    func testRestoreDefaultsToUnknownSelectionWhenBackupRemovesManagedEntry() throws {
        try installFixtureWallpaper(id: "currently-managed", title: "Current")
        let confirmed = try XCTUnwrap(store.latestBackup())
        let currentData = try Data(contentsOf: paths.manifest)
        let backupsBefore = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)

        XCTAssertThrowsError(try store.restoreBackup(confirmed)) { error in
            guard case AerialDropError.backupRestoreRejected(let reason) = error else {
                return XCTFail("Expected backupRestoreRejected, got \(error)")
            }
            XCTAssertTrue(reason.contains("couldn’t verify which wallpaper is active"))
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)),
            Set(backupsBefore)
        )

        // An explicit reader reports a verified-inactive selection at commit time.
        try store.restoreBackup(confirmed, protectingActiveAssetIDs: { [] })
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
    }

    func testRestoreRechecksSelectionBeforeWritingCatalogueOrBackup() throws {
        let id = "became-active-before-restore"
        try installFixtureWallpaper(id: id, title: "Current")
        let confirmed = try XCTUnwrap(store.latestBackup())
        let currentData = try Data(contentsOf: paths.manifest)
        let backupsBefore = Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path))
        for activationRead in [2, 3] {
            var reads = 0
            XCTAssertThrowsError(try store.restoreBackup(confirmed, protectingActiveAssetIDs: {
                reads += 1
                return reads < activationRead ? [] : [id]
            })) { error in
                guard case AerialDropError.backupRestoreRejected(let reason) = error else {
                    return XCTFail("Expected backupRestoreRejected, got \(error)")
                }
                XCTAssertTrue(reason.contains("currently active"))
            }
            XCTAssertEqual(reads, activationRead)
            XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
            XCTAssertEqual(
                Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)),
                backupsBefore
            )
        }
    }

    func testRestoreKeepsCommittedCatalogueAndSafetyBackupIfSelectionChangesAfterWrite() throws {
        let id = "became-active-at-commit"
        try installFixtureWallpaper(id: id, title: "Current")
        let confirmed = try XCTUnwrap(store.latestBackup())
        let currentData = try Data(contentsOf: paths.manifest)
        let backupsBefore = Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path))
        var reads = 0
        var becameActive = false

        XCTAssertThrowsError(try store.restoreBackup(confirmed, protectingActiveAssetIDs: {
            reads += 1
            if reads == 3 {
                defer { becameActive = true }
                return []
            }
            return becameActive ? [id] : []
        })) { error in
            guard case AerialDropError.backupRestoreCommitted(let reason) = error else {
                return XCTFail("Expected backupRestoreCommitted, got \(error)")
            }
            XCTAssertTrue(reason.contains("left the restored catalogue in place"))
            XCTAssertTrue(reason.contains("safety backup"))
        }

        XCTAssertEqual(reads, 4)
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
        let backupsAfter = Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path))
        XCTAssertEqual(backupsAfter.count, backupsBefore.count + 1)
        let addedBackups = backupsAfter.subtracting(backupsBefore)
        XCTAssertEqual(addedBackups.count, 1)
        let safetyBackup = try XCTUnwrap(addedBackups.first)
        XCTAssertEqual(
            try Data(contentsOf: paths.backups.appending(path: safetyBackup)),
            currentData
        )
    }

    func testRestoreDoesNotOverwriteConcurrentManifestAfterCommit() throws {
        let id = "became-active-with-concurrent-manifest"
        try installFixtureWallpaper(id: id, title: "Current")
        let confirmed = try XCTUnwrap(store.latestBackup())
        let currentData = try Data(contentsOf: paths.manifest)
        let backupsBefore = Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path))
        var concurrentRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        concurrentRoot["concurrentUpdate"] = true
        let concurrentData = try JSONSerialization.data(withJSONObject: concurrentRoot, options: [.prettyPrinted])
        let manifestURL = paths.manifest
        var reads = 0
        var becameActive = false

        XCTAssertThrowsError(try store.restoreBackup(confirmed, protectingActiveAssetIDs: {
            reads += 1
            if reads == 3 {
                defer { becameActive = true }
                return []
            }
            if reads == 4 {
                try concurrentData.write(to: manifestURL, options: .atomic)
            }
            return becameActive ? [id] : []
        })) { error in
            guard case AerialDropError.backupRestoreSuperseded(let reason) = error else {
                return XCTFail("Expected backupRestoreSuperseded, got \(error)")
            }
            XCTAssertTrue(reason.contains("kept the current catalogue untouched"))
        }

        XCTAssertEqual(reads, 4)
        XCTAssertEqual(try Data(contentsOf: paths.manifest), concurrentData)
        let backupsAfter = Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path))
        XCTAssertEqual(backupsAfter.count, backupsBefore.count + 1)
        let addedBackups = backupsAfter.subtracting(backupsBefore)
        let safetyBackup = try XCTUnwrap(addedBackups.first)
        XCTAssertEqual(
            try Data(contentsOf: paths.backups.appending(path: safetyBackup)),
            currentData
        )
    }

    func testUnsafeInputIDsAreRejectedBeforeMutationOrDeletion() throws {
        let before = try Data(contentsOf: paths.manifest)
        let sentinel = paths.base.appending(path: "sentinel.mov")
        try Data("outside videos".utf8).write(to: sentinel)
        for id in ["", ".", "..", "../sentinel", "folder/item", "folder\\item", "item\0suffix"] {
            XCTAssertThrowsError(try store.addWallpaper(id: id, title: "Unsafe"), id)
            XCTAssertThrowsError(try store.renameWallpaper(id: id, title: "Unsafe"), id)
            XCTAssertThrowsError(try store.removeWallpaper(id: id), id)
            XCTAssertEqual(try Data(contentsOf: paths.manifest), before, id)
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("outside videos".utf8), id)
        }
    }

    func testUnsafeExistingIDsAreRejectedBeforePathExposureOrNormalization() throws {
        let safeID = "legacy-safe-id"
        try installFixtureWallpaper(id: safeID, title: "Safe")
        let safeRoot = try json(at: paths.manifest)
        let sentinel = paths.base.appending(path: "sentinel.mov")
        try Data("outside videos".utf8).write(to: sentinel)
        for id in ["", ".", "..", "../sentinel", "folder/item", "folder\\item", "item\0suffix"] {
            var root = safeRoot
            var assets = try XCTUnwrap(root["assets"] as? [[String: Any]])
            let managedIndex = try XCTUnwrap(assets.firstIndex { ($0["id"] as? String) == safeID })
            assets[managedIndex]["id"] = id
            root["assets"] = assets
            let malformedData = try JSONSerialization.data(withJSONObject: root)
            try malformedData.write(to: paths.manifest, options: .atomic)

            XCTAssertThrowsError(try store.importedWallpapers(), id)
            XCTAssertThrowsError(try store.removeAllManaged(), id)
            // Even a safe requested ID must not let normalization drop the unsafe original entry.
            XCTAssertThrowsError(try store.renameWallpaper(id: safeID, title: "Changed"), id)
            XCTAssertThrowsError(try store.removeWallpaper(id: safeID), id)
            XCTAssertThrowsError(try store.addWallpaper(id: safeID, title: "Changed"), id)
            XCTAssertEqual(try Data(contentsOf: paths.manifest), malformedData, id)
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("outside videos".utf8), id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: safeID).path))
        }
    }

    func testSafeLegacyIDRemainsReadableAndRemovableWithMissingFiles() throws {
        let id = "Legacy Wallpaper_1.0"
        try installFixtureWallpaper(id: id, title: "Legacy")
        try FileManager.default.removeItem(at: paths.videoURL(for: id))
        let wallpaper = try XCTUnwrap(store.importedWallpapers().first { $0.id == id })
        XCTAssertFalse(wallpaper.videoExists)
        try store.removeWallpaper(id: id)
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
    }

    func testRestoreRefusesForeignTopLevelKeyAddedOrRemovedSinceBackup() throws {
        for removeCurrentKey in [true, false] {
            var backupRoot = try JSONSerialization.jsonObject(with: fixtureData()) as! [String: Any]
            var currentRoot = backupRoot
            if removeCurrentKey {
                backupRoot["ForeignFeature"] = ["enabled": true]
            } else {
                currentRoot["ForeignFeature"] = ["enabled": true]
            }
            let backupURL = paths.backups.appending(path: "entries-20260809-181419-745-foreign.json")
            try JSONSerialization.data(withJSONObject: backupRoot).write(to: backupURL)
            let currentData = try JSONSerialization.data(withJSONObject: currentRoot)
            try currentData.write(to: paths.manifest, options: .atomic)
            let info = ManifestStore.BackupInfo(url: backupURL, date: Date(), operation: "foreign")

            XCTAssertThrowsError(try store.restoreBackup(info))
            XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
        }
    }

    func testRenameRepairsMissingRepresentativeAndPreservesForeignEntries() throws {
        for missingThumbnail in [true, false] {
            try fixtureData().write(to: paths.manifest, options: .atomic)
            try installFixtureWallpaper(id: "survivor", title: "Original", width: 1920, height: 1080)
            try installFixtureWallpaper(id: "representative", title: "Missing")
            let before = try json(at: paths.manifest)
            try FileManager.default.removeItem(at: missingThumbnail
                ? paths.thumbnailURL(for: "representative") : paths.videoURL(for: "representative"))

            try store.renameWallpaper(id: "survivor", title: "Renamed")

            let after = try json(at: paths.manifest)
            let assets = try XCTUnwrap(after["assets"] as? [[String: Any]])
            let categories = try XCTUnwrap(after["categories"] as? [[String: Any]])
            XCTAssertEqual(canonical(assets[0]), canonical((before["assets"] as! [[String: Any]])[0]))
            XCTAssertEqual(canonical(categories[0]), canonical((before["categories"] as! [[String: Any]])[0]))
            let wallpapers = try store.importedWallpapers()
            XCTAssertEqual(wallpapers.map(\.id), ["survivor"])
            XCTAssertEqual(wallpapers.first?.title, "Renamed")
            XCTAssertEqual(wallpapers.first?.preferredOrder, 0)
            XCTAssertEqual(wallpapers.first?.resolution, CGSize(width: 1920, height: 1080))
            let category = try XCTUnwrap(categories.first { ($0["id"] as? String) == ManifestStore.categoryID })
            XCTAssertEqual(category["representativeAssetID"] as? String, "survivor")
            let subcategory = try XCTUnwrap((category["subcategories"] as? [[String: Any]])?.first)
            XCTAssertEqual(subcategory["representativeAssetID"] as? String, "survivor")
            try store.validateCurrentManifest()
        }
    }

    func testRenameRefusesMissingTargetFilesWithoutDroppingEntriesOrWritingBackup() throws {
        for soleTarget in [true, false] {
            for missingThumbnail in [true, false] {
                try fixtureData().write(to: paths.manifest, options: .atomic)
                if !soleTarget {
                    try installFixtureWallpaper(id: "survivor", title: "Healthy")
                }
                try installFixtureWallpaper(id: "target", title: "Original")
                let missingURL = missingThumbnail ? paths.thumbnailURL(for: "target") : paths.videoURL(for: "target")
                try FileManager.default.removeItem(at: missingURL)
                let originalData = try Data(contentsOf: paths.manifest)
                let originalBackups = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)

                XCTAssertThrowsError(try store.renameWallpaper(id: "target", title: "Renamed")) { error in
                    guard case AerialDropError.installedFileMissing(let url) = error else {
                        return XCTFail("Expected installedFileMissing, got \(error)")
                    }
                    XCTAssertEqual(url, missingURL)
                }

                XCTAssertEqual(try Data(contentsOf: paths.manifest), originalData)
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)), Set(originalBackups))
                XCTAssertEqual(try store.importedWallpapers().first { $0.id == "target" }?.title, "Original")
            }
        }
    }

    func testCatalogueReadRejectsMalformedBaseStructureAndCounts() throws {
        let original = try json(at: paths.manifest)
        for key in ["assets", "categories", "version", "initialAssetCount"] {
            var root = original
            root.removeValue(forKey: key)
            try JSONSerialization.data(withJSONObject: root).write(to: paths.manifest)
            XCTAssertThrowsError(try store.importedWallpapers(), key)
        }
        for (description, invalidCount) in [
            ("above total", 2),
            ("negative", -1),
            ("fraction", 1.5),
            ("boolean", true),
            ("string", "1"),
            ("integer overflow", Double.greatestFiniteMagnitude)
        ] as [(String, Any)] {
            var root = original
            root["initialAssetCount"] = invalidCount
            try JSONSerialization.data(withJSONObject: root).write(to: paths.manifest)
            XCTAssertThrowsError(try store.importedWallpapers(), description)
        }
        try FileManager.default.removeItem(at: paths.manifest)
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
    }

    func testCatalogueReadAcceptsZeroInitialAssetCount() throws {
        var root = try json(at: paths.manifest)
        root["initialAssetCount"] = 0
        try JSONSerialization.data(withJSONObject: root).write(to: paths.manifest)

        XCTAssertNoThrow(try store.validateCurrentManifest())
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
    }

    func testNativeShapedPartialInitialAssetCountValidatesWithoutChangingBytes() throws {
        let originalData = try partialInitialCountFixtureData(assetCount: 164, initialAssetCount: 4)
        try originalData.write(to: paths.manifest, options: .atomic)

        XCTAssertTrue(try store.importedWallpapers().isEmpty)
        XCTAssertNoThrow(try store.validateCurrentManifest())
        XCTAssertEqual(try Data(contentsOf: paths.manifest), originalData)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path).isEmpty)
    }

    func testImportFromPartialInitialAssetCountPreservesBackupAndNormalizesLifecycleCounts() throws {
        let originalData = try partialInitialCountFixtureData(assetCount: 6, initialAssetCount: 4)
        try originalData.write(to: paths.manifest, options: .atomic)
        let originalRoot = try json(at: paths.manifest)
        let originalForeignAssets = try XCTUnwrap(originalRoot["assets"] as? [[String: Any]])
        let id = "PARTIAL-COUNT-LIFECYCLE"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: id))

        try store.addWallpaper(id: id, title: "Partial Count")

        let importBackup = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(importBackup.operation, "import")
        XCTAssertEqual(importBackup.content, originalData)
        var current = try json(at: paths.manifest)
        var currentAssets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        XCTAssertEqual(current["initialAssetCount"] as? Int, currentAssets.count)
        XCTAssertEqual(currentAssets.count, 7)
        XCTAssertEqual(canonical(Array(currentAssets.prefix(6))), canonical(originalForeignAssets))

        try store.renameWallpaper(id: id, title: "Renamed Partial Count")
        current = try json(at: paths.manifest)
        currentAssets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        XCTAssertEqual(current["initialAssetCount"] as? Int, currentAssets.count)
        XCTAssertEqual(try store.importedWallpapers().first?.title, "Renamed Partial Count")

        try store.removeWallpaper(id: id)
        current = try json(at: paths.manifest)
        currentAssets = try XCTUnwrap(current["assets"] as? [[String: Any]])
        XCTAssertEqual(current["initialAssetCount"] as? Int, currentAssets.count)
        XCTAssertEqual(canonical(currentAssets), canonical(originalForeignAssets))
    }

    func testRestoreAcceptsPartialInitialAssetCountAndBacksUpNormalizedCatalogue() throws {
        let originalData = try partialInitialCountFixtureData(assetCount: 6, initialAssetCount: 4)
        try originalData.write(to: paths.manifest, options: .atomic)
        let originalRoot = try json(at: paths.manifest)
        let id = "PARTIAL-COUNT-RESTORE"
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: "Restore Partial Count")
        let partialCountBackup = try XCTUnwrap(store.latestBackup())
        let preRestoreData = try Data(contentsOf: paths.manifest)
        let preRestoreRoot = try json(at: paths.manifest)
        XCTAssertEqual(preRestoreRoot["initialAssetCount"] as? Int, 7)
        XCTAssertEqual((preRestoreRoot["assets"] as? [[String: Any]])?.count, 7)

        try store.restoreBackup(partialCountBackup, protectingActiveAssetIDs: { [] })

        let restoredRoot = try json(at: paths.manifest)
        let restoredAssets = try XCTUnwrap(restoredRoot["assets"] as? [[String: Any]])
        XCTAssertEqual(restoredRoot["initialAssetCount"] as? Int, 4)
        XCTAssertEqual(restoredAssets.count, 6)
        XCTAssertFalse(restoredAssets.contains { ($0["id"] as? String) == id })
        XCTAssertEqual(canonical(restoredRoot), canonical(originalRoot))
        let restoreBackup = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(restoreBackup.operation, "restore")
        XCTAssertEqual(restoreBackup.content, preRestoreData)
    }

    private func installFixtureWallpaper(id: String, title: String, width: Int = 0, height: Int = 0) throws {
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: title, width: width, height: height)
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

    private func partialInitialCountFixtureData(assetCount: Int, initialAssetCount: Int) throws -> Data {
        let assets: [[String: Any]] = (0..<assetCount).map { index in
            [
                "id": "FOREIGN-\(index)",
                "categories": ["FOREIGN-CATEGORY"],
                "unknownNativeField": ["index": index]
            ]
        }
        let fixture: [String: Any] = [
            "version": 1,
            "localizationVersion": "native-shaped-fixture",
            "initialAssetCount": initialAssetCount,
            "assets": assets,
            "categories": []
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
