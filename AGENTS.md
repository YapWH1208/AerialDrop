# AGENTS.md

macOS Tahoe 26-only Swift Package (SPM executable → SwiftUI app) that imports a user's MP4/MOV into Apple's private Aerial wallpaper catalogue. It writes directly to `~/Library/Application Support/com.apple.wallpaper/aerials/` and restarts Apple's `WallpaperAgent`/`WallpaperAerialsExtension`; there is no app-managed player.

## Build / test

- Requires the macOS 26 (Tahoe) SDK and a Swift 6.2+ toolchain: `Package.swift` pins `.macOS("26.0")` with `swift-tools-version: 6.2` (Swift 6 language mode — new code must satisfy strict concurrency), and the SwiftUI UI uses Liquid Glass `glassEffect` materials. Building or testing on an older SDK fails.
- `swift build`, `swift test`, `swift build -c release` are the only commands (no lint/format/typecheck tooling). Run a single test with `swift test --filter ManifestStoreTests`. The Command Line Tools toolchain has no XCTest — if `swift test` fails to find it, pin `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `Scripts/build-app.sh` produces `dist/AerialDrop.app` (Info.plist + ad-hoc codesign; icon from `Assets/AppIcon.icns`, regenerable via `Scripts/make-icon.swift`, which resolves `Assets/` relative to cwd and must run from the repo root). It **wipes `.build` first**, so it is a full rebuild; CI runs `build → test → release build → build-app.sh` on a GitHub-hosted `macos-26` runner.
- Six test classes; run one with `swift test --filter <TestClass>`: `ManifestStoreTests`, `ConversionOptionsTests`, `VideoGeometryTests`, `WallpaperSelectionStoreTests` (uses the `Tests/AerialDropTests/Fixtures/TahoeLinkedAerialSelection.plist` fixture), `AppPreferencesTests`, and `AppModelWallpaperTests` (async `AppModel`-level tests that inject a `FakeWallpaperService` through the `WallpaperServicing` protocol — not pure-function tests). **VideoProcessor has no tests** — real imports must be verified manually on a Tahoe machine per TESTING.md (lock/unlock cycles, `VideoSampleReadingErrors` in the WallpaperAerialsExtension log).
- `./build-and-open.sh` is the one-shot "wipe `.build` + `dist`, build app, launch new instance" wrapper (it also deletes `dist`, so don't run it while keeping a packaged release around).

## Hard-won invariants (do not casually change)

- **Encoding contract** (VideoProcessor.swift): HEVC Main10, 30 fps, 10-bit full-range YUV, Rec.709, temporal sub-layers with `kVTCompressionPropertyKey_BaseLayerFrameRate` = 15, closed GOP (`AllowOpenGOP` false), keyframe interval 1.9 s. Validator requires duration ≥ 79.5 s, starts at PTS 0, and a sync sample at every loop boundary. Breaking these causes a black desktop after lock/unlock (`VideoSampleReadingErrors Code=4`).
- **Short sources (< 80 s)** are encoded once, loop duration snapped to whole 30 fps frames, then repeated via passthrough export. Fractional loops drift one frame per repeat and fail sync-sample validation.
- **Thumbnail is HEIF content with a `.png` extension** (matches Apple's Wallper assets; Tahoe detects by contents). Do not "fix" the extension.
- **Manifest writes preserve everything foreign.** `ManifestStore.mutateManifest` compares foreign entries semantically before/after, refuses if the file changed mid-operation, and backs up to `aerials/AerialDropBackups` before every write. It round-trips via `JSONSerialization` (not Codable) on purpose to survive unknown keys. Never switch the manifest to Codable.

## Structural notes

- Entry point: `AerialDropApp.swift` → `AppModel` (`@MainActor` `@Observable`; orchestrates import and activation) → `VideoProcessor` (async AVFoundation encode), `ManifestStore` (sync manifest writes), `SystemWallpaperService` (activation + refresh + System Settings), `WallpaperSelectionStore` (owning the private `Store/Index.plist` linked-selection format). UI lives in `Views/` (`ImportPane` consumes import options; `LibraryPane` drives rename/remove through `ManifestStore` mutations, `LoopPlayerView`/`VideoPreview` are read-only previews).
- `SystemWallpaperService` implements the `WallpaperServicing` protocol, which `AppModel` takes as an injectable (the `FakeWallpaperService` in tests implements it too). Activation applies the linked selection via `WallpaperSelectionStore`, then terminates `WallpaperAgent`/`WallpaperAerialsExtension` to refresh and verifies; System Settings opens only for onboarding/manual fallback, not activation.
- `ManifestStore` owns the `aerials/entries.json` catalogue; `WallpaperSelectionStore` separately owns the private `Store/Index.plist` selection format (compare-before-write binary plist, backed up to `Store/AerialDropBackups`). The two Apple-owned formats have unrelated preservation contracts — never conflate them.
- `ContentView` itself only hosts the sidebar/destination scaffolding — no business logic; the pane structure it instantiates (Library ↔ Import) is what matters.
- Import geometry and per-import options live in pure functions: `VideoGeometry.swift` (display size from preferred transform) and `ConversionOptions.swift` (crop pan/bands, quality→bitrate buckets, output-height clamping — never upscales). These are unit-tested; `VideoProcessor` and `ImportPane` consume them.
- `WallpaperPaths(homeDirectory:)` takes an injectable home. Tests always redirect into a temp dir; never point tests or new code at real user paths.
- Stable IDs live in `ManifestStore` (`categoryID`/`subcategoryID`, `categoryName = "AerialDrop"`).
- Errors funnel through the `AerialDropError` enum in Models.swift (localized descriptions surface directly in the UI).

## Versioning / release

- Version/build is in **AppVersion.swift** (single source; `Scripts/build-app.sh` parses it for Info.plist — update **both** `shortVersion` and `buildNumber` or the script exits 1).
- Release order matters: in one commit, bump AppVersion.swift **and** add the `## <version>` section to CHANGELOG.md, push it, then push tag `v<version>` pointing at that commit. release.yml's changelog extraction exits 1 if the section is missing, and the Info.plist version comes from AppVersion.swift — tagging a commit without either publishes the wrong version or fails the run (a moved tag is the only recovery). Release zips `dist/AerialDrop.app` as `AerialDrop-<version>-macOS.zip`.
- The Pages site hardcodes the current version as a no-JS/offline fallback: bump `v1.1.3` in `docs/index.html` (hero terminal output, `#expectVersion`, unzip commands, release chip) and the `applyRelease("v1.1.3", …)` fallback in `docs/app.js` in the same commit as AppVersion.swift, or visitors whose release fetch fails see a stale version. `Assets/icon.svg` and `docs/assets/icon.svg` must stay byte-identical, and `docs/assets/icon.png` must be regenerated from it when the art changes.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
