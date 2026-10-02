import Foundation
import CoreFoundation

struct ManifestStore {
    // Stable IDs let the app find and manage only its own catalogue entries.
    static let categoryID = "A0D92C42-1E4D-47E5-9AB6-9C76B7914DF1"
    static let subcategoryID = "7C7A90BF-3993-41F3-8CDA-4CD741FD0B18"
    static let dayNightSubcategoryID = "763FFF88-F451-45B2-9F95-337F7FB6CB7B"
    static let categoryName = "AerialDrop"

    private static let dayNightName = "AerialDrop Day & Night"
    private static let solarAzimuth = 180
    private static let daySolarAltitude = 35
    private static let nightSolarAltitude = -35

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
        _ = try managedDayNightPair(in: root)

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

    /// The pair currently registered in the native Aerial catalogue. Editable
    /// UI draft choices are persisted separately and do not appear here until
    /// the user explicitly applies them.
    func dayNightPair() throws -> DayNightWallpaperPair? {
        guard fileManager.fileExists(atPath: paths.manifest.path) else { return nil }
        let root = try loadRoot(from: Data(contentsOf: paths.manifest))
        try validateCandidate(root, preservingForeignEntriesFrom: root)
        return try managedDayNightPair(in: root)
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
    /// reader is rechecked before and after the write. If post-write validation
    /// fails, rollback is avoided because an external catalogue writer could
    /// race it; the current catalogue outcome is reported and the safety backup
    /// is retained.
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
            var currentPair: DayNightWallpaperPair?
            var restoredPair: DayNightWallpaperPair?
            func verifyActiveSelection() throws {
                let changesPair = currentPair != restoredPair
                guard !removedIDs.isEmpty || changesPair else { return }
                guard let activeIDs else {
                    throw AerialDropError.wallpaperSelectionUnknownForRestore
                }
                let selectedIDs: Set<String>
                do {
                    selectedIDs = try activeIDs()
                } catch {
                    throw AerialDropError.wallpaperSelectionUnknownForRestore
                }
                let removesSelectedAsset = !removedIDs.isDisjoint(with: selectedIDs)
                let changedPairMemberIDs = (currentPair?.memberAssetIDs ?? [])
                    .union(restoredPair?.memberAssetIDs ?? [])
                let changesActivePair = changesPair
                    && (selectedIDs.contains(Self.dayNightSubcategoryID)
                        || !selectedIDs.isDisjoint(with: changedPairMemberIDs))
                guard !removesSelectedAsset, !changesActivePair else {
                    throw AerialDropError.activeWallpaperCannotBeRemovedByRestore
                }
            }
            try mutateManifest(
                operation: "restore",
                requireManagedFiles: false,
                commitValidation: verifyActiveSelection
            ) { root in
                try validateBaseManifest(backupRoot)
                currentPair = try managedDayNightPair(in: root)
                restoredPair = try managedDayNightPair(in: backupRoot)
                removedIDs = try managedAssetIDs(in: root)
                    .subtracting(managedAssetIDs(in: backupRoot))
                try verifyActiveSelection()
                root = backupRoot
            }
        } catch let error as AerialDropError {
            if case .backupRestoreRejected = error { throw error }
            if case .backupRestoreCommitted = error { throw error }
            if case .backupRestoreSuperseded = error { throw error }
            if case .backupRestoreOutcomeUnknown = error { throw error }
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

            let pair = try managedDayNightPair(in: root)
            assets.removeAll { ($0["id"] as? String) == id }
            assets = try normalizeManagedAssets(assets, preserving: pair)

            let managedCount = assets.filter {
                (($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
            }.count
            assets.append(makeAsset(
                id: id,
                title: title,
                preferredOrder: managedCount,
                width: width,
                height: height,
                pair: pair
            ))

            categories = rebuildManagedCategory(
                categories,
                assets: assets,
                preferredRepresentativeAssetID: id,
                pair: pair
            )

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }
    }

    /// Registers two existing imported assets as the one native solar group.
    /// This mutation is called only by an explicit Apply action; it does not own
    /// or persist the UI's editable draft selections.
    /// Before replacing a registered pair, the caller must persist protection
    /// for these source IDs until a fresh native activation is verified. Native
    /// services may still cache the previous pair after a failed refresh.
    func configureDayNightPair(
        _ pair: DayNightWallpaperPair,
        protectingPreviousPairMembers protectPreviousMembers: ((Set<String>) throws -> Void)? = nil
    ) throws {
        try validateManagedID(pair.dayAssetID)
        try validateManagedID(pair.nightAssetID)
        guard pair.dayAssetID != pair.nightAssetID else {
            throw AerialDropError.malformedManifest("Day and Night must use different imported wallpapers")
        }
        try requireManifest()
        try prepareDirectories()

        try mutateManifest(operation: "configure-day-night") { root in
            // Applying a pair must start from a fully valid installed catalogue.
            // Unlike import/rename normalization, configuration must not repair
            // malformed paths or silently discard unrelated managed assets.
            try validateCandidate(root, preservingForeignEntriesFrom: root)
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }
            let previousPair = try managedDayNightPair(in: root)

            let managedIDs = Set(assets.compactMap { asset -> String? in
                guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else { return nil }
                return asset["id"] as? String
            })
            guard pair.memberAssetIDs.isSubset(of: managedIDs) else {
                throw AerialDropError.wallpaperNotFound
            }
            for id in pair.memberAssetIDs {
                guard assets.filter({ ($0["id"] as? String) == id }).count == 1 else {
                    throw AerialDropError.malformedManifest(
                        "Day and Night asset IDs must be unique across the catalogue"
                    )
                }
            }

            if let previousPair, previousPair != pair {
                guard let protectPreviousMembers else {
                    throw AerialDropError.dayNightPairChangeRequiresProtection
                }
                try protectPreviousMembers(previousPair.memberAssetIDs.union(pair.memberAssetIDs))
            }

            assets = try normalizeManagedAssets(assets, preserving: pair)
            let existingRepresentative = categories.first {
                ($0["id"] as? String) == Self.categoryID
            }?["representativeAssetID"] as? String
            categories = rebuildManagedCategory(
                categories,
                assets: assets,
                preferredRepresentativeAssetID: existingRepresentative,
                pair: pair
            )

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

            let pair = try managedDayNightPair(in: root)
            var asset = assets[index]
            asset["localizedNameKey"] = title
            asset["accessibilityLabel"] = title
            assets[index] = asset

            let normalized = try normalizeManagedAssets(assets, preserving: pair)
            let remainingIDs = normalized.compactMap { asset -> String? in
                guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else { return nil }
                return asset["id"] as? String
            }
            let existingRepresentative = categories.first {
                ($0["id"] as? String) == Self.categoryID
            }?["representativeAssetID"] as? String
            let representative = existingRepresentative.flatMap { remainingIDs.contains($0) ? $0 : nil }
                ?? remainingIDs.first
            categories = rebuildManagedCategory(
                categories,
                assets: normalized,
                preferredRepresentativeAssetID: representative,
                pair: pair
            )
            root["assets"] = normalized
            root["categories"] = categories
            root["initialAssetCount"] = normalized.count
        }
    }

    func removeWallpaper(
        id: String,
        protectingActiveAssetIDs activeIDs: (() throws -> Set<String>)? = nil
    ) throws {
        try validateManagedID(id)
        try requireManifest()

        var removedPair: DayNightWallpaperPair?
        func verifyActiveSelection() throws {
            guard removedPair != nil else { return }
            guard let activeIDs else {
                throw AerialDropError.wallpaperSelectionUnknownForRemoval
            }
            let selectedIDs: Set<String>
            do {
                selectedIDs = try activeIDs()
            } catch {
                throw AerialDropError.wallpaperSelectionUnknownForRemoval
            }
            guard let pair = removedPair,
                  !selectedIDs.contains(Self.dayNightSubcategoryID),
                  selectedIDs.isDisjoint(with: pair.memberAssetIDs) else {
                throw AerialDropError.activeWallpaperCannotBeRemoved
            }
        }

        try mutateManifest(
            operation: "remove",
            commitValidation: verifyActiveSelection
        ) { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }

            let pair = try managedDayNightPair(in: root)
            if let pair, pair.memberAssetIDs.contains(id) {
                removedPair = pair
                for survivingID in pair.memberAssetIDs where survivingID != id {
                    for url in [paths.videoURL(for: survivingID), paths.thumbnailURL(for: survivingID)] {
                        guard fileManager.fileExists(atPath: url.path) else {
                            throw AerialDropError.installedFileMissing(url)
                        }
                    }
                }
                try verifyActiveSelection()
            }

            let oldCount = assets.count
            assets.removeAll { ($0["id"] as? String) == id }
            guard assets.count != oldCount else {
                throw AerialDropError.wallpaperNotFound
            }
            let remainingPair = removedPair == nil ? pair : nil
            assets = try normalizeManagedAssets(assets, preserving: remainingPair)

            let remainingIDs = assets.compactMap { asset -> String? in
                guard
                    ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID),
                    let assetID = asset["id"] as? String
                else { return nil }
                return assetID
            }

            categories = rebuildManagedCategory(
                categories,
                assets: assets,
                preferredRepresentativeAssetID: remainingIDs.first,
                pair: remainingPair
            )

            root["assets"] = assets
            root["categories"] = categories
            root["initialAssetCount"] = assets.count
        }

        try? fileManager.removeItem(at: paths.videoURL(for: id))
        try? fileManager.removeItem(at: paths.thumbnailURL(for: id))
    }

    func removeAllManaged(
        protectingActiveAssetIDs activeIDs: (() throws -> Set<String>)? = nil
    ) throws {
        let wallpapers = try importedWallpapers()
        guard !wallpapers.isEmpty else { return }

        try requireManifest()
        var removedIDs = Set(wallpapers.map(\.id))
        var removesPair = false
        func verifyActiveSelection() throws {
            guard removesPair else { return }
            guard let activeIDs else {
                throw AerialDropError.wallpaperSelectionUnknownForRemoval
            }
            let selectedIDs: Set<String>
            do {
                selectedIDs = try activeIDs()
            } catch {
                throw AerialDropError.wallpaperSelectionUnknownForRemoval
            }
            guard !selectedIDs.contains(Self.dayNightSubcategoryID),
                  removedIDs.isDisjoint(with: selectedIDs) else {
                throw AerialDropError.activeWallpaperCannotBeRemoved
            }
        }

        try mutateManifest(
            operation: "remove-all",
            commitValidation: verifyActiveSelection
        ) { root in
            guard var assets = root["assets"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level assets array")
            }
            guard var categories = root["categories"] as? [[String: Any]] else {
                throw AerialDropError.malformedManifest("missing top-level categories array")
            }

            removesPair = try managedDayNightPair(in: root) != nil
            removedIDs = try managedAssetIDs(in: root)
            try verifyActiveSelection()

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

    private func makeAsset(
        id: String,
        title: String,
        preferredOrder: Int,
        width: Int = 0,
        height: Int = 0,
        pair: DayNightWallpaperPair? = nil
    ) -> [String: Any] {
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
            "subcategories": [pair?.memberAssetIDs.contains(id) == true
                ? Self.dayNightSubcategoryID
                : Self.subcategoryID],
            // Tahoe custom entries observed in a working catalogue use one freeze/transition marker.
            "pointsOfInterest": ["0": "\(shotID)_0"],
            "previewImage": paths.thumbnailURL(for: id).absoluteString,
            "url-4K-SDR-240FPS": paths.videoURL(for: id).absoluteString
        ]
        if width > 0 && height > 0 {
            asset["width"] = width
            asset["height"] = height
        }
        if id == pair?.dayAssetID {
            asset["variant"] = solarVariant(altitude: Self.daySolarAltitude)
        } else if id == pair?.nightAssetID {
            asset["variant"] = solarVariant(altitude: Self.nightSolarAltitude)
        }
        return asset
    }

    private func makeCategory(
        representativeAssetID id: String,
        managedAssetIDs: [String],
        pair: DayNightWallpaperPair?
    ) -> [String: Any] {
        let preview = paths.thumbnailURL(for: id).absoluteString
        let ordinaryIDs = managedAssetIDs.filter { pair?.memberAssetIDs.contains($0) != true }
        var subcategories = [[String: Any]]()
        if let ordinaryRepresentative = ordinaryIDs.contains(id) ? id : ordinaryIDs.first {
            subcategories.append([
                "id": Self.subcategoryID,
                "localizedNameKey": Self.categoryName,
                "localizedDescriptionKey": Self.categoryName,
                "preferredOrder": subcategories.count,
                "previewImage": paths.thumbnailURL(for: ordinaryRepresentative).absoluteString,
                "representativeAssetID": ordinaryRepresentative
            ])
        }
        if let pair {
            subcategories.append([
                "id": Self.dayNightSubcategoryID,
                "localizedNameKey": Self.dayNightName,
                "localizedDescriptionKey": Self.dayNightName,
                "preferredOrder": subcategories.count,
                "previewImage": paths.thumbnailURL(for: pair.dayAssetID).absoluteString,
                "representativeAssetID": pair.dayAssetID,
                "combineVariants": true
            ])
        }
        return [
            "id": Self.categoryID,
            "localizedNameKey": Self.categoryName,
            "localizedDescriptionKey": Self.categoryName,
            "preferredOrder": 0,
            "previewImage": preview,
            "representativeAssetID": id,
            "subcategories": subcategories
        ]
    }

    private func solarVariant(altitude: Int) -> [String: Any] {
        [
            "solar": [
                "altitude": altitude,
                "azimuth": Self.solarAzimuth
            ]
        ]
    }

    private func customShotID(for id: String) -> String {
        "CUSTOM_\(id.replacing("-", with: "_"))"
    }

    private func rebuildManagedCategory(
        _ categories: [[String: Any]],
        assets: [[String: Any]],
        preferredRepresentativeAssetID: String?,
        pair: DayNightWallpaperPair?
    ) -> [[String: Any]] {
        let managedIDs = assets.compactMap { asset -> String? in
            guard ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) else { return nil }
            return asset["id"] as? String
        }
        var rebuilt = categories.filter { ($0["id"] as? String) != Self.categoryID }
        guard let representative = preferredRepresentativeAssetID.flatMap({ managedIDs.contains($0) ? $0 : nil })
            ?? managedIDs.first else {
            return rebuilt
        }
        rebuilt.append(makeCategory(
            representativeAssetID: representative,
            managedAssetIDs: managedIDs,
            pair: pair
        ))
        return rebuilt
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
    private func normalizeManagedAssets(
        _ assets: [[String: Any]],
        preserving pair: DayNightWallpaperPair?
    ) throws -> [[String: Any]] {
        if let pair {
            for id in pair.memberAssetIDs {
                for url in [paths.videoURL(for: id), paths.thumbnailURL(for: id)] {
                    guard fileManager.fileExists(atPath: url.path) else {
                        throw AerialDropError.installedFileMissing(url)
                    }
                }
            }
        }
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
                height: assetHeight,
                pair: pair
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
        // and remove only our new backup if the operation has become unsafe.
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
                if latestData == candidateData {
                    if operation != "restore" {
                        throw AerialDropError.manifestMutationCommitted(
                            "Set another wallpaper before trying again. The safety backup \(backup.lastPathComponent) is available for recovery."
                        )
                    }
                    throw AerialDropError.backupRestoreCommitted(
                        "AerialDrop left the restored catalogue in place because undoing the write could overwrite a concurrent macOS catalogue update. The safety backup \(backup.lastPathComponent) was retained. Open Wallpaper Settings to check the active wallpaper; the backup remains available if a later restore passes the foreign-data checks."
                    )
                }
                if operation != "restore" {
                    throw AerialDropError.manifestMutationSuperseded(
                        "Reload the Library and check the current wallpaper before trying again. The safety backup \(backup.lastPathComponent) is available for recovery."
                    )
                }
                throw AerialDropError.backupRestoreSuperseded(
                    "AerialDrop kept the current catalogue untouched and retained the safety backup \(backup.lastPathComponent). Reload the Library to inspect the current entries."
                )
            } catch let outcome as AerialDropError {
                throw outcome
            } catch {
                if operation != "restore" {
                    throw AerialDropError.manifestMutationOutcomeUnknown(
                        "Reload the catalogue and check the current wallpaper before trying again. The safety backup \(backup.lastPathComponent) is available for recovery."
                    )
                }
                throw AerialDropError.backupRestoreOutcomeUnknown(
                    "AerialDrop could not read the catalogue after active-wallpaper verification failed. It did not attempt a rollback that could overwrite a concurrent update. The safety backup \(backup.lastPathComponent) was retained. Reload the catalogue before restoring again."
                )
            }
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
        guard (0...assets.count).contains(count) else {
            throw AerialDropError.malformedManifest(
                "initialAssetCount must be between 0 and the assets array count (\(assets.count))"
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
        try validateManagedIDs(in: candidateAssets)
        try validateDayNightIdentityCollisions(in: candidate)
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
        let pair = try managedDayNightPair(in: candidate)
        try validateManagedCategory(
            category,
            managedAssets: managedAssets,
            pair: pair
        )
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
        guard let subcategories = asset["subcategories"] as? [String],
              subcategories.count == 1,
              subcategories[0] == Self.subcategoryID || subcategories[0] == Self.dayNightSubcategoryID else {
            throw AerialDropError.malformedManifest("AerialDrop asset has the wrong subcategory")
        }
        if subcategories[0] == Self.subcategoryID, asset["variant"] != nil {
            throw AerialDropError.malformedManifest("ordinary AerialDrop asset contains unexpected variant metadata")
        }
        guard let points = asset["pointsOfInterest"] as? [String: String], points["0"] != nil else {
            throw AerialDropError.malformedManifest("AerialDrop asset is missing its transition point")
        }
    }

    private func validateManagedCategory(
        _ category: [String: Any],
        managedAssets: [[String: Any]],
        pair: DayNightWallpaperPair?
    ) throws {
        let validAssetIDs = Set(managedAssets.compactMap { $0["id"] as? String })
        guard
            let representative = category["representativeAssetID"] as? String,
            validAssetIDs.contains(representative),
            category["previewImage"] as? String == paths.thumbnailURL(for: representative).absoluteString,
            let subcategories = category["subcategories"] as? [[String: Any]]
        else {
            throw AerialDropError.malformedManifest("AerialDrop category metadata is incomplete")
        }

        let ordinaryIDs = validAssetIDs.subtracting(pair?.memberAssetIDs ?? [])
        let expectedSubcategoryCount = (ordinaryIDs.isEmpty ? 0 : 1) + (pair == nil ? 0 : 1)
        guard subcategories.count == expectedSubcategoryCount else {
            throw AerialDropError.malformedManifest("AerialDrop category has unexpected subcategories")
        }
        for (index, subcategory) in subcategories.enumerated() {
            guard integerValue(subcategory["preferredOrder"]) == index else {
                throw AerialDropError.malformedManifest("AerialDrop subcategory order is invalid")
            }
        }

        let ordinarySubcategories = subcategories.filter { ($0["id"] as? String) == Self.subcategoryID }
        if ordinaryIDs.isEmpty {
            guard ordinarySubcategories.isEmpty else {
                throw AerialDropError.malformedManifest("ordinary AerialDrop subcategory exists without ordinary assets")
            }
        } else {
            guard ordinarySubcategories.count == 1,
                  let ordinary = ordinarySubcategories.first,
                  let ordinaryRepresentative = ordinary["representativeAssetID"] as? String,
                  ordinaryIDs.contains(ordinaryRepresentative),
                  ordinary["previewImage"] as? String == paths.thumbnailURL(for: ordinaryRepresentative).absoluteString,
                  integerValue(ordinary["preferredOrder"]) != nil else {
                throw AerialDropError.malformedManifest("ordinary AerialDrop subcategory metadata is incomplete")
            }
        }

        let groupSubcategories = subcategories.filter { ($0["id"] as? String) == Self.dayNightSubcategoryID }
        guard groupSubcategories.count == (pair == nil ? 0 : 1) else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night subcategory is duplicated or missing")
        }
    }

    private enum SolarRole {
        case day
        case night
    }

    private func managedDayNightPair(in root: [String: Any]) throws -> DayNightWallpaperPair? {
        guard let assets = root["assets"] as? [[String: Any]],
              let categories = root["categories"] as? [[String: Any]] else {
            throw AerialDropError.malformedManifest("catalogue arrays could not be read for Day & Night")
        }
        try validateDayNightIdentityCollisions(in: root)

        let managedAssets = assets.filter {
            (($0["categories"] as? [String]) ?? []).contains(Self.categoryID)
        }
        let managedCategories = categories.filter { ($0["id"] as? String) == Self.categoryID }
        guard managedCategories.count <= 1 else {
            throw AerialDropError.malformedManifest("AerialDrop category is duplicated")
        }

        let ownedSubcategories = (managedCategories.first?["subcategories"] as? [[String: Any]]) ?? []
        let groups = ownedSubcategories.filter { ($0["id"] as? String) == Self.dayNightSubcategoryID }
        let groupMembers = managedAssets.filter {
            (($0["subcategories"] as? [String]) ?? []).contains(Self.dayNightSubcategoryID)
        }

        guard !groups.isEmpty else {
            guard groupMembers.isEmpty,
                  managedAssets.allSatisfy({ $0["variant"] == nil }) else {
                throw AerialDropError.malformedManifest("AerialDrop Day & Night metadata is partial")
            }
            return nil
        }
        guard groups.count == 1, let group = groups.first else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night subcategory is duplicated")
        }
        guard groupMembers.count == 2 else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night must contain exactly two assets")
        }

        let expectedGroupKeys: Set<String> = [
            "id", "localizedNameKey", "localizedDescriptionKey", "preferredOrder",
            "previewImage", "representativeAssetID", "combineVariants"
        ]
        guard Set(group.keys) == expectedGroupKeys,
              group["localizedNameKey"] as? String == Self.dayNightName,
              group["localizedDescriptionKey"] as? String == Self.dayNightName,
              booleanValue(group["combineVariants"]) == true,
              integerValue(group["preferredOrder"]) != nil else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night subcategory metadata is invalid")
        }

        var dayID: String?
        var nightID: String?
        for asset in groupMembers {
            guard let id = asset["id"] as? String,
                  asset["subcategories"] as? [String] == [Self.dayNightSubcategoryID] else {
                throw AerialDropError.malformedManifest("AerialDrop Day & Night member has invalid subcategories")
            }
            switch try solarRole(in: asset) {
            case .day:
                guard dayID == nil else {
                    throw AerialDropError.malformedManifest("AerialDrop Day & Night has duplicate Day members")
                }
                dayID = id
            case .night:
                guard nightID == nil else {
                    throw AerialDropError.malformedManifest("AerialDrop Day & Night has duplicate Night members")
                }
                nightID = id
            }
        }

        guard let dayID, let nightID, dayID != nightID else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night roles are incomplete")
        }
        guard group["representativeAssetID"] as? String == dayID,
              group["previewImage"] as? String == paths.thumbnailURL(for: dayID).absoluteString else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night representative must be the Day asset")
        }

        let pair = DayNightWallpaperPair(dayAssetID: dayID, nightAssetID: nightID)
        for id in pair.memberAssetIDs {
            guard assets.filter({ ($0["id"] as? String) == id }).count == 1 else {
                throw AerialDropError.malformedManifest(
                    "AerialDrop Day & Night member ID is not unique across the catalogue"
                )
            }
        }
        for asset in managedAssets where !pair.memberAssetIDs.contains(asset["id"] as? String ?? "") {
            guard asset["variant"] == nil,
                  asset["subcategories"] as? [String] == [Self.subcategoryID] else {
                throw AerialDropError.malformedManifest("unpaired AerialDrop asset contains Day & Night metadata")
            }
        }
        return pair
    }

    private func solarRole(in asset: [String: Any]) throws -> SolarRole {
        guard let variant = asset["variant"] as? [String: Any],
              Set(variant.keys) == ["solar"],
              let solar = variant["solar"] as? [String: Any],
              Set(solar.keys) == ["altitude", "azimuth"],
              let altitude = integerValue(solar["altitude"]),
              let azimuth = integerValue(solar["azimuth"]),
              azimuth == Self.solarAzimuth else {
            throw AerialDropError.malformedManifest("AerialDrop Day & Night member has invalid solar metadata")
        }
        switch altitude {
        case Self.daySolarAltitude:
            return .day
        case Self.nightSolarAltitude:
            return .night
        default:
            throw AerialDropError.malformedManifest("AerialDrop Day & Night member has an unsupported solar altitude")
        }
    }

    private func validateDayNightIdentityCollisions(in root: [String: Any]) throws {
        guard let assets = root["assets"] as? [[String: Any]],
              let categories = root["categories"] as? [[String: Any]] else { return }
        for asset in assets {
            let isManaged = ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID)
            if asset["id"] as? String == Self.dayNightSubcategoryID
                || (!isManaged && ((asset["subcategories"] as? [String]) ?? []).contains(Self.dayNightSubcategoryID)) {
                throw AerialDropError.malformedManifest("AerialDrop Day & Night identity collides with a foreign asset")
            }
        }
        for category in categories where (category["id"] as? String) != Self.categoryID {
            let subcategories = (category["subcategories"] as? [[String: Any]]) ?? []
            if category["id"] as? String == Self.dayNightSubcategoryID
                || subcategories.contains(where: { ($0["id"] as? String) == Self.dayNightSubcategoryID }) {
                throw AerialDropError.malformedManifest("AerialDrop Day & Night identity collides with a foreign category")
            }
        }
    }

    private func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func validateManagedIDs(in assets: [[String: Any]]) throws {
        var seen = Set<String>()
        for asset in assets where ((asset["categories"] as? [String]) ?? []).contains(Self.categoryID) {
            guard let id = asset["id"] as? String else {
                throw AerialDropError.malformedManifest("AerialDrop asset is missing 'id'")
            }
            try validateManagedID(id)
            guard seen.insert(id).inserted else {
                throw AerialDropError.malformedManifest("AerialDrop asset ID '\(id)' is duplicated")
            }
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
