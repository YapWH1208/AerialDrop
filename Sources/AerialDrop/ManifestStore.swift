import Foundation
import CoreFoundation

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
        try validateBaseManifest(root)
        guard let assets = root["assets"] as? [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level assets array")
        }
        try validateManagedIDs(in: assets)

        return assets.compactMap { asset in
            guard
                let categories = asset["categories"] as? [String],
                categories.contains(Self.categoryID),
                let id = asset["id"] as? String
            else { return nil }

            let title = (asset["accessibilityLabel"] as? String)
                ?? (asset["localizedNameKey"] as? String)
                ?? id

            let resolution: CGSize? = {
                if let w = asset["width"] as? Int, let h = asset["height"] as? Int, w > 0, h > 0 {
                    return CGSize(width: w, height: h)
                }
                return nil
            }()

            let preferredOrder = (asset["preferredOrder"] as? NSNumber)?.intValue

            return ManagedWallpaper(
                id: id,
                title: title,
                videoURL: paths.videoURL(for: id),
                thumbnailURL: paths.thumbnailURL(for: id),
                resolution: resolution,
                preferredOrder: preferredOrder
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

    /// A restorable catalogue backup, including the exact bytes selected for confirmation.
    struct BackupInfo: Equatable {
        let url: URL
        let date: Date
        let operation: String
        let content: Data?

        init(url: URL, date: Date, operation: String) {
            self.url = url
            self.date = date
            self.operation = operation
            content = try? Data(contentsOf: url)
        }
    }

    /// The newest AerialDrop manifest backup, or nil when none exists.
    /// Backups written within the same millisecond share a timestamp, so they
    /// are ordered by the file's modification date (the actual write order);
    /// the full backup name breaks any remaining ties so that directory
    /// enumeration order never decides the winner.
    func latestBackup() -> BackupInfo? {
        guard let names = try? fileManager.contentsOfDirectory(atPath: paths.backups.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

        let candidates: [(name: String, url: URL, date: Date, operation: String)] = names.compactMap { name in
            guard name.hasPrefix("entries-"), name.hasSuffix(".json") else { return nil }
            let core = String(name.dropFirst("entries-".count).dropLast(".json".count))
            guard core.count > 20 else { return nil }
            let timestamp = String(core.prefix(19))
            let operation = String(core.dropFirst(20))
            guard let date = formatter.date(from: timestamp) else { return nil }
            return (name, paths.backups.appending(path: name), date, operation)
        }

        let newest = candidates
            .sorted { lhs, rhs in
                guard lhs.date == rhs.date else { return lhs.date > rhs.date }
                let lhsModified = (try? lhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? lhs.date
                let rhsModified = (try? rhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? rhs.date
                guard lhsModified == rhsModified else { return lhsModified > rhsModified }
                return lhs.name > rhs.name
            }
            .first
        guard let newest else { return nil }
        return BackupInfo(url: newest.url, date: newest.date, operation: newest.operation)
    }

    /// Replaces the current manifest with the backup's content, after backing
    /// up the current manifest and refusing when foreign (non-AerialDrop)
    /// catalogue data changed since the backup. Managed assets whose installed
    /// files are missing are tolerated — they surface as "Video missing" in
    /// the Library and can be removed there.
    /// A nil selection reader means active status is unknown: restoring may
    /// update metadata, but must not remove a managed catalogue entry. The
    /// reader is rechecked around the write, with guarded rollback if selection
    /// changes during the commit.
    func restoreBackup(
        _ info: BackupInfo,
        protectingActiveAssetIDs activeIDs: (() throws -> Set<String>)? = nil
    ) throws {
        do {
            guard let confirmedContent = info.content else {
                throw AerialDropError.backupRestoreRejected("The selected backup could not be read. Select the backup again and retry.")
            }
            let backupData = try Data(contentsOf: info.url)
            guard backupData == confirmedContent else {
                throw AerialDropError.backupRestoreRejected("The selected backup changed after confirmation. Select the backup again and retry.")
            }
            let backupRoot = try loadRoot(from: backupData)
            var removedIDs = Set<String>()
            func verifyActiveSelection() throws {
                guard !removedIDs.isEmpty else { return }
                guard let activeIDs else {
                    throw AerialDropError.wallpaperSelectionUnknownForRestore
                }
                let selectedIDs: Set<String>
                do {
                    selectedIDs = try activeIDs()
                } catch {
                    throw AerialDropError.wallpaperSelectionUnknownForRestore
                }
                guard removedIDs.isDisjoint(with: selectedIDs) else {
                    throw AerialDropError.activeWallpaperCannotBeRemovedByRestore
                }
            }
            try mutateManifest(
                operation: "restore",
                requireManagedFiles: false,
                commitValidation: verifyActiveSelection
            ) { root in
                try validateBaseManifest(backupRoot)
                removedIDs = try managedAssetIDs(in: root)
                    .subtracting(managedAssetIDs(in: backupRoot))
                try verifyActiveSelection()
                root = backupRoot
            }
        } catch let error as AerialDropError {
            if case .backupRestoreRejected = error { throw error }
            throw AerialDropError.backupRestoreRejected(reason(for: error))
        } catch {
            throw AerialDropError.backupRestoreRejected(error.localizedDescription)
        }
    }

    private func reason(for error: AerialDropError) -> String {
        switch error {
        case .foreignManifestDataChanged:
            return "The catalogue has changed since this backup was created, and restoring it would remove newer changes."
        case .manifestChangedDuringOperation:
            return "The catalogue changed while the restore was being prepared. Try again."
        default:
            return error.localizedDescription
        }
    }

    func addWallpaper(id: String, title: String, width: Int = 0, height: Int = 0) throws {
        try validateManagedID(id)
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
            assets.append(makeAsset(id: id, title: title, preferredOrder: managedCount, width: width, height: height))

            categories.removeAll { ($0["id"] as? String) == Self.categoryID }
            categories.append(makeCategory(representativeAssetID: id))

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }
    }

    func renameWallpaper(id: String, title: String) throws {
        try validateManagedID(id)
        try requireManifest()

        try mutateManifest(operation: "rename") { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }
            guard let index = assets.firstIndex(where: { ($0["id"] as? String) == id }),
                  ((assets[index]["categories"] as? [String]) ?? []).contains(Self.categoryID) else {
                throw AerialDropError.wallpaperNotFound
            }
            // Renaming must not silently drop its own target during normalization.
            for url in [paths.videoURL(for: id), paths.thumbnailURL(for: id)] {
                guard fileManager.fileExists(atPath: url.path) else {
                    throw AerialDropError.installedFileMissing(url)
                }
            }

            var asset = assets[index]
            asset["localizedNameKey"] = title
            asset["accessibilityLabel"] = title
            assets[index] = asset

            let normalized = normalizeManagedAssets(assets)
            let remainingIDs = normalized.compactMap { asset -> String? in
                guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else { return nil }
                return asset["id"] as? String
            }
            let existingRepresentative = categories.first {
                ($0["id"] as? String) == Self.categoryID
            }?["representativeAssetID"] as? String
            let representative = existingRepresentative.flatMap { remainingIDs.contains($0) ? $0 : nil }
                ?? remainingIDs.first
            categories.removeAll { ($0["id"] as? String) == Self.categoryID }
            if let representative {
                categories.append(makeCategory(representativeAssetID: representative))
            }
            root["assets"] = normalized
            root["categories"] = categories
            root["initialAssetCount"] = normalized.count
        }
    }

    func removeWallpaper(id: String) throws {
        try validateManagedID(id)
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

    private func makeAsset(id: String, title: String, preferredOrder: Int, width: Int = 0, height: Int = 0) -> [String: Any] {
        let shotID = customShotID(for: id)
        var asset: [String: Any] = [
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
        if width > 0 && height > 0 {
            asset["width"] = width
            asset["height"] = height
        }
        return asset
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
        "CUSTOM_\(id.replacing("-", with: "_"))"
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
            let assetWidth = (asset["width"] as? Int) ?? 0
            let assetHeight = (asset["height"] as? Int) ?? 0
            defer { managedOrder += 1 }
            return makeAsset(
                id: assetID,
                title: assetTitle,
                preferredOrder: managedOrder,
                width: assetWidth,
                height: assetHeight
            )
        }
    }

    private func mutateManifest(
        operation: String,
        requireManagedFiles: Bool = true,
        commitValidation: (() throws -> Void)? = nil,
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        let originalData = try Data(contentsOf: paths.manifest)
        let originalRoot = try loadRoot(from: originalData)
        try validateBaseManifest(originalRoot)
        // Candidate-only validation misses unsafe IDs whose entries are removed or dropped
        // during normalization. Reject them before any path lookup or catalogue mutation.
        if let originalAssets = originalRoot["assets"] as? [[String: Any]] {
            try validateManagedIDs(in: originalAssets)
        }

        var candidateRoot = originalRoot
        try mutation(&candidateRoot)
        try validateCandidate(
            candidateRoot,
            preservingForeignEntriesFrom: originalRoot,
            requireManagedFiles: requireManagedFiles
        )

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

        try commitValidation?()
        let backup = try backupManifest(data: originalData, operation: operation)
        // Backup creation takes time. Check the selection again after it finishes,
        // and remove only our new backup if the restore has become unsafe.
        do {
            try commitValidation?()
        } catch {
            try fileManager.removeItem(at: backup)
            throw error
        }
        try candidateData.write(to: paths.manifest, options: .atomic)
        do {
            try commitValidation?()
        } catch {
            do {
                let latestData = try Data(contentsOf: paths.manifest)
                guard latestData == candidateData else {
                    throw AerialDropError.manifestChangedDuringOperation
                }
                try originalData.write(to: paths.manifest, options: .atomic)
                guard try Data(contentsOf: paths.manifest) == originalData else {
                    throw AerialDropError.manifestChangedDuringOperation
                }
            } catch {
                throw AerialDropError.backupRestoreRejected(
                    "The active wallpaper changed during restore, and rollback could not be verified. A safety backup was retained as \(backup.lastPathComponent)."
                )
            }
            throw error
        }

        let writtenData = try Data(contentsOf: paths.manifest)
        guard writtenData == candidateData else {
            throw AerialDropError.manifestChangedDuringOperation
        }
        let writtenRoot = try loadRoot(from: writtenData)
        try validateCandidate(
            writtenRoot,
            preservingForeignEntriesFrom: originalRoot,
            requireManagedFiles: requireManagedFiles
        )
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
        guard let assets = root["assets"] as? [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level assets array")
        }
        guard root["categories"] is [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level categories array")
        }
        guard root["version"] != nil else {
            throw AerialDropError.malformedManifest("missing top-level version")
        }
        guard let count = integerValue(root["initialAssetCount"]) else {
            throw AerialDropError.malformedManifest("missing or invalid top-level initialAssetCount")
        }
        guard count == assets.count else {
            throw AerialDropError.malformedManifest(
                "initialAssetCount must match the assets array count (expected \(assets.count))"
            )
        }
    }

    private func validateCandidate(
        _ candidate: [String: Any],
        preservingForeignEntriesFrom original: [String: Any],
        requireManagedFiles: Bool = true
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

        let managedKeys: Set<String> = ["assets", "categories", "initialAssetCount"]
        try requireSemanticEquality(
            original.filter { !managedKeys.contains($0.key) },
            candidate.filter { !managedKeys.contains($0.key) },
            description: "foreign top-level catalogue data"
        )

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
            try validateManagedAsset(asset, requireFiles: requireManagedFiles)
        }

        guard let category = candidateCategories.first(where: { ($0["id"] as? String) == Self.categoryID }) else {
            throw AerialDropError.malformedManifest("AerialDrop category is missing")
        }
        try validateManagedCategory(category, validAssetIDs: Set(managedAssets.compactMap { $0["id"] as? String }))
    }

    private func validateManagedAsset(_ asset: [String: Any], requireFiles: Bool = true) throws {
        guard let id = asset["id"] as? String else {
            throw AerialDropError.malformedManifest("AerialDrop asset is missing 'id'")
        }
        try validateManagedID(id)
        let requiredStrings = [
            "id", "shotID", "localizedNameKey", "accessibilityLabel",
            "previewImage", "url-4K-SDR-240FPS"
        ]
        for key in requiredStrings where (asset[key] as? String)?.isEmpty != false {
            throw AerialDropError.malformedManifest("AerialDrop asset is missing '\(key)'")
        }
        guard (asset["previewImage"] as? String) == paths.thumbnailURL(for: id).absoluteString,
              (asset["url-4K-SDR-240FPS"] as? String) == paths.videoURL(for: id).absoluteString
        else {
            throw AerialDropError.malformedManifest("AerialDrop asset paths are invalid")
        }
        if requireFiles {
            guard fileManager.fileExists(atPath: paths.thumbnailURL(for: id).path),
                  fileManager.fileExists(atPath: paths.videoURL(for: id).path)
            else {
                throw AerialDropError.malformedManifest("AerialDrop asset paths or installed files are invalid")
            }
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
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }

    private func validateManagedIDs(in assets: [[String: Any]]) throws {
        for asset in assets where ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) {
            guard let id = asset["id"] as? String else {
                throw AerialDropError.malformedManifest("AerialDrop asset is missing 'id'")
            }
            try validateManagedID(id)
        }
    }

    private func managedAssetIDs(in root: [String: Any]) throws -> Set<String> {
        guard let assets = root["assets"] as? [[String: Any]] else {
            throw AerialDropError.malformedManifest("missing top-level assets array")
        }
        try validateManagedIDs(in: assets)
        return Set(assets.compactMap { asset in
            guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else { return nil }
            return asset["id"] as? String
        })
    }

    /// Managed IDs become filename components. Safe legacy IDs need not be UUIDs.
    private func validateManagedID(_ id: String) throws {
        guard !id.isEmpty, id != ".", id != "..",
              !id.contains("/"), !id.contains("\\"), !id.contains("\0") else {
            throw AerialDropError.malformedManifest("AerialDrop asset ID is not a safe filename component")
        }
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
