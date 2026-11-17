import CoreFoundation
import Foundation

/// Compares snapshots only; it never reads or writes either system catalogue.
enum AerialCatalogueCompatibility {
    enum Assessment: Equatable {
        case current
        case promotion(version: Int)
    }

    enum Failure: LocalizedError, Equatable {
        case invalidCatalogue
        case incompatibleCatalogue

        var errorDescription: String? {
            switch self {
            case .invalidCatalogue:
                return "The wallpaper catalogues could not be checked. Open Wallpaper Settings and try again."
            case .incompatibleCatalogue:
                return "The macOS and installed wallpaper catalogues differ. AerialDrop can’t safely update the catalogue. Use a built-in wallpaper or check for an AerialDrop update."
            }
        }
    }

    static func assess(installed: Data, bundled: Data) throws -> Assessment {
        let installedRoot = try root(installed)
        let bundledRoot = try root(bundled)
        let installedVersion = try integer(installedRoot["version"])
        let bundledVersion = try integer(bundledRoot["version"])
        try validateBase(installedRoot)
        try validateBase(bundledRoot)
        guard installedVersion < bundledVersion else { return .current }
        let installedGraph = try graph(installedRoot)
        let bundledGraph = try graph(bundledRoot)
        let understoodKeys: Set<String> = ["version", "initialAssetCount", "assets", "categories", "localizationVersion"]
        guard Set(bundledRoot.keys).isSubset(of: understoodKeys) else { throw Failure.incompatibleCatalogue }
        // Other supported metadata must agree before the older catalogue is promoted.
        let separatelyHandled: Set<String> = ["version", "initialAssetCount", "assets", "categories"]
        for (key, value) in bundledRoot where !separatelyHandled.contains(key) {
            guard let other = installedRoot[key], try equal(value, other) else {
                throw Failure.incompatibleCatalogue
            }
        }
        for (id, entry) in bundledGraph.assets {
            guard let other = installedGraph.assets[id], try equal(entry, other) else {
                throw Failure.incompatibleCatalogue
            }
        }
        // Category equality includes every nested subcategory and its fields.
        for (id, entry) in bundledGraph.categories {
            guard let other = installedGraph.categories[id], try equal(entry, other) else {
                throw Failure.incompatibleCatalogue
            }
        }
        return .promotion(version: bundledVersion)
    }

    private static func root(_ data: Data) throws -> [String: Any] {
        guard let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.invalidCatalogue
        }
        return result
    }

    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              "cCsSiIlLqQ".contains(String(cString: number.objCType)),
              let result = Int(number.stringValue), result >= 0 else {
            throw Failure.invalidCatalogue
        }
        return result
    }

    private struct Graph {
        let assets: [String: [String: Any]]
        let categories: [String: [String: Any]]
    }

    private static func validateBase(_ root: [String: Any]) throws {
        guard let assets = root["assets"] as? [[String: Any]],
              root["categories"] is [[String: Any]],
              try integer(root["initialAssetCount"]) <= assets.count else {
            throw Failure.invalidCatalogue
        }
    }

    private static func graph(_ root: [String: Any]) throws -> Graph {
        guard let assets = root["assets"] as? [[String: Any]],
              let categories = root["categories"] as? [[String: Any]],
              try integer(root["initialAssetCount"]) <= assets.count else {
            throw Failure.invalidCatalogue
        }
        let assetsByID = try indexed(assets)
        let categoriesByID = try indexed(categories)
        var subcategoriesByID: [String: [String: Any]] = [:]
        var subcategoryParents: [String: String] = [:]
        for category in categories {
            guard let categoryID = category["id"] as? String,
                  let subcategories = category["subcategories"] as? [[String: Any]] else {
                throw Failure.invalidCatalogue
            }
            for (id, subcategory) in try indexed(subcategories) {
                guard subcategoriesByID.updateValue(subcategory, forKey: id) == nil else {
                    throw Failure.invalidCatalogue
                }
                subcategoryParents[id] = categoryID
                try validateRepresentative(subcategory, assets: assetsByID, membership: "subcategories", id: id)
            }
            try validateRepresentative(category, assets: assetsByID, membership: "categories", id: categoryID)
        }
        for asset in assets {
            guard let categories = asset["categories"] as? [String],
                  let subcategories = asset["subcategories"] as? [String],
                  categories.allSatisfy({ categoriesByID[$0] != nil }),
                  subcategories.allSatisfy({ subcategoriesByID[$0] != nil }),
                  subcategories.allSatisfy({ subcategoryParents[$0].map(categories.contains) == true }) else {
                throw Failure.invalidCatalogue
            }
        }
        return Graph(assets: assetsByID, categories: categoriesByID)
    }

    private static func indexed(_ entries: [[String: Any]]) throws -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String, !id.isEmpty,
                  result.updateValue(entry, forKey: id) == nil else {
                throw Failure.invalidCatalogue
            }
        }
        return result
    }

    private static func validateRepresentative(
        _ entry: [String: Any], assets: [String: [String: Any]], membership: String, id: String
    ) throws {
        if let value = entry["representativeAssetID"] {
            guard let representative = value as? String,
                  let memberships = assets[representative]?[membership] as? [String],
                  memberships.contains(id) else { throw Failure.invalidCatalogue }
        }
    }

    private static func equal(_ lhs: Any, _ rhs: Any) throws -> Bool {
        do {
            return try JSONSerialization.data(withJSONObject: ["value": lhs], options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: ["value": rhs], options: [.sortedKeys])
        } catch {
            throw Failure.invalidCatalogue
        }
    }
}
