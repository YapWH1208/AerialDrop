# AerialDrop: Import & Conversion Controls — Design

**Date:** 2026-08-05
**Status:** Approved by user (design sections 1–2)
**Scope:** Items #1–4 of the brainstorm request; item #5 (time-of-day switching) is explicitly deferred to a separate spec.

## 1. Problem

User feedback on the current import flow:

1. **Bug:** The selected-video preview in the Import pane is excessively large on wide windows — an ultrawide source blows past the screen. It must be resized to a manageable, predictable size.
2. **Missing:** Users cannot choose which part of an ultrawide (21:9 / 32:9) source is kept; the pipeline always keeps the center.
3. **Missing:** The resolution of imported videos is not displayed anywhere.
4. **Missing:** No user control over the video conversion (quality, output resolution).

Deferred (separate spec): dynamic time-of-day wallpaper switching.

## 2. Goals & non-goals

**Goals**

- Preview never exceeds a fixed cap (640×360) in the drop zone.
- User can spatially crop an ultrawide source (Left / Center / Right presets + fine position slider), with live visual feedback on the preview.
- Source resolution shown on the import preview; encoded resolution shown on library cards and the detail preview sheet.
- User can choose conversion quality (Standard / High / Maximum) and output resolution (Original / 2160p / 1440p / 1080p, downscale-only).
- All hard-won encoding invariants remain untouched: HEVC Main10, 30 fps, 10-bit full-range YUV, Rec.709, temporal sub-layers (base 15 fps), closed GOP, keyframe interval 1.9 s, duration ≥ 79.5 s, PTS 0, sync sample at every loop boundary.

**Non-goals**

- Time-based trimming (start/end segment selection) — not requested.
- Auto center-crop mode — the user explicitly chose manual crop control; Center is the default, which equals today's behavior.
- Frame-rate or loop-length configuration — risky per the encoding contract; explicitly declined by user.
- Persisting conversion settings globally (no Settings window) — Approach A approved: per-import state in the Import pane.
- Upscaling output beyond the source resolution.

## 3. Decisions (from brainstorm Q&A)

| Question | Decision |
|---|---|
| Scope grouping | #1–4 in this spec; #5 (time-of-day) later |
| "Ultrawide trimming" meaning | Spatial crop — user chooses which part of the wide frame to keep |
| Preview sizing | Fixed cap, max 640×360 |
| Resolution display locations | Import preview overlay + library cards + detail preview sheet |
| Conversion knobs | Quality/bitrate + output resolution downscale only (no fps, no loop length) |
| Approach | A: per-import settings in the Import pane, state in `AppModel` |

## 4. Current pipeline (context)

`VideoProcessor.makeNativeMOV(from:destination:progress:)`:

1. Inserts a 80 s-or-less segment of the source into an `AVMutableComposition`.
2. Computes `renderSize = evenSize(target16by9Size(from: sourceSize))` — already crop-to-fill 16:9, capped at 4K, never upscaling.
3. `makeVideoComposition` applies a centered crop-to-fill transform (`scale = max(renderW/sourceW, renderH/sourceH)`, centered `offsetX`/`offsetY`).
4. Encodes HEVC Main10 with the invariant properties; short segments are repeated via passthrough export with loop boundaries snapped to whole 30 fps frames.
5. Validates the installed video (duration, PTS 0, fps, Main10, full range, sync samples at loop boundaries).

Key insight: ultrawide sources are already crop-to-filled and **centered**. The crop feature adds a horizontal pan to the existing transform math.

## 5. Design

### 5.1 UI — Import pane (`ImportPane.swift`, `VideoPreview.swift`)

**Preview cap.** The selected-video preview is constrained to `maxWidth: 640, maxHeight: 360`, `.fit`, centered inside the drop-zone card. The card layout itself is unchanged; the preview simply never exceeds the cap.

**Crop section** (only when `sourceAspect > 16/9 + tolerance`):

- Segmented control **Left / Center / Right**.
- Fine-position slider beneath, clamped so the visible 16:9 window stays inside the frame (maps slider value to the same 0…1 `cropOffset` space as the presets: 0 = left, 0.5 = center, 1 = right).
- Live dimmed side bands on the preview showing what will be cropped away (overlay in `VideoPreview` driven by the current `cropOffset`).
- Default **Center** — identical to today's behavior for users who don't touch it.

**Conversion section** (visible whenever a video is selected):

- Quality popup: **Standard / High / Maximum**.
- Output resolution popup: **Original / 2160p / 1440p / 1080p**, listing only options that do not upscale the source. Default **Original**.
- Both reset to defaults when a new file is picked.

**Resolution display:**

- Import preview overlay capsule: source resolution (`3440×1440`) added next to duration and file size.
- Library cards + detail preview sheet: encoded resolution from the catalogue entry (nil for pre-feature entries → display nothing, not a placeholder).

### 5.2 State — `AppModel`

New `@Observable` properties:

- `cropOffset: Double = 0.5` (0…1; 0.5 = center)
- `conversionQuality: Quality = .standard`
- `outputHeightCap: Int? = nil` (nil = Original; note Original still obeys the pipeline's existing absolute 4K cap, so for sources taller than 2160 it equals 2160p)
- `sourceResolution: CGSize?` (loaded on `chooseVideo`)

Reset to defaults inside `chooseVideo` (new file → fresh settings). Passed to `videoProcessor.makeNativeMOV` as a `ConversionOptions` struct.

### 5.3 Pipeline — `VideoProcessor.swift`

New value type `ConversionOptions: Sendable`:

```swift
struct ConversionOptions {
    enum Quality { case standard, high, maximum }
    var cropOffset: Double = 0.5   // 0 = left edge, 1 = right edge
    var outputHeightCap: Int? = nil // nil = keep source height (Original)
    var quality: Quality = .standard
}
```

**Crop pan.** `makeVideoComposition` gains a `cropOffset` parameter. The transform math changes:

```
scale      = max(renderW / sourceW, renderH / sourceH)          // unchanged
offsetX    = (renderW − sourceW·scale) / 2  −  pan               // pan added
pan        = clamp(cropOffset − 0.5) · (sourceW·scale − renderW) // ∈ ±(excess)/2
offsetY    = (renderH − sourceH·scale) / 2                       // unchanged
```

`pan` is clamped so the visible window never leaves the frame. For non-wide sources the excess is zero → `pan = 0` → behavior identical to today. The clamp math is extracted into a pure, unit-testable function (e.g. `func cropPan(cropOffset:sourceSize:renderSize:) -> CGFloat`).

**Output resolution.** `target16by9Size(from:)` gains a `maxHeight: Int?` parameter (default 2160): `height = min(sourceHeight, maxHeight ?? 2160)`, width derived at 16:9. A 3440×1440 source with cap 1080 renders at 1920×1080.

**Bitrate.** `encodeMain10FullRange` sets `AVVideoAverageBitRateKey` from the quality preset. Fixed mapping (per rendered height), conservative:

| Quality | 1080p | 1440p | 2160p |
|---|---|---|---|
| Standard | 8 Mbps | 12 Mbps | 20 Mbps |
| High | 12 Mbps | 18 Mbps | 32 Mbps |
| Maximum | 18 Mbps | 28 Mbps | 48 Mbps |

Bucket the rendered height for lookup: `≥ 1600` → 2160 row, `1200–1599` → 1440 row, `< 1200` → 1080 row.

**Return value.** `makeNativeMOV` returns the encoded `CGSize` (the `renderSize` it actually used). `AppModel` forwards it to the manifest write.

### 5.4 Data model & persistence — `ManifestStore.swift`, `Models.swift`

- `ManifestStore.addWallpaper(id:title:)` gains `width: Int`, `height: Int` parameters and writes them into the AerialDrop entry (own-category fields; foreign keys untouched; still `JSONSerialization` round-trip — **never Codable**).
- `ManagedWallpaper` gains `var resolution: CGSize?` parsed from the entry on load; entries without the keys (imported before this feature) read `nil`.
- Library cards / detail sheet render `resolution` only when non-nil.

### 5.5 Error handling

No new error cases. Pan/cap inputs are clamped; existing encode/validate failures surface through `AerialDropError` unchanged.

## 6. Testing

- `ManifestStoreTests`: new round-trip test — add with width/height, reload, assert preserved; legacy entry without keys yields `nil`.
- New unit test for the crop-pan clamp function (pure math): center = 0 pan, edges clamp to ±excess/2, non-wide source = 0 pan.
- UI logic (preset ↔ slider mapping, popup options) is pure enough to unit test; at minimum verify mapping function in tests.
- Video-pipeline behavior (cropped/bitrated output plays natively) is manual per TESTING.md on a Tahoe machine — no video-pipeline tests exist in this repo.

## 7. Out of scope / follow-ups

- **Time-of-day wallpaper switching (#5)** — separate brainstorm + spec. Requires research into what Tahoe's Aerial catalogue supports natively; may conflict with the no-background-process architecture.
- Time trim (start/end segment) — not requested, revisit if wanted.
- Settings window / global defaults — declined (Approach A).
