import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class AppModelWallpaperTests: XCTestCase {
    func testManualActivationRefreshesTheActiveAerialID() async {
        let service = FakeWallpaperService()
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0001")

        await model.activateWallpaper(wallpaper)

        XCTAssertEqual(service.activatedAssetIDs, [wallpaper.id])
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.alertMessage)
    }

    func testActivationFailureKeepsExistingActiveStateAndSurfacesAnError() async {
        let service = FakeWallpaperService(activeIDs: ["CURRENT-AERIAL"])
        service.activationError = TestError.activationFailed
        let model = makeModel(service: service)
        await model.reload()

        await model.activateWallpaper(makeWallpaper(id: "C0D3X-0002"))

        XCTAssertEqual(service.activatedAssetIDs, ["C0D3X-0002"])
        XCTAssertEqual(model.activeAerialAssetIDs, Set(["CURRENT-AERIAL"]))
        XCTAssertEqual(model.alertMessage, TestError.activationFailed.localizedDescription)
        XCTAssertFalse(model.isWorking)
    }

    func testSuccessfulActivationClearsTheRetryTarget() async {
        let service = FakeWallpaperService()
        let model = makeModel(service: service)
        let wallpaper = makeWallpaper(id: "C0D3X-0003")
        model.activationFailure = wallpaper

        await model.activateWallpaper(wallpaper)

        XCTAssertNil(model.activationFailure)
        XCTAssertEqual(model.activeAerialAssetIDs, Set([wallpaper.id]))
    }

    private func makeModel(service: FakeWallpaperService) -> AppModel {
        AppModel(
            paths: WallpaperPaths(homeDirectory: URL(fileURLWithPath: "/tmp/AerialDropAppModelTests")),
            systemService: service,
            automaticallyReload: false
        )
    }

    private func makeWallpaper(id: String) -> ManagedWallpaper {
        ManagedWallpaper(
            id: id,
            title: "Test Aerial",
            videoURL: URL(fileURLWithPath: "/tmp/\(id).mov"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/\(id).png"),
            resolution: CGSize(width: 3_840, height: 2_160)
        )
    }
}

@MainActor
private final class FakeWallpaperService: WallpaperServicing {
    var activeIDs: Set<String>
    var activatedAssetIDs: [String] = []
    var activationError: Error?

    init(activeIDs: Set<String> = []) {
        self.activeIDs = activeIDs
    }

    func activeAerialAssetIDs() throws -> Set<String> {
        activeIDs
    }

    func activateAerial(assetID: String) async throws {
        activatedAssetIDs.append(assetID)
        if let activationError {
            throw activationError
        }
        activeIDs = [assetID]
    }

    func refresh() async { }

    func openWallpaperSettings() { }

    func openFolder(_: URL) { }

    func revealInFinder(_: URL) { }
}

private enum TestError: LocalizedError {
    case activationFailed

    var errorDescription: String? {
        "The simulated wallpaper activation failed."
    }
}
