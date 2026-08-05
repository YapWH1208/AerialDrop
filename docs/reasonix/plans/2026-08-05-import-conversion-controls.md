# Import & Conversion Controls Implementation Plan

> **For agentic workers:** implement this plan task-by-task — dispatch a fresh subagent per task with the native `task` tool (recommended for quality), or use the superpowers-executing-plans skill to work through it inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-import conversion controls to AerialDrop — a capped preview, spatial crop for ultrawide sources, quality/output-resolution options, and resolution display — per `docs/reasonix/specs/2026-08-05-import-conversion-controls-design.md`.

**Architecture:** A new `ConversionOptions` value type (crop offset 0–1, output-height cap, quality) plus pure helper functions flows from `AppModel` state into `VideoProcessor.makeNativeMOV`, which applies a horizontal pan to the existing centered crop-to-fill transform, caps the render height, and picks a bitrate by quality. The encoded size is returned, stored as `width`/`height` in the AerialDrop manifest entry (JSONSerialization round-trip — never Codable), and displayed in the Import pane, library cards, and the detail preview sheet.

**Tech Stack:** Swift 6.2, SwiftUI (macOS 26 Tahoe SDK, Liquid Glass), AVFoundation (`AVMutableComposition` + `AVAssetReader`/`AVAssetWriter` HEVC Main10 pipeline), XCTest.

**Test commands:** All test runs below use `swift test --filter <TargetTests>` (or `swift test` for the full suite). The Command Line Tools toolchain has no XCTest — if `swift test` fails to find it, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (CI does exactly this). Builds: `swift build`.

---

### Task 1: Persist resolution in the manifest (TDD)

**Files:**
- Modify: `Sources/AerialDrop/Models.swift:3-16`
- Modify: `Sources/AerialDrop/ManifestStore.swift:29-53, 63-99, 193-210`
- Test: `Tests/AerialDropTests/ManifestStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AerialDropTests/ManifestStoreTests.swift` (inside `final class ManifestStoreTests`):

```swift
func testAddWallpaperPersistsResolutionAndDefaultEntriesReadNil() throws {
    let id = "CCCCCCCC-DDDD-4EEE-8FFF-000000000001"
    try Data("video".utf8).write(to: paths.videoURL(for: id))
    try Data("png".utf8).write(to: paths.thumbnailURL(for: id))
    try store.addWallpaper(id: id, title: "Resolution Test", width: 3440, height: 1440)

    let result = try json(at: paths.manifest)
    let assets = try XCTUnwrap(result["assets"] as? [[String: Any]])
    let asset = try XCTUnwrap(assets.first(where: { ($0["id"] as? String) == id }))
    XCTAssertEqual(asset["width"] as? Int, 3440)
    XCTAssertEqual(asset["height"] as? Int, 1440)

    let wallpapers = try store.importedWallpapers()
    XCTAssertEqual(wallpapers.first { $0.id == id }?.resolution, CGSize(width: 3440, height: 1440))

    // An entry added without width/height (the legacy shape) reads back as nil.
    let legacyID = "DDDDDDDD-EEEE-4FFF-8AAA-111111111111"
    try Data("video".utf8).write(to: paths.videoURL(for: legacyID))
    try Data("png".utf8).write(to: paths.thumbnailURL(for: legacyID))
    try store.addWallpaper(id: legacyID, title: "Legacy")
    let legacyWallpapers = try store.importedWallpapers()
    XCTAssertNil(legacyWallpapers.first { $0.id == legacyID }?.resolution)
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `swift test --filter ManifestStoreTests/testAddWallpaperPersistsResolutionAndDefaultEntriesReadNil`
Expected: FAIL — `addWallpaper` has no `width`/`height` parameters and `ManagedWallpaper` has no `resolution` member (compile error), plus no `width`/`height` keys written.

- [ ] **Step 3: Implement `resolution` on `ManagedWallpaper`**

In `Sources/AerialDrop/Models.swift`, change the struct to:

```swift
struct ManagedWallpaper: Identifiable, Hashable {
    let id: String
    let title: String
    let videoURL: URL
    let thumbnailURL: URL
    var resolution: CGSize? = nil
```

(keep `videoExists`/`thumbnailExists` unchanged).

- [ ] **Step 4: Implement manifest persistence**

In `Sources/AerialDrop/ManifestStore.swift`:

Change `addWallpaper` (line 63) signature to:

```swift
func addWallpaper(id: String, title: String, width: Int = 0, height: Int = 0) throws {
```

and its `makeAsset` call (line 90) to:

```swift
assets.append(makeAsset(id: id, title: title, preferredOrder: managedCount, width: width, height: height))
```

Replace `makeAsset` (lines 193-210) with:

```swift
private func makeAsset(id: String, title: String, preferredOrder: Int, width: Int = 0, height: Int = 0) -> [String: Any] {
    let shotID = customShotID(for: id)
    var asset: [String: Any] = [
        "id": id,
        "shotID": shotID,
        "localizedNameKey": title,
        "accessibilityLabel": title,
        "includeInShuffle": true,
        "showInTopLevel": true,
        "preferredOrder": preferredOrder,
        "categories": [Self.categoryID],
        "subcategories": [Self.subcategoryID],
        // Tahoe custom entries observed in a working catalogue use one freeze/transition marker.
        "pointsOfInterest": ["0": "\(shotID)_0"],
        "previewImage": paths.thumbnailURL(for: id).absoluteString,
        "url-4K-SDR-240FPS": paths.videoURL(for: id).absoluteString
    ]
    if width > 0 && height > 0 {
        asset["width"] = width
        asset["height"] = height
    }
    return asset
}
```

In `importedWallpapers` (lines 34-51), replace the `return ManagedWallpaper(...)` block (lines 45-50) with:

```swift
            let resolution: CGSize? = {
                if let w = asset["width"] as? Int, let h = asset["height"] as? Int, w > 0, h > 0 {
                    return CGSize(width: w, height: h)
                }
                return nil
            }()

            return ManagedWallpaper(
                id: id,
                title: title,
                videoURL: paths.videoURL(for: id),
                thumbnailURL: paths.thumbnailURL(for: id),
                resolution: resolution
            )
```

Do **not** add `width`/`height` to `validateManagedAsset`'s `requiredStrings` — legacy entries lack them and must stay valid.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ManifestStoreTests`
Expected: PASS — all 5 existing tests plus the new one (existing call sites still compile because `width`/`height` default to 0, which writes no keys).

- [ ] **Step 6: Commit**

```bash
git add Sources/AerialDrop/Models.swift Sources/AerialDrop/ManifestStore.swift Tests/AerialDropTests/ManifestStoreTests.swift
git commit -m "feat: persist encoded resolution in the AerialDrop manifest entry"
```

---

### Task 2: `ConversionOptions` value type and pure helpers (TDD)

**Files:**
- Create: `Sources/AerialDrop/ConversionOptions.swift`
- Test: `Tests/AerialDropTests/ConversionOptionsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AerialDropTests/ConversionOptionsTests.swift`:

```swift
import XCTest
@testable import AerialDrop

final class ConversionOptionsTests: XCTestCase {
    func testCropPanCenterIsZero() {
        XCTAssertEqual(
            cropPan(cropOffset: 0.5, sourceSize: CGSize(width: 3440, height: 1440), renderSize: CGSize(width: 1920, height: 1080)),
            0, accuracy: 0.001
        )
    }

    func testCropPanLeftAndRightClampToHalfTheExcess() {
        // scale = 1080/1440 = 0.75; excess = 3440*0.75 - 1920 = 660; half = 330
        let source = CGSize(width: 3440, height: 1440)
        let render = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: 0, sourceSize: source, renderSize: render), -330, accuracy: 0.001)
        XCTAssertEqual(cropPan(cropOffset: 1, sourceSize: source, renderSize: render), 330, accuracy: 0.001)
    }

    func testCropPanNonWideSourceIsZero() {
        let square = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: 0, sourceSize: square, renderSize: square), 0)
        XCTAssertEqual(cropPan(cropOffset: 1, sourceSize: square, renderSize: square), 0)
        XCTAssertEqual(cropPan(cropOffset: 0.5, sourceSize: square, renderSize: square), 0)
    }

    func testCropPanClampsOutOfRangeInput() {
        let source = CGSize(width: 3440, height: 1440)
        let render = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(cropPan(cropOffset: -1, sourceSize: source, renderSize: render), -330, accuracy: 0.001)
        XCTAssertEqual(cropPan(cropOffset: 2, sourceSize: source, renderSize: render), 330, accuracy: 0.001)
    }

    func testBitrateBucketsByRenderHeightAndQuality() {
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1080), 8_000_000)
        XCTAssertEqual(bitrateBps(quality: .maximum, renderHeight: 1080), 18_000_000)
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1440), 12_000_000)
        XCTAssertEqual(bitrateBps(quality: .high, renderHeight: 1440), 18_000_000)
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 2160), 20_000_000)
        XCTAssertEqual(bitrateBps(quality: .maximum, renderHeight: 2160), 48_000_000)
        XCTAssertEqual(bitrateBps(quality: .high, renderHeight: 1600), 32_000_000) // ≥1600 → 2160 row
        XCTAssertEqual(bitrateBps(quality: .standard, renderHeight: 1199), 8_000_000) // <1200 → 1080 row
    }

    func testClampedOutputHeightNeverUpscales() {
        XCTAssertEqual(clampedOutputHeight(nil, sourceHeight: 1440), 1440)
        XCTAssertEqual(clampedOutputHeight(nil, sourceHeight: 4320), 2160) // existing 4K cap
        XCTAssertEqual(clampedOutputHeight(1080, sourceHeight: 1440), 1080)
        XCTAssertEqual(clampedOutputHeight(2160, sourceHeight: 1080), 1080)
    }

    func testIsWiderThan16By9() {
        XCTAssertTrue(isWiderThan16By9(CGSize(width: 3440, height: 1440)))
        XCTAssertTrue(isWiderThan16By9(CGSize(width: 7680, height: 2160)))
        XCTAssertFalse(isWiderThan16By9(CGSize(width: 1920, height: 1080)))
        XCTAssertFalse(isWiderThan16By9(CGSize(width: 1000, height: 1000)))
    }

    func testNearestCropPreset() {
        XCTAssertEqual(nearestCropPreset(0), 0)
        XCTAssertEqual(nearestCropPreset(0.24), 0)
        XCTAssertEqual(nearestCropPreset(0.25), 0.5)
        XCTAssertEqual(nearestCropPreset(0.5), 0.5)
        XCTAssertEqual(nearestCropPreset(0.75), 0.5)
        XCTAssertEqual(nearestCropPreset(0.76), 1)
        XCTAssertEqual(nearestCropPreset(1), 1)
    }
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `swift test --filter ConversionOptionsTests`
Expected: FAIL — `cropPan`, `bitrateBps`, `clampedOutputHeight`, `isWiderThan16By9` are not defined.

- [ ] **Step 3: Implement `ConversionOptions.swift`**

Create `Sources/AerialDrop/ConversionOptions.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConversionOptionsTests`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AerialDrop/ConversionOptions.swift Tests/AerialDropTests/ConversionOptionsTests.swift
git commit -m "feat: add ConversionOptions with crop pan, bitrate, and cap helpers"
```

---

### Task 3: Wire options through `VideoProcessor` (compile + manual verification)

**Files:**
- Modify: `Sources/AerialDrop/VideoProcessor.swift:149-154, 187-290, 292-330, 332-425`

- [ ] **Step 1: Change `makeNativeMOV` signature and compute pan/bitrate**

Replace the signature (lines 187-191) with:

```swift
    func makeNativeMOV(
        from source: URL,
        destination: URL,
        options: ConversionOptions = .init(),
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CGSize {
```

Replace the render-size block (lines 250-264) with:

```swift
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let sourceSize = CGSize(
            width: max(2, abs(transformedRect.width)),
            height: max(2, abs(transformedRect.height))
        )
        let maxHeight = clampedOutputHeight(options.outputHeightCap, sourceHeight: Int(sourceSize.height))
        let renderSize = evenSize(target16by9Size(from: sourceSize, maxHeight: maxHeight))
        let pan = cropPan(cropOffset: options.cropOffset, sourceSize: sourceSize, renderSize: renderSize)

        let videoComposition = makeVideoComposition(
            track: segmentTrack,
            preferredTransform: preferredTransform,
            transformedRect: transformedRect,
            renderSize: renderSize,
            pan: pan,
            duration: segmentDuration
        )
```

Replace the `encodeMain10FullRange` call (lines 266-274) with:

```swift
        try await encodeMain10FullRange(
            composition: segmentComposition,
            track: segmentTrack,
            videoComposition: videoComposition,
            renderSize: renderSize,
            duration: segmentDuration,
            bitrate: bitrateBps(quality: options.quality, renderHeight: Int(renderSize.height)),
            destination: segmentURL,
            progress: progress
        )
```

Replace the end of the function (lines 288-290) with:

```swift
        try await validateInstalledVideo(destination, loopDuration: segmentDuration)
        try Task.checkCancellation()
        return renderSize
    }
```

- [ ] **Step 2: Update `makeVideoComposition` to accept the pan**

Replace the signature (lines 292-298) to add `pan: CGFloat` after `renderSize: CGSize,`:

```swift
    private func makeVideoComposition(
        track: AVCompositionTrack,
        preferredTransform: CGAffineTransform,
        transformedRect: CGRect,
        renderSize: CGSize,
        pan: CGFloat,
        duration: CMTime
    ) -> AVVideoComposition {
```

Replace the offset lines (308-309) with:

```swift
        let offsetX = (renderSize.width - sourceSize.width * scale) / 2 - pan
        let offsetY = (renderSize.height - sourceSize.height * scale) / 2
```

- [ ] **Step 3: Update `target16by9Size` to accept the height cap**

Replace lines 696-704 with:

```swift
    /// Fits a source into a 16:9 frame capped at the given height (default 2160,
    /// the existing 4K cap), never upscaling. Sources that already fit pass
    /// through unchanged. The crop-to-fill scale and centering are applied by
    /// the video-composition layer transform.
    private func target16by9Size(from sourceSize: CGSize, maxHeight: Int = 2160) -> CGSize {
        if sourceSize.width / sourceSize.height >= 16.0 / 9.0 {
            let height = min(sourceSize.height, CGFloat(maxHeight))
            return CGSize(width: height * (16.0 / 9.0), height: height)
        } else {
            let width = min(sourceSize.width, CGFloat(maxHeight) * (16.0 / 9.0))
            return CGSize(width: width, height: width * (9.0 / 16.0))
        }
    }
```

- [ ] **Step 4: Update `encodeMain10FullRange` to take the bitrate**

Replace the signature (lines 332-340) to add `bitrate: Int` after `renderSize: CGSize,`:

```swift
    private func encodeMain10FullRange(
        composition: AVComposition,
        track: AVCompositionTrack,
        videoComposition: AVVideoComposition,
        renderSize: CGSize,
        duration: CMTime,
        bitrate: Int,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
```

Replace line 362 (`AVVideoAverageBitRateKey: targetBitRate,`) with:

```swift
            AVVideoAverageBitRateKey: bitrate,
```

Remove the now-unused constant (line 152):

```swift
    private let targetBitRate = 20_000_000
```

- [ ] **Step 5: Build and run the full test suite**

Run: `swift build` then `swift test`
Expected: both succeed. (Existing tests don't cover the encode path; the crop/bitrate math is covered by `ConversionOptionsTests`.)

- [ ] **Step 6: Commit**

```bash
git add Sources/AerialDrop/VideoProcessor.swift
git commit -m "feat: apply crop pan, height cap, and quality bitrate in the encode pipeline"
```

---

### Task 4: `AppModel` state, source resolution, and options plumbing

**Files:**
- Modify: `Sources/AerialDrop/AppModel.swift:8-27, 46-64, 70-135`

- [ ] **Step 1: Add state and reset-on-new-file behavior**

In `AppModel`'s public state block (after `var importSucceeded = false`, line 17), add:

```swift
    var cropOffset: Double = 0.5
    var conversionQuality: ConversionOptions.Quality = .standard
    var outputHeightCap: Int? = nil
    var sourceResolution: CGSize?
```

In `chooseVideo` (after `selectedVideo = url`, line 53), add the resets:

```swift
        cropOffset = 0.5
        conversionQuality = .standard
        outputHeightCap = nil
        sourceResolution = nil
```

Replace the validation task in `chooseVideo` (lines 54-63) with:

```swift
        Task {
            do {
                try await videoProcessor.validate(source: url)
                let asset = AVURLAsset(url: url)
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let naturalSize = try await track.load(.naturalSize)
                    guard version == selectionVersion else { return }
                    sourceResolution = naturalSize
                }
            } catch {
                guard version == selectionVersion else { return }
                alertMessage = error.localizedDescription
                selectedVideo = nil
                title = ""
            }
        }
```

- [ ] **Step 2: Pass options into the encode and store the encoded size**

In `importSelectedVideo`, replace the processing/manifest block (lines 103-114) with:

```swift
                stage = .processingVideo
                let encodedSize = try await videoProcessor.makeNativeMOV(
                    from: source,
                    destination: videoDestination,
                    options: ConversionOptions(
                        cropOffset: cropOffset,
                        outputHeightCap: outputHeightCap,
                        quality: conversionQuality
                    )
                ) { fraction in
                    Task { @MainActor in
                        self.importProgress = fraction
                    }
                }

                stage = .generatingThumbnail
                try await videoProcessor.generateThumbnail(from: videoDestination, destination: thumbnailDestination)

                stage = .updatingManifest
                try manifestStore.addWallpaper(
                    id: id,
                    title: cleanTitle,
                    width: Int(encodedSize.width),
                    height: Int(encodedSize.height)
                )
```

- [ ] **Step 3: Build and test**

Run: `swift build` then `swift test`
Expected: both succeed (`makeNativeMOV`'s `options` parameter has a default, and the return type is now `CGSize` — used here).

- [ ] **Step 4: Commit**

```bash
git add Sources/AerialDrop/AppModel.swift
git commit -m "feat: plumb conversion options and encoded resolution through AppModel"
```

---

### Task 5: Preview cap, crop bands, and resolution overlay in the Import pane

**Files:**
- Modify: `Sources/AerialDrop/Views/VideoPreview.swift`
- Modify: `Sources/AerialDrop/Views/ImportPane.swift:81-158, 246-257`

- [ ] **Step 1: Extend `VideoPreview` with resolution and crop-offset parameters**

Replace the struct header and `body` overlay block in `Sources/AerialDrop/Views/VideoPreview.swift`:

```swift
struct VideoPreview: View {
    let url: URL
    var resolution: CGSize? = nil
    var cropOffset: Double? = nil

    @State private var frame: NSImage?
    @State private var duration: Double?
    @State private var fileSize: Int64?
```

Replace the overlay (lines 24-36) with:

```swift
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                if let resolution {
                    Label("\(Int(resolution.width))×\(Int(resolution.height))", systemImage: "rectangle.inset.filled")
                }
                if let duration, let fileSize {
                    Label(timeString(duration), systemImage: "clock")
                    Label(fileSize.formatted(.byteCount(style: .file)), systemImage: "internaldrive")
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(8)
        }
        .overlay {
            if let cropOffset, let resolution, isWiderThan16By9(resolution) {
                cropBands(cropOffset: cropOffset, resolution: resolution)
            }
        }
```

Add the crop-bands helper at the end of the struct (before `timeString`):

```swift
    /// Dims the parts of the frame that the chosen crop window will cut away.
    /// The visible window is 16:9; `cropOffset` positions it in source space.
    private func cropBands(cropOffset: Double, resolution: CGSize) -> some View {
        GeometryReader { geo in
            let visibleFraction = min(1, (resolution.height * 16.0 / 9.0) / resolution.width)
            let left = max(0, cropOffset * (1 - visibleFraction))
            let right = max(0, 1 - visibleFraction - left)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .frame(width: geo.size.width * left)
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .frame(width: geo.size.width * right)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
```

- [ ] **Step 2: Cap the preview and add the crop + conversion sections in `ImportPane`**

In `ImportPane`, replace the `VideoPreview` call inside `dropZoneButton` (lines 98-105) with:

```swift
                if let url = model.selectedVideo {
                    VideoPreview(
                        url: url,
                        resolution: model.sourceResolution,
                        cropOffset: isWide ? model.cropOffset : nil
                    )
                    .frame(maxWidth: 640, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
```

(`cropOffset` passed as `nil` for non-wide sources keeps today's look.)

Add `isWide` as a computed property on `ImportPane` (after `dropZone`):

```swift
    private var isWide: Bool {
        guard let resolution = model.sourceResolution else { return false }
        return isWiderThan16By9(resolution)
    }
```

In `body`, after the `dropZone` line and before the "Wallpaper name" `VStack` (line 28), insert:

```swift
                if isWide {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Crop")
                            .font(.callout.weight(.semibold))
                        Picker("Position", selection: cropPreset) {
                            Text("Left").tag(0.0)
                            Text("Center").tag(0.5)
                            Text("Right").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        Slider(value: $model.cropOffset, in: 0...1)
                            .help("Position of the visible 16:9 window")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Conversion")
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 16) {
                        Picker("Quality", selection: $model.conversionQuality) {
                            Text("Standard").tag(ConversionOptions.Quality.standard)
                            Text("High").tag(ConversionOptions.Quality.high)
                            Text("Maximum").tag(ConversionOptions.Quality.maximum)
                        }
                        Picker("Output resolution", selection: $model.outputHeightCap) {
                            Text("Original").tag(Int?.none)
                            ForEach(availableHeightCaps, id: \.self) { cap in
                                Text("\(cap)p").tag(Int?.some(cap))
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
```

Add the two helpers (after `isWide`):

```swift
    /// Segmented-preset binding: snaps the continuous slider position to the
    /// nearest preset; picking a preset sets the slider value.
    private var cropPreset: Binding<Double> {
        Binding(
            get: { nearestCropPreset(model.cropOffset) },
            set: { model.cropOffset = $0 }
        )
    }

    /// Downscale-only resolution options, derived from the source height.
    private var availableHeightCaps: [Int] {
        guard let sourceHeight = model.sourceResolution?.height else { return [] }
        return [2160, 1440, 1080].filter { $0 < Int(sourceHeight) }
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds. (No unit tests cover SwiftUI views; the mapping logic — `isWiderThan16By9`, `cropPan` — is already tested in Task 2.)

- [ ] **Step 4: Commit**

```bash
git add Sources/AerialDrop/Views/VideoPreview.swift Sources/AerialDrop/Views/ImportPane.swift
git commit -m "feat: cap import preview, add crop and conversion controls to the Import pane"
```

---

### Task 6: Resolution display in the library and preview sheet

**Files:**
- Modify: `Sources/AerialDrop/Views/WallpaperCard.swift:24-32`
- Modify: `Sources/AerialDrop/Views/WallpaperPreviewView.swift:13-27`

- [ ] **Step 1: Show resolution on library cards**

In `WallpaperCard`, replace the title `HStack` (lines 24-32) with:

```swift
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(wallpaper.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            statusIcon
                        }
                        if let resolution = wallpaper.resolution {
                            Text("\(Int(resolution.width))×\(Int(resolution.height))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
```

- [ ] **Step 2: Show resolution in the detail preview sheet**

In `WallpaperPreviewView`, inside the header `HStack` (after the title `Text`, before `Spacer()` — lines 19-24), add:

```swift
                if let resolution = wallpaper.resolution {
                    Text("\(Int(resolution.width))×\(Int(resolution.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Build and test**

Run: `swift build` then `swift test`
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add Sources/AerialDrop/Views/WallpaperCard.swift Sources/AerialDrop/Views/WallpaperPreviewView.swift
git commit -m "feat: show encoded resolution on wallpaper cards and the preview sheet"
```

---

### Task 7: Changelog and full verification

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the changelog entry**

Insert at the top of `CHANGELOG.md` (above `## 0.6.1`):

```markdown
## Unreleased

- Capped the import preview at 640×360 so ultrawide videos fit the window.
- Added ultrawide cropping (Left/Center/Right presets plus a fine position slider) with a live crop preview in the Import pane.
- Shows the source resolution in the Import pane and the encoded resolution on library cards and the preview sheet.
- Added per-import conversion options: quality (Standard/High/Maximum) and output resolution (downscale to 2160p/1440p/1080p).
```

- [ ] **Step 2: Full verification**

Run: `swift build` then `swift test`
Expected: full test suite passes (ManifestStoreTests: 6 tests, ConversionOptionsTests: 8 tests).

Run: `swift build -c release`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for import and conversion controls"
```

- [ ] **Step 4: Manual on-device verification (per TESTING.md, Tahoe machine)**

Per `TESTING.md`: import a 21:9 source with each crop preset and with 1080p/Maximum, verify the wallpaper plays natively and the sync-sample/duration validation passes; confirm resolution shows on the card and preview sheet. Not automatable in this repo.
