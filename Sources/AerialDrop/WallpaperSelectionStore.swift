import Foundation

/// Safely reads and updates the private Tahoe wallpaper selection store.
///
/// This type deliberately owns `Index.plist` separately from `ManifestStore`:
/// the two Apple-owned formats have unrelated preservation contracts.
struct WallpaperSelectionStore {
    static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    private static let allSpacesAndDisplaysKey = "AllSpacesAndDisplays"
    private static let systemDefaultKey = "SystemDefault"
    private static let spacesKey = "Spaces"
    private static let defaultKey = "Default"

    private let paths: WallpaperPaths
    private let fileManager: FileManager
    private let now: () -> Date
    private let beforeCompare: () throws -> Void
    private let afterWrite: () throws -> Void

    init(
        paths: WallpaperPaths = WallpaperPaths(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() },
        beforeCompare: @escaping () throws -> Void = {},
        afterWrite: @escaping () throws -> Void = {}
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.now = now
        self.beforeCompare = beforeCompare
        self.afterWrite = afterWrite
    }

    /// Returns native Aerial IDs configured in the global, system-default, and
    /// existing per-Space selections. Non-Aerial selections are ignored.
    func activeAerialAssetIDs() throws -> Set<String> {
        let root = try root(from: try selectionStoreData())
        return Set(try targetSelections(in: root).flatMap { try aerialAssetIDs(in: $0) })
    }

    /// Replaces every linked selection target with the fixture-locked native
    /// Aerial form, preserving every other property-list value in the store.
    func apply(assetID: String) throws {
        guard UUID(uuidString: assetID) != nil else {
            throw AerialDropError.malformedWallpaperSelectionStore("asset ID is not a UUID")
        }

        let originalData = try selectionStoreData()
        let originalRoot = try root(from: originalData)
        let candidateRoot = try applying(assetID: assetID, to: originalRoot)
        try validatePreservation(from: originalRoot, to: candidateRoot)
        let candidateData = try propertyListData(from: candidateRoot)
        _ = try root(from: candidateData)

        try beforeCompare()
        let latestData = try selectionStoreData()
        guard latestData == originalData else {
            throw AerialDropError.wallpaperSelectionStoreChangedDuringOperation
        }

        _ = try backup(data: originalData)
        try candidateData.write(to: paths.selectionStore, options: .atomic)
        try afterWrite()

        let writtenRoot = try root(from: try selectionStoreData())
        try validatePreservation(from: originalRoot, to: writtenRoot)
        guard try Set(targetSelections(in: writtenRoot).flatMap { try aerialAssetIDs(in: $0) }) == Set([assetID]) else {
            throw AerialDropError.wallpaperSelectionVerificationFailed(assetID)
        }
    }

    private func applying(assetID: String, to root: [String: Any]) throws -> [String: Any] {
        let timestamp = now()
        var candidate = root
        candidate[Self.allSpacesAndDisplaysKey] = try replacingSelection(
            try requiredSelection(named: Self.allSpacesAndDisplaysKey, in: root),
            assetID: assetID,
            timestamp: timestamp
        )
        candidate[Self.systemDefaultKey] = try replacingSelection(
            try requiredSelection(named: Self.systemDefaultKey, in: root),
            assetID: assetID,
            timestamp: timestamp
        )

        guard var spaces = root[Self.spacesKey] as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing top-level Spaces dictionary")
        }
        for spaceID in Array(spaces.keys) {
            guard var space = spaces[spaceID] as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' is not a dictionary")
            }
            guard let defaultSelection = space[Self.defaultKey] else {
                continue
            }
            guard let selection = defaultSelection as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' Default is not a dictionary")
            }
            space[Self.defaultKey] = try replacingSelection(selection, assetID: assetID, timestamp: timestamp)
            spaces[spaceID] = space
        }
        candidate[Self.spacesKey] = spaces
        return candidate
    }

    private func targetSelections(in root: [String: Any]) throws -> [[String: Any]] {
        var selections = [
            try requiredSelection(named: Self.allSpacesAndDisplaysKey, in: root),
            try requiredSelection(named: Self.systemDefaultKey, in: root)
        ]
        guard let spaces = root[Self.spacesKey] as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing top-level Spaces dictionary")
        }
        for (spaceID, value) in spaces {
            guard let space = value as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' is not a dictionary")
            }
            guard let defaultSelection = space[Self.defaultKey] else {
                continue
            }
            guard let selection = defaultSelection as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' Default is not a dictionary")
            }
            selections.append(selection)
        }
        return selections
    }

    private func requiredSelection(named name: String, in root: [String: Any]) throws -> [String: Any] {
        guard let selection = root[name] as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing '\(name)' selection")
        }
        return selection
    }

    private func replacingSelection(
        _ original: [String: Any],
        assetID: String,
        timestamp: Date
    ) throws -> [String: Any] {
        var replacement = original
        replacement["Type"] = "linked"
        replacement["Linked"] = try linkedSelection(assetID: assetID, timestamp: timestamp)
        return replacement
    }

    /// This is the exact sanitized Tahoe fixture shape: one native Aerial
    /// choice, an `assetID` configuration plist, empty encoded options, and
    /// the `$null` shuffle marker. Only the asset ID and timestamps vary.
    private func linkedSelection(assetID: String, timestamp: Date) throws -> [String: Any] {
        let configuration = try propertyListData(from: ["assetID": assetID])
        let options = try propertyListData(from: ["values": [String: Any]()])
        return [
            "Content": [
                "Choices": [[
                    "Configuration": configuration,
                    "Files": [Any](),
                    "Provider": Self.aerialProvider
                ]],
                "EncodedOptionValues": options,
                "Shuffle": "$null"
            ],
            "LastSet": timestamp,
            "LastUse": timestamp
        ]
    }

    /// Returns the Aerial asset IDs referenced by a linked selection. A
    /// shuffle-mode selection legitimately carries several aerial choices, so
    /// every matching ID is returned rather than treated as malformed.
    private func aerialAssetIDs(in selection: [String: Any]) throws -> Set<String> {
        guard selection["Type"] as? String == "linked" else {
            return []
        }
        guard let linked = selection["Linked"] as? [String: Any],
              let content = linked["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]]
        else {
            throw AerialDropError.malformedWallpaperSelectionStore("linked selection is incomplete")
        }
        var assetIDs: Set<String> = []
        for choice in choices where (choice["Provider"] as? String) == Self.aerialProvider {
            guard let configuration = choice["Configuration"] as? Data else {
                throw AerialDropError.malformedWallpaperSelectionStore("native Aerial choice is missing Configuration")
            }
            let decodedConfiguration = try root(from: configuration)
            guard decodedConfiguration.count == 1,
                  let assetID = decodedConfiguration["assetID"] as? String,
                  UUID(uuidString: assetID) != nil
            else {
                throw AerialDropError.malformedWallpaperSelectionStore("native Aerial Configuration does not contain exactly one UUID assetID")
            }
            assetIDs.insert(assetID)
        }
        return assetIDs
    }

    private func validatePreservation(from original: [String: Any], to candidate: [String: Any]) throws {
        let targetRootKeys: Set<String> = [
            Self.allSpacesAndDisplaysKey,
            Self.systemDefaultKey,
            Self.spacesKey
        ]
        for (key, value) in original where !targetRootKeys.contains(key) {
            guard let candidateValue = candidate[key], propertyListValuesEqual(value, candidateValue) else {
                throw AerialDropError.foreignWallpaperSelectionDataChanged("top-level key '\(key)'")
            }
        }

        for key in [Self.allSpacesAndDisplaysKey, Self.systemDefaultKey] {
            let originalSelection = try requiredSelection(named: key, in: original)
            let candidateSelection = try requiredSelection(named: key, in: candidate)
            try validateSelectionPreservation(
                from: originalSelection,
                to: candidateSelection,
                description: "\(key) selection"
            )
        }

        guard let originalSpaces = original[Self.spacesKey] as? [String: Any],
              let candidateSpaces = candidate[Self.spacesKey] as? [String: Any]
        else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing top-level Spaces dictionary")
        }
        for (spaceID, originalValue) in originalSpaces {
            guard let originalSpace = originalValue as? [String: Any],
                  let candidateSpace = candidateSpaces[spaceID] as? [String: Any]
            else {
                throw AerialDropError.foreignWallpaperSelectionDataChanged("Space '\(spaceID)'")
            }
            for (key, value) in originalSpace where key != Self.defaultKey {
                guard let candidateValue = candidateSpace[key], propertyListValuesEqual(value, candidateValue) else {
                    throw AerialDropError.foreignWallpaperSelectionDataChanged("Space '\(spaceID)' key '\(key)'")
                }
            }
            if let originalDefault = originalSpace[Self.defaultKey] {
                guard let originalSelection = originalDefault as? [String: Any],
                      let candidateSelection = candidateSpace[Self.defaultKey] as? [String: Any]
                else {
                    throw AerialDropError.foreignWallpaperSelectionDataChanged("Space '\(spaceID)' Default")
                }
                try validateSelectionPreservation(
                    from: originalSelection,
                    to: candidateSelection,
                    description: "Space '\(spaceID)' Default"
                )
            }
        }
    }

    private func validateSelectionPreservation(
        from original: [String: Any],
        to candidate: [String: Any],
        description: String
    ) throws {
        for (key, value) in original where key != "Type" && key != "Linked" {
            guard let candidateValue = candidate[key], propertyListValuesEqual(value, candidateValue) else {
                throw AerialDropError.foreignWallpaperSelectionDataChanged("\(description) key '\(key)'")
            }
        }
    }

    private func selectionStoreData() throws -> Data {
        guard fileManager.fileExists(atPath: paths.selectionStore.path) else {
            throw AerialDropError.missingWallpaperSelectionStore(paths.selectionStore)
        }
        do {
            return try Data(contentsOf: paths.selectionStore)
        } catch {
            throw AerialDropError.malformedWallpaperSelectionStore("could not read Index.plist: \(error.localizedDescription)")
        }
    }

    private func root(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw AerialDropError.malformedWallpaperSelectionStore("invalid property list: \(error.localizedDescription)")
        }
        guard let root = object as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("top level is not a dictionary")
        }
        return root
    }

    private func propertyListData(from root: [String: Any]) throws -> Data {
        guard PropertyListSerialization.propertyList(root, isValidFor: .binary) else {
            throw AerialDropError.malformedWallpaperSelectionStore("generated property list is invalid")
        }
        do {
            return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        } catch {
            throw AerialDropError.malformedWallpaperSelectionStore("could not encode property list: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func backup(data: Data) throws -> URL {
        try fileManager.createDirectory(at: paths.selectionBackups, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: now())
        var backup = paths.selectionBackups.appending(path: "Index-\(timestamp)-apply.plist")
        var suffix = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = paths.selectionBackups.appending(path: "Index-\(timestamp)-apply-\(suffix).plist")
            suffix += 1
        }
        try data.write(to: backup, options: .atomic)
        return backup
    }

    private func propertyListValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (left as [String: Any], right as [String: Any]):
            return left.count == right.count && left.allSatisfy { key, value in
                right[key].map { propertyListValuesEqual(value, $0) } ?? false
            }
        case let (left as [Any], right as [Any]):
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy { propertyListValuesEqual($0, $1) }
        case let (left as Data, right as Data):
            return left == right
        case let (left as Date, right as Date):
            return left == right
        case let (left as String, right as String):
            return left == right
        case let (left as NSNumber, right as NSNumber):
            return String(cString: left.objCType) == String(cString: right.objCType) && left == right
        default:
            return false
        }
    }
}
