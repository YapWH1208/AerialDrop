import CoreGraphics
import Foundation

/// Per-import conversion choices. All values are clamped downstream; the
/// hard-won encoding invariants (HEVC Main10, 30 fps, temporal sub-layers,
/// closed GOP) are fixed and are NOT part of this type.
struct ConversionOptions: Sendable, Equatable {
    enum Quality: String, Sendable, Equatable {
        case standard
        case high
        case maximum
    }

    /// Horizontal position of the visible 16:9 window in source space:
    /// 0 = left edge, 0.5 = center (today's behavior), 1 = right edge.
    var cropOffset: Double = 0.5
    /// Desired output height cap in points/pixels; nil = no user cap
    /// (the pipeline's existing absolute 4K cap still applies).
    var outputHeightCap: Int? = nil
    var quality: Quality = .standard
}

/// Horizontal pan applied on top of the centered crop-to-fill transform.
/// For sources wider than the render aspect, the visible window can slide by
/// ±excess/2, where excess is the over-wide source width after scaling.
/// Non-wide sources (no horizontal excess) always return 0.
func cropPan(cropOffset: Double, sourceSize: CGSize, renderSize: CGSize) -> CGFloat {
    let scale = max(renderSize.width / sourceSize.width, renderSize.height / sourceSize.height)
    let excess = sourceSize.width * scale - renderSize.width
    guard excess > 0 else { return 0 }
    let fraction = min(max(cropOffset, 0), 1) - 0.5
    return CGFloat(fraction) * excess
}

/// Effective output height: the user's cap (if any), never above the source
/// height and never above the existing absolute 4K cap when no cap is set.
func clampedOutputHeight(_ requested: Int?, sourceHeight: Int) -> Int {
    min(sourceHeight, requested ?? 2160)
}

/// Output bitrate for a quality preset, bucketed by rendered height.
/// Buckets: ≥1600 → 2160p row, 1200–1599 → 1440p row, <1200 → 1080p row.
func bitrateBps(quality: ConversionOptions.Quality, renderHeight: Int) -> Int {
    let standard: Int
    let high: Int
    let maximum: Int
    switch renderHeight {
    case 1600...:
        (standard, high, maximum) = (20_000_000, 32_000_000, 48_000_000)
    case 1200..<1600:
        (standard, high, maximum) = (12_000_000, 18_000_000, 28_000_000)
    default:
        (standard, high, maximum) = (8_000_000, 12_000_000, 18_000_000)
    }
    switch quality {
    case .standard: return standard
    case .high: return high
    case .maximum: return maximum
    }
}

/// True when the source is wider than 16:9 (small tolerance so 16:9 sources
/// never trigger the crop UI).
func isWiderThan16By9(_ size: CGSize) -> Bool {
    size.width / size.height > (16.0 / 9.0) + 0.001
}

/// Snaps a continuous crop offset to the nearest segmented preset
/// (0 = Left, 0.5 = Center, 1 = Right), used by the crop UI's picker binding.
func nearestCropPreset(_ offset: Double) -> Double {
    if offset < 0.25 { return 0 }
    if offset > 0.75 { return 1 }
    return 0.5
}
