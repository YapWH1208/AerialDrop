import Foundation
import XCTest
@testable import AerialDrop

final class ManifestCatalogueRepairTests: XCTestCase {
    private var home: URL!
    private var paths: WallpaperPaths!
    private var bundled: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialDropRepair-\(UUID().uuidString)")
        paths = WallpaperPaths(homeDirectory: home)
        bundled = home.appendingPathComponent("bundled.json")
        try FileManager.default.createDirectory(at: paths.manifestDirectory, withIntermediateDirectories: true)
        try fixture(version: 1).write(to: paths.manifest)
        try fixture(version: 2).write(to: bundled)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeStore(
        beforeWrite: (() throws -> Void)? = nil,
        afterWrite: (() throws -> Void)? = nil,
        writer: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) -> ManifestStore {
        let source = bundled!
        return ManifestStore(paths: paths, bundledManifestReader: { try Data(contentsOf: source) },
                             beforeCompatibilityWrite: beforeWrite, afterCompatibilityWrite: afterWrite,
                             compatibilityWriter: writer)
    }

    func testPromotionBacksUpExactBytesAndPreservesAllOtherContent() throws {
        let original = try Data(contentsOf: paths.manifest)
        let store = makeStore()
        XCTAssertEqual(try store.assessCatalogueCompatibility(), .promotion(version: 2))
        XCTAssertTrue(try store.repairCatalogueCompatibility())
        let changed = try Data(contentsOf: paths.manifest)
        var oldRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let newRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: changed) as? [String: Any])
        oldRoot["version"] = 2
        XCTAssertEqual(try canonical(oldRoot), try canonical(newRoot))
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        XCTAssertEqual(try store.assessCatalogueCompatibility(), .current)
        XCTAssertFalse(try store.repairCatalogueCompatibility())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.backups.path).count, 1)
    }

    func testEqualOrNewerVersionsAreNoOpWithoutCreatingBackup() throws {
        for version in [2, 3] {
            let data = try fixture(version: version)
            try data.write(to: paths.manifest)
            XCTAssertFalse(try makeStore().repairCatalogueCompatibility())
            XCTAssertEqual(try Data(contentsOf: paths.manifest), data)
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.backups.path))
        }
    }

    func testConflictAndInvalidOrUnavailableBundledDataNeverWrite() throws {
        let original = try Data(contentsOf: paths.manifest)
        for invalid in [try fixture(version: 2, url: "other"), Data("bad json".utf8), Data("{}".utf8)] {
            try invalid.write(to: bundled)
            XCTAssertThrowsError(try makeStore().repairCatalogueCompatibility())
            XCTAssertEqual(try Data(contentsOf: paths.manifest), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.backups.path))
        }
        try FileManager.default.removeItem(at: bundled)
        XCTAssertThrowsError(try makeStore().repairCatalogueCompatibility())
        XCTAssertEqual(try Data(contentsOf: paths.manifest), original)
    }

    func testDownloadedCatalogueRaceAfterBackupDoesNotOverwriteConcurrentData() throws {
        let original = try Data(contentsOf: paths.manifest)
        let concurrent = try fixture(version: 3)
        let path = paths.manifest
        let store = makeStore(beforeWrite: { try concurrent.write(to: path, options: .atomic) })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility())
        XCTAssertEqual(try Data(contentsOf: paths.manifest), concurrent)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testBundledCatalogueRaceAfterBackupDoesNotModifyDownloadedCatalogue() throws {
        let original = try Data(contentsOf: paths.manifest)
        let source = bundled!
        let changed = try fixture(version: 3)
        let store = makeStore(beforeWrite: { try changed.write(to: source, options: .atomic) })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility())
        XCTAssertEqual(try Data(contentsOf: paths.manifest), original)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testPostWriteConcurrentChangeIsReportedAndNeverOverwritten() throws {
        let original = try Data(contentsOf: paths.manifest)
        let concurrent = try fixture(version: 3)
        let path = paths.manifest
        let store = makeStore(afterWrite: { try concurrent.write(to: path, options: .atomic) })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility()) {
            guard case ManifestCompatibilityRepairError.superseded = $0 else { return XCTFail("Expected superseded outcome, got \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: path), concurrent)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testUnreadablePostWriteOutcomeKeepsBackupWithoutRollback() throws {
        let original = try Data(contentsOf: paths.manifest)
        let path = paths.manifest
        let store = makeStore(afterWrite: { try FileManager.default.removeItem(at: path) })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility()) {
            guard case ManifestCompatibilityRepairError.outcomeUnknown = $0 else { return XCTFail("Expected unknown outcome, got \($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testWriterErrorAfterReplacementReportsCommittedAndKeepsBackup() throws {
        let original = try Data(contentsOf: paths.manifest)
        let store = makeStore(writer: { data, url in
            try data.write(to: url, options: .atomic)
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility()) {
            guard case ManifestCompatibilityRepairError.committed = $0 else { return XCTFail("Expected committed outcome, got \($0)") }
        }
        let current = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: paths.manifest)) as? [String: Any])
        XCTAssertEqual(current["version"] as? Int, 2)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testWriterErrorBeforeReplacementKeepsOriginalAndBackup() throws {
        let original = try Data(contentsOf: paths.manifest)
        let store = makeStore(writer: { _, _ in throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try store.repairCatalogueCompatibility()) {
            guard case ManifestCompatibilityRepairError.outcomeUnknown = $0 else { return XCTFail("Expected unknown outcome, got \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), original)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func fixture(version: Int, url: String = "apple") throws -> Data {
        var root: [String: Any] = [
            "version": version, "initialAssetCount": 1, "localizationVersion": 1,
            "assets": [["id": "apple", "categories": ["category"], "subcategories": ["subcategory"], "url": url]],
            "categories": [["id": "category", "representativeAssetID": "apple",
                            "subcategories": [["id": "subcategory", "representativeAssetID": "apple"]]]]
        ]
        if version == 1 { root["unknownDownloadedField"] = ["kept": true] }
        return try canonical(root)
    }
}
