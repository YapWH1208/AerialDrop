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
    guard cropOffset.isFinite else { return 0 }
    let scale = max(renderSize.width / sourceSize.width, renderSize.height / sourceSize.height)
    let excess = sourceSize.width * scale - renderSize.width
    guard excess > 0 else { return 0 }
    let fraction = min(max(cropOffset, 0), 1) - 0.5
    return CGFloat(fraction) * excess
}

/// Effective output height: the user's cap (if any), never above the source
/// height and never above the existing absolute 4K cap when no cap is set,
/// and never below 2.
func clampedOutputHeight(_ requested: Int?, sourceHeight: Int) -> Int {
    max(2, min(sourceHeight, requested ?? 2160))
}

/// Exact even-sized 16:9 output frame used by the native HEVC encoder. This
/// keeps preview metadata and the encoder on the same no-upscale, 4K-capped
/// contract for wide, portrait, and standard landscape sources.
func encodedOutputSize(sourceSize: CGSize, outputHeightCap: Int?) -> CGSize {
    guard sourceSize.width.isFinite, sourceSize.height.isFinite,
          sourceSize.width > 0, sourceSize.height > 0 else {
        return CGSize(width: 2, height: 2)
    }

    let maxHeight = clampedOutputHeight(outputHeightCap, sourceHeight: Int(sourceSize.height))
    let target: CGSize
    if sourceSize.width / sourceSize.height >= 16.0 / 9.0 {
        let height = min(sourceSize.height, CGFloat(maxHeight))
        target = CGSize(width: height * (16.0 / 9.0), height: height)
    } else {
        let width = min(sourceSize.width, CGFloat(maxHeight) * (16.0 / 9.0))
        target = CGSize(width: width, height: width * (9.0 / 16.0))
    }
    return CGSize(
        width: max(2, floor(target.width / 2) * 2),
        height: max(2, floor(target.height / 2) * 2)
    )
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

/// Estimated encoded bytes for the fixed 80-second native Aerial loop. The
/// estimate intentionally uses the same bitrate bucket as the encoder; the
/// container's short-lived overhead is covered by the working-space reserve.
func estimatedAerialOutputBytes(
    sourceSize: CGSize,
    options: ConversionOptions
) -> Int64 {
    let outputSize = encodedOutputSize(
        sourceSize: sourceSize,
        outputHeightCap: options.outputHeightCap
    )
    let bitsPerSecond = Int64(
        bitrateBps(
            quality: options.quality,
            renderHeight: Int(outputSize.height)
        )
    )
    return bitsPerSecond * 80 / 8
}

/// Peak free space required before encoding begins. Short sources briefly
/// keep both the encoded segment and its repeated final movie, so reserve two
/// output-sized files plus 128 MiB for container variance, thumbnails, and
/// catalogue backups.
func requiredImportStorageBytes(
    sourceSize: CGSize,
    options: ConversionOptions
) -> Int64 {
    estimatedAerialOutputBytes(sourceSize: sourceSize, options: options) * 2
        + 128 * 1_024 * 1_024
}

/// Human-readable statement of the fixed 80-second loop contract, shown in
/// the Import pane before the user commits to an encode. Sources longer than
/// the loop are trimmed to their first ~80 seconds; shorter ones repeat.
func loopDescription(sourceDuration: Double?) -> String {
    guard let sourceDuration, sourceDuration.isFinite, sourceDuration > 0 else {
        return "80-second loop"
    }
    if sourceDuration >= 80 {
        return "First 1:20 of the source, looped"
    }
    return "Whole video, repeated to fill 1:20"
}

/// A remembered height cap only applies when it actually downscales the
/// source's natural 16:9 window; a cap that would encode identically to
/// "Original" must fall back to Original so the picker shows a real selection.
func applicableHeightCap(_ cap: Int?, sourceSize: CGSize) -> Int? {
    guard let cap, CGFloat(cap) < naturalWindowHeight(sourceSize: sourceSize) else { return nil }
    return cap
}

/// True when the source is at least 21:9 — the threshold where crop controls
/// become useful. Sub-21:9 sources crop trivially, so the UI hides them.
func isUltrawide(_ size: CGSize) -> Bool {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0 else { return false }
    return size.width / size.height >= (21.0 / 9.0) - 0.001
}

/// True when the source is narrower than 16:9 (e.g. portrait or 4:3) — the
/// encode centers a 16:9 window on the source and crops the top and bottom.
func isNarrowerThan16By9(_ size: CGSize) -> Bool {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0 else { return false }
    return size.width / size.height < (16.0 / 9.0) - 0.001
}

/// True when the source is not 16:9 — the encode crops it in one direction to
/// fill the 16:9 frame (horizontally for ultrawide, vertically otherwise).
func hasCropWindow(_ size: CGSize) -> Bool {
    isUltrawide(size) || isNarrowerThan16By9(size)
}

/// The height of the largest 16:9 window that fits inside the source without
/// upscaling — the encode's natural output height before any user cap. For
/// wide sources this is the source height; for portrait/4:3 sources it is
/// `width × 9/16` (the vertical-center-crop window).
func naturalWindowHeight(sourceSize: CGSize) -> Double {
    guard sourceSize.width.isFinite, sourceSize.height.isFinite,
          sourceSize.width > 0, sourceSize.height > 0 else { return 0 }
    return min(sourceSize.height, sourceSize.width * (9.0 / 16.0))
}

/// Snaps a continuous crop offset to the nearest segmented preset
/// (0 = Left, 0.5 = Center, 1 = Right), used by the crop UI's picker binding.
func nearestCropPreset(_ offset: Double) -> Double {
    if offset < 0.25 { return 0 }
    if offset > 0.75 { return 1 }
    return 0.5
}

/// Fractions of the preview box width to darken, in 0...1 box space. The box
/// shows the entire source fitted (scaledToFit, width-filling for wide
/// sources), so these darken everything outside the chosen 16:9 crop window.
/// Matches the encode-side window from `cropPan`.
func cropBandFractions(cropOffset: Double, sourceSize: CGSize) -> (left: Double, right: Double) {
    guard cropOffset.isFinite else { return (0, 0) }
    let aspect = sourceSize.width / sourceSize.height
    guard aspect.isFinite else { return (0, 0) }
    guard aspect > 16.0 / 9.0 else { return (0, 0) }
    let f = (16.0 / 9.0) / aspect
    let c = min(max(cropOffset, 0), 1)
    return (
        left: c * (1 - f),
        right: (1 - c) * (1 - f)
    )
}

/// Fractions of the preview box height to darken above and below the visible
/// 16:9 crop window, in 0...1 box space. The window is always vertically
/// centered — the encode pan is horizontal only — so the bands are symmetric.
/// Sources narrower than 16:9 only; 16:9 and ultrawide sources return none.
func verticalCropBandFractions(sourceSize: CGSize) -> (top: Double, bottom: Double) {
    guard isNarrowerThan16By9(sourceSize) else { return (0, 0) }
    let f = (sourceSize.width / sourceSize.height) / (16.0 / 9.0)
    return ((1 - f) / 2, (1 - f) / 2)
}
