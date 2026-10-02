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

        let requiredSpaceIDs = try store.apply(assetID: targetID)
        XCTAssertEqual(requiredSpaceIDs, Set(["space-one", "space-two"]))
        try store.verifyAerialSelection(assetID: targetID, requiringSpaceIDs: requiredSpaceIDs)

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

    func testActiveAerialAssetIDsReturnEveryChoiceInAShuffleSelection() throws {
        let fixture = try fixtureRoot()
        var selection = try XCTUnwrap(fixture["AllSpacesAndDisplays"] as? [String: Any])
        var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
        var content = try XCTUnwrap(linked["Content"] as? [String: Any])
        var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        var secondChoice = try XCTUnwrap(choices.first)
        secondChoice["Configuration"] = try propertyListData(["assetID": targetID])
        choices.append(secondChoice)
        content["Choices"] = choices
        linked["Content"] = content
        selection["Linked"] = linked

        var root = try propertyListRoot(at: paths.selectionStore)
        root["AllSpacesAndDisplays"] = selection
        try propertyListData(root).write(to: paths.selectionStore, options: .atomic)

        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        XCTAssertEqual(
            try store.activeAerialAssetIDs(),
            Set(["00000000-0000-0000-0000-000000000001", targetID])
        )
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

    func testApplyRejectsOneTargetRevertingToANonAerialSelection() throws {
        for path in [["AllSpacesAndDisplays"], ["SystemDefault"], ["Spaces", "space-one", "Default"]] {
            for individualSelection in [true, false] {
                let original = try indexData()
                try original.write(to: paths.selectionStore, options: .atomic)
                var externalData: Data?
                let store = WallpaperSelectionStore(
                    paths: paths,
                    now: { self.fixedDate },
                    afterWrite: {
                        let writtenRoot = try self.propertyListRoot(at: self.paths.selectionStore)
                        let externalRoot = try self.mutatingDictionary(in: writtenRoot, at: path) { selection in
                            if individualSelection {
                                selection["Type"] = "individual"
                            } else {
                                var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
                                var content = try XCTUnwrap(linked["Content"] as? [String: Any])
                                var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
                                choices[0]["Provider"] = "com.apple.wallpaper.choice.image"
                                content["Choices"] = choices
                                linked["Content"] = content
                                selection["Linked"] = linked
                            }
                        }
                        let data = try self.propertyListData(externalRoot)
                        try data.write(to: self.paths.selectionStore, options: .atomic)
                        externalData = data
                    }
                )

                XCTAssertThrowsError(try store.apply(assetID: targetID), "\(path), individual: \(individualSelection)") { error in
                    guard case AerialDropError.wallpaperSelectionVerificationFailed = error else {
                        return XCTFail("Expected wallpaperSelectionVerificationFailed, got \(error)")
                    }
                }

                XCTAssertEqual(try Data(contentsOf: paths.selectionStore), try XCTUnwrap(externalData))
                // The union still looks correct: this is why activation needs per-target verification.
                XCTAssertEqual(try store.activeAerialAssetIDs(), Set([targetID]))
                let backups = try FileManager.default.contentsOfDirectory(
                    at: paths.selectionBackups, includingPropertiesForKeys: nil
                )
                XCTAssertTrue(backups.contains { (try? Data(contentsOf: $0)) == original })
            }
        }
    }

    func testVerifierRejectsEmptyMixedDuplicateAndShuffleChoices() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        try store.apply(assetID: targetID)
        let appliedRoot = try propertyListRoot(at: paths.selectionStore)
        let backupNames = Set(try FileManager.default.contentsOfDirectory(atPath: paths.selectionBackups.path))
        for mutation in ["empty", "mixed", "duplicate", "shuffle", "files"] {
            let changedRoot = try mutatingDictionary(in: appliedRoot, at: ["SystemDefault"]) { selection in
                var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
                var content = try XCTUnwrap(linked["Content"] as? [String: Any])
                var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
                switch mutation {
                case "empty":
                    choices = []
                case "mixed":
                    var imageChoice = choices[0]
                    imageChoice["Provider"] = "com.apple.wallpaper.choice.image"
                    choices.append(imageChoice)
                case "duplicate":
                    choices.append(choices[0])
                case "shuffle":
                    content["Shuffle"] = "enabled"
                default:
                    choices[0]["Files"] = ["file:///external-image.jpg"]
                }
                content["Choices"] = choices
                linked["Content"] = content
                selection["Linked"] = linked
            }
            let changedData = try propertyListData(changedRoot)
            try changedData.write(to: paths.selectionStore, options: .atomic)

            XCTAssertThrowsError(try store.verifyAerialSelection(assetID: targetID), mutation)
            XCTAssertEqual(try Data(contentsOf: paths.selectionStore), changedData)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: paths.selectionBackups.path)), backupNames)
            XCTAssertEqual(try store.activeAerialAssetIDs(), Set([targetID]))
        }
    }

    func testVerifierRejectsDisappearedOriginalSpaceTargets() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        let requiredSpaceIDs = try store.apply(assetID: targetID)
        let appliedRoot = try propertyListRoot(at: paths.selectionStore)
        for removeWholeSpace in [false, true] {
            var changedRoot = appliedRoot
            var spaces = try XCTUnwrap(changedRoot["Spaces"] as? [String: Any])
            if removeWholeSpace {
                spaces.removeValue(forKey: "space-one")
            } else {
                var space = try XCTUnwrap(spaces["space-one"] as? [String: Any])
                space.removeValue(forKey: "Default")
                spaces["space-one"] = space
            }
            changedRoot["Spaces"] = spaces
            let changedData = try propertyListData(changedRoot)
            try changedData.write(to: paths.selectionStore, options: .atomic)

            // Current selections alone remain valid, but the activation's original targets do not.
            try store.verifyAerialSelection(assetID: targetID)
            XCTAssertThrowsError(try store.verifyAerialSelection(assetID: targetID, requiringSpaceIDs: requiredSpaceIDs)) { error in
                guard case AerialDropError.wallpaperSelectionVerificationFailed = error else {
                    return XCTFail("Expected wallpaperSelectionVerificationFailed, got \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: paths.selectionStore), changedData)
        }
    }

    func testVerifierRejectsMissingRequiredGlobalSelections() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        try store.apply(assetID: targetID)
        let appliedRoot = try propertyListRoot(at: paths.selectionStore)
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Spaces"] {
            var changedRoot = appliedRoot
            changedRoot.removeValue(forKey: key)
            let changedData = try propertyListData(changedRoot)
            try changedData.write(to: paths.selectionStore, options: .atomic)
            XCTAssertThrowsError(try store.verifyAerialSelection(assetID: targetID), key)
            XCTAssertEqual(try Data(contentsOf: paths.selectionStore), changedData)
        }
    }

    func testAutomaticWriterMatchesObservedNativeOptionsAndEveryTarget() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "MacOS27SolarAutomaticSelection", withExtension: "plist", subdirectory: "Fixtures"
        ))
        let fixture = try propertyListRoot(at: fixtureURL)
        let linked = try XCTUnwrap(fixture["Linked"] as? [String: Any])
        let content = try XCTUnwrap(linked["Content"] as? [String: Any])
        let choice = try XCTUnwrap((content["Choices"] as? [[String: Any]])?.first)
        let fixtureConfiguration = try propertyListRoot(from: XCTUnwrap(choice["Configuration"] as? Data))
        let groupID = try XCTUnwrap(fixtureConfiguration["assetID"] as? String)
        let request = AerialSelectionRequest.automatic(groupID: groupID)
        let original = try propertyListRoot(at: paths.selectionStore)
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })

        let required = try store.apply(request)
        try store.verifySelection(request, requiringSpaceIDs: required)
        let inspection = try store.inspectAerialSelections()
        XCTAssertTrue(inspection.matches(request))
        XCTAssertEqual(inspection.rawAssetIDs, [groupID])
        XCTAssertEqual(inspection.targets.map(\.target), [
            .allSpacesAndDisplays, .systemDefault, .space("space-one"), .space("space-two")
        ])
        let written = try propertyListRoot(at: paths.selectionStore)
        try validateSelectionPayload(in: written, at: ["AllSpacesAndDisplays"], equals: fixture)
        XCTAssertTrue(propertyListValuesEqual(try XCTUnwrap(original["Foreign"]), try XCTUnwrap(written["Foreign"])))
    }

    func testFixedVariantAndLegacySingleHaveDistinctExactOptions() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        for request in [AerialSelectionRequest.fixedVariant(assetID: targetID), .single(assetID: targetID)] {
            try store.apply(request)
            XCTAssertTrue(try store.inspectAerialSelections().matches(request))
            try store.verifySelection(request)
            let root = try propertyListRoot(at: paths.selectionStore)
            let selection = try XCTUnwrap(root["AllSpacesAndDisplays"] as? [String: Any])
            let content = try XCTUnwrap((selection["Linked"] as? [String: Any])?["Content"] as? [String: Any])
            let options = try propertyListRoot(from: XCTUnwrap(content["EncodedOptionValues"] as? Data))
            let expected: [String: Any] = request == .single(assetID: targetID)
                ? ["values": [String: Any]()]
                : ["values": ["aerialVariant": ["picker": ["_0": ["id": targetID]]]]]
            XCTAssertTrue(propertyListValuesEqual(options, expected))
        }
        try store.apply(.fixedVariant(assetID: targetID))
        XCTAssertThrowsError(try store.verifyAerialSelection(assetID: targetID))
        try store.apply(assetID: targetID)
        try store.verifyAerialSelection(assetID: targetID)
    }

    func testOptionMismatchOnAnyTargetFailsWhileRawIDsRemainVisible() throws {
        let store = WallpaperSelectionStore(paths: paths, now: { self.fixedDate })
        let request = AerialSelectionRequest.automatic(groupID: targetID)
        try store.apply(request)
        let applied = try propertyListRoot(at: paths.selectionStore)
        let backups = Set(try FileManager.default.contentsOfDirectory(atPath: paths.selectionBackups.path))
        let optionMutations: [(String, Any?)] = [
            ("missing", nil),
            ("wrong-type", "automatic"),
            ("invalid-plist", Data("invalid".utf8)),
            ("empty-values", try propertyListData(["values": [String: Any]()])),
            ("fixed-member", try propertyListData(["values": ["aerialVariant": ["picker": ["_0": ["id": targetID]]]]])),
            ("wrong-picker", try propertyListData(["values": ["aerialVariant": ["picker": ["_0": ["id": alternateID]]]]])),
            ("extra-value", try propertyListData(["values": ["aerialVariant": ["picker": ["_0": ["id": "automatic"]]], "foreign": true]])),
            ("extra-root", try propertyListData(["values": ["aerialVariant": ["picker": ["_0": ["id": "automatic"]]]], "foreign": true]))
        ]
        for path in [["AllSpacesAndDisplays"], ["SystemDefault"], ["Spaces", "space-one", "Default"], ["Spaces", "space-two", "Default"]] {
            for (name, value) in optionMutations {
                let changed = try mutatingDictionary(in: applied, at: path) { selection in
                    var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
                    var content = try XCTUnwrap(linked["Content"] as? [String: Any])
                    content["EncodedOptionValues"] = value
                    linked["Content"] = content
                    selection["Linked"] = linked
                }
                let data = try propertyListData(changed)
                try data.write(to: paths.selectionStore, options: .atomic)
                let inspection = try store.inspectAerialSelections()
                XCTAssertEqual(inspection.rawAssetIDs, [targetID], name)
                XCTAssertFalse(inspection.matches(request), name)
                XCTAssertThrowsError(try store.verifySelection(request), name)
                XCTAssertEqual(try Data(contentsOf: paths.selectionStore), data)
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: paths.selectionBackups.path)), backups)
            }
        }
    }

    func testInspectionRetainsMultipleReferencesWithUnsupportedOptionsAndConfiguration() throws {
        var root = try propertyListRoot(at: paths.selectionStore)
        root = try mutatingDictionary(in: root, at: ["SystemDefault"]) { selection in
            var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
            var content = try XCTUnwrap(linked["Content"] as? [String: Any])
            var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
            choices[0]["Configuration"] = try propertyListData(["assetID": targetID, "future-key": true])
            var second = choices[0]
            second["Configuration"] = try propertyListData(["assetID": alternateID])
            choices.append(second)
            content["Choices"] = choices
            content["EncodedOptionValues"] = Data("unsupported".utf8)
            linked["Content"] = content
            selection["Linked"] = linked
        }
        try propertyListData(root).write(to: paths.selectionStore, options: .atomic)
        let store = WallpaperSelectionStore(paths: paths)
        let inspection = try store.inspectAerialSelections()
        let target = try XCTUnwrap(inspection.targets.first { $0.target == .systemDefault })
        XCTAssertEqual(target.rawAssetIDs, [targetID, alternateID])
        XCTAssertNil(target.recognizedSelection)
        XCTAssertEqual(inspection.rawAssetIDs, [targetID, alternateID, "00000000-0000-0000-0000-000000000001"])
    }

    func testCanonicalRecognitionRejectsExtraConfigurationFieldsWithoutLosingReference() throws {
        let store = WallpaperSelectionStore(paths: paths)
        let request = AerialSelectionRequest.automatic(groupID: targetID)
        try store.apply(request)
        let applied = try propertyListRoot(at: paths.selectionStore)
        let changed = try mutatingDictionary(in: applied, at: ["SystemDefault"]) { selection in
            var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
            var content = try XCTUnwrap(linked["Content"] as? [String: Any])
            var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
            choices[0]["Configuration"] = try propertyListData(["assetID": targetID, "future-key": true])
            content["Choices"] = choices
            linked["Content"] = content
            selection["Linked"] = linked
        }
        try propertyListData(changed).write(to: paths.selectionStore, options: .atomic)
        let target = try XCTUnwrap(store.inspectAerialSelections().targets.first { $0.target == .systemDefault })
        XCTAssertEqual(target.rawAssetIDs, [targetID])
        XCTAssertNil(target.recognizedSelection)
        XCTAssertThrowsError(try store.verifySelection(request))
    }

    func testAutomaticApplyKeepsBackupsAndRefusesConcurrentSelectionChanges() throws {
        let request = AerialSelectionRequest.automatic(groupID: targetID)
        let original = try Data(contentsOf: paths.selectionStore)
        var concurrentRoot = try propertyListRoot(from: original)
        concurrentRoot["ForeignMutation"] = true
        let concurrent = try propertyListData(concurrentRoot)
        let racingStore = WallpaperSelectionStore(paths: paths, beforeCompare: {
            try concurrent.write(to: self.paths.selectionStore, options: .atomic)
        })
        XCTAssertThrowsError(try racingStore.apply(request))
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), concurrent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))

        try original.write(to: paths.selectionStore, options: .atomic)
        let postWriteStore = WallpaperSelectionStore(paths: paths, afterWrite: {
            try concurrent.write(to: self.paths.selectionStore, options: .atomic)
        })
        XCTAssertThrowsError(try postWriteStore.apply(request))
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), concurrent)
        let backups = try FileManager.default.contentsOfDirectory(at: paths.selectionBackups, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testTypedWriterRejectsInvalidIdentityBeforeBackupOrWrite() throws {
        let store = WallpaperSelectionStore(paths: paths)
        let original = try Data(contentsOf: paths.selectionStore)
        for request in [AerialSelectionRequest.automatic(groupID: "invalid"), .fixedVariant(assetID: "invalid")] {
            XCTAssertThrowsError(try store.apply(request))
        }
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
    }

    func testApplyPreflightDoesNotWriteBackupOrInvokeMutationHooks() throws {
        let original = try Data(contentsOf: paths.selectionStore)
        var hookCalls = 0
        let store = WallpaperSelectionStore(paths: paths, beforeCompare: {
            hookCalls += 1
        }, afterWrite: {
            hookCalls += 1
        })
        for request in [AerialSelectionRequest.single(assetID: targetID), .fixedVariant(assetID: targetID), .automatic(groupID: targetID)] {
            try store.validateForApplying(request)
        }
        XCTAssertEqual(hookCalls, 0)
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
    }

    func testApplyPreflightRejectsInvalidIdentityAndTargetTopologyWithoutWriting() throws {
        let original = try propertyListRoot(at: paths.selectionStore)
        let store = WallpaperSelectionStore(paths: paths)
        var candidates: [[String: Any]] = []
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Spaces"] {
            var candidate = original
            candidate.removeValue(forKey: key)
            candidates.append(candidate)
        }
        var malformedSpace = original
        malformedSpace["Spaces"] = ["bad-space": "invalid"]
        candidates.append(malformedSpace)
        var malformedDefault = original
        malformedDefault["Spaces"] = ["bad-space": ["Default": "invalid"]]
        candidates.append(malformedDefault)
        for candidate in candidates {
            let data = try propertyListData(candidate)
            try data.write(to: paths.selectionStore, options: .atomic)
            XCTAssertThrowsError(try store.validateForApplying(.automatic(groupID: targetID)))
            XCTAssertEqual(try Data(contentsOf: paths.selectionStore), data)
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
        }
        let originalData = try propertyListData(original)
        try originalData.write(to: paths.selectionStore, options: .atomic)
        XCTAssertThrowsError(try store.validateForApplying(.automatic(groupID: "invalid")))
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
    }

    func testApplyPreflightAllowsCurrentNonAerialTargets() throws {
        var root = try propertyListRoot(at: paths.selectionStore)
        for path in [["AllSpacesAndDisplays"], ["SystemDefault"], ["Spaces", "space-one", "Default"], ["Spaces", "space-two", "Default"]] {
            root = try mutatingDictionary(in: root, at: path) { selection in
                selection["Type"] = "individual"
                selection.removeValue(forKey: "Linked")
                selection["Individual"] = ["Provider": "com.apple.wallpaper.choice.image"]
            }
        }
        let data = try propertyListData(root)
        try data.write(to: paths.selectionStore, options: .atomic)
        let store = WallpaperSelectionStore(paths: paths)
        try store.validateForApplying(.automatic(groupID: targetID))
        XCTAssertEqual(try Data(contentsOf: paths.selectionStore), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.selectionBackups.path))
    }

    private func validateSelectionPayload(
        in root: [String: Any], at path: [String], equals expected: [String: Any]
    ) throws {
        var value: Any = root
        for key in path { value = try XCTUnwrap((value as? [String: Any])?[key]) }
        let selection = try XCTUnwrap(value as? [String: Any])
        let content = try XCTUnwrap((selection["Linked"] as? [String: Any])?["Content"] as? [String: Any])
        let expectedContent = try XCTUnwrap((expected["Linked"] as? [String: Any])?["Content"] as? [String: Any])
        XCTAssertEqual(selection["Type"] as? String, expected["Type"] as? String)
        XCTAssertEqual(content["Shuffle"] as? String, expectedContent["Shuffle"] as? String)
        XCTAssertTrue(propertyListValuesEqual(
            try propertyListRoot(from: XCTUnwrap(content["EncodedOptionValues"] as? Data)),
            try propertyListRoot(from: XCTUnwrap(expectedContent["EncodedOptionValues"] as? Data))
        ))
        let choice = try XCTUnwrap((content["Choices"] as? [[String: Any]])?.first)
        let expectedChoice = try XCTUnwrap((expectedContent["Choices"] as? [[String: Any]])?.first)
        XCTAssertEqual(choice["Provider"] as? String, expectedChoice["Provider"] as? String)
        XCTAssertTrue(propertyListValuesEqual(try XCTUnwrap(choice["Files"]), try XCTUnwrap(expectedChoice["Files"])))
        XCTAssertTrue(propertyListValuesEqual(
            try propertyListRoot(from: XCTUnwrap(choice["Configuration"] as? Data)),
            try propertyListRoot(from: XCTUnwrap(expectedChoice["Configuration"] as? Data))
        ))
    }

    private func mutatingDictionary(
        in root: [String: Any],
        at path: [String],
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> [String: Any] {
        var result = root
        guard let key = path.first else {
            try mutation(&result)
            return result
        }
        let child = try XCTUnwrap(result[key] as? [String: Any])
        result[key] = try mutatingDictionary(in: child, at: Array(path.dropFirst()), mutation: mutation)
        return result
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
