# Import Preview Fit & Crop Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the full imported video in the Import pane preview (fit, not fill), darken exactly what the crop window cuts away, and show crop controls only for ≥21:9 sources.

**Architecture:** One pure helper (`isUltrawide`) plus a rewrite of `cropBandFractions` to full-frame space in ConversionOptions.swift, then a small SwiftUI change in VideoPreview/ImportPane. Encoding is untouched — sub-21:9 sources keep today's centered crop.

**Tech Stack:** Swift 6.2, SwiftUI (Liquid Glass), AVFoundation. Build: `swift build` / `swift test` (pin `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if XCTest is missing).

## Global Constraints

- macOS 26 SDK only; Swift 6 language mode (strict concurrency) — new code must compile under Swift 6.
- Do not touch VideoProcessor.swift encode invariants (HEVC Main10, crop transform, keyframe structure).
- All crop helpers must be hardened against non-finite/zero input (existing convention).
- Tests always use temp dirs; never real user paths. Only test files: `Tests/AerialDropTests/ConversionOptionsTests.swift` (this plan), `VideoGeometryTests.swift`, `ManifestStoreTests.swift`.
- Update CHANGELOG.md under `## Unreleased`.

---

### Task 1: Fit-space crop band math + `isUltrawide` helper

**Files:**
- Modify: `Sources/AerialDrop/ConversionOptions.swift:64-95` (replace `isWiderThan16By9`, rewrite `cropBandFractions`)
- Test: `Tests/AerialDropTests/ConversionOptionsTests.swift:52-57, 69-95`

**Interfaces:**
- Produces: `func isUltrawide(_ size: CGSize) -> Bool` (aspect ≥ 21/9 − 0.001, false for non-finite/≤0 dims); `func cropBandFractions(cropOffset: Double, sourceSize: CGSize) -> (left: Double, right: Double)` in full-frame space (`left = c·(1−f)`, `right = (1−c)·(1−f)`, `f = (16/9)/aspect`, clamped `c`). `isWiderThan16By9` is deleted — later tasks must not reference it.
- Consumes: nothing (pure functions).

- [ ] **Step 1: Replace `testIsWiderThan16By9` with `testIsUltrawide`** in `Tests/AerialDropTests/ConversionOptionsTests.swift` (lines 52–57)

```swift
func testIsUltrawide() {
    XCTAssertTrue(isUltrawide(CGSize(width: 3440, height: 1440)))
    XCTAssertTrue(isUltrawide(CGSize(width: 2560, height: 1080)))
    XCTAssertTrue(isUltrawide(CGSize(width: 5120, height: 2160)))
    XCTAssertTrue(isUltrawide(CGSize(width: 2100, height: 900))) // exact 21:9
    XCTAssertFalse(isUltrawide(CGSize(width: 1920, height: 1080)))
    XCTAssertFalse(isUltrawide(CGSize(width: 2048, height: 1152)))
    XCTAssertFalse(isUltrawide(CGSize(width: 3440, height: 1720))) // 2:1
    XCTAssertFalse(isUltrawide(CGSize(width: 1000, height: 1000)))
}
```

- [ ] **Step 2: Replace the body of `testCropBandFractionsMatchEncodeWindow`** (lines 69–95) with full-frame expectations

```swift
func testCropBandFractionsDarkenOutsideWindowInFullFrame() {
    // 3440×1440: f = (16/9)/2.3889 = 0.7442, 1-f = 0.2558
    let ultrawide = CGSize(width: 3440, height: 1440)
    // Center preset: equal bands on both sides (half the trimmed width each).
    XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).left, 0.128, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: ultrawide).right, 0.128, accuracy: 0.001)
    // Left preset: window [0, 0.744] -> right band 0.256.
    XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).left, 0, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: ultrawide).right, 0.256, accuracy: 0.001)
    // Right preset: left band 0.256.
    XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).left, 0.256, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: ultrawide).right, 0, accuracy: 0.001)
    // Quarter offset: left 0.064, right 0.192.
    XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).left, 0.064, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 0.25, sourceSize: ultrawide).right, 0.192, accuracy: 0.001)
    // Out-of-range offsets clamp like cropPan.
    XCTAssertEqual(cropBandFractions(cropOffset: -1, sourceSize: ultrawide).right, 0.256, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 2, sourceSize: ultrawide).left, 0.256, accuracy: 0.001)
    // 32:9: f = 0.5; Left darkens the right half, Center darkens a quarter on each side.
    let superUltrawide = CGSize(width: 7680, height: 2160)
    XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: superUltrawide).right, 0.5, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: superUltrawide).left, 0.5, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: superUltrawide).left, 0.25, accuracy: 0.001)
    XCTAssertEqual(cropBandFractions(cropOffset: 0.5, sourceSize: superUltrawide).right, 0.25, accuracy: 0.001)
    // Non-wide sources: no bands.
    XCTAssertEqual(cropBandFractions(cropOffset: 0, sourceSize: CGSize(width: 1920, height: 1080)).left, 0)
    XCTAssertEqual(cropBandFractions(cropOffset: 1, sourceSize: CGSize(width: 1920, height: 1080)).right, 0)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ConversionOptionsTests`
Expected: FAIL — `isUltrawide` not defined, band expectations wrong.

- [ ] **Step 4: Implement in `Sources/AerialDrop/ConversionOptions.swift`**

Replace lines 64–68:

```swift
/// True when the source is at least 21:9 — the threshold where crop controls
/// become useful. Sub-21:9 sources crop trivially, so the UI hides them.
func isUltrawide(_ size: CGSize) -> Bool {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0 else { return false }
    return size.width / size.height >= (21.0 / 9.0) - 0.001
}
```

Replace lines 78–95 (update doc comment and math):

```swift
/// Fractions of the preview box width to darken, in 0...1 box space. The box
/// shows the entire source fitted (scaledToFit, width-filling for wide
/// sources), so these darken everything outside the chosen 16:9 crop window.
/// Matches the encode-side window from `cropPan`.
func cropBandFractions(cropOffset: Double, sourceSize: CGSize) -> (left: Double, right: Double) {
    guard cropOffset.isFinite else { return (0, 0) }
    let aspect = sourceSize.width / sourceSize.height
    guard aspect > 16.0 / 9.0 else { return (0, 0) }
    let f = (16.0 / 9.0) / aspect
    let c = min(max(cropOffset, 0), 1)
    return (
        left: c * (1 - f),
        right: (1 - c) * (1 - f)
    )
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ConversionOptionsTests`
Expected: PASS (all ConversionOptionsTests, including the untouched hardening test at lines 97–108).

- [ ] **Step 6: Commit**

```bash
git add Sources/AerialDrop/ConversionOptions.swift Tests/AerialDropTests/ConversionOptionsTests.swift
git commit -m "feat: gate crop UI on 21:9 and darken full-frame crop bands"
```

---

### Task 2: Fit the import preview and gate the overlay

**Files:**
- Modify: `Sources/AerialDrop/Views/VideoPreview.swift:19, 43, 76-78`
- Modify: `Sources/AerialDrop/Views/ImportPane.swift:28, 133-136, 162`

**Interfaces:**
- Consumes: `isUltrawide(_:)` from Task 1.
- Produces: `ImportPane.isUltrawideSource` computed property; VideoPreview still takes `resolution` + optional `cropOffset` and renders bands only for ultrawide sources.

- [ ] **Step 1: Switch the frame to fit** — `VideoPreview.swift:17-25`

Change line 19 from `.scaledToFill()` to `.scaledToFit()`, and give the ZStack a black background so letterbox bars read as deliberate video letterboxing (background applies behind the frame; the outer `clipShape` in ImportPane rounds it):

```swift
ZStack {
    if let frame {
        Image(nsImage: frame)
            .resizable()
            .scaledToFit()
    } else {
        Rectangle().fill(.quaternary.opacity(0.6))
        ProgressView()
            .controlSize(.small)
    }
}
.background(Color.black)
```

- [ ] **Step 2: Gate the overlay on ultrawide** — `VideoPreview.swift:43`

Change `isWiderThan16By9(resolution)` to `isUltrawide(resolution)`.

- [ ] **Step 3: Update the `cropBands` doc comment** — `VideoPreview.swift:76-78`

```swift
/// Dims the parts of the preview box that the chosen crop window cuts away.
/// The box shows the entire source fitted (scaledToFit), so the bands darken
/// everything outside the chosen 16:9 window.
```

- [ ] **Step 4: Switch ImportPane to the 21:9 threshold** — `ImportPane.swift`

Replace the `isWide` property (lines 133–136) with:

```swift
private var isUltrawideSource: Bool {
    guard let resolution = model.sourceResolution else { return false }
    return isUltrawide(resolution)
}
```

Rename the two references (line 28 `if isWide {` and line 162 `cropOffset: isWide ? model.cropOffset : nil`) to `isUltrawideSource`. Note: the property cannot be named `isUltrawide` — it would shadow the free function from Task 1.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: succeeds; no warnings about unused `isWiderThan16By9` (deleted in Task 1).

- [ ] **Step 6: Full test suite**

Run: `swift test`
Expected: PASS (ConversionOptions, VideoGeometry, ManifestStore suites).

- [ ] **Step 7: Commit**

```bash
git add Sources/AerialDrop/Views/VideoPreview.swift Sources/AerialDrop/Views/ImportPane.swift
git commit -m "feat: fit import preview and gate crop overlay on ultrawide"
```

---

### Task 3: Changelog, release build, manual check

**Files:**
- Modify: `CHANGELOG.md` (under `## Unreleased`)

- [ ] **Step 1: Add changelog entries** above the existing Unreleased bullets

```markdown
- The Import preview now shows the entire video fitted (not zoomed), and the crop overlay darkens exactly what the chosen 16:9 window cuts away.
- Crop controls now appear only for ultrawide sources (21:9 and wider).
```

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for fitted preview and 21:9 crop gating"
```

- [ ] **Step 4: Manual verification (user, on a Tahoe machine)** — import a 3440×1440 (or 5120×2160) video and a 1920×1080 video:
  - Ultrawide: full video visible in the 440×248 box, side regions darkened per the Left/Center/Right picker, crop card present.
  - 16:9: no crop card, preview unchanged (fills box exactly).
  - Optionally drop a ~17:9 source: no crop card; encoded output still uses the centered window as before.
