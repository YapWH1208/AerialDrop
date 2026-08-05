import SwiftUI

/// Single source of truth for the AerialDrop visual identity:
/// one desaturated moonlit-indigo accent family plus tuned semantic colors.
enum AerialTheme {
    /// The brand accent — a moonlit indigo that reads on glass in both
    /// light and dark appearances without screaming.
    static let accent = Color(red: 0.46, green: 0.53, blue: 0.85)

    /// Soft moss green, desaturated to sit inside the glass surfaces.
    static let success = Color(red: 0.40, green: 0.66, blue: 0.52)

    /// Dusky amber, desaturated to avoid clashing with the indigo family.
    static let warning = Color(red: 0.82, green: 0.64, blue: 0.34)

    /// Muted rose for destructive moments.
    static let danger = Color(red: 0.83, green: 0.45, blue: 0.52)

    /// Tight negative tracking for large display text.
    static let displayTracking: Double = -0.4
}
