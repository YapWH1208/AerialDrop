# AGENTS.md

macOS Tahoe 26-only Swift Package (SPM executable → SwiftUI app) that imports a user's MP4/MOV into Apple's private Aerial wallpaper catalogue. It writes directly to `~/Library/Application Support/com.apple.wallpaper/aerials/` and restarts Apple's `WallpaperAgent`/`WallpaperAerialsExtension`; there is no app-managed player.

## Build / test

- Requires the macOS 26 (Tahoe) SDK: `Package.swift` pins `.macOS("26.0")`, and `ContentView` uses Liquid Glass `glassEffect` materials. Building or testing on an older SDK fails.
- `swift build`, `swift test`, `swift build -c release` are the only commands (no lint/format/typecheck tooling).
- `Scripts/build-app.sh` produces `dist/AerialDrop.app` (Info.plist + ad-hoc codesign). It **wipes `.build` first**, so it is a full rebuild; CI runs `build → test → release build → build-app.sh` on `macos-26`.
- Only unit tests exist: `ManifestStoreTests`. There are no video-pipeline tests — real imports must be verified manually on a Tahoe machine per TESTING.md.

## Hard-won invariants (do not casually change)

- **Encoding contract** (VideoProcessor.swift): HEVC Main10, 30 fps, 10-bit full-range YUV, Rec.709, temporal sub-layers with `kVTCompressionPropertyKey_BaseLayerFrameRate` = 15, closed GOP (`AllowOpenGOP` false), keyframe interval 1.9 s. Validator requires duration ≥ 79.5 s, starts at PTS 0, and a sync sample at every loop boundary. Breaking these causes a black desktop after lock/unlock (`VideoSampleReadingErrors Code=4`).
- **Short sources (< 80 s)** are encoded once, loop duration snapped to whole 30 fps frames, then repeated via passthrough export. Fractional loops drift one frame per repeat and fail sync-sample validation.
- **Thumbnail is HEIF content with a `.png` extension** (matches Apple's Wallper assets; Tahoe detects by contents). Do not "fix" the extension.
- **Manifest writes preserve everything foreign.** `ManifestStore.mutateManifest` compares foreign entries semantically before/after, refuses if the file changed mid-operation, and backs up to `aerials/AerialDropBackups` before every write. It round-trips via `JSONSerialization` (not Codable) on purpose to survive unknown keys. Never switch the manifest to Codable.

## Structural notes

- Entry point: `AerialDropApp.swift` → `AppModel` (@MainActor orchestrates import) → `VideoProcessor` (async AVFoundation encode), `ManifestStore` (sync manifest writes), `SystemWallpaperService` (killall + open System Settings).
- `WallpaperPaths(homeDirectory:)` takes an injectable home. Tests always redirect into a temp dir; never point tests or new code at real user paths.
- Stable IDs live in `ManifestStore` (`categoryID`/`subcategoryID`, `categoryName = "AerialDrop"`).
- Errors funnel through the `AerialDropError` enum in Models.swift (localized descriptions surface directly in the UI).

## Versioning / release

- Version/build is in **AppVersion.swift** (single source; `Scripts/build-app.sh` parses it for Info.plist).
- Releasing = add a `## <version>` section to CHANGELOG.md, then push tag `v<version>`. Release.yml extracts the changelog section for notes (fails if the section is missing) and zips `dist/AerialDrop.app` as `AerialDrop-<version>-macOS.zip`.