import Foundation
import XCTest
@testable import AerialDrop

final class WallpaperSelectionStoreTests: XCTestCase {
    private let targetID = "11111111-2222-4333-8444-555555555555"
    private let alternateID = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000)

    private var home: URL!
    private var paths: WallpaperPaths!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appending(path: "AerialDropWallpaperSelectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = WallpaperPaths(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: paths.selectionStoreDirectory,
            withIntermediateDirectories: true
        )
        try indexData().write(to: paths.selectionStore, options: .atomic)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testTahoeLinkedAerialFixtureDecodesExpectedPayload() throws {
        let fixture = try fixtureRoot()
        let selection = try XCTUnwrap(fixture["AllSpacesAndDisplays"] as? [String: Any])
        let linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
        let content = try XCTUnwrap(linked["Content"] as? [String: Any])
        let choice = try XCTUnwrap((content["Choices"] as? [[String: Any]])?.first)
        let configuration = try XCTUnwrap(choice["Configuration"] as? Data)
        let decodedConfiguration = try propertyListRoot(from: configuration)
        let encodedOptions = try XCTUnwrap(content["EncodedOptionValues"] as? Data)

        XCTAssertEqual(selection["Type"] as? String, "linked")
        XCTAssertEqual(choice["Provider"] as? String, WallpaperSelectionStore.aerialProvider)
        XCTAssertEqual(decodedConfiguration["assetID"] as? String, "00000000-0000-0000-0000-000000000001")
        let options = try propertyListRoot(from: encodedOptions)
        XCTAssertTrue(propertyListValuesEqual(options, ["values": [String: Any]()]))
    }

    func testSelectionPathsStayInsideThePrivateStoreDirectory() {
        XCTAssertEqual(paths.selectionStore.lastPathComponent, "Index.plist")
        XCTAssertEqual(paths.selectionStore.deletingLastPathComponent(), paths.selectionStoreDirectory)
        XCTAssertEqual(paths.selectionBackups.deletingLastPathComponent(), paths.selectionStoreDirectory)
        XCTAssertEqual(paths.selectionStoreDirectory.lastPathComponent, "Store")
    }

    func testApplyUpdatesEveryTargetSelectionAndPreservesForeignValues() throws {
        let original = try propertyListRoot(at: paths.selectionStore)
        let originalForeign = try XCTUnwrap(original["Foreign"] as? [String: Any])
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })

        try store.apply(assetID: targetID)

        let result = try propertyListRoot(at: paths.selectionStore)
        let foreign = try XCTUnwrap(result["Foreign"] as? [String: Any])
        XCTAssertTrue(propertyListValuesEqual(foreign, originalForeign))
        XCTAssertEqual(try store.activeAerialAssetIDs(), Set([targetID]))
        XCTAssertEqual(try assetID(in: result, at: ["AllSpacesAndDisplays"]), targetID)
        XCTAssertEqual(try assetID(in: result, at: ["SystemDefault"]), targetID)
        XCTAssertEqual(try assetID(in: result, at: ["Spaces", "space-one", "Default"]), targetID)
        XCTAssertEqual(try assetID(in: result, at: ["Spaces", "space-two", "Default"]), targetID)

        let noDefaultSpace = try XCTUnwrap(
            (try XCTUnwrap(result["Spaces"] as? [String: Any]))["space-without-default"] as? [String: Any]
        )
        XCTAssertEqual(noDefaultSpace["Metadata"] as? String, "untouched")
    }

    func testActiveAerialAssetIDsIgnoreNonAerialSelections() throws {
        var root = try propertyListRoot(at: paths.selectionStore)
        var systemDefault = try XCTUnwrap(root["SystemDefault"] as? [String: Any])
        systemDefault["Type"] = "individual"
        root["SystemDefault"] = systemDefault
        try propertyListData(root).write(to: paths.selectionStore, options: .atomic)

        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        XCTAssertEqual(try store.activeAerialAssetIDs(), Set(["00000000-0000-0000-0000-000000000001"]))
    }

    func testMissingOrMalformedSelectionStoreFailsClosed() throws {
        try FileManager.default.removeItem(at: paths.selectionStore)
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })

        XCTAssertThrowsError(try store.apply(assetID: targetID)) { error in
            guard case AerialDropError.missingWallpaperSelectionStore = error else {
                return XCTFail("Expected missingWallpaperSelectionStore, got \(error)")
            }
        }

        try Data("not a plist".utf8).write(to: paths.selectionStore, options: .atomic)
        XCTAssertThrowsError(try store.apply(assetID: targetID)) { error in
            guard case AerialDropError.malformedWallpaperSelectionStore = error else {
                return XCTFail("Expected malformedWallpaperSelectionStore, got \(error)")
            }
        }
    }

    func testApplyRefusesConcurrentStoreChangesBeforeBackup() throws {
        var concurrentRoot = try propertyListRoot(at: paths.selectionStore)
        concurrentRoot["ExternalMutation"] = "new wallpaper state"
        let concurrentData = try propertyListData(concurrentRoot)
        let store = WallpaperSelectionStore(
            paths: paths,
            now: { self.fixedDate },
            beforeCompare: { try concurrentData.write(to: self.paths.selectionStore, options: .atomic) }
        )

        XCTAssertThrowsError(try store.apply(assetID: targetID)) { error in
            guard case AerialDropError.wallpaperSelectionStoreChangedDuringOperation = error else {
                return XCTFail("Expected wallpaperSelectionStoreChangedDuringOperation, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), concurrentData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
    }

    func testApplyCreatesUniqueBinaryBackups() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        let original = try Data(contentsOf: paths.selectionStore)

        try store.apply(assetID: targetID)
        let afterFirstApply = try Data(contentsOf: paths.selectionStore)
        try store.apply(assetID: alternateID)

        let backups = try FileManager.default.contentsOfDirectory(
            at: paths.selectionBackups,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.count, 2)
        XCTAssertTrue(backups.allSatisfy { $0.pathExtension == "plist" })
        XCTAssertTrue(backups.contains { backup in
            (try? Data(contentsOf: backup)).map { $0 == original } ?? false
        })
        XCTAssertTrue(backups.contains { backup in
            (try? Data(contentsOf: backup)).map { $0 == afterFirstApply } ?? false
        })

        var format = PropertyListSerialization.PropertyListFormat.xml
        _ = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: paths.selectionStore),
            options: [],
            format: &format
        )
        XCTAssertEqual(format, .binary)
    }

    func testApplyRetainsTheBackupWhenPostWriteVerificationFails() throws {
        var replacementRoot = try propertyListRoot(at: paths.selectionStore)
        var replacementSelection = try XCTUnwrap(replacementRoot["AllSpacesAndDisplays"] as? [String: Any])
        replacementSelection = try replacingAssetID(in: replacementSelection, with: alternateID)
        replacementRoot["AllSpacesAndDisplays"] = replacementSelection
        replacementRoot["SystemDefault"] = replacementSelection
        var spaces = try XCTUnwrap(replacementRoot["Spaces"] as? [String: Any])
        for key in ["space-one", "space-two"] {
            var space = try XCTUnwrap(spaces[key] as? [String: Any])
            space["Default"] = replacementSelection
            spaces[key] = space
        }
        replacementRoot["Spaces"] = spaces
        let replacementData = try propertyListData(replacementRoot)
        let store = WallpaperSelectionStore(
            paths: paths,
            now: { self.fixedDate },
            afterWrite: { try replacementData.write(to: self.paths.selectionStore, options: .atomic) }
        )

        XCTAssertThrowsError(try store.apply(assetID: targetID)) { error in
            guard case AerialDropError.wallpaperSelectionVerificationFailed = error else {
                return XCTFail("Expected wallpaperSelectionVerificationFailed, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), replacementData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: paths.selectionBackups, includingPropertiesForKeys: nil).count,
            1
        )
    }

    private func indexData() throws -> Data {
        let fixture = try fixtureRoot()
        let selection = try XCTUnwrap(fixture["AllSpacesAndDisplays"] as? [String: Any])
        let root: [String: Any] = [
            "AllSpacesAndDisplays": selection,
            "SystemDefault": selection,
            "Spaces": [
                "space-one": ["Default": selection, "DisplayName": "Primary"],
                "space-two": ["Default": selection],
                "space-without-default": ["Metadata": "untouched"]
            ],
            "Foreign": [
                "String": "preserve me",
                "Number": NSNumber(value: 42),
                "Flag": true,
                "Date": Date(timeIntervalSinceReferenceDate: 123),
                "Data": Data([0x00, 0x01, 0xFE])
            ]
        ]
        return try propertyListData(root)
    }

    private func fixtureRoot() throws -> [String: Any] {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "TahoeLinkedAerialSelection",
                withExtension: "plist",
                subdirectory: "Fixtures"
            )
        )
        return try propertyListRoot(at: fixtureURL)
    }

    private func assetID(in root: [String: Any], at path: [String]) throws -> String {
        var value: Any = root
        for key in path {
            value = try XCTUnwrap((value as? [String: Any])?[key])
        }
        let selection = try XCTUnwrap(value as? [String: Any])
        let linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
        let content = try XCTUnwrap(linked["Content"] as? [String: Any])
        let choice = try XCTUnwrap((content["Choices"] as? [[String: Any]])?.first)
        let configuration = try XCTUnwrap(choice["Configuration"] as? Data)
        return try XCTUnwrap(try propertyListRoot(from: configuration)["assetID"] as? String)
    }

    private func replacingAssetID(in selection: [String: Any], with assetID: String) throws -> [String: Any] {
        var result = selection
        var linked = try XCTUnwrap(result["Linked"] as? [String: Any])
        var content = try XCTUnwrap(linked["Content"] as? [String: Any])
        var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        var choice = try XCTUnwrap(choices.first)
        choice["Configuration"] = try propertyListData(["assetID": assetID])
        choices[0] = choice
        content["Choices"] = choices
        linked["Content"] = content
        result["Linked"] = linked
        return result
    }

    private func propertyListRoot(at url: URL) throws -> [String: Any] {
        try propertyListRoot(from: Data(contentsOf: url))
    }

    private func propertyListRoot(from data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func propertyListData(_ root: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func propertyListValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (left as [String: Any], right as [String: Any]):
            return left.count == right.count && left.allSatisfy { key, value in
                right[key].map { propertyListValuesEqual(value, $0) } ?? false
            }
        case let (left as [Any], right as [Any]):
            return left.count == right.count && zip(left, right).allSatisfy(propertyListValuesEqual)
        case let (left as Data, right as Data):
            return left == right
        case let (left as Date, right as Date):
            return left == right
        case let (left as NSString, right as NSString):
            return left == right
        case let (left as NSNumber, right as NSNumber):
            return String(cString: left.objCType) == String(cString: right.objCType) && left == right
        default:
            return false
        }
    }
}
