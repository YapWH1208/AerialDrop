import Foundation
import XCTest
@testable import AerialDrop

final class WallpaperSelectionStoreTests: XCTestCase {
    private var home: URL!
    private var paths: WallpaperPaths!
    private var store: WallpaperSelectionStore!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AerialDropSelectionTests-\(UUID().uuidString)", isDirectory: true)
        paths = WallpaperPaths(homeDirectory: home)
        store = WallpaperSelectionStore(paths: paths)
        try FileManager.default.createDirectory(at: paths.storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testLinkCopiesManagedDesktopChoiceToIdleAndPreservesForeignChoice() throws {
        let managedID = "29789010-D35A-4B03-8B81-0118C2EE82C3"
        let foreignID = "AB94463D-F624-4C2F-8117-8D2060CD37D0"

        let managedSettings = settings(desktopID: managedID, idleID: foreignID)
        let foreignSettings = settings(desktopID: foreignID, idleID: foreignID)
        let root: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "SystemDefault": managedSettings,
            "Displays": ["display": managedSettings],
            "Spaces": [
                "": [
                    "Default": managedSettings,
                    "Displays": ["display": managedSettings]
                ],
                "foreign-space": [
                    "Default": foreignSettings,
                    "Displays": ["display": foreignSettings]
                ]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try data.write(to: paths.storeIndex, options: .atomic)

        XCTAssertEqual(
            try store.linkSelectedManagedWallpaper(managedIDs: [managedID]),
            managedID
        )

        var format = PropertyListSerialization.PropertyListFormat.binary
        let written = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: paths.storeIndex),
                options: [],
                format: &format
            ) as? [String: Any]
        )

        let systemDefault = try XCTUnwrap(written["SystemDefault"] as? [String: Any])
        XCTAssertEqual(assetID(in: systemDefault["Desktop"]), managedID)
        XCTAssertEqual(assetID(in: systemDefault["Idle"]), managedID)

        let spaces = try XCTUnwrap(written["Spaces"] as? [String: Any])
        let foreignSpace = try XCTUnwrap(spaces["foreign-space"] as? [String: Any])
        let foreignDefault = try XCTUnwrap(foreignSpace["Default"] as? [String: Any])
        XCTAssertEqual(assetID(in: foreignDefault["Desktop"]), foreignID)
        XCTAssertEqual(assetID(in: foreignDefault["Idle"]), foreignID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.storeBackups.path))
    }

    private func settings(desktopID: String, idleID: String) -> [String: Any] {
        [
            "Type": "individual",
            "Desktop": presentation(assetID: desktopID),
            "Idle": presentation(assetID: idleID)
        ]
    }

    private func presentation(assetID: String) -> [String: Any] {
        [
            "LastSet": Date(timeIntervalSince1970: 0),
            "LastUse": Date(timeIntervalSince1970: 0),
            "Content": [
                "Choices": [[
                    "Provider": "com.apple.wallpaper.choice.aerials",
                    "Files": [],
                    "Configuration": configurationData(assetID: assetID)
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": "$null"
            ]
        ]
    }

    private func configurationData(assetID: String) -> Data {
        try! PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
    }

    private func assetID(in value: Any?) -> String? {
        guard let presentation = value as? [String: Any],
              let content = presentation["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let data = choices.first?["Configuration"] as? Data else {
            return nil
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        let configuration = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any]
        return configuration?["assetID"] as? String
    }
}
