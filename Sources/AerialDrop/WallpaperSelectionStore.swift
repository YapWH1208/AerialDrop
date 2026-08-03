import Foundation

struct WallpaperSelectionStore {
    private let paths: WallpaperPaths
    private let fileManager = FileManager.default

    init(paths: WallpaperPaths) {
        self.paths = paths
    }

    /// Converts every current Desktop presentation that selects an AerialDrop asset into
    /// Tahoe's native `linked` representation. A linked presentation is what WallpaperAgent
    /// resolves as `useAsBoth:true`; merely copying Desktop into Idle leaves the store as
    /// `individual` and does not provide native Aerial continuity.
    func linkSelectedManagedWallpaper(managedIDs: Set<String>) throws -> String {
        guard fileManager.fileExists(atPath: paths.storeIndex.path) else {
            throw AerialDropError.missingWallpaperStore(paths.storeIndex)
        }

        let originalData = try Data(contentsOf: paths.storeIndex)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(
                from: originalData,
                options: [.mutableContainersAndLeaves],
                format: &format
            )
        } catch {
            throw AerialDropError.malformedWallpaperStore(error.localizedDescription)
        }
        guard var root = object as? [String: Any] else {
            throw AerialDropError.malformedWallpaperStore("the top level is not a dictionary")
        }

        var linkedIDs = Set<String>()
        mutateRoot(&root, managedIDs: managedIDs, linkedIDs: &linkedIDs)
        guard linkedIDs.count == 1, let selectedID = linkedIDs.first else {
            if linkedIDs.isEmpty {
                throw AerialDropError.noManagedDesktopSelection
            }
            throw AerialDropError.multipleManagedDesktopSelections(linkedIDs.sorted())
        }

        guard PropertyListSerialization.propertyList(root, isValidFor: format) else {
            throw AerialDropError.malformedWallpaperStore("the updated property list is invalid")
        }
        let candidateData = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: format,
            options: 0
        )

        let latestData = try Data(contentsOf: paths.storeIndex)
        guard latestData == originalData else {
            throw AerialDropError.wallpaperStoreChangedDuringOperation
        }

        try fileManager.createDirectory(at: paths.storeBackups, withIntermediateDirectories: true)
        let backupURL = paths.storeBackups.appendingPathComponent(
            "Index-\(timestamp())-pre-native-link.plist",
            isDirectory: false
        )
        try originalData.write(to: backupURL, options: .atomic)
        try candidateData.write(to: paths.storeIndex, options: .atomic)

        let writtenData = try Data(contentsOf: paths.storeIndex)
        guard writtenData == candidateData else {
            throw AerialDropError.wallpaperStoreChangedDuringOperation
        }
        try validateLinkedStore(data: writtenData, managedID: selectedID)
        return selectedID
    }

    /// Reopens Index.plist after WallpaperAgent has restarted and confirms that the linked
    /// representation survived the restart instead of being replaced by the agent's old
    /// in-memory `individual` value.
    func validatePersistedNativeLink(managedID: String) throws {
        guard fileManager.fileExists(atPath: paths.storeIndex.path) else {
            throw AerialDropError.missingWallpaperStore(paths.storeIndex)
        }
        let data = try Data(contentsOf: paths.storeIndex)
        try validateLinkedStore(data: data, managedID: managedID)
    }

    func restoreLatestBackup() throws {
        guard fileManager.fileExists(atPath: paths.storeBackups.path) else {
            throw AerialDropError.noWallpaperStoreBackup
        }

        let candidates = try fileManager.contentsOfDirectory(
            at: paths.storeBackups,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "plist" }
        .sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }

        guard let latest = candidates.first else {
            throw AerialDropError.noWallpaperStoreBackup
        }

        let backupData = try Data(contentsOf: latest)
        var format = PropertyListSerialization.PropertyListFormat.binary
        _ = try PropertyListSerialization.propertyList(from: backupData, options: [], format: &format)

        if fileManager.fileExists(atPath: paths.storeIndex.path) {
            let currentData = try Data(contentsOf: paths.storeIndex)
            let safetyURL = paths.storeBackups.appendingPathComponent(
                "Index-\(timestamp())-pre-restore.plist",
                isDirectory: false
            )
            try currentData.write(to: safetyURL, options: .atomic)
        }
        try backupData.write(to: paths.storeIndex, options: .atomic)
    }

    private func mutateRoot(
        _ root: inout [String: Any],
        managedIDs: Set<String>,
        linkedIDs: inout Set<String>
    ) {
        if var settings = root["AllSpacesAndDisplays"] as? [String: Any] {
            mutateSettings(&settings, managedIDs: managedIDs, linkedIDs: &linkedIDs)
            root["AllSpacesAndDisplays"] = settings
        }

        if var settings = root["SystemDefault"] as? [String: Any] {
            mutateSettings(&settings, managedIDs: managedIDs, linkedIDs: &linkedIDs)
            root["SystemDefault"] = settings
        }

        if var displays = root["Displays"] as? [String: Any] {
            for key in displays.keys.sorted() {
                guard var settings = displays[key] as? [String: Any] else { continue }
                mutateSettings(&settings, managedIDs: managedIDs, linkedIDs: &linkedIDs)
                displays[key] = settings
            }
            root["Displays"] = displays
        }

        if var spaces = root["Spaces"] as? [String: Any] {
            for spaceKey in spaces.keys.sorted() {
                guard var space = spaces[spaceKey] as? [String: Any] else { continue }

                if var settings = space["Default"] as? [String: Any] {
                    mutateSettings(&settings, managedIDs: managedIDs, linkedIDs: &linkedIDs)
                    space["Default"] = settings
                }

                if var displays = space["Displays"] as? [String: Any] {
                    for displayKey in displays.keys.sorted() {
                        guard var settings = displays[displayKey] as? [String: Any] else { continue }
                        mutateSettings(&settings, managedIDs: managedIDs, linkedIDs: &linkedIDs)
                        displays[displayKey] = settings
                    }
                    space["Displays"] = displays
                }

                spaces[spaceKey] = space
            }
            root["Spaces"] = spaces
        }
    }

    private func mutateSettings(
        _ settings: inout [String: Any],
        managedIDs: Set<String>,
        linkedIDs: inout Set<String>
    ) {
        if settings["Type"] as? String == "linked",
           let linked = settings["Linked"] as? [String: Any],
           let linkedID = assetID(from: linked),
           managedIDs.contains(linkedID) {
            linkedIDs.insert(linkedID)
            return
        }

        guard let desktop = settings["Desktop"] as? [String: Any],
              let selectedID = assetID(from: desktop),
              managedIDs.contains(selectedID),
              var linkedContent = desktop["Content"] as? [String: Any] else {
            return
        }

        // The linked records already created by Tahoe use a null option payload. Keeping the
        // Desktop crop/color payload here makes WallpaperAgent resolve an individual pair even
        // if Desktop and Idle point to the same asset.
        linkedContent["EncodedOptionValues"] = "$null"

        let now = Date()
        var linked = desktop
        linked["Content"] = linkedContent
        linked["LastSet"] = now
        linked["LastUse"] = now

        settings["Linked"] = linked
        settings["Type"] = "linked"
        settings.removeValue(forKey: "Desktop")
        settings.removeValue(forKey: "Idle")
        linkedIDs.insert(selectedID)
    }

    private func assetID(from presentation: [String: Any]) -> String? {
        guard let content = presentation["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let choice = choices.first,
              let data = choice["Configuration"] as? Data else {
            return nil
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let configuration = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            return nil
        }
        return configuration["assetID"] as? String
    }

    private func validateLinkedStore(data: Data, managedID: String) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw AerialDropError.malformedWallpaperStore("the written store could not be reopened")
        }

        var matchingLinkedRecords = 0
        var remainingIndividualRecords = 0
        inspectRoot(root) { settings in
            if settings["Type"] as? String == "linked",
               let linked = settings["Linked"] as? [String: Any],
               assetID(from: linked) == managedID {
                matchingLinkedRecords += 1
            }

            if let desktop = settings["Desktop"] as? [String: Any], assetID(from: desktop) == managedID {
                remainingIndividualRecords += 1
            }
            if let idle = settings["Idle"] as? [String: Any], assetID(from: idle) == managedID {
                remainingIndividualRecords += 1
            }
        }

        guard matchingLinkedRecords > 0, remainingIndividualRecords == 0 else {
            throw AerialDropError.nativeLinkDidNotPersist(
                linkedRecords: matchingLinkedRecords,
                individualRecords: remainingIndividualRecords
            )
        }
    }

    private func inspectRoot(_ root: [String: Any], visit: ([String: Any]) -> Void) {
        if let settings = root["AllSpacesAndDisplays"] as? [String: Any] { visit(settings) }
        if let settings = root["SystemDefault"] as? [String: Any] { visit(settings) }
        if let displays = root["Displays"] as? [String: Any] {
            for value in displays.values {
                if let settings = value as? [String: Any] { visit(settings) }
            }
        }
        if let spaces = root["Spaces"] as? [String: Any] {
            for value in spaces.values {
                guard let space = value as? [String: Any] else { continue }
                if let settings = space["Default"] as? [String: Any] { visit(settings) }
                if let displays = space["Displays"] as? [String: Any] {
                    for displayValue in displays.values {
                        if let settings = displayValue as? [String: Any] { visit(settings) }
                    }
                }
            }
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
