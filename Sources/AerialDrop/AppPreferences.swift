import Foundation

enum AppPreferences {
    static let setWallpaperAfterImportKey = "setWallpaperAfterImport"
    static let lastConversionQualityKey = "lastConversionQuality"
    static let lastOutputHeightCapKey = "lastOutputHeightCap"
    static let dayNightDraftKey = "dayNightWallpaperDraft"
    static let pendingDayNightAssetIDsKey = "pendingDayNightAssetIDs"

    static func dayNightDraft(defaults: UserDefaults = .standard) throws -> DayNightWallpaperDraft {
        guard let stored = defaults.object(forKey: dayNightDraftKey) else {
            return DayNightWallpaperDraft()
        }
        guard let values = stored as? [String: Any],
              Set(values.keys).isSubset(of: ["dayAssetID", "nightAssetID"]) else {
            throw AerialDropError.dayNightPreferencesInvalid
        }
        func role(_ key: String) throws -> String? {
            guard let value = values[key] else { return nil }
            guard let id = value as? String, UUID(uuidString: id) != nil else {
                throw AerialDropError.dayNightPreferencesInvalid
            }
            return id
        }
        return try DayNightWallpaperDraft(dayAssetID: role("dayAssetID"), nightAssetID: role("nightAssetID"))
    }

    static func setDayNightDraft(
        _ draft: DayNightWallpaperDraft,
        defaults: UserDefaults = .standard,
        flush: (UserDefaults) -> Bool = { $0.synchronize() }
    ) throws {
        try validateDayNightIDs(Set([draft.dayAssetID, draft.nightAssetID].compactMap { $0 }))
        let old = defaults.object(forKey: dayNightDraftKey)
        var values: [String: String] = [:]
        values["dayAssetID"] = draft.dayAssetID
        values["nightAssetID"] = draft.nightAssetID
        defaults.set(values, forKey: dayNightDraftKey)
        guard flush(defaults), (try? dayNightDraft(defaults: defaults)) == draft else {
            restorePreference(old, key: dayNightDraftKey, defaults: defaults)
            _ = flush(defaults)
            restorePreference(old, key: dayNightDraftKey, defaults: defaults)
            throw AerialDropError.dayNightPreferencesWriteFailed
        }
    }

    /// A durable conservative guard retained until a native generation proves
    /// the applied pair. A malformed guard is never interpreted as empty.
    static func pendingDayNightAssetIDs(defaults: UserDefaults = .standard) throws -> Set<String> {
        try decodedDayNightIDs(defaults.object(forKey: pendingDayNightAssetIDsKey))
    }

    private static func decodedDayNightIDs(_ stored: Any?) throws -> Set<String> {
        guard let stored else { return [] }
        guard let values = stored as? [String] else {
            throw AerialDropError.dayNightPreferencesInvalid
        }
        let ids = Set(values)
        try validateDayNightIDs(ids)
        return ids
    }

    static func protectDayNightAssetIDs(
        _ assetIDs: Set<String>,
        defaults: UserDefaults = .standard,
        flush: (UserDefaults) -> Bool = { $0.synchronize() }
    ) throws {
        try validateDayNightIDs(assetIDs)
        let protected = try pendingDayNightAssetIDs(defaults: defaults).union(assetIDs)
        defaults.set(protected.sorted(), forKey: pendingDayNightAssetIDsKey)
        guard flush(defaults),
              let readBack = try? pendingDayNightAssetIDs(defaults: defaults),
              protected.isSubset(of: readBack) else {
            // Keep attempted and concurrently observed protection. Unknown
            // protection remains malformed so all removals stay blocked.
            let retained = conservativelyMergedProtection(protected.sorted(), defaults.object(forKey: pendingDayNightAssetIDsKey))
            restorePreference(retained, key: pendingDayNightAssetIDsKey, defaults: defaults)
            _ = flush(defaults)
            let afterRetry = conservativelyMergedProtection(retained, defaults.object(forKey: pendingDayNightAssetIDsKey))
            restorePreference(afterRetry, key: pendingDayNightAssetIDsKey, defaults: defaults)
            throw AerialDropError.dayNightPreferencesWriteFailed
        }
    }

    static func clearPendingDayNightAssetIDs(
        expectingAssetIDs: Set<String>? = nil,
        expectingMalformedValue: NSObject? = nil,
        defaults: UserDefaults = .standard,
        flush: (UserDefaults) -> Bool = { $0.synchronize() }
    ) throws {
        // The caller must first prove a fresh typed activation (Automatic,
        // fixed variant, or ordinary single) and verify its native selection.
        // That recovery also permits removing a malformed stale guard.
        let old = defaults.object(forKey: pendingDayNightAssetIDsKey)
        if let expectingMalformedValue {
            guard expectingAssetIDs == nil,
                  (try? decodedDayNightIDs(expectingMalformedValue)) == nil else {
                throw AerialDropError.dayNightPreferencesInvalid
            }
            guard let current = old as? NSObject,
                  expectingMalformedValue.isEqual(current) else {
                throw AerialDropError.dayNightPreferencesWriteFailed
            }
        }
        if let expectingAssetIDs {
            try validateDayNightIDs(expectingAssetIDs)
            guard try decodedDayNightIDs(old) == expectingAssetIDs else {
                throw AerialDropError.dayNightPreferencesWriteFailed
            }
        }
        defaults.removeObject(forKey: pendingDayNightAssetIDsKey)
        guard flush(defaults), defaults.object(forKey: pendingDayNightAssetIDsKey) == nil else {
            let retained = conservativelyMergedProtection(old, defaults.object(forKey: pendingDayNightAssetIDsKey))
            restorePreference(retained, key: pendingDayNightAssetIDsKey, defaults: defaults)
            _ = flush(defaults)
            let afterRetry = conservativelyMergedProtection(retained, defaults.object(forKey: pendingDayNightAssetIDsKey))
            restorePreference(afterRetry, key: pendingDayNightAssetIDsKey, defaults: defaults)
            throw AerialDropError.dayNightPreferencesWriteFailed
        }
    }

    /// Valid guards merge without losing newly observed references. Any unknown
    /// guard stays unknown, so callers block removal rather than assume empty.
    private static func conservativelyMergedProtection(_ lhs: Any?, _ rhs: Any?) -> Any? {
        guard let left = try? decodedDayNightIDs(lhs) else { return lhs }
        guard let right = try? decodedDayNightIDs(rhs) else { return rhs }
        return left.union(right).sorted()
    }

    private static func validateDayNightIDs(_ ids: Set<String>) throws {
        guard ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw AerialDropError.dayNightPreferencesInvalid
        }
    }

    private static func restorePreference(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    static func isSetWallpaperAfterImportEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: setWallpaperAfterImportKey) != nil else {
            return true
        }
        return defaults.bool(forKey: setWallpaperAfterImportKey)
    }

    static func setSetWallpaperAfterImportEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: setWallpaperAfterImportKey)
    }

    /// The quality preset used by the most recent import, if any. Seeds the
    /// Import pane so repeated importers do not re-pick it for every video.
    static func lastConversionQuality(defaults: UserDefaults = .standard) -> ConversionOptions.Quality? {
        guard let raw = defaults.string(forKey: lastConversionQualityKey) else { return nil }
        return ConversionOptions.Quality(rawValue: raw)
    }

    static func setLastConversionQuality(_ quality: ConversionOptions.Quality, defaults: UserDefaults = .standard) {
        defaults.set(quality.rawValue, forKey: lastConversionQualityKey)
    }

    /// The output-height cap used by the most recent import, if any. Stored
    /// only when the user actually chose one (nil means "Original").
    static func lastOutputHeightCap(defaults: UserDefaults = .standard) -> Int? {
        let value = defaults.integer(forKey: lastOutputHeightCapKey)
        guard value > 0 else { return nil }
        return value
    }

    static func setLastOutputHeightCap(_ cap: Int?, defaults: UserDefaults = .standard) {
        if let cap {
            defaults.set(cap, forKey: lastOutputHeightCapKey)
        } else {
            defaults.removeObject(forKey: lastOutputHeightCapKey)
        }
    }
}
