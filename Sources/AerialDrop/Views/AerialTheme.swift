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

    /// The 4×4 moonlit-indigo ramp behind the app. Deep charcoal-indigo at
    /// the edges, a soft indigo glow at the center, faint silver-blue —
    /// one hue family, no clashing accents.
    static let auroraColors: [Color] = [
        Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.18, green: 0.22, blue: 0.38), Color(red: 0.17, green: 0.21, blue: 0.37), Color(red: 0.15, green: 0.17, blue: 0.30),
        Color(red: 0.20, green: 0.24, blue: 0.42), Color(red: 0.28, green: 0.34, blue: 0.58), Color(red: 0.32, green: 0.38, blue: 0.62), Color(red: 0.19, green: 0.23, blue: 0.40),
        Color(red: 0.18, green: 0.23, blue: 0.40), Color(red: 0.30, green: 0.36, blue: 0.60), Color(red: 0.26, green: 0.32, blue: 0.56), Color(red: 0.17, green: 0.21, blue: 0.38),
        Color(red: 0.15, green: 0.17, blue: 0.30), Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.15, green: 0.17, blue: 0.30), Color(red: 0.13, green: 0.15, blue: 0.27)
    ]
}
