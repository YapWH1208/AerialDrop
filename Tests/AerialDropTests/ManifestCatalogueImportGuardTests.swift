import Foundation
import XCTest
@testable import AerialDrop

final class ManifestCatalogueImportGuardTests: XCTestCase {
    func testImportRejectsBundledChangeDuringCommitWithoutLosingConcurrentState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialImportGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = WallpaperPaths(homeDirectory: home)
        let original = try fixture(version: 2)
        let changed = try fixture(version: 3)
        var reads = 0
        let store = ManifestStore(paths: paths, bundledManifestReader: {
            reads += 1
            return reads >= 3 ? changed : original
        })
        try store.prepareDirectories()
        try original.write(to: paths.manifest)
        try Data("video".utf8).write(to: paths.videoURL(for: "TEST"))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: "TEST"))
        XCTAssertThrowsError(try store.addWallpaper(id: "TEST", title: "Test", requiringCompatibleCatalogue: true))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: "TEST").path))
    }

    func testImportRequiresCurrentCompatibleCatalogue() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialImportGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = WallpaperPaths(homeDirectory: home)
        let installed = try fixture(version: 1)
        let bundled = try fixture(version: 2)
        let store = ManifestStore(paths: paths, bundledManifestReader: { bundled })
        try store.prepareDirectories()
        try installed.write(to: paths.manifest)
        try Data("video".utf8).write(to: paths.videoURL(for: "TEST"))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: "TEST"))
        XCTAssertThrowsError(try store.addWallpaper(id: "TEST", title: "Test", requiringCompatibleCatalogue: true))
        XCTAssertEqual(try Data(contentsOf: paths.manifest), installed)
    }

    func testImportReportsCommittedWhenBundledCatalogueChangesAfterWrite() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialImportGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = WallpaperPaths(homeDirectory: home)
        let original = try fixture(version: 2)
        let changed = try fixture(version: 3)
        var reads = 0
        let store = ManifestStore(paths: paths, bundledManifestReader: {
            reads += 1
            return reads >= 4 ? changed : original
        })
        try store.prepareDirectories()
        try original.write(to: paths.manifest)
        try Data("video".utf8).write(to: paths.videoURL(for: "TEST"))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: "TEST"))
        XCTAssertThrowsError(try store.addWallpaper(id: "TEST", title: "Test", requiringCompatibleCatalogue: true)) {
            guard case AerialDropError.manifestMutationCommitted = $0 else {
                return XCTFail("Expected a committed outcome, got \($0)")
            }
        }
        XCTAssertEqual(try store.importedWallpapers().map(\.id), ["TEST"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: "TEST").path))
    }

    func testImportReportsSupersededWhenCatalogueChangesAfterCompatibilityCheck() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialImportGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = WallpaperPaths(homeDirectory: home)
        let original = try fixture(version: 2)
        let concurrent = try fixture(version: 3)
        let store = ManifestStore(paths: paths, bundledManifestReader: { original },
                                  afterImportCompatibilityCheck: { try concurrent.write(to: paths.manifest, options: .atomic) })
        try store.prepareDirectories()
        try original.write(to: paths.manifest)
        try Data("video".utf8).write(to: paths.videoURL(for: "TEST"))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: "TEST"))
        XCTAssertThrowsError(try store.addWallpaper(id: "TEST", title: "Test", requiringCompatibleCatalogue: true)) {
            guard case AerialDropError.manifestMutationSuperseded = $0 else {
                return XCTFail("Expected a superseded outcome, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: paths.manifest), concurrent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.videoURL(for: "TEST").path))
    }

    func testImportReportsCommittedWhenAtomicWriterThrowsAfterReplacement() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AerialImportGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = WallpaperPaths(homeDirectory: home)
        let original = try fixture(version: 2)
        let store = ManifestStore(paths: paths, bundledManifestReader: { original }, importWriter: { data, url in
            try data.write(to: url, options: .atomic)
            throw CocoaError(.fileWriteUnknown)
        })
        try store.prepareDirectories()
        try original.write(to: paths.manifest)
        try Data("video".utf8).write(to: paths.videoURL(for: "TEST"))
        try Data("thumbnail".utf8).write(to: paths.thumbnailURL(for: "TEST"))
        XCTAssertThrowsError(try store.addWallpaper(id: "TEST", title: "Test", requiringCompatibleCatalogue: true)) {
            guard case AerialDropError.manifestMutationCommitted = $0 else {
                return XCTFail("Expected a committed outcome, got \($0)")
            }
        }
        XCTAssertEqual(try store.importedWallpapers().map(\.id), ["TEST"])
    }

    private func fixture(version: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": version, "initialAssetCount": 0, "assets": [], "categories": []])
    }
}
