import Darwin
import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class SystemWallpaperServiceTests: XCTestCase {
    func testCapabilityAllowsObservedBuildAndRejectsOlderOrUnknownFormats() throws {
        let known: [String: Any] = [
            "CFBundleIdentifier": "com.apple.wallpaper.extension.aerials",
            "CFBundleVersion": "313.0.4.401"
        ]
        XCTAssertNoThrow(try DayNightWallpaperCapability.validate(osMajor: 27, bundleInfo: known))
        XCTAssertThrowsError(try DayNightWallpaperCapability.validate(osMajor: 26, bundleInfo: known))
        XCTAssertThrowsError(try DayNightWallpaperCapability.validate(osMajor: 28, bundleInfo: known))
        XCTAssertThrowsError(try DayNightWallpaperCapability.validate(osMajor: 27, bundleInfo: [:]))
        XCTAssertThrowsError(try DayNightWallpaperCapability.validate(osMajor: 27, bundleInfo: [
            "CFBundleIdentifier": "com.apple.wallpaper.extension.aerials", "CFBundleVersion": "unknown"
        ]))
        XCTAssertThrowsError(try DayNightWallpaperCapability.validate(osMajor: 27, bundleInfo: [
            "CFBundleIdentifier": "other.provider", "CFBundleVersion": "313.0.4.401"
        ]))
    }

    func testSupportPreflightAcceptsNonAerialProviderWithoutWriting() throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        try h.useNonAerialProvider()
        let before = try Data(contentsOf: h.paths.selectionStore)
        let catalogue = try Data(contentsOf: h.paths.manifest)
        try h.service().validateDayNightSupport()
        XCTAssertEqual(try Data(contentsOf: h.paths.selectionStore), before)
        XCTAssertEqual(try Data(contentsOf: h.paths.manifest), catalogue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.paths.selectionBackups.path))
        XCTAssertTrue(h.signaled.isEmpty)
    }

    func testAutomaticActivationVerifiesEveryTargetAndUsesFreshServices() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        let before = try Data(contentsOf: h.paths.selectionStore)
        let service = h.service()
        try await service.activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
        XCTAssertEqual(h.signaled.map(\.role), [.aerials, .agent])
        XCTAssertTrue(try service.inspectAerialSelections().matches(.automatic(groupID: ManifestStore.dayNightSubcategoryID)))
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: h.paths.selectionBackups,
            includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), before)
        XCTAssertEqual(try h.manifest.dayNightPair(), h.pair)
    }

    func testFixedAndFreshSingleSelectionsRetainDistinctNativeOptions() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        let service = h.service()
        try await service.activateAerial(.fixedVariant(assetID: h.dayID), verifyingPair: h.pair)
        XCTAssertTrue(try service.inspectAerialSelections().matches(.fixedVariant(assetID: h.dayID)))
        h.resetProcesses()
        try await service.activateAerial(.single(assetID: h.thirdID), verifyingPair: nil)
        XCTAssertTrue(try service.inspectAerialSelections().matches(.single(assetID: h.thirdID)))
    }

    func testUnsupportedCapabilityOrIncorrectRolesRefuseBeforeSelectionWrites() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        let before = try Data(contentsOf: h.paths.selectionStore)
        let unsupported = h.service(capability: { throw AerialDropError.dayNightUnavailable("unsupported") })
        do {
            try await unsupported.activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
            XCTFail("Expected unsupported capability")
        } catch { XCTAssertTrue(error.localizedDescription.contains("unsupported")) }
        let reversed = DayNightWallpaperPair(dayAssetID: h.nightID, nightAssetID: h.dayID)
        do {
            try await h.service().activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: reversed)
            XCTFail("Expected exact role refusal")
        } catch { XCTAssertTrue(error.localizedDescription.contains("videos changed")) }
        XCTAssertEqual(try Data(contentsOf: h.paths.selectionStore), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.paths.selectionBackups.path))
        XCTAssertTrue(h.signaled.isEmpty)
    }

    func testMissingPairedPreviewRefusesBeforeSelectionWrite() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        try FileManager.default.removeItem(at: h.paths.thumbnailURL(for: h.nightID))
        let before = try Data(contentsOf: h.paths.selectionStore)
        do {
            try await h.service().activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
            XCTFail("Expected missing preview refusal")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: h.paths.selectionStore), before)
        XCTAssertTrue(h.signaled.isEmpty)
    }

    func testStrictSingleRejectsPairedMemberBeforeSelectionBackup() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        let before = try Data(contentsOf: h.paths.selectionStore)
        do {
            try await h.service().activateAerial(.single(assetID: h.dayID), verifyingPair: nil)
            XCTFail("Expected paired member to require fixed variant")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Day or Night variant")) }
        XCTAssertEqual(try Data(contentsOf: h.paths.selectionStore), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.paths.selectionBackups.path))
        XCTAssertTrue(h.signaled.isEmpty)
    }

    func testStrictSingleRejectsMalformedCatalogueFileReference() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: h.paths.manifest)) as? [String: Any])
        var assets = try XCTUnwrap(root["assets"] as? [[String: Any]])
        let index = try XCTUnwrap(assets.firstIndex { $0["id"] as? String == h.thirdID })
        assets[index]["url-4K-SDR-240FPS"] = "file:///unrelated.mov"
        root["assets"] = assets
        try JSONSerialization.data(withJSONObject: root).write(to: h.paths.manifest)
        let before = try Data(contentsOf: h.paths.selectionStore)
        do {
            try await h.service().activateAerial(.single(assetID: h.thirdID), verifyingPair: nil)
            XCTFail("Expected malformed media reference")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: h.paths.selectionStore), before)
        XCTAssertTrue(h.signaled.isEmpty)
    }

    func testLookupCommandHasBoundedTimeoutForItsOwnChild() throws {
        let start = ContinuousClock.now
        XCTAssertThrowsError(try BoundedWallpaperCommand.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: .milliseconds(20)
        ))
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    func testLookupCommandCollectsOutputAndExitStatus() throws {
        let result = try BoundedWallpaperCommand.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["pid = 123\\n"]
        )
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "pid = 123\n")
        XCTAssertEqual(result.status, 0)
    }

    func testRefreshFailureRetainsSelectionBackupAndNeverClaimsSuccess() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        h.restartEnabled = false
        do {
            try await h.service().activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
            XCTFail("Expected refresh failure")
        } catch {
            guard case AerialDropError.nativeWallpaperRefreshFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(try WallpaperSelectionStore(paths: h.paths).inspectAerialSelections()
            .matches(.automatic(groupID: ManifestStore.dayNightSubcategoryID)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.paths.selectionBackups.path).count, 1)
        XCTAssertEqual(try h.manifest.dayNightPair(), h.pair)
    }

    func testChangedCatalogueRolesDuringReloadFailFinalVerification() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        h.onSettle = {
            h.onSettle = nil
            try h.manifest.configureDayNightPair(
                .init(dayAssetID: h.thirdID, nightAssetID: h.nightID), protectingPreviousPairMembers: { _ in }
            )
        }
        do {
            try await h.service().activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
            XCTFail("Expected changed roles")
        } catch { XCTAssertTrue(error.localizedDescription.contains("videos changed")) }
        XCTAssertEqual(try h.manifest.dayNightPair()?.dayAssetID, h.thirdID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: h.paths.selectionBackups.path).count, 1)
    }

    func testSelectionChangingAfterFirstVerificationIsNotOverwritten() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        h.onSettle = {
            guard h.settles == 2 else { return }
            try WallpaperSelectionStore(paths: h.paths).apply(.fixedVariant(assetID: h.nightID))
        }
        do {
            try await h.service().activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
            XCTFail("Expected selection change")
        } catch {
            guard case AerialDropError.wallpaperSelectionVerificationFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(try WallpaperSelectionStore(paths: h.paths).inspectAerialSelections().matches(.fixedVariant(assetID: h.nightID)))
    }

    func testReentrantActivationIsRejectedAndRefreshCannotInterleave() async throws {
        let h = try ServiceHarness()
        defer { h.cleanup() }
        let service = h.service()
        var checked = false
        h.asyncOnSettle = {
            guard !checked else { return }
            checked = true
            do {
                try await service.activateAerial(assetID: h.thirdID)
                XCTFail("Expected concurrent activation refusal")
            } catch {
                guard case AerialDropError.wallpaperActivationInProgress = error else { return XCTFail("\(error)") }
            }
            await service.refresh()
        }
        try await service.activateAerial(.automatic(groupID: ManifestStore.dayNightSubcategoryID), verifyingPair: h.pair)
        XCTAssertTrue(checked)
        XCTAssertEqual(h.signaled.count, 2)
    }
}

@MainActor
private final class ServiceHarness {
    let dayID = "11111111-2222-4333-8444-555555555555"
    let nightID = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    let thirdID = "99999999-2222-4333-8444-555555555555"
    let home: URL
    let paths: WallpaperPaths
    let manifest: ManifestStore
    var pair: DayNightWallpaperPair { .init(dayAssetID: dayID, nightAssetID: nightID) }
    var actors: Set<NativeWallpaperProcess> = []
    var signaled: [NativeWallpaperProcess] = []
    var restartEnabled = true
    var settles = 0
    var onSettle: (() throws -> Void)?
    var asyncOnSettle: (() async throws -> Void)?

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "AerialDropServiceTests-\(UUID().uuidString)")
        paths = WallpaperPaths(homeDirectory: home)
        manifest = ManifestStore(paths: paths)
        try manifest.prepareDirectories()
        try FileManager.default.createDirectory(at: paths.selectionStoreDirectory, withIntermediateDirectories: true)
        let root: [String: Any] = ["version": 1, "initialAssetCount": 0, "assets": [[String: Any]](), "categories": [[String: Any]]()]
        try JSONSerialization.data(withJSONObject: root).write(to: paths.manifest)
        for id in [dayID, nightID, thirdID] {
            try Data("video".utf8).write(to: paths.videoURL(for: id))
            try Data("preview".utf8).write(to: paths.thumbnailURL(for: id))
            try manifest.addWallpaper(id: id, title: id)
        }
        try manifest.configureDayNightPair(pair)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "TahoeLinkedAerialSelection", withExtension: "plist", subdirectory: "Fixtures"))
        let fixtureRoot = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: fixture), format: nil) as? [String: Any])
        let selection = try XCTUnwrap(fixtureRoot["AllSpacesAndDisplays"])
        let index: [String: Any] = ["AllSpacesAndDisplays": selection, "SystemDefault": selection,
            "Spaces": ["space-one": ["Default": selection]], "Foreign": "kept"]
        try PropertyListSerialization.data(fromPropertyList: index, format: .binary, options: 0).write(to: paths.selectionStore)
        resetProcesses()
    }

    func cleanup() { try? FileManager.default.removeItem(at: home) }

    func process(_ role: NativeWallpaperProcess.Role, pid: Int32) -> NativeWallpaperProcess {
        .init(role: role, pid: pid, uid: getuid(), startSeconds: UInt64(pid), startMicroseconds: 0, executablePath: role.executablePath)
    }

    func resetProcesses() { actors = [process(.agent, pid: 101), process(.aerials, pid: 102)] }

    func service(capability: @escaping () throws -> Void = {}) -> SystemWallpaperService {
        let controller = WallpaperProcessController(
            inventory: { self.actors },
            launchdAgentPID: { self.actors.first { $0.role == .agent }?.pid ?? 0 },
            signal: { actor in
                self.signaled.append(actor)
                if self.restartEnabled {
                    self.actors.remove(actor)
                    if actor.role == .agent { self.actors.insert(self.process(.agent, pid: 201)) }
                }
            },
            settle: {
                self.settles += 1
                try self.onSettle?()
                try await self.asyncOnSettle?()
            }, maximumPolls: 2
        )
        return SystemWallpaperService(selectionStore: WallpaperSelectionStore(paths: paths), manifestStore: manifest,
            processController: controller, validateCapability: capability)
    }

    func useNonAerialProvider() throws {
        var index = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: paths.selectionStore), format: nil) as? [String: Any])
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            var selection = try XCTUnwrap(index[key] as? [String: Any])
            var linked = try XCTUnwrap(selection["Linked"] as? [String: Any])
            var content = try XCTUnwrap(linked["Content"] as? [String: Any])
            var choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
            choices[0]["Provider"] = "com.apple.wallpaper.choice.other"
            content["Choices"] = choices; linked["Content"] = content; selection["Linked"] = linked
            index[key] = selection
        }
        try PropertyListSerialization.data(fromPropertyList: index, format: .binary, options: 0).write(to: paths.selectionStore)
    }
}
