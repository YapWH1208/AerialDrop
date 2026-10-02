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

    let paths: WallpaperPaths
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

    /// Raw configuration references, without expanding manifest group members.
    /// Unfamiliar option payloads cannot hide references from removal protection.
    func activeAerialAssetIDs() throws -> Set<String> {
        try inspectAerialSelections().rawAssetIDs
    }

    func inspectAerialSelections() throws -> AerialSelectionInspection {
        try inspectAerialSelections(in: root(from: selectionStoreData()))
    }

    func verifyAerialSelection(assetID: String, requiringSpaceIDs: Set<String> = []) throws {
        try verifySelection(.single(assetID: assetID), requiringSpaceIDs: requiringSpaceIDs)
    }

    /// Verifies identity and exact decoded options independently for every target.
    func verifySelection(
        _ selection: AerialSelectionRequest,
        requiringSpaceIDs: Set<String> = []
    ) throws {
        let root = try root(from: try selectionStoreData())
        try verifySelection(selection, in: root, requiringSpaceIDs: requiringSpaceIDs)
    }

    @discardableResult
    func apply(assetID: String) throws -> Set<String> {
        try apply(.single(assetID: assetID))
    }

    /// Checks that the current store can safely accept this request, without
    /// invoking mutation hooks, creating a backup, or writing either store.
    /// Existing selections need not already use the Aerial provider.
    func validateForApplying(_ selection: AerialSelectionRequest) throws {
        try validateIdentity(of: selection)
        let originalRoot = try root(from: try selectionStoreData())
        _ = try preparedApplication(selection, to: originalRoot)
    }

    /// Replaces linked targets while retaining unrelated plist values and the
    /// independent backup/compare-before-write contract.
    @discardableResult
    func apply(_ selection: AerialSelectionRequest) throws -> Set<String> {
        try validateIdentity(of: selection)
        let originalData = try selectionStoreData()
        let originalRoot = try root(from: originalData)
        let (candidateData, requiredSpaceIDs) = try preparedApplication(selection, to: originalRoot)

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
        try verifySelection(selection, in: writtenRoot, requiringSpaceIDs: requiredSpaceIDs)
        return requiredSpaceIDs
    }

    private func validateIdentity(of selection: AerialSelectionRequest) throws {
        guard UUID(uuidString: selection.assetID) != nil else {
            throw AerialDropError.malformedWallpaperSelectionStore("asset ID is not a UUID")
        }
    }

    private func preparedApplication(
        _ selection: AerialSelectionRequest,
        to originalRoot: [String: Any]
    ) throws -> (Data, Set<String>) {
        let candidateRoot = try applying(selection, to: originalRoot)
        let requiredSpaceIDs = try defaultSpaceIDs(in: originalRoot)
        try validatePreservation(from: originalRoot, to: candidateRoot)
        let candidateData = try propertyListData(from: candidateRoot)
        let decodedCandidate = try root(from: candidateData)
        try verifySelection(selection, in: decodedCandidate, requiringSpaceIDs: requiredSpaceIDs)
        return (candidateData, requiredSpaceIDs)
    }

    private func verifySelection(
        _ selection: AerialSelectionRequest,
        in root: [String: Any],
        requiringSpaceIDs: Set<String>
    ) throws {
        guard try requiringSpaceIDs.isSubset(of: defaultSpaceIDs(in: root)),
              try inspectAerialSelections(in: root).matches(selection) else {
            throw AerialDropError.wallpaperSelectionVerificationFailed(selection.assetID)
        }
    }

    private func inspectAerialSelections(in root: [String: Any]) throws -> AerialSelectionInspection {
        let targets = try targetSelections(in: root).map { target, selection in
            AerialTargetSelection(
                target: target,
                rawAssetIDs: try aerialAssetIDs(in: selection),
                recognizedSelection: recognizedSelection(in: selection)
            )
        }
        return AerialSelectionInspection(targets: targets)
    }

    /// Unknown options are observable without discarding raw configuration IDs.
    /// Exact semantic comparison prevents accepting a group in a fixed mode.
    private func recognizedSelection(in selection: [String: Any]) -> AerialSelectionRequest? {
        guard selection["Type"] as? String == "linked",
              let linked = selection["Linked"] as? [String: Any],
              let content = linked["Content"] as? [String: Any],
              content["Shuffle"] as? String == "$null",
              let choices = content["Choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first,
              choice["Provider"] as? String == Self.aerialProvider,
              let files = choice["Files"] as? [Any], files.isEmpty,
              let configurationData = choice["Configuration"] as? Data,
              let configuration = try? root(from: configurationData),
              configuration.count == 1,
              let assetID = configuration["assetID"] as? String,
              UUID(uuidString: assetID) != nil,
              let optionsData = content["EncodedOptionValues"] as? Data,
              let options = try? root(from: optionsData) else { return nil }

        for request in [
            AerialSelectionRequest.single(assetID: assetID),
            .fixedVariant(assetID: assetID),
            .automatic(groupID: assetID)
        ] where propertyListValuesEqual(options, optionValues(for: request)) {
            return request
        }
        return nil
    }

    private func defaultSpaceIDs(in root: [String: Any]) throws -> Set<String> {
        guard let spaces = root[Self.spacesKey] as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing top-level Spaces dictionary")
        }
        return Set(try spaces.compactMap { spaceID, value -> String? in
            guard let space = value as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' is not a dictionary")
            }
            return space[Self.defaultKey] == nil ? nil : spaceID
        })
    }

    private func applying(_ request: AerialSelectionRequest, to root: [String: Any]) throws -> [String: Any] {
        let timestamp = now()
        var candidate = root
        candidate[Self.allSpacesAndDisplaysKey] = try replacingSelection(
            try requiredSelection(named: Self.allSpacesAndDisplaysKey, in: root),
            request: request,
            timestamp: timestamp
        )
        candidate[Self.systemDefaultKey] = try replacingSelection(
            try requiredSelection(named: Self.systemDefaultKey, in: root),
            request: request,
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
            space[Self.defaultKey] = try replacingSelection(selection, request: request, timestamp: timestamp)
            spaces[spaceID] = space
        }
        candidate[Self.spacesKey] = spaces
        return candidate
    }

    private func targetSelections(in root: [String: Any]) throws -> [(AerialSelectionTarget, [String: Any])] {
        var selections: [(AerialSelectionTarget, [String: Any])] = [
            (.allSpacesAndDisplays, try requiredSelection(named: Self.allSpacesAndDisplaysKey, in: root)),
            (.systemDefault, try requiredSelection(named: Self.systemDefaultKey, in: root))
        ]
        guard let spaces = root[Self.spacesKey] as? [String: Any] else {
            throw AerialDropError.malformedWallpaperSelectionStore("missing top-level Spaces dictionary")
        }
        for (spaceID, value) in spaces.sorted(by: { $0.key < $1.key }) {
            guard let space = value as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' is not a dictionary")
            }
            guard let defaultSelection = space[Self.defaultKey] else {
                continue
            }
            guard let selection = defaultSelection as? [String: Any] else {
                throw AerialDropError.malformedWallpaperSelectionStore("Space '\(spaceID)' Default is not a dictionary")
            }
            selections.append((.space(spaceID), selection))
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
        request: AerialSelectionRequest,
        timestamp: Date
    ) throws -> [String: Any] {
        var replacement = original
        replacement["Type"] = "linked"
        replacement["Linked"] = try linkedSelection(request, timestamp: timestamp)
        return replacement
    }

    /// Fixture-locked Tahoe and observed macOS 27 variant option payloads.
    private func linkedSelection(_ request: AerialSelectionRequest, timestamp: Date) throws -> [String: Any] {
        let configuration = try propertyListData(from: ["assetID": request.assetID])
        let options = try propertyListData(from: optionValues(for: request))
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

    private func optionValues(for request: AerialSelectionRequest) -> [String: Any] {
        switch request {
        case .single:
            return ["values": [String: Any]()]
        case .fixedVariant(let assetID):
            return ["values": ["aerialVariant": ["picker": ["_0": ["id": assetID]]]]]
        case .automatic:
            return ["values": ["aerialVariant": ["picker": ["_0": ["id": "automatic"]]]]]
        }
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
            guard let assetID = decodedConfiguration["assetID"] as? String,
                  UUID(uuidString: assetID) != nil
            else {
                throw AerialDropError.malformedWallpaperSelectionStore("native Aerial Configuration does not contain a UUID assetID")
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
