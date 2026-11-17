import Foundation
import XCTest
@testable import AerialDrop

final class AerialCatalogueCompatibilityTests: XCTestCase {
    private typealias Compatibility = AerialCatalogueCompatibility

    func testOlderVersionWithEquivalentForeignEntriesCanBePromoted() throws {
        var installed = fixture(version: 1)
        installed["initialAssetCount"] = 0
        installed["futureLocalKey"] = ["preserve": true]
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .promotion(version: 2))
    }

    func testEqualOrNewerVersionNeedsNoPromotionEvenWhenRecordsDiffer() throws {
        var installed = fixture(version: 2)
        var assets = installed["assets"] as! [[String: Any]]
        assets[0]["url"] = "different"
        installed["assets"] = assets
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .current)
        installed["version"] = 3
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .current)
    }

    func testInvalidVersionsFailClosed() throws {
        for value: Any in [true, false, -1, 1.5, "1", NSNull()] {
            var installed = fixture(version: 1)
            installed["version"] = value
            XCTAssertThrowsError(try assess(installed, fixture(version: 2))) {
                XCTAssertEqual($0 as? Compatibility.Failure, .invalidCatalogue)
            }
            var bundled = fixture(version: 2)
            bundled["version"] = value
            XCTAssertThrowsError(try assess(fixture(version: 1), bundled))
        }
        var missing = fixture(version: 1)
        missing.removeValue(forKey: "version")
        XCTAssertThrowsError(try assess(missing, fixture(version: 2)))
    }

    func testMalformedJSONAndMalformedEqualVersionFailClosed() throws {
        let good = try data(fixture(version: 1))
        XCTAssertThrowsError(try Compatibility.assess(installed: Data("not json".utf8), bundled: good))
        XCTAssertThrowsError(try Compatibility.assess(installed: good, bundled: Data("{}".utf8)))
        var bad = fixture(version: 1)
        bad.removeValue(forKey: "categories")
        XCTAssertThrowsError(try assess(bad, fixture(version: 1)))
    }

    func testNoPromotionDoesNotRejectPreviouslyAcceptedForeignShapes() throws {
        var installed = fixture(version: 2)
        installed["categories"] = [["id": "unfamiliar-foreign-category"]]
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .current)
        installed["version"] = 3
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .current)
    }

    func testDifferentSharedAssetOrCategoryFailsClosed() throws {
        var installed = fixture(version: 1)
        var assets = installed["assets"] as! [[String: Any]]
        assets[0]["url"] = "different"
        installed["assets"] = assets
        XCTAssertThrowsError(try assess(installed, fixture(version: 2))) {
            XCTAssertEqual($0 as? Compatibility.Failure, .incompatibleCatalogue)
        }
        installed = fixture(version: 1)
        var categories = installed["categories"] as! [[String: Any]]
        var subcategories = categories[0]["subcategories"] as! [[String: Any]]
        subcategories[0]["name"] = "changed"
        categories[0]["subcategories"] = subcategories
        installed["categories"] = categories
        XCTAssertThrowsError(try assess(installed, fixture(version: 2))) {
            XCTAssertEqual($0 as? Compatibility.Failure, .incompatibleCatalogue)
        }
    }

    func testMissingBundledAssetCategoryAndSubcategoryFailClosed() throws {
        var bundled = fixture(version: 2)
        var assets = bundled["assets"] as! [[String: Any]]
        assets.append(["id": "extra", "categories": ["category"], "subcategories": ["subcategory"]])
        bundled["assets"] = assets
        XCTAssertThrowsError(try assess(fixture(version: 1), bundled)) {
            XCTAssertEqual($0 as? Compatibility.Failure, .incompatibleCatalogue)
        }
        bundled = fixture(version: 2)
        var categories = bundled["categories"] as! [[String: Any]]
        categories.append(["id": "extra", "subcategories": []])
        bundled["categories"] = categories
        XCTAssertThrowsError(try assess(fixture(version: 1), bundled))
        bundled = fixture(version: 2)
        categories = bundled["categories"] as! [[String: Any]]
        var subcategories = categories[0]["subcategories"] as! [[String: Any]]
        subcategories.append(["id": "extra-subcategory"])
        categories[0]["subcategories"] = subcategories
        bundled["categories"] = categories
        XCTAssertThrowsError(try assess(fixture(version: 1), bundled))
    }

    func testDownloadedOnlyEntriesArePreservedByAssessment() throws {
        var installed = fixture(version: 1)
        var assets = installed["assets"] as! [[String: Any]]
        assets.append(["id": "managed", "categories": ["managed-category"], "subcategories": ["managed-subcategory"]])
        installed["assets"] = assets
        var categories = installed["categories"] as! [[String: Any]]
        categories.append(["id": "managed-category", "subcategories": [["id": "managed-subcategory"]]])
        installed["categories"] = categories
        installed["initialAssetCount"] = 2
        XCTAssertEqual(try assess(installed, fixture(version: 2)), .promotion(version: 2))
    }

    func testMissingReferencesAndDuplicateIdentifiersFailClosed() throws {
        var installed = fixture(version: 1)
        var assets = installed["assets"] as! [[String: Any]]
        assets[0]["subcategories"] = ["unknown"]
        installed["assets"] = assets
        XCTAssertThrowsError(try assess(installed, fixture(version: 2)))
        installed = fixture(version: 1)
        assets = installed["assets"] as! [[String: Any]]
        assets.append(assets[0])
        installed["assets"] = assets
        XCTAssertThrowsError(try assess(installed, fixture(version: 2)))
    }

    func testDifferentOrMissingBundledTopLevelMetadataFailsClosed() throws {
        var installed = fixture(version: 1)
        installed["localizationVersion"] = 2
        XCTAssertThrowsError(try assess(installed, fixture(version: 2)))
        installed.removeValue(forKey: "localizationVersion")
        XCTAssertThrowsError(try assess(installed, fixture(version: 2)))
        var future = fixture(version: 2)
        future["futureSchemaField"] = "unknown"
        XCTAssertThrowsError(try assess(fixture(version: 1), future))
    }

    func testAssetSubcategoryMustBelongToOneOfItsCategories() throws {
        var installed = fixture(version: 1)
        var categories = installed["categories"] as! [[String: Any]]
        categories.append(["id": "other", "subcategories": [["id": "other-subcategory"]]])
        installed["categories"] = categories
        var assets = installed["assets"] as! [[String: Any]]
        assets[0]["subcategories"] = ["other-subcategory"]
        installed["assets"] = assets
        XCTAssertThrowsError(try assess(installed, fixture(version: 2)))
        assets[0]["categories"] = ["category", "other"]
        assets[0]["subcategories"] = ["subcategory", "other-subcategory"]
        installed["assets"] = assets
        // The graph is valid but this changed shared record must still not be promoted.
        XCTAssertThrowsError(try assess(installed, fixture(version: 2))) {
            XCTAssertEqual($0 as? Compatibility.Failure, .incompatibleCatalogue)
        }
    }

    func testRepresentativeMustBelongToTheCategoryItRepresents() throws {
        var installed = fixture(version: 1)
        var assets = installed["assets"] as! [[String: Any]]
        assets.append(["id": "other-asset", "categories": ["other"], "subcategories": []])
        installed["assets"] = assets
        var categories = installed["categories"] as! [[String: Any]]
        categories[0]["representativeAssetID"] = "other-asset"
        categories.append(["id": "other", "subcategories": []])
        installed["categories"] = categories
        XCTAssertThrowsError(try assess(installed, fixture(version: 2))) {
            XCTAssertEqual($0 as? Compatibility.Failure, .invalidCatalogue)
        }
    }

    private func fixture(version: Int) -> [String: Any] {
        ["version": version, "initialAssetCount": 1, "localizationVersion": 1,
         "assets": [["id": "asset", "categories": ["category"], "subcategories": ["subcategory"], "url": "apple"]],
         "categories": [["id": "category", "representativeAssetID": "asset",
                          "subcategories": [["id": "subcategory", "representativeAssetID": "asset"]]]]]
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func assess(_ installed: [String: Any], _ bundled: [String: Any]) throws -> Compatibility.Assessment {
        try Compatibility.assess(installed: data(installed), bundled: data(bundled))
    }
}
