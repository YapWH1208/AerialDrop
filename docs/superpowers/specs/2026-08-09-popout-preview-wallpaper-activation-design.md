# Pop-out Preview and In-App Wallpaper Activation Design

**Status:** Design approved; written specification pending user review

**Date:** 2026-08-09

**Target:** AerialDrop for macOS Tahoe 26

**Branch:** `agent/popout-preview-wallpaper-activation`

## Purpose

AerialDrop currently previews only a generated still frame in the Import pane and requires the user to finish every import by selecting the new Aerial in System Settings. This change adds a dedicated, synchronized video editor window and makes AerialDrop capable of activating an imported Aerial across all Spaces and displays.

The implementation must continue using Apple's Aerial renderer. It must not add an app-managed desktop player, change the native encoding contract, or replace the manifest-preserving `ManifestStore` design.

## Decisions

- The preview opens as a dedicated, single-instance SwiftUI window.
- The window includes live video playback, crop controls, quality, and output resolution.
- Controls in the pop-out and Import pane share the same `AppModel` state.
- The app gains a standard macOS Settings scene.
- “Set as wallpaper after importing” is persistent and defaults to enabled.
- Wallpaper activation targets all Spaces and displays using linked Aerial behavior.
- Library cards expose “Set as Wallpaper”; the preview sheet also exposes a prominent activation button.
- The currently applied managed wallpaper has a distinct Active badge.
- Activation failure does not roll back a successful import.
- Removing an active managed wallpaper is blocked until another wallpaper is selected.
- AerialDrop will implement a focused `WallpaperSelectionStore`, not add PaperSaver as a dependency.
- The private wallpaper-store write must be based on a sanitized record captured from a real Tahoe AerialDrop selection before production implementation begins.

## Considered approaches

### 1. Focused in-repository store and native preview window — selected

Add a small `WallpaperSelectionStore` beside `ManifestStore`, plus a SwiftUI preview `Window`. This follows the repository's existing boundaries, adds no dependency, and limits private-schema handling to the exact Aerial selection operation AerialDrop needs.

### 2. Add PaperSaver

PaperSaver contains useful Sonoma-and-later wallpaper-store research, but its wallpaper API is broader than this requirement and the project identifies itself as work in progress. Depending on it would increase maintenance and schema surface without removing AerialDrop's need to validate the Aerial provider's Tahoe-specific configuration.

### 3. Public desktop-image API or custom player

`NSWorkspace.setDesktopImageURL` handles image backgrounds, not the native Aerial pipeline. A custom desktop player would lose the native Screen Saver → Lock Screen → slowdown → static desktop behavior that defines AerialDrop. Neither approach satisfies the requirement.

## Architecture

```text
ImportPane ───────────────┐
                         ├── shared AppModel conversion state
ImportPreviewWindow ─────┘
          │
          └── source playback + crop mask + computed output metadata

AppSettings/UserDefaults
          │
          └── apply after import (default true)

AppModel
  ├── VideoProcessor               existing native encode
  ├── ManifestStore                existing entries.json preservation
  ├── WallpaperSelectionStore      new Index.plist preservation
  └── SystemWallpaperService       restart agents + Settings fallback
```

`ContentView` remains pane and toolbar scaffolding. Business logic stays in `AppModel` and focused stores/services.

## Pop-out preview editor

### Window behavior

`AerialDropApp` adds one named `Window` scene for import preview and adjustment. `ImportPane` exposes “Preview & Adjust” only when a source video is selected and opens that scene through SwiftUI's window environment.

The scene is single-instance rather than a `WindowGroup`. Repeated button presses bring the same editor forward. Selecting a different source updates the open window. Closing it does not reset the selection or conversion settings.

### Playback

The editor uses an `AVPlayerView`-backed representable with an `AVQueuePlayer` and `AVPlayerLooper`, providing:

- automatic looping playback;
- native play/pause controls;
- a scrubber;
- aspect-fit source presentation;
- deterministic teardown when the scene or source changes.

The player holds the source URL's security-scoped access for the lifetime of that playback session and releases it during teardown. It is a preview only: it never becomes a desktop player or modifies the source file.

### Live crop visualization

The preview shows the entire transformed source and dims the regions discarded by the 16:9 encode window:

- left/right bands for sources wider than 16:9;
- top/bottom bands for sources narrower than 16:9;
- no bands for exact 16:9 sources.

Horizontal crop position is adjustable only where the encode has horizontal excess. Portrait and 4:3 sources retain the existing centered vertical crop.

The existing pure crop helpers remain authoritative. New preview output calculations are also pure functions and are tested independently of AVFoundation UI.

### Controls and metadata

The editor includes:

- Left, Center, and Right crop presets when applicable;
- continuous crop-position slider when applicable;
- Standard, High, and Maximum quality;
- Original or meaningful downscale-only output-height caps;
- source resolution, duration, and file size;
- computed encoded dimensions and bitrate.

The existing Import-pane controls stay available in compact form. Both surfaces bind directly to the same model properties, so every update is immediate and bidirectional.

## Settings

Add a standard SwiftUI `Settings` scene with a General settings view. It contains one preference:

> Set as wallpaper after importing

The preference is stored in `UserDefaults`, defaults to `true` when the key is absent, and is read at the point the import reaches activation. The Settings text explains that activation applies the native linked Aerial across all Spaces and displays.

There is no duplicate per-import checkbox. The global setting is the sole automatic-activation control.

## Wallpaper selection store

### Scope

`WallpaperSelectionStore` owns only:

`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`

It must not absorb manifest behavior or mutate `entries.json`. `WallpaperPaths(homeDirectory:)` is extended with injectable wallpaper-store and selection-backup paths so every unit test uses a temporary home directory.

### Ground-truth prerequisite

Before writing the production transformation, a user must manually select an existing AerialDrop asset once in System Settings on Tahoe. A read-only capture will extract only the relevant linked selection structure and replace personal identifiers and timestamps with deterministic fixture values.

The fixture becomes the authoritative schema for:

- the linked section shape;
- provider identifier;
- binary `Configuration` payload shape;
- required content fields and sentinels;
- the top-level and per-Space locations macOS writes.

No implementation may guess a private-schema field that the captured fixture can establish.

### Mutation contract

The store performs a read-transform-compare-backup-write-verify sequence:

1. Read the original `Index.plist` bytes.
2. Decode with `PropertyListSerialization` into property-list objects.
3. Build the linked Aerial selection from the sanitized ground-truth schema using the requested asset ID.
4. Update `AllSpacesAndDisplays`, `SystemDefault`, and every existing `Spaces[*].Default` section.
5. Preserve every unrelated root key, display entry, Space field, unknown field, and value type.
6. Re-read the file immediately before writing and require byte equality with the original bytes.
7. Write a uniquely named backup under `Store/AerialDropBackups`.
8. Serialize as a binary property list and replace the original atomically.

If the store changes between steps 1 and 6, the operation fails without writing.

### Activation and verification

`SystemWallpaperService.applyAerial(assetID:)` coordinates selection and process refresh:

1. Ask `WallpaperSelectionStore` to install the linked selection.
2. Restart `WallpaperAerialsExtension` and `WallpaperAgent` using the existing termination mechanism.
3. Wait briefly for macOS to reload its store.
4. Re-read the active Aerial ID.
5. Require the expected ID in every section the operation targeted.

Verification failure is reported as an activation failure. It does not automatically restore the backup because doing so could overwrite a legitimate system change made after AerialDrop's write. The backup remains available for manual recovery.

## Application flows

### Import with automatic activation enabled

```text
Validate source
  → Encode native Aerial MOV
  → Generate HEIF-content preview
  → Add manifest entry
  → Write linked selection to Index.plist
  → Restart Apple wallpaper processes
  → Verify active asset ID
  → Reload Library and show Active badge
```

Once the manifest entry is written, the import is considered installed. A later activation failure must not delete the video, thumbnail, or manifest entry.

### Import with automatic activation disabled

The existing catalogue processes are refreshed, the import completes, and System Settings is not opened automatically. The user can activate the entry later from Library.

### Manual Library activation

“Set as Wallpaper” appears in the card context menu and as a prominent button in `WallpaperPreviewView`. `AppModel` performs the same apply-and-verify operation used after import, then refreshes active state.

### Active-state display

`AppModel` maintains an optional active Aerial asset ID obtained from `WallpaperSelectionStore`. It refreshes after:

- app/model initialization;
- catalogue reload;
- automatic activation;
- manual activation;
- app activation after the user may have changed wallpaper externally.

The Library card's existing checkmark continues to mean “installed video exists.” A separate Active badge indicates the current linked Aerial.

### Removal protection

Immediately before removal, `AppModel` re-reads the live active Aerial ID from `WallpaperSelectionStore`; it does not rely only on the cached badge state. Removing a wallpaper whose ID equals that live ID is blocked with an explanation and an action to open Wallpaper Settings. The user must activate another wallpaper first. “Remove All” is also blocked while any managed Aerial is active.

## Error handling

New localized errors cover:

- missing wallpaper store;
- malformed or unsupported selection schema;
- store changed during operation;
- backup failure;
- atomic write failure;
- wallpaper did not activate after restart;
- attempt to remove an active wallpaper.

Automatic or manual activation failure presents:

- **Try Again**, which retries activation for the already installed asset;
- **Open Wallpaper Settings**, which invokes the existing fallback;
- a dismiss action.

Generic failures continue to surface through AerialDrop's localized error flow.

## Testing

### Automated tests

Add pure and temporary-filesystem tests for:

- exact Aerial provider/configuration generation from the sanitized fixture;
- updates to `AllSpacesAndDisplays`, `SystemDefault`, and all `Spaces[*].Default` entries;
- preservation of unrelated keys and property-list value types;
- binary output and uniquely named backups;
- byte-level concurrent-change refusal;
- active asset-ID detection and verification;
- missing and malformed store errors;
- default-true and persisted-false setting behavior;
- preview output dimensions, meaningful caps, and bitrate calculations.

No test may point at the user's real wallpaper directory.

### Repository validation

Run:

- `swift build`
- `swift test`
- `swift build -c release`
- `./Scripts/build-app.sh`

### Manual Tahoe validation

- Capture and sanitize a real manually selected AerialDrop linked record before implementation.
- Open, close, and reopen the preview editor; verify shared state is preserved.
- Change every editor control and confirm Import mirrors it.
- Import with automatic activation enabled and disabled.
- Apply multiple Library items in succession.
- Verify all existing Spaces and connected displays change.
- Verify Active badges after in-app and external changes.
- Exercise retry and Settings fallback behavior.
- Attempt to remove the active item and Remove All.
- Lock and unlock repeatedly, reboot, and verify persistence.
- Confirm no `VideoSampleReadingErrors Code=4` regression.

## Documentation

Update README usage/features, ARCHITECTURE data flow, and TESTING manual steps. Documentation must continue to disclose that AerialDrop depends on undocumented macOS formats and that future macOS versions require schema revalidation.

## Non-goals

- Supporting macOS versions earlier or later than Tahoe 26 without separate schema validation.
- Providing per-display or per-Space selection controls.
- Wallpaper-only or screensaver-only modes.
- Replacing Apple's renderer with an AerialDrop player.
- Editing video content beyond the existing crop, output resolution, and quality controls.
- Adding PaperSaver or another dependency.
- Changing the native encoding contract.
- Publishing, tagging, or releasing as part of this requirement.

## Completion criteria

The feature is complete when the pop-out editor works as specified, the setting defaults on and persists, both automatic and manual activation succeed across all Spaces and displays, active state is represented accurately, destructive removal is guarded, private-store writes meet the preservation and backup contract, automated checks pass, and the manual Tahoe workflow is completed without playback regressions.
