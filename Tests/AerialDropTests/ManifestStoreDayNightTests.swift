import Foundation
import XCTest
@testable import AerialDrop

final class ManifestStoreDayNightTests: XCTestCase {
    private var home: URL!
    private var paths: WallpaperPaths!
    private var store: ManifestStore!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AerialDropDayNightTests-\(UUID().uuidString)", isDirectory: true)
        paths = WallpaperPaths(homeDirectory: home)
        store = ManifestStore(paths: paths)
        try store.prepareDirectories()
        try fixtureData().write(to: paths.manifest, options: .atomic)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testConfigureCreatesDirectTwoMemberSolarGroupAndPreservesItThroughRenameAndImport() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let ordinaryID = "ORDINARY-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try install(id: ordinaryID, title: "Ordinary")

        let beforeConfiguration = try Data(contentsOf: paths.manifest)
        let beforeRoot = try json(at: paths.manifest)
        let foreignAsset = try XCTUnwrap((beforeRoot["assets"] as? [[String: Any]])?.first)
        let foreignCategory = try XCTUnwrap((beforeRoot["categories"] as? [[String: Any]])?.first)
        let videosBefore = try directoryNames(at: paths.videos)
        let thumbnailsBefore = try directoryNames(at: paths.thumbnails)
        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)

        try store.configureDayNightPair(pair)

        XCTAssertEqual(try store.dayNightPair(), pair)
        try assertPairShape(pair, ordinaryIDs: [ordinaryID])
        let configured = try json(at: paths.manifest)
        let configuredAssets = try XCTUnwrap(configured["assets"] as? [[String: Any]])
        let configuredCategories = try XCTUnwrap(configured["categories"] as? [[String: Any]])
        XCTAssertEqual(configuredAssets.count, 4)
        XCTAssertEqual(configured["initialAssetCount"] as? Int, configuredAssets.count)
        XCTAssertEqual(canonical(configuredAssets.first!), canonical(foreignAsset))
        XCTAssertEqual(canonical(configuredCategories.first!), canonical(foreignCategory))
        XCTAssertEqual(configured["foreignRoot"] as? [String: String], ["preserved": "yes"])
        XCTAssertEqual(try directoryNames(at: paths.videos), videosBefore)
        XCTAssertEqual(try directoryNames(at: paths.thumbnails), thumbnailsBefore)
        let configurationBackup = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(configurationBackup.operation, "configure-day-night")
        XCTAssertEqual(configurationBackup.content, beforeConfiguration)

        try store.renameWallpaper(id: dayID, title: "Renamed Day")
        XCTAssertEqual(try store.dayNightPair(), pair)
        try assertPairShape(pair, ordinaryIDs: [ordinaryID])

        let laterID = "LATER-IMPORT"
        try install(id: laterID, title: "Later")
        XCTAssertEqual(try store.dayNightPair(), pair)
        try assertPairShape(pair, ordinaryIDs: [ordinaryID, laterID])

        try store.addWallpaper(id: dayID, title: "Reimported Day")
        XCTAssertEqual(try store.dayNightPair(), pair)
        XCTAssertEqual(try store.importedWallpapers().first { $0.id == dayID }?.title, "Reimported Day")
        try assertPairShape(pair, ordinaryIDs: [ordinaryID, laterID])
    }

    func testConfigureReplacesAndSwapsRolesWithoutCreatingAliasesOrMediaCopies() throws {
        let firstID = "FIRST-ASSET"
        let secondID = "SECOND-ASSET"
        let thirdID = "THIRD-ASSET"
        try install(id: firstID, title: "First")
        try install(id: secondID, title: "Second")
        try install(id: thirdID, title: "Third")
        try store.configureDayNightPair(.init(dayAssetID: firstID, nightAssetID: secondID))

        let replacement = DayNightWallpaperPair(dayAssetID: thirdID, nightAssetID: firstID)
        try store.configureDayNightPair(replacement, protectingPreviousPairMembers: { _ in })
        XCTAssertEqual(try store.dayNightPair(), replacement)
        try assertPairShape(replacement, ordinaryIDs: [secondID])

        let swapped = DayNightWallpaperPair(dayAssetID: firstID, nightAssetID: thirdID)
        try store.configureDayNightPair(swapped, protectingPreviousPairMembers: { _ in })
        XCTAssertEqual(try store.dayNightPair(), swapped)
        try assertPairShape(swapped, ordinaryIDs: [secondID])
        XCTAssertEqual(try directoryNames(at: paths.videos), Set([firstID, secondID, thirdID].map { "\($0).mov" }))
        XCTAssertEqual(try directoryNames(at: paths.thumbnails), Set([firstID, secondID, thirdID].map { "\($0).png" }))
    }

    func testReconfigurationRequiresProtectionBeforeChangingTheCatalogue() throws {
        let firstID = "FIRST-ASSET"
        let secondID = "SECOND-ASSET"
        let thirdID = "THIRD-ASSET"
        for id in [firstID, secondID, thirdID] {
            try install(id: id, title: id)
        }
        let original = DayNightWallpaperPair(dayAssetID: firstID, nightAssetID: secondID)
        let replacement = DayNightWallpaperPair(dayAssetID: thirdID, nightAssetID: secondID)
        try store.configureDayNightPair(original)
        let before = try Data(contentsOf: paths.manifest)
        let backups = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.configureDayNightPair(replacement)) { error in
            guard case AerialDropError.dayNightPairChangeRequiresProtection = error else {
                return XCTFail("Expected previous-pair protection, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), before)
        XCTAssertEqual(try directoryNames(at: paths.backups), backups)

        var requestedProtection = Set<String>()
        XCTAssertThrowsError(try store.configureDayNightPair(
            replacement,
            protectingPreviousPairMembers: { ids in
                requestedProtection = ids
                XCTAssertEqual(try Data(contentsOf: self.paths.manifest), before)
                XCTAssertEqual(try self.directoryNames(at: self.paths.backups), backups)
                throw AerialDropError.manifestChangedDuringOperation
            }
        ))
        XCTAssertEqual(requestedProtection, Set([firstID, secondID, thirdID]))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), before)
        XCTAssertEqual(try directoryNames(at: paths.backups), backups)

        try store.configureDayNightPair(original)
        XCTAssertEqual(try store.dayNightPair(), original)
    }

    func testLegacyLibraryReadAllowsFieldsThatExistingNormalizationRepairs() throws {
        let id = "LEGACY-ASSET"
        try install(id: id, title: "Legacy")
        var root = try json(at: paths.manifest)
        var assets = try XCTUnwrap(root["assets"] as? [[String: Any]])
        let index = try XCTUnwrap(assets.firstIndex { ($0["id"] as? String) == id })
        assets[index]["previewImage"] = "file:///legacy-thumbnail.png"
        root["assets"] = assets
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        try legacyData.write(to: paths.manifest, options: .atomic)

        XCTAssertEqual(try store.importedWallpapers().map(\.id), [id])
        XCTAssertEqual(try Data(contentsOf: paths.manifest), legacyData)
        try store.renameWallpaper(id: id, title: "Repaired")
        let repaired = try managedAsset(id: id, in: json(at: paths.manifest))
        XCTAssertEqual(repaired["previewImage"] as? String, paths.thumbnailURL(for: id).absoluteString)
    }

    func testConfigureRejectsSameMissingAndForeignIDsBeforeBackupOrManifestWrite() throws {
        let dayID = "DAY-ASSET"
        try install(id: dayID, title: "Day")
        let originalData = try Data(contentsOf: paths.manifest)
        let originalBackups = try directoryNames(at: paths.backups)

        for pair in [
            DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: dayID),
            DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: "MISSING-ASSET"),
            DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: "FOREIGN-ASSET")
        ] {
            XCTAssertThrowsError(try store.configureDayNightPair(pair))
            XCTAssertEqual(try Data(contentsOf: paths.manifest), originalData)
            XCTAssertEqual(try directoryNames(at: paths.backups), originalBackups)
        }
    }

    func testConfigureRejectsMalformedManagedPathsAndMissingFilesWithoutRepairingCatalogue() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        var malformedRoot = try json(at: paths.manifest)
        var assets = try XCTUnwrap(malformedRoot["assets"] as? [[String: Any]])
        let dayIndex = try XCTUnwrap(assets.firstIndex { ($0["id"] as? String) == dayID })
        assets[dayIndex]["previewImage"] = "file:///wrong-thumbnail.png"
        malformedRoot["assets"] = assets
        let malformedData = try JSONSerialization.data(withJSONObject: malformedRoot, options: [.prettyPrinted])
        try malformedData.write(to: paths.manifest, options: .atomic)
        let backupsBeforeMalformedPath = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID)))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), malformedData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBeforeMalformedPath)

        try fixtureData().write(to: paths.manifest, options: .atomic)
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try FileManager.default.removeItem(at: paths.videoURL(for: nightID))
        let missingFileData = try Data(contentsOf: paths.manifest)
        let backupsBeforeMissingFile = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID)))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), missingFileData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBeforeMissingFile)
    }

    func testConfigureRejectsPairMemberIDDuplicatedByForeignAsset() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        var collisionRoot = try json(at: paths.manifest)
        var assets = try XCTUnwrap(collisionRoot["assets"] as? [[String: Any]])
        assets[0]["id"] = dayID
        collisionRoot["assets"] = assets
        let collisionData = try JSONSerialization.data(withJSONObject: collisionRoot, options: [.prettyPrinted])
        try collisionData.write(to: paths.manifest, options: .atomic)
        let backupsBefore = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID)))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), collisionData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBefore)
    }

    func testRemoveUnrelatedAssetPreservesPairAndRemovingInactiveMemberDismantlesPair() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let ordinaryID = "ORDINARY-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try install(id: ordinaryID, title: "Ordinary")
        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
        try store.configureDayNightPair(pair)

        try store.removeWallpaper(id: ordinaryID)
        XCTAssertEqual(try store.dayNightPair(), pair)
        try assertPairShape(pair, ordinaryIDs: [])

        let pairedData = try Data(contentsOf: paths.manifest)
        XCTAssertThrowsError(try store.removeWallpaper(id: dayID)) { error in
            guard case AerialDropError.wallpaperSelectionUnknownForRemoval = error else {
                return XCTFail("Expected wallpaperSelectionUnknownForRemoval, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: {
            [ManifestStore.dayNightSubcategoryID]
        })) { error in
            guard case AerialDropError.activeWallpaperCannotBeRemoved = error else {
                return XCTFail("Expected activeWallpaperCannotBeRemoved, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: {
            [nightID]
        })) { error in
            guard case AerialDropError.activeWallpaperCannotBeRemoved = error else {
                return XCTFail("Expected activeWallpaperCannotBeRemoved, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), pairedData)

        try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: { [] })

        XCTAssertNil(try store.dayNightPair())
        let root = try json(at: paths.manifest)
        let nightAsset = try managedAsset(id: nightID, in: root)
        XCTAssertEqual(nightAsset["subcategories"] as? [String], [ManifestStore.subcategoryID])
        XCTAssertNil(nightAsset["variant"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: nightID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: nightID).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.videoURL(for: dayID).path))
        let removalBackup = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(removalBackup.operation, "remove")
        XCTAssertEqual(removalBackup.content, pairedData)
    }

    func testRemoveAllProtectsActiveGroupAndVerifiedInactiveRemovalDeletesManagedFiles() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID))
        let pairedData = try Data(contentsOf: paths.manifest)

        XCTAssertThrowsError(try store.removeAllManaged(protectingActiveAssetIDs: {
            [ManifestStore.dayNightSubcategoryID]
        })) { error in
            guard case AerialDropError.activeWallpaperCannotBeRemoved = error else {
                return XCTFail("Expected activeWallpaperCannotBeRemoved, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), pairedData)

        try store.removeAllManaged(protectingActiveAssetIDs: { [] })
        XCTAssertTrue(try store.importedWallpapers().isEmpty)
        XCTAssertNil(try store.dayNightPair())
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.videoURL(for: dayID).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.videoURL(for: nightID).path))
    }

    func testRemovingPairMemberRefusesToDropSurvivorWhoseMediaIsMissing() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try store.configureDayNightPair(pair)
        try FileManager.default.removeItem(at: paths.videoURL(for: nightID))
        let pairedData = try Data(contentsOf: paths.manifest)
        let backupsBefore = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: { [] })) { error in
            guard case AerialDropError.installedFileMissing(let url) = error else {
                return XCTFail("Expected installedFileMissing, got \(error)")
            }
            XCTAssertEqual(url, self.paths.videoURL(for: nightID))
        }

        XCTAssertEqual(try Data(contentsOf: paths.manifest), pairedData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: dayID).path))
    }

    func testPairRemovalRechecksSelectionAfterWriteAndRetainsMediaAndSafetyBackup() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID))
        let pairedData = try Data(contentsOf: paths.manifest)
        let backupsBefore = try directoryNames(at: paths.backups)
        var reads = 0

        XCTAssertThrowsError(try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: {
            reads += 1
            return reads == 4 ? [nightID] : []
        })) { error in
            guard case AerialDropError.manifestMutationCommitted(let reason) = error else {
                return XCTFail("Expected manifestMutationCommitted, got \(error)")
            }
            XCTAssertTrue(reason.contains("safety backup"))
        }

        XCTAssertEqual(reads, 4)
        XCTAssertNil(try store.dayNightPair())
        XCTAssertEqual(Set(try store.importedWallpapers().map(\.id)), Set([nightID]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: dayID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: dayID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: nightID).path))
        let backupsAfter = try directoryNames(at: paths.backups)
        let addedBackups = backupsAfter.subtracting(backupsBefore)
        XCTAssertEqual(addedBackups.count, 1)
        let backupName = try XCTUnwrap(addedBackups.first)
        XCTAssertEqual(try Data(contentsOf: paths.backups.appending(path: backupName)), pairedData)
    }

    func testLateRemovalFailureDistinguishesConcurrentCatalogueAndUnknownOutcome() throws {
        for removeCatalogue in [false, true] {
            try fixtureData().write(to: paths.manifest, options: .atomic)
            let dayID = "DAY-ASSET"
            let nightID = "NIGHT-ASSET"
            try install(id: dayID, title: "Day")
            try install(id: nightID, title: "Night")
            try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID))
            let before = try Data(contentsOf: paths.manifest)
            var concurrent = try json(at: paths.manifest)
            concurrent["foreignConcurrentUpdate"] = "kept"
            let concurrentData = try JSONSerialization.data(withJSONObject: concurrent)
            var reads = 0

            XCTAssertThrowsError(try store.removeWallpaper(id: dayID, protectingActiveAssetIDs: {
                reads += 1
                if reads == 4 {
                    if removeCatalogue {
                        try FileManager.default.removeItem(at: self.paths.manifest)
                    } else {
                        try concurrentData.write(to: self.paths.manifest, options: .atomic)
                    }
                    return [nightID]
                }
                return []
            })) { error in
                if removeCatalogue {
                    guard case AerialDropError.manifestMutationOutcomeUnknown = error else {
                        return XCTFail("Expected unknown cleanup outcome, got \(error)")
                    }
                } else {
                    guard case AerialDropError.manifestMutationSuperseded = error else {
                        return XCTFail("Expected concurrent cleanup outcome, got \(error)")
                    }
                }
            }
            XCTAssertEqual(reads, 4)
            XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: dayID).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: dayID).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: nightID).path))
            if !removeCatalogue {
                XCTAssertEqual(try Data(contentsOf: paths.manifest), concurrentData)
            }
            let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
            XCTAssertTrue(try backups.contains { try Data(contentsOf: $0) == before })
        }
    }

    func testRestoreWithActiveGroupRejectsPairRemovalAndRoleChangeWithoutWritingBackup() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let thirdID = "THIRD-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try install(id: thirdID, title: "Third")
        try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID))
        let ordinaryBackup = try XCTUnwrap(store.latestBackup())
        let ordinaryBackupRoot = try json(data: XCTUnwrap(ordinaryBackup.content))
        XCTAssertNil(try groupSubcategory(in: ordinaryBackupRoot))
        try store.configureDayNightPair(
            .init(dayAssetID: thirdID, nightAssetID: nightID),
            protectingPreviousPairMembers: { _ in }
        )
        let roleMapBackup = try XCTUnwrap(store.latestBackup())
        let roleMapBackupRoot = try json(data: XCTUnwrap(roleMapBackup.content))
        XCTAssertEqual(
            try groupSubcategory(in: roleMapBackupRoot)?["representativeAssetID"] as? String,
            dayID
        )
        let currentData = try Data(contentsOf: paths.manifest)
        let backupsBefore = try directoryNames(at: paths.backups)

        XCTAssertThrowsError(try store.restoreBackup(roleMapBackup, protectingActiveAssetIDs: {
            [nightID]
        })) { error in
            guard case AerialDropError.backupRestoreRejected(let reason) = error else {
                return XCTFail("Expected backupRestoreRejected, got \(error)")
            }
            XCTAssertTrue(reason.contains("currently active"))
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBefore)

        XCTAssertThrowsError(try store.restoreBackup(ordinaryBackup, protectingActiveAssetIDs: {
            [ManifestStore.dayNightSubcategoryID]
        }))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), currentData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBefore)
    }

    func testRestoreWithActiveGroupAllowsMetadataRestoreWhenExactRolesRemain() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
        try install(id: dayID, title: "Original Day")
        try install(id: nightID, title: "Night")
        try store.configureDayNightPair(pair)
        try store.renameWallpaper(id: dayID, title: "Changed Day")
        let exactPairBackup = try XCTUnwrap(store.latestBackup())
        XCTAssertEqual(exactPairBackup.operation, "rename")

        try store.restoreBackup(exactPairBackup, protectingActiveAssetIDs: {
            [ManifestStore.dayNightSubcategoryID]
        })

        XCTAssertEqual(try store.dayNightPair(), pair)
        XCTAssertEqual(try store.importedWallpapers().first { $0.id == dayID }?.title, "Original Day")
        try assertPairShape(pair, ordinaryIDs: [])
    }

    func testStrictReaderRejectsMalformedOwnedGroupAndForeignStableIDCollision() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let thirdID = "THIRD-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        try install(id: thirdID, title: "Third")
        try store.configureDayNightPair(.init(dayAssetID: dayID, nightAssetID: nightID))
        let validRoot = try json(at: paths.manifest)

        let malformed: [(String, ([String: Any]) throws -> [String: Any])] = [
            ("combine false", { root in
                try self.mutatingGroup(in: root) { $0["combineVariants"] = false }
            }),
            ("combine numeric", { root in
                try self.mutatingGroup(in: root) { $0["combineVariants"] = 1 }
            }),
            ("combine string", { root in
                try self.mutatingGroup(in: root) { $0["combineVariants"] = "true" }
            }),
            ("extra native key", { root in
                try self.mutatingGroup(in: root) { $0["selectableVariantDimensions"] = ["solar"] }
            }),
            ("night representative", { root in
                try self.mutatingGroup(in: root) {
                    $0["representativeAssetID"] = nightID
                    $0["previewImage"] = self.paths.thumbnailURL(for: nightID).absoluteString
                }
            }),
            ("boolean altitude", { root in
                try self.mutatingSolar(in: root, assetID: dayID) { $0["altitude"] = true }
            }),
            ("fraction altitude", { root in
                try self.mutatingSolar(in: root, assetID: dayID) { $0["altitude"] = 35.5 }
            }),
            ("third member", { root in
                var changed = root
                var assets = try XCTUnwrap(changed["assets"] as? [[String: Any]])
                let index = try XCTUnwrap(assets.firstIndex { ($0["id"] as? String) == thirdID })
                assets[index]["subcategories"] = [ManifestStore.dayNightSubcategoryID]
                assets[index]["variant"] = ["solar": ["altitude": 35, "azimuth": 180]]
                changed["assets"] = assets
                return changed
            })
        ]

        for (description, change) in malformed {
            let data = try JSONSerialization.data(withJSONObject: change(validRoot), options: [.prettyPrinted])
            try data.write(to: paths.manifest, options: .atomic)
            XCTAssertThrowsError(try store.dayNightPair(), description)
            XCTAssertEqual(try Data(contentsOf: paths.manifest), data, description)
        }

        var collisionRoot = validRoot
        var categories = try XCTUnwrap(collisionRoot["categories"] as? [[String: Any]])
        categories[0]["subcategories"] = [["id": ManifestStore.dayNightSubcategoryID]]
        collisionRoot["categories"] = categories
        let collisionData = try JSONSerialization.data(withJSONObject: collisionRoot, options: [.prettyPrinted])
        try collisionData.write(to: paths.manifest, options: .atomic)
        XCTAssertThrowsError(try store.dayNightPair())
        XCTAssertEqual(try Data(contentsOf: paths.manifest), collisionData)
    }

    func testMissingPairMemberFileBlocksImportAndRenameWithoutDissolvingGroup() throws {
        let dayID = "DAY-ASSET"
        let nightID = "NIGHT-ASSET"
        let laterID = "LATER-ASSET"
        try install(id: dayID, title: "Day")
        try install(id: nightID, title: "Night")
        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
        try store.configureDayNightPair(pair)
        try FileManager.default.removeItem(at: paths.videoURL(for: nightID))
        let pairedData = try Data(contentsOf: paths.manifest)
        let backupsBefore = try directoryNames(at: paths.backups)
        try Data("video".utf8).write(to: paths.videoURL(for: laterID))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: laterID))

        XCTAssertThrowsError(try store.addWallpaper(id: laterID, title: "Later"))
        XCTAssertThrowsError(try store.renameWallpaper(id: dayID, title: "Changed"))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), pairedData)
        XCTAssertEqual(try directoryNames(at: paths.backups), backupsBefore)
    }

    private func install(id: String, title: String) throws {
        try Data("video".utf8).write(to: paths.videoURL(for: id))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: id))
        try store.addWallpaper(id: id, title: title)
    }

    private func assertPairShape(_ pair: DayNightWallpaperPair, ordinaryIDs: Set<String>) throws {
        let root = try json(at: paths.manifest)
        let assets = try XCTUnwrap(root["assets"] as? [[String: Any]])
        let managedAssets = assets.filter {
            (($0["categories"] as? [String]) ?? []).contains(ManifestStore.categoryID)
        }
        XCTAssertEqual(Set(managedAssets.compactMap { $0["id"] as? String }), pair.memberAssetIDs.union(ordinaryIDs))
        let day = try managedAsset(id: pair.dayAssetID, in: root)
        let night = try managedAsset(id: pair.nightAssetID, in: root)
        XCTAssertEqual(day["subcategories"] as? [String], [ManifestStore.dayNightSubcategoryID])
        XCTAssertEqual(night["subcategories"] as? [String], [ManifestStore.dayNightSubcategoryID])
        XCTAssertEqual(solar(in: day)["altitude"] as? Int, 35)
        XCTAssertEqual(solar(in: day)["azimuth"] as? Int, 180)
        XCTAssertEqual(solar(in: night)["altitude"] as? Int, -35)
        XCTAssertEqual(solar(in: night)["azimuth"] as? Int, 180)
        for id in ordinaryIDs {
            let asset = try managedAsset(id: id, in: root)
            XCTAssertEqual(asset["subcategories"] as? [String], [ManifestStore.subcategoryID])
            XCTAssertNil(asset["variant"])
        }

        let group = try XCTUnwrap(groupSubcategory(in: root))
        XCTAssertEqual(Set(group.keys), [
            "id", "localizedNameKey", "localizedDescriptionKey", "preferredOrder",
            "previewImage", "representativeAssetID", "combineVariants"
        ])
        XCTAssertEqual(group["representativeAssetID"] as? String, pair.dayAssetID)
        XCTAssertEqual(group["previewImage"] as? String, paths.thumbnailURL(for: pair.dayAssetID).absoluteString)
        XCTAssertEqual(group["combineVariants"] as? Bool, true)
        XCTAssertNil(group["selectableVariantDimensions"])
        try store.validateCurrentManifest()
    }

    private func managedAsset(id: String, in root: [String: Any]) throws -> [String: Any] {
        let assets = try XCTUnwrap(root["assets"] as? [[String: Any]])
        return try XCTUnwrap(assets.first { ($0["id"] as? String) == id })
    }

    private func solar(in asset: [String: Any]) -> [String: Any] {
        ((asset["variant"] as? [String: Any])?["solar"] as? [String: Any]) ?? [:]
    }

    private func groupSubcategory(in root: [String: Any]) throws -> [String: Any]? {
        let categories = try XCTUnwrap(root["categories"] as? [[String: Any]])
        let category = categories.first { ($0["id"] as? String) == ManifestStore.categoryID }
        let subcategories = category?["subcategories"] as? [[String: Any]]
        return subcategories?.first { ($0["id"] as? String) == ManifestStore.dayNightSubcategoryID }
    }

    private func mutatingGroup(
        in root: [String: Any],
        mutation: (inout [String: Any]) -> Void
    ) throws -> [String: Any] {
        var changed = root
        var categories = try XCTUnwrap(changed["categories"] as? [[String: Any]])
        let categoryIndex = try XCTUnwrap(categories.firstIndex {
            ($0["id"] as? String) == ManifestStore.categoryID
        })
        var subcategories = try XCTUnwrap(categories[categoryIndex]["subcategories"] as? [[String: Any]])
        let groupIndex = try XCTUnwrap(subcategories.firstIndex {
            ($0["id"] as? String) == ManifestStore.dayNightSubcategoryID
        })
        mutation(&subcategories[groupIndex])
        categories[categoryIndex]["subcategories"] = subcategories
        changed["categories"] = categories
        return changed
    }

    private func mutatingSolar(
        in root: [String: Any],
        assetID: String,
        mutation: (inout [String: Any]) -> Void
    ) throws -> [String: Any] {
        var changed = root
        var assets = try XCTUnwrap(changed["assets"] as? [[String: Any]])
        let index = try XCTUnwrap(assets.firstIndex { ($0["id"] as? String) == assetID })
        var variant = try XCTUnwrap(assets[index]["variant"] as? [String: Any])
        var solar = try XCTUnwrap(variant["solar"] as? [String: Any])
        mutation(&solar)
        variant["solar"] = solar
        assets[index]["variant"] = variant
        changed["assets"] = assets
        return changed
    }

    private func fixtureData() throws -> Data {
        let fixture: [String: Any] = [
            "version": 1,
            "initialAssetCount": 1,
            "foreignRoot": ["preserved": "yes"],
            "assets": [[
                "id": "FOREIGN-ASSET",
                "categories": ["FOREIGN-CATEGORY"],
                "subcategories": ["FOREIGN-SUBCATEGORY"],
                "unknownForeignAssetData": ["preserved": true]
            ]],
            "categories": [[
                "id": "FOREIGN-CATEGORY",
                "representativeAssetID": "FOREIGN-ASSET",
                "subcategories": [[
                    "id": "FOREIGN-SUBCATEGORY",
                    "unknownForeignCategoryData": ["preserved": true]
                ]]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted])
    }

    private func json(at url: URL) throws -> [String: Any] {
        try json(data: Data(contentsOf: url))
    }

    private func json(data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func canonical(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func directoryNames(at directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }
}
