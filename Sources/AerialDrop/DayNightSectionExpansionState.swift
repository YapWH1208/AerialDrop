import Foundation

enum DayNightSectionExpansionState {
    /// Resolves the persisted manual choice against current setup or recovery
    /// attention. A dismissed token stays closed until it changes or resolves.
    static func reconcile(
        attentionToken: String?,
        preference: inout DayNightSectionExpansionPreference
    ) -> Bool {
        guard let attentionToken else {
            preference.dismissedAttentionToken = nil
            return preference.mode == .expanded
        }
        if preference.mode == .expanded {
            return true
        }
        return preference.dismissedAttentionToken != attentionToken
    }

    static func recordUserChoice(
        expanded: Bool,
        attentionToken: String?,
        preference: inout DayNightSectionExpansionPreference
    ) {
        preference.mode = expanded ? .expanded : .collapsed
        preference.dismissedAttentionToken = expanded ? nil : attentionToken
    }
}
