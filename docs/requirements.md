# Requirements

## 1. Document control

- Status: Approved
- Version: 1.0
- Owner: AerialDrop
- Last updated: 2026-08-09

## 2. Problem statement

AerialDrop's Import pane provides only a still-frame crop preview, so conversion choices cannot be evaluated against moving content in a dedicated workspace. After import, the app only refreshes Apple's catalogue and opens System Settings, requiring manual activation every time. Users need a synchronized pop-out editor and safe in-app activation of the native linked Aerial across all Spaces and displays.

## 3. Goals and success metrics

- Provide one dedicated, reusable window for live preview of every existing import modification.
- Make a newly imported wallpaper active automatically by default.
- Allow any installed AerialDrop wallpaper to be activated from Library.
- Preserve Apple's native Aerial playback and every unrelated wallpaper-store value.
- Pass all automated repository checks and the Tahoe manual-validation matrix.

## 4. Users and stakeholders

- Primary user: a macOS Tahoe user importing personal MP4/MOV files.
- Maintainer: the AerialDrop project owner responsible for private-schema compatibility.
- External system: macOS `WallpaperAgent`, `WallpaperAerialsExtension`, Aerial catalogue, and wallpaper selection store.

## 5. Scope

### 5.1 In scope

- Live pop-out preview with crop, quality, and resolution controls.
- Persistent default-on automatic activation setting.
- Manual Library activation and active-state display.
- Linked activation across all Spaces and displays.
- Safe, backed-up, concurrent-change-aware `Index.plist` mutation.
- Active-wallpaper removal protection.
- Automated and manual validation plus affected documentation.

### 5.2 Out of scope

- Per-display or per-Space UI.
- Wallpaper-only or screensaver-only modes.
- An app-managed desktop player.
- New video-editing operations.
- Encoding-contract changes.
- PaperSaver or other dependencies.
- macOS 27 support without a separately validated fixture.
- Release publication.

## 6. User journeys

1. The user selects a source, opens Preview & Adjust, plays or scrubs the video, changes crop/quality/resolution, closes the window, and imports with the same choices preserved.
2. With the default setting enabled, a successful import becomes the active linked Aerial everywhere without opening System Settings.
3. With the setting disabled, import succeeds and refreshes the catalogue without changing the active wallpaper.
4. The user activates any installed item from a Library card or its preview and sees its Active badge.
5. If activation fails, the installed item remains and the user can retry or open Wallpaper Settings.
6. If the user tries to remove the active item, AerialDrop blocks the operation until another wallpaper is selected.

## 7. Functional requirements

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-001 | The app MUST expose Preview & Adjust after a valid source video is selected. | Must | AC-001 |
| FR-002 | Preview & Adjust MUST open one reusable dedicated window and MUST NOT create duplicate editor windows. | Must | AC-001 |
| FR-003 | The editor MUST autoplay the source in a loop and provide native play/pause and scrubbing controls. | Must | AC-002 |
| FR-004 | The editor MUST show live 16:9 crop masks matching the encode crop for ultrawide, portrait, and non-16:9 landscape sources. | Must | AC-003 |
| FR-005 | The editor MUST include crop position, quality, and output-resolution controls. | Must | AC-004 |
| FR-006 | Editor and Import controls MUST share state bidirectionally, and closing the editor MUST NOT reset values. | Must | AC-004 |
| FR-007 | The editor SHOULD show source metadata, computed output dimensions, and computed bitrate. | Should | AC-005 |
| FR-008 | The app MUST add a macOS Settings scene with “Set as wallpaper after importing.” | Must | AC-006 |
| FR-009 | The automatic-activation preference MUST default to `true` when unset and MUST persist user changes. | Must | AC-006 |
| FR-010 | A successful import MUST activate the new Aerial when the preference is enabled. | Must | AC-007 |
| FR-011 | A successful import MUST only refresh the catalogue when the preference is disabled and MUST NOT open System Settings automatically. | Must | AC-008 |
| FR-012 | Library cards MUST provide “Set as Wallpaper” in their context menus. | Must | AC-009 |
| FR-013 | The Library preview MUST provide a prominent “Set as Wallpaper” action. | Must | AC-009 |
| FR-014 | Activation MUST use linked native Aerial behavior across `AllSpacesAndDisplays`, `SystemDefault`, and every existing `Spaces[*].Default`. | Must | AC-010 |
| FR-015 | The app MUST read and display the active managed asset ID separately from installed-file status. | Must | AC-011 |
| FR-016 | Active state MUST refresh after startup, reload, in-app activation, and return from external wallpaper changes. | Must | AC-011 |
| FR-017 | Activation failure after manifest installation MUST NOT remove the imported video, thumbnail, or manifest entry. | Must | AC-012 |
| FR-018 | Activation failure MUST offer Try Again and Open Wallpaper Settings. | Must | AC-012 |
| FR-019 | Removing the active managed wallpaper MUST be blocked until another wallpaper is active. | Must | AC-013 |
| FR-020 | Remove All MUST be blocked while any managed wallpaper is active. | Must | AC-013 |
| FR-021 | The exact Aerial selection payload MUST be derived from a sanitized Tahoe fixture captured after manual System Settings selection. | Must | AC-014 |
| FR-022 | The wallpaper selection store MUST preserve every value outside the explicitly targeted linked-selection paths. | Must | AC-015 |
| FR-023 | The store MUST refuse to write if `Index.plist` changed after its initial read. | Must | AC-016 |
| FR-024 | The store MUST create a recoverable backup before every write and replace `Index.plist` atomically. | Must | AC-017 |
| FR-025 | Activation MUST restart the relevant Apple wallpaper processes and verify the expected asset ID afterward. | Must | AC-018 |
| FR-026 | The existing HEVC Main10 encoding, loop-boundary, thumbnail-content, and manifest-preservation contracts MUST remain unchanged. | Must | AC-019 |

## 8. Non-functional requirements

| ID | Category | Requirement | Target |
|---|---|---|---|
| NFR-001 | Compatibility | Production behavior MUST target macOS Tahoe 26 and Swift 6.2 strict concurrency. | Build and run on the repository's supported environment. |
| NFR-002 | Data safety | No test MUST read or write the real user wallpaper catalogue or selection store. | All filesystem tests use an injected temporary home. |
| NFR-003 | Preservation | Unknown property-list keys and supported property-list value types MUST round-trip unchanged outside targeted paths. | Exact semantic equality in fixtures. |
| NFR-004 | Recovery | Every selection-store write MUST have a uniquely named backup. | Backup readable as the original binary plist. |
| NFR-005 | Responsiveness | Preview playback and control updates SHOULD remain interactive without re-encoding. | No encode starts until Import. |
| NFR-006 | Privacy | Preview, preference, and activation features MUST operate locally without transmitting filenames, video content, or wallpaper state. | No new network integration. |
| NFR-007 | Maintainability | Private manifest and private selection-store logic MUST remain in separate focused stores. | No `Index.plist` mutation in `ManifestStore`. |
| NFR-008 | Accessibility | New controls MUST have meaningful labels, help, and keyboard-accessible native behavior. | Manual accessibility inspection. |

## 9. Interfaces and integrations

- `AerialDropApp`: owns the main `WindowGroup`, preview `Window`, and Settings scene.
- `ImportPane`: opens the preview editor and retains compact controls.
- `ImportPreviewView`: binds to current source and conversion state.
- Preview player representable: owns local AVFoundation playback only.
- `AppModel`: coordinates preview state, import, activation, active ID, retry, and removal guards.
- `WallpaperSelectionStore`: reads, transforms, backs up, atomically writes, and verifies `Index.plist` selection data.
- `SystemWallpaperService`: restarts Apple processes and opens System Settings as fallback.
- `WallpaperPaths(homeDirectory:)`: provides injectable selection-store and backup paths.
- `UserDefaults`: stores the automatic-activation preference.

## 10. Data model and lifecycle

- The conversion state remains `selectedVideo`, `cropOffset`, `conversionQuality`, `outputHeightCap`, and source metadata in `AppModel`.
- The automatic-activation preference is a persisted Boolean whose absent value resolves to `true`.
- The active wallpaper ID is runtime state derived from the wallpaper store; it is not added to `entries.json`.
- Selection backups live under the wallpaper Store directory in `AerialDropBackups` and are never treated as active state.
- Activation uses the stable uppercase UUID already assigned to the manifest asset.

## 11. Security and privacy

- The implementation MUST NOT log or transmit personal video paths or full wallpaper-store content.
- Source videos remain security-scoped and read-only during preview.
- The pop-out player MUST retain security-scoped access only for the playback lifetime and release it during teardown.
- The selection store MUST not follow instructions or data from external content; fixture values are treated as untrusted input until validated against expected property-list types.
- No privilege escalation, root write, credential, or network dependency is introduced.

## 12. Reliability, recovery, and failure behavior

- Import installation and wallpaper activation are separate commit points.
- Activation failure leaves a valid installed asset and exposes retry/fallback actions.
- Concurrent wallpaper-store mutation causes a no-write failure.
- Verification failure retains the backup but does not automatically restore it over potentially newer system state.
- Missing or malformed stores produce localized errors and never synthesize a replacement store.
- Removal MUST re-read the live active selection before mutation, and active items cannot be removed into a dangling selection.

## 13. Observability and operations

- UI progress distinguishes catalogue installation from wallpaper activation.
- Localized errors state whether import succeeded but activation failed.
- Manual testing inspects `WallpaperAerialsExtension` logs for `VideoSampleReadingErrors Code=4`.
- Backups provide operator-visible recovery artifacts without background telemetry.

## 14. Compatibility and migration

- The current release remains Tahoe 26-only.
- Existing managed wallpapers require no manifest migration.
- Existing users receive the automatic setting as enabled because the absent preference key maps to `true`.
- A future macOS schema must be captured and revalidated before support is claimed.

## 15. Testing requirements

- Add `WallpaperSelectionStoreTests` using sanitized binary-plist fixtures and an injected temporary home.
- Add preference tests for absent/default-on and persisted-off behavior.
- Add pure output-geometry and bitrate tests used by the preview.
- Run `swift build`, `swift test`, `swift build -c release`, and `./Scripts/build-app.sh`.
- Complete the manual Tahoe matrix for preview lifecycle, all controls, automatic/manual activation, Spaces, displays, external changes, failure fallback, active removal, lock/unlock, reboot, and playback logs.

## 16. Deployment and rollout

- Implement on `agent/popout-preview-wallpaper-activation` in coherent tested commits.
- Do not push, publish a PR, tag, merge, or release without separate authorization.
- Do not bump `AppVersion` or CHANGELOG release sections as part of local implementation unless separately requested.

## 17. Dependencies

- Existing AppKit, SwiftUI, AVFoundation/AVKit, Foundation, Observation, and XCTest only.
- A manually selected AerialDrop fixture from a Tahoe 26 system is a prerequisite for selection-store implementation.
- The existing Aerial catalogue manifest and wallpaper store must be present for manual end-to-end validation.

## 18. Risks and mitigations

- Private schema changes: fixture-driven implementation, fail-closed parsing, future-version revalidation.
- WallpaperAgent in-memory state: restart both relevant processes and verify after a bounded wait.
- Multi-Space overrides: update global/default and every existing per-Space Default section.
- Unrelated data corruption: copy-on-write property-list transformation, preservation assertions, compare-before-write, backup, atomic replacement.
- Playback resource leaks: deterministic player teardown on source or scene lifecycle changes.
- Strict concurrency errors: keep UI/model ownership on `@MainActor` and isolate process/player callbacks safely.

## 19. Assumptions

- One active linked Aerial ID applies everywhere after AerialDrop's all-Spaces/all-displays operation.
- The selected source remains available through its security-scoped URL while the preview is open.
- The manually captured fixture represents the supported Tahoe 26 schema and is sanitized before commit.
- System Settings remains the only fallback when the private activation mechanism fails.

## 20. Decision log

| Decision | Recommended choice | Alternatives | Rationale | User confirmation |
|---|---|---|---|---|
| Automatic activation | Settings preference, persistent and default on | Library-only; unconditional activation | One-click default without removing user control | Approved 2026-08-09 |
| Editor scope | Crop, quality, and resolution | Crop only; read-only preview | Every import modification belongs in the dedicated editor | Approved 2026-08-09 |
| Activation scope | All Spaces and displays | Current Space/display only | Matches linked native Aerial behavior | Approved 2026-08-09 |
| Preview playback | Loop with play/pause and scrubber | Static frame; loop without controls | Moving content and crop timing can be inspected | Approved 2026-08-09 |
| Control placement | Shared controls in Import and pop-out | Move controls entirely | Compact workflow plus focused editor | Approved 2026-08-09 |
| Library UX | Context action, preview action, Active badge | Context action only; card button | Discoverability without card clutter | Approved 2026-08-09 |
| Activation failure | Preserve import; retry and Settings fallback | Roll back import | Catalogue installation remains valid | Approved 2026-08-09 |
| Active removal | Block until another wallpaper is active | Allow dangling selection | Protect system configuration | Approved 2026-08-09 |
| Selection implementation | Focused internal store with fixture | PaperSaver dependency; public image API | Minimum scope and native Aerial behavior | Approved 2026-08-09 |

## 21. Open questions

No product decisions are open. Production selection-store implementation is gated on capturing the accepted Tahoe ground-truth fixture; the current selection was still `com.apple.NeptuneOneExtension` when planning began.

## 22. Acceptance criteria index

| ID | Requirement IDs | Verification method |
|---|---|---|
| AC-001 | FR-001, FR-002 | Manual window lifecycle test |
| AC-002 | FR-003 | Manual playback/control test |
| AC-003 | FR-004 | Pure crop tests plus visual manual test |
| AC-004 | FR-005, FR-006 | UI state synchronization test and build |
| AC-005 | FR-007 | Pure calculation tests and visual inspection |
| AC-006 | FR-008, FR-009 | Preference unit tests and Settings inspection |
| AC-007 | FR-010 | Manual enabled import on Tahoe |
| AC-008 | FR-011 | Manual disabled import on Tahoe |
| AC-009 | FR-012, FR-013 | Library interaction test |
| AC-010 | FR-014 | Fixture tests plus multi-Space/display manual verification |
| AC-011 | FR-015, FR-016 | Active-ID tests and external-change manual test |
| AC-012 | FR-017, FR-018 | Injected activation failure plus UI test |
| AC-013 | FR-019, FR-020 | Model/store removal-guard tests and manual interaction |
| AC-014 | FR-021 | Sanitized fixture review against real Tahoe selection |
| AC-015 | FR-022 | Semantic preservation assertions |
| AC-016 | FR-023 | Concurrent-change test |
| AC-017 | FR-024 | Backup and binary atomic-write tests |
| AC-018 | FR-025 | Active-ID unit tests and Tahoe end-to-end verification |
| AC-019 | FR-026 | Existing test suite, release build, app bundle, lock/unlock logs |
