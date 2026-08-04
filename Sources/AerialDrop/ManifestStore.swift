import Foundation

struct ManifestStore {
    // Stable IDs let the app find and manage only its own catalogue entries.
    static let categoryID = "A0D92C42-1E4D-47E5-9AB6-9C76B7914DF1"
    static let subcategoryID = "7C7A90BF-3993-41F3-8CDA-4CD741FD0B18"
    static let categoryName = "AerialDrop"

    private let fileManager = FileManager.default
    let paths: WallpaperPaths

    init(paths: WallpaperPaths = WallpaperPaths()) {
        self.paths = paths
    }

    func prepareDirectories() throws {
        try fileManager.createDirectory(at: paths.manifestDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.videos, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.thumbnails, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true)
    }

    func requireManifest() throws {
        guard fileManager.fileExists(atPath: paths.manifest.path) else {
            throw AerialDropError.missingManifest(paths.manifest)
        }
    }

    func importedWallpapers() throws -> [ManagedWallpaper] {
        guard fileManager.fileExists(atPath: paths.manifest.path) else { return [] }
        let root = try loadRoot(from: Data(contentsOf: paths.manifest))
        guard let assets = root["assets"] as? [[String: Any]] else { return [] }

        return assets.compactMap { asset in
            guard
                let categories = asset["categories"] as? [String],
                categories.contains(Self.categoryID),
                let id = asset["id"] as? String
            else { return nil }

            let title = (asset["accessibilityLabel"] as? String)
                ?? (asset["localizedNameKey"] as? String)
                ?? id

            return ManagedWallpaper(
                id: id,
                title: title,
                videoURL: paths.videoURL(for: id),
                thumbnailURL: paths.thumbnailURL(for: id)
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }


    func validateCurrentManifest() throws {
        try requireManifest()
        let data = try Data(contentsOf: paths.manifest)
        let root = try loadRoot(from: data)
        try validateCandidate(root, preservingForeignEntriesFrom: root)
    }

    func addWallpaper(id: String, title: String) throws {
        try requireManifest()
        try prepareDirectories()

        let videoURL = paths.videoURL(for: id)
        let thumbnailURL = paths.thumbnailURL(for: id)
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw AerialDropError.installedFileMissing(videoURL)
        }
        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            throw AerialDropError.installedFileMissing(thumbnailURL)
        }

        try mutateManifest(operation: "import") { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }

            assets.removeAll { ($0["id"] as? String) == id }
            assets = normalizeManagedAssets(assets)

            let managedCount = assets.filter {
                (($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
            }.count
            assets.append(makeAsset(id: id, title: title, preferredOrder: managedCount))

            categories.removeAll { ($0["id"] as? String) == Self.categoryID }
            categories.append(makeCategory(representativeAssetID: id))

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }
    }

    func removeWallpaper(id: String) throws {
        try requireManifest()

        try mutateManifest(operation: "remove") { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }

            let oldCount = assets.count
            assets.removeAll { ($0["id"] as? String) == id }
            guard assets.count != oldCount else {
                throw AerialDropError.wallpaperNotFound
            }
            assets = dropMissingManagedAssets(assets)

            let remainingIDs = assets.compactMap { asset -> String? in
                guard
                    ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID),
                    let assetID = asset["id"] as? String
                else { return nil }
                return assetID
            }

            categories.removeAll { ($0["id"] as? String) == Self.categoryID }
            if let representative = remainingIDs.first {
                categories.append(makeCategory(representativeAssetID: representative))
            }

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }

        try? fileManager.removeItem(at: paths.videoURL(for: id))
        try? fileManager.removeItem(at: paths.thumbnailURL(for: id))
    }

    func removeAllManaged() throws {
        let wallpapers = try importedWallpapers()
        guard !wallpapers.isEmpty else { return }

        try requireManifest()
        try mutateManifest(operation: "remove-all") { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }

            assets.removeAll {
                (($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
            }
            categories.removeAll { ($0["id"] as? String) == Self.categoryID }

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }

        for wallpaper in wallpapers {
            try? fileManager.removeItem(at: wallpaper.videoURL)
            try? fileManager.removeItem(at: wallpaper.thumbnailURL)
        }
    }

    private func makeAsset(id: String, title: String, preferredOrder: Int) -> [String: Any] {
        let shotID = customShotID(for: id)
        return [
            "id": id,
            "shotID": shotID,
            "localizedNameKey": title,
            "accessibilityLabel": title,
            "includeInShuffle": true,
            "showInTopLevel": true,
            "preferredOrder": preferredOrder,
            "categories": [Self.categoryID],
            "subcategories": [Self.subcategoryID],
            // Tahoe custom entries observed in a working catalogue use one freeze/transition marker.
            "pointsOfInterest": ["0": "\(shotID)_0"],
            "previewImage": paths.thumbnailURL(for: id).absoluteString,
            "url-4K-SDR-240FPS": paths.videoURL(for: id).absoluteString
        ]
    }

    private func makeCategory(representativeAssetID id: String) -> [String: Any] {
        let preview = paths.thumbnailURL(for: id).absoluteString
        let subcategory: [String: Any] = [
            "id": Self.subcategoryID,
            "localizedNameKey": Self.categoryName,
            "localizedDescriptionKey": Self.categoryName,
            "preferredOrder": 0,
            "previewImage": preview,
            "representativeAssetID": id
        ]
        return [
            "id": Self.categoryID,
            "localizedNameKey": Self.categoryName,
            "localizedDescriptionKey": Self.categoryName,
            "preferredOrder": 0,
            "previewImage": preview,
            "representativeAssetID": id,
            "subcategories": [subcategory]
        ]
    }

    private func customShotID(for id: String) -> String {
        "CUSTOM_\(id.replacingOccurrences(of: "-", with: "_"))"
    }

    /// Drops AerialDrop-owned assets whose installed files are missing while leaving foreign
    /// entries untouched.
    private func dropMissingManagedAssets(_ assets: [[String: Any]]) -> [[String: Any]] {
        assets.filter { asset in
            guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else {
                return true
            }
            guard let assetID = asset["id"] as? String else { return false }
            return fileManager.fileExists(atPath: paths.videoURL(for: assetID).path)
                && fileManager.fileExists(atPath: paths.thumbnailURL(for: assetID).path)
        }
    }

    /// Drops AerialDrop-owned assets whose installed files are missing and normalizes the
    /// metadata (titles and preferred order) of the remaining AerialDrop-owned assets while
    /// leaving foreign entries untouched.
    private func normalizeManagedAssets(_ assets: [[String: Any]]) -> [[String: Any]] {
        let present = dropMissingManagedAssets(assets)

        var managedOrder = 0
        return present.map { asset in
            guard
                let assetID = asset["id"] as? String,
                ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID)
            else { return asset }

            let assetTitle = (asset["accessibilityLabel"] as? String)
                ?? (asset["localizedNameKey"] as? String)
                ?? assetID
            defer { managedOrder += 1 }
            return makeAsset(id: assetID, title: assetTitle, preferredOrder: managedOrder)
        }
    }

    private func mutateManifest(
        operation: String,
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        let originalData = try Data(contentsOf: paths.manifest)
        let originalRoot = try loadRoot(from: originalData)
        try validateBaseManifest(originalRoot)

        var candidateRoot = originalRoot
        try mutation(&candidateRoot)
        try validateCandidate(candidateRoot, preservingForeignEntriesFrom: originalRoot)

        guard JSONSerialization.isValidJSONObject(candidateRoot) else {
            throw AerialDropError.malformedManifest("generated JSON is invalid")
        }
        let candidateData = try JSONSerialization.data(
            withJSONObject: candidateRoot,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        _ = try loadRoot(from: candidateData)

        // Do not overwrite a catalogue changed by Wallper or macOS while import was running.
        let latestData = try Data(contentsOf: paths.manifest)
        guard latestData == originalData else {
            throw AerialDropError.manifestChangedDuringOperation
        }

        _ = try backupManifest(data: originalData, operation: operation)
        try candidateData.write(to: paths.manifest, options: .atomic)

        let writtenData = try Data(contentsOf: paths.manifest)
        guard writtenData == candidateData else {
            throw AerialDropError.manifestChangedDuringOperation
        }
        let writtenRoot = try loadRoot(from: writtenData)
        try validateCandidate(writtenRoot, preservingForeignEntriesFrom: originalRoot)
    }

    private func loadRoot(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
        } catch {
            throw AerialDropError.malformedManifest("invalid JSON: \(error.localizedDescription)")
        }
        guard let root = object as? [String: Any] else {
            throw AerialDropError.malformedManifest("top level is not a JSON object")
        }
        return root
    }

    private func validateBaseManifest(_ root: [String: Any]) throws {
        guard root["assets"] is [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level assets array")
        }
        guard root["categories"] is [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level categories array")
        }
        guard root["version"] != nil else {
            throw AerialDropError.malformedManifest("missing top-level version")
        }
        guard integerValue(root["initialAssetCount"]) != nil else {
            throw AerialDropError.malformedManifest("missing or invalid top-level initialAssetCount")
        }
    }

    private func validateCandidate(
        _ candidate: [String: Any],
        preservingForeignEntriesFrom original: [String: Any]
    ) throws {
        try validateBaseManifest(candidate)

        guard
            let originalAssets = original["assets"] as? [[String: Any]],
            let originalCategories = original["categories"] as? [[String: Any]],
            let candidateAssets = candidate["assets"] as? [[String: Any]],
            let candidateCategories = candidate["categories"] as? [[String: Any]]
        else {
            throw AerialDropError.malformedManifest("catalogue arrays could not be validated")
        }

        guard let visibleAssetCount = integerValue(candidate["initialAssetCount"]),
              visibleAssetCount == candidateAssets.count else {
            throw AerialDropError.malformedManifest(
                "initialAssetCount must match the assets array count (expected \(candidateAssets.count))"
            )
        }

        let originalForeignAssets = originalAssets.filter {
            !(($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
        }
        let candidateForeignAssets = candidateAssets.filter {
            !(($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
        }
        try requireSemanticEquality(
            originalForeignAssets,
            candidateForeignAssets,
            description: "non-AerialDrop assets"
        )

        let originalForeignCategories = originalCategories.filter {
            ($0["id"] as? String) != Self.categoryID
        }
        let candidateForeignCategories = candidateCategories.filter {
            ($0["id"] as? String) != Self.categoryID
        }
        try requireSemanticEquality(
            originalForeignCategories,
            candidateForeignCategories,
            description: "non-AerialDrop categories"
        )

        for (key, value) in original
        where key != "assets" && key != "categories" && key != "initialAssetCount" {
            guard let candidateValue = candidate[key] else {
                throw AerialDropError.malformedManifest("top-level key '\(key)' was removed")
            }
            try requireSemanticEquality(value, candidateValue, description: "top-level key '\(key)'")
        }

        let managedAssets = candidateAssets.filter {
            (($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
        }
        if managedAssets.isEmpty {
            guard !candidateCategories.contains(where: { ($0["id"] as? String) == Self.categoryID }) else {
                throw AerialDropError.malformedManifest("AerialDrop category exists without assets")
            }
            return
        }

        for asset in managedAssets {
            try validateManagedAsset(asset)
        }

        guard let category = candidateCategories.first(where: { ($0["id"] as? String) == Self.categoryID }) else {
            throw AerialDropError.malformedManifest("AerialDrop category is missing")
        }
        try validateManagedCategory(category, validAssetIDs: Set(managedAssets.compactMap { $0["id"] as? String }))
    }

    private func validateManagedAsset(_ asset: [String: Any]) throws {
        let requiredStrings = [
            "id", "shotID", "localizedNameKey", "accessibilityLabel",
            "previewImage", "url-4K-SDR-240FPS"
        ]
        for key in requiredStrings where (asset[key] as? String)?.isEmpty != false {
            throw AerialDropError.malformedManifest("AerialDrop asset is missing '\(key)'")
        }
        guard let id = asset["id"] as? String,
              (asset["previewImage"] as? String) == paths.thumbnailURL(for: id).absoluteString,
              (asset["url-4K-SDR-240FPS"] as? String) == paths.videoURL(for: id).absoluteString,
              fileManager.fileExists(atPath: paths.thumbnailURL(for: id).path),
              fileManager.fileExists(atPath: paths.videoURL(for: id).path)
        else {
            throw AerialDropError.malformedManifest("AerialDrop asset paths or installed files are invalid")
        }
        guard (asset["categories"] as? [String])?.contains(Self.categoryID) == true else {
            throw AerialDropError.malformedManifest("AerialDrop asset has the wrong category")
        }
        guard (asset["subcategories"] as? [String])?.contains(Self.subcategoryID) == true else {
            throw AerialDropError.malformedManifest("AerialDrop asset has the wrong subcategory")
        }
        guard let points = asset["pointsOfInterest"] as? [String: String], points["0"] != nil else {
            throw AerialDropError.malformedManifest("AerialDrop asset is missing its transition point")
        }
    }

    private func validateManagedCategory(_ category: [String: Any], validAssetIDs: Set<String>) throws {
        guard
            let representative = category["representativeAssetID"] as? String,
            validAssetIDs.contains(representative),
            (category["previewImage"] as? String)?.isEmpty == false,
            let subcategories = category["subcategories"] as? [[String: Any]],
            let subcategory = subcategories.first(where: { ($0["id"] as? String) == Self.subcategoryID }),
            (subcategory["representativeAssetID"] as? String) == representative,
            (subcategory["previewImage"] as? String)?.isEmpty == false,
            subcategory["preferredOrder"] is NSNumber
        else {
            throw AerialDropError.malformedManifest("AerialDrop category metadata is incomplete")
        }
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private func requireSemanticEquality(_ lhs: Any, _ rhs: Any, description: String) throws {
        guard JSONSerialization.isValidJSONObject(["value": lhs]),
              JSONSerialization.isValidJSONObject(["value": rhs]) else {
            throw AerialDropError.malformedManifest("could not compare \(description)")
        }
        let left = try JSONSerialization.data(withJSONObject: ["value": lhs], options: [.sortedKeys])
        let right = try JSONSerialization.data(withJSONObject: ["value": rhs], options: [.sortedKeys])
        guard left == right else {
            throw AerialDropError.foreignManifestDataChanged(description)
        }
    }

    @discardableResult
    private func backupManifest(data: Data, operation: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: Date())
        var backup = paths.backups.appendingPathComponent("entries-\(timestamp)-\(operation).json")
        var suffix = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = paths.backups.appendingPathComponent("entries-\(timestamp)-\(operation)-\(suffix).json")
            suffix += 1
        }
        try data.write(to: backup, options: .atomic)
        return backup
    }
}
