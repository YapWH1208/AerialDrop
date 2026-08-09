# Implementation Plan

## 1. Inputs

- Requirements: `./docs/requirements.md`, approved 2026-08-09
- Design: `./docs/superpowers/specs/2026-08-09-popout-preview-wallpaper-activation-design.md`
- Approved scope: local implementation and validation only; no push, PR, merge, tag, version bump, or release
- Target branch: `agent/popout-preview-wallpaper-activation`
- Base branch: `main` at `a37eaabd10ae47472504be0f76211f5b2c3ec9a3`
- Planning commit: `970e1b78ff91d8867ae2efac01a42fb21a1dbdf4`

## 2. Repository assessment

- Swift Package Manager executable targeting macOS 26 with Swift tools 6.2 and strict concurrency.
- App architecture: `AerialDropApp` scenes → `ContentView` pane scaffolding → main-actor `AppModel` orchestration → focused processor/stores/services.
- Existing import controls and crop math were introduced in the recent “Import & conversion controls” change. The implementation must extend those helpers rather than duplicate or reinterpret them.
- `VideoProcessor` currently owns private target-size/even-dimension helpers; these must move to a pure shared helper so preview metadata and encode output use identical math.
- `ManifestStore.mutateManifest` provides the repository precedent for compare-before-write, foreign-data preservation, unique backups, atomic replacement, and post-write verification.
- `SystemWallpaperService.refresh()` currently has three graph-confirmed callers: import, single removal, and remove-all. Activation integration must preserve the removal refresh paths.
- `ContentView` currently supports message-only alerts. Actionable activation failure requires a small typed alert state while retaining generic localized errors.
- CI already runs debug build, tests, release build, and app-bundle packaging on a self-hosted macOS 26 runner. No CI change is required unless implementation introduces a new command or reveals a coverage omission.
- Canonical validation commands are `swift build`, `swift test`, `swift build -c release`, and `./Scripts/build-app.sh`, with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if the default toolchain lacks XCTest.
- No database, migration system, lockfile, or third-party package dependency is involved.

### Initial Code Review Graph findings

- The refreshed graph at planning start contained 177 nodes and 1,984 edges across 27 parsed files.
- The architecture grouped code into four communities; relevant work spans the application/validation, crop tests, and SwiftUI/AppKit view communities.
- A hypothetical impact scan over the 10 primary files reported 59 directly changed nodes, 69 impacted nodes, and 15 affected files within two hops, so final review must watch for unintended coupling.
- The graph linked all `SystemWallpaperService.refresh()` callers accurately.
- The graph reported no tests for `ConversionOptions`, although `Tests/AerialDropTests/ConversionOptionsTests.swift` directly exercises its pure functions. This is a graph coverage limitation; manual inspection confirmed the tests.
- Earlier graph change detection did not enumerate the relevant recent commits, so Git log/diff inspection was used as the required manual fallback. It confirmed that crop geometry, transformed source resolution, output caps, and bitrate buckets evolved together in commits leading to `41de55f`; the new preview must consume those decisions rather than fork them.
- Current branch changes at plan start were documentation only. The graph was rebuilt at `970e1b7` and matched HEAD before this plan was written.

## 3. Technical decisions

| Decision | Recommended option | Alternatives | Rationale | Status |
|---|---|---|---|---|
| Private schema source | Sanitized fixture captured from a real Tahoe AerialDrop linked selection | Trust shared-chat sample; infer from PaperSaver | Fails closed and satisfies FR-021 | Approved; fixture pending |
| Fixture form | Reviewable sanitized plist subtree; tests serialize a full binary `Index.plist` | Commit opaque binary only; construct schema only in Swift | Keeps provenance reviewable while testing binary round trips | Approved |
| Selection boundary | New `WallpaperSelectionStore` beside `ManifestStore` | Add logic to `ManifestStore`; add PaperSaver | Isolates two unrelated private formats | Approved |
| Selection mutation | Property-list copy, targeted linked replacements, semantic preservation assertions, byte CAS, backup, atomic write | Rewrite whole store from template; mutate with `defaults` | Matches existing safety invariants and preserves unknown keys/types | Approved |
| Selection scope | `AllSpacesAndDisplays`, `SystemDefault`, every `Spaces[*].Default` | Current Space/display only | Implements approved all-everywhere behavior | Approved |
| Apply coordination | `SystemWallpaperService` writes via selection store, refreshes processes, then verifies | Store launches processes; `AppModel` manipulates plist | Keeps persistence and process responsibilities separate | Approved |
| Service test seam | Main-actor wallpaper-service protocol with production implementation and test fake | Global hooks; no integration seam | Enables deterministic active/failure model tests under Swift 6 | Approved |
| Preference | Shared key/default helper plus SwiftUI `@AppStorage` Settings control | Model-only property; per-import toggle | Persistent, default-on, and testable | Approved |
| Preview window | Single SwiftUI `Window` scene sharing `AppModel` | `WindowGroup`; modal sheet | Dedicated reusable window without duplicates | Approved |
| Preview player | `AVPlayerView` + `AVQueuePlayer` + `AVPlayerLooper`, lifetime security scope | Still frames; custom transport controls | Native controls and deterministic looping | Approved |
| Crop overlay | Extract reusable overlay driven by existing pure crop fractions | Duplicate crop code | Keeps Import and pop-out visualization identical | Approved |
| Output metadata | Shared pure `encodedOutputSize` used by `VideoProcessor` and preview | Duplicate private geometry | Prevents preview/encode drift | Approved |
| Activation failure | Typed actionable alert, installed asset retained | Roll back entire import | Preserves successful catalogue installation | Approved |
| Active removal | Re-read live store immediately before removal and block matches | Trust cached badge; allow removal | Prevents dangling system selection | Approved |

## 4. Requirement coverage matrix

| Requirement ID | Implementation steps | Verification |
|---|---|---|
| FR-001–FR-007 | 4, 5 | `ConversionOptionsTests`, debug build, manual editor matrix |
| FR-008–FR-009 | 3 | preference unit tests, Settings inspection |
| FR-010–FR-011 | 6 | model tests with enabled/disabled fake preference/service, Tahoe imports |
| FR-012–FR-013 | 7 | debug build, Library interaction matrix |
| FR-014 | 1, 2, 6 | fixture transformation tests, multi-Space/display validation |
| FR-015–FR-016 | 2, 6, 7 | active-ID store/model tests, external-change manual test |
| FR-017–FR-018 | 6 | injected activation failure tests, actionable-alert manual test |
| FR-019–FR-020 | 6, 7 | live-ID removal tests, manual single/remove-all attempts |
| FR-021 | 1 | fixture provenance review and decoded configuration assertion |
| FR-022, FR-023, FR-024 | 2 | preservation, concurrency, backup, and binary-write tests |
| FR-025 | 2, 6 | service/store tests plus Tahoe apply verification |
| FR-026 | 4, 8, 9 | existing tests, full build ladder, lock/unlock log inspection |
| NFR-001 | All | Swift 6.2 builds under Tahoe 26 SDK |
| NFR-002–NFR-004 | 1, 2 | temporary-home tests only; backup and preservation assertions |
| NFR-005 | 4, 5 | no encode on editor changes; manual responsiveness |
| NFR-006 | All | dependency/diff review; no networking/logging of personal state |
| NFR-007 | 2, 6 | architecture and final graph review |
| NFR-008 | 3, 5, 7 | labels/help review and keyboard interaction |

## 5. Test and validation ladder

### 5.1 Before every commit

1. `git status --short`
2. Review the complete intended working-tree and staged diff.
3. `git diff --check`
4. Scan staged files for secrets, personal fixture values, and unrelated changes.
5. Run the smallest relevant `swift test --filter <TestClass>` where tests exist.
6. Run `swift build` for source/UI steps that are not fully compiled by a targeted test.

### 5.2 Per-step targeted checks

- Step 1: `plutil -lint` on the sanitized fixture; decode the embedded Configuration and confirm only deterministic IDs/timestamps remain.
- Step 2: `swift test --filter WallpaperSelectionStoreTests`.
- Step 3: `swift test --filter AppPreferencesTests` and `swift build`.
- Step 4: `swift test --filter ConversionOptionsTests` and `swift build`.
- Step 5: `swift build`; manual preview open/reuse/play/scrub/state/security-scope lifecycle checks.
- Step 6: `swift test --filter AppModelWallpaperTests`, `swift test --filter WallpaperSelectionStoreTests`, and `swift build`.
- Step 7: `swift build`; manual Library actions, badge refresh, retry/fallback, and removal guard checks.
- Step 8: `git diff --check` plus documentation cross-check against behavior.

### 5.3 Full pre-push suite

Run from the repository root in this order:

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release`
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh`
5. Manual Tahoe validation from `TESTING.md`, including multiple Spaces/displays, lock/unlock, reboot persistence, and `VideoSampleReadingErrors` inspection.
6. Final Code Review Graph `detect_changes`, affected flows, tests-for queries, and manual diff/history fallback where graph coverage is incomplete.

`build-app.sh` runs last because it wipes `.build` before packaging.

### 5.4 GitHub Actions jobs

The existing `build-and-test` job already covers debug build, unit tests, release build, and app packaging on macOS 26. No CI edit is planned. If a new test fixture cannot be located under SwiftPM resources, fix package resource declaration in the same coherent step; do not add a parallel CI job.

## 6. Implementation steps

### Step 1 — Capture and sanitize the Tahoe linked-Aerial fixture

- Requirement IDs: FR-021, NFR-002, NFR-003
- Purpose: Establish the exact private selection schema before any production mutation code exists.
- Files/modules:
  - `Tests/AerialDropTests/Fixtures/TahoeLinkedAerialSelection.plist`
  - `Package.swift` only if SwiftPM resource declaration is required
  - optional fixture provenance note in `TESTING.md`
- Actions:
  1. Require the user/system to select an existing AerialDrop wallpaper in System Settings.
  2. Confirm `AllSpacesAndDisplays.Type` is `linked` and the provider is the native Aerial provider, not Neptune or another extension.
  3. Read only the relevant linked subtree and binary Configuration payload.
  4. Replace the real asset ID, dates, display/Space identifiers, and any personal paths with deterministic fixture values.
  5. Store a reviewable plist fixture and prove it decodes to the accepted provider and asset-ID shape.
- Tests: Fixture decode assertion will be added with Step 2; Step 1 validates the artifact directly.
- Validation commands:
  - `plutil -lint Tests/AerialDropTests/Fixtures/TahoeLinkedAerialSelection.plist`
  - focused decode command recorded without personal output
- Commit message: `test: add Tahoe Aerial selection fixture`
- Dependencies: User-selected AerialDrop wallpaper on Tahoe 26.
- Risks: Capturing unrelated personal wallpaper state or accepting a non-Aerial provider.
- Rollback: Remove only the sanitized fixture commit; never alter the live store during capture.
- Status: [x] Completed in `da8c46c` after confirming the native Aerial provider and committing a sanitized Tahoe fixture.

### Step 2 — Implement the safe wallpaper selection store

- Requirement IDs: FR-014, FR-015, FR-021–FR-025, NFR-002–NFR-004, NFR-006, NFR-007
- Purpose: Provide fixture-locked, preservation-first read/write behavior independently of UI and process control.
- Files/modules:
  - `Sources/AerialDrop/WallpaperPaths.swift`
  - `Sources/AerialDrop/WallpaperSelectionStore.swift` (new)
  - `Sources/AerialDrop/Models.swift`
  - `Tests/AerialDropTests/WallpaperSelectionStoreTests.swift` (new)
  - fixture helper/resource configuration as required
- Actions:
  1. Add injectable `Index.plist` and selection-backup paths.
  2. Add typed loading and fail-closed linked Aerial ID decoding using `PropertyListSerialization`.
  3. Build linked choices from the accepted fixture shape with only asset ID and timestamps changed.
  4. Transform both global sections and every existing per-Space Default.
  5. Assert preservation outside targeted paths and validate property-list serializability.
  6. Re-read and compare original bytes, create a unique backup, atomically write binary data, and verify the written semantic structure.
  7. Expose current/expected asset-ID verification without launching processes.
- Tests: Fixture decode, global/per-Space updates, unknown values, unrelated displays, malformed/missing store, active ID, CAS refusal, backup uniqueness, binary output, and post-write verification.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WallpaperSelectionStoreTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- Commit message: `feat: add safe wallpaper selection store`
- Dependencies: Step 1.
- Risks: Shallow-copy mutation accidentally changing foreign subtrees; plist equality across Foundation bridge types.
- Rollback: Revert the store/path/error/test commit; no live store is touched by automated tests.
- Status: [x] Completed in `1149969` with temporary-home tests for fixture decoding, preservation, CAS, backup, binary output, and post-write verification.

### Step 3 — Add the persistent automatic-activation setting

- Requirement IDs: FR-008, FR-009, NFR-001, NFR-006, NFR-008
- Purpose: Provide a standard default-on macOS preference without per-import duplication.
- Files/modules:
  - `Sources/AerialDrop/AppPreferences.swift` (new)
  - `Sources/AerialDrop/Views/SettingsView.swift` (new)
  - `Sources/AerialDrop/AerialDropApp.swift`
  - `Tests/AerialDropTests/AppPreferencesTests.swift` (new)
- Actions:
  1. Define one shared preference key and absent-value default of `true` with injectable `UserDefaults` for tests.
  2. Add a Settings scene and accessible explanatory toggle using `@AppStorage` with the shared key/default.
  3. Keep the preference read at activation time so an open app honors the latest Settings value.
- Tests: Absent key → true, persisted false, persisted true, isolated suite cleanup.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppPreferencesTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- Commit message: `feat: add automatic wallpaper activation setting`
- Dependencies: None after plan approval; may proceed only under the active implementation goal.
- Risks: Tests polluting standard defaults or the UI and model using different keys/defaults.
- Rollback: Revert the preference/settings commit; existing users retain no project-specific preference dependency.
- Status: [x] Completed in `2850fab` with isolated UserDefaults coverage for unset/default-on and persisted values.

### Step 4 — Share exact encoded-output calculations

- Requirement IDs: FR-004, FR-007, FR-026, NFR-005
- Purpose: Guarantee preview metadata uses the same size and bitrate inputs as the native encoder.
- Files/modules:
  - `Sources/AerialDrop/ConversionOptions.swift`
  - `Sources/AerialDrop/VideoProcessor.swift`
  - `Tests/AerialDropTests/ConversionOptionsTests.swift`
- Actions:
  1. Move the private 16:9 target-size and even-dimension logic into hardened pure helpers.
  2. Add a single computed output descriptor containing even dimensions and bitrate for a source/options pair.
  3. Make `VideoProcessor` consume the shared helper without changing transforms, codec properties, timing, or validation.
  4. Cover ultrawide, 16:9, portrait, caps, no-upscale, even rounding, degenerate input, and quality buckets.
- Tests: Extend `ConversionOptionsTests`; existing geometry and manifest tests remain unchanged.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionOptionsTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- Commit message: `refactor: share import output calculations`
- Dependencies: None after plan approval.
- Risks: One-pixel/even-rounding drift changing actual encoding output.
- Rollback: Revert the helper refactor and tests; verify `VideoProcessor` returns to its original private math.
- Status: [x] Completed in `ec69220`; `VideoProcessor` now uses the tested shared output-size helper.

### Step 5 — Build the synchronized pop-out preview editor

- Requirement IDs: FR-001–FR-007, NFR-001, NFR-005, NFR-006, NFR-008
- Purpose: Provide live playback and every approved conversion control in one reusable window.
- Files/modules:
  - `Sources/AerialDrop/AerialDropApp.swift`
  - `Sources/AerialDrop/Views/ImportPane.swift`
  - `Sources/AerialDrop/Views/VideoPreview.swift`
  - `Sources/AerialDrop/Views/VideoCropOverlay.swift` (new)
  - `Sources/AerialDrop/Views/ImportPreviewPlayer.swift` (new)
  - `Sources/AerialDrop/Views/ImportPreviewView.swift` (new)
- Actions:
  1. Extract the existing mask into a reusable, non-interactive crop overlay.
  2. Add an `AVPlayerView` representable with looper, native controls, security-scope lifetime ownership, source-change replacement, and teardown.
  3. Add the single named preview `Window` sharing the root `AppModel`.
  4. Add Preview & Adjust to Import when a source exists.
  5. Bind crop, quality, and resolution directly to the same model state and show computed output metadata.
  6. Keep non-applicable crop controls hidden/disabled while preserving centered vertical crop behavior.
- Tests: Pure calculations and crop tests from Step 4; UI/player behavior is build- and manually-validated.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionOptionsTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
  - manual open/reopen/play/pause/scrub/source-change/state/lifecycle matrix
- Commit message: `feat: add pop-out import preview editor`
- Dependencies: Step 4.
- Risks: Security-scope imbalance, player observers/loopers leaking, duplicate windows, crop overlay not matching aspect-fit content bounds.
- Rollback: Revert the window/player/view commit; compact Import controls remain functional.
- Status: [x] Completed in `16106ca` with a reusable Window scene, native looping player, shared crop mask, and synchronized controls.

### Step 6 — Integrate activation, active state, and failure recovery

- Requirement IDs: FR-010, FR-011, FR-014–FR-020, FR-025, FR-026, NFR-001, NFR-006, NFR-007
- Purpose: Make automatic and manual activation reliable without coupling import installation rollback to activation.
- Files/modules:
  - `Sources/AerialDrop/SystemWallpaperService.swift`
  - `Sources/AerialDrop/AppModel.swift`
  - `Sources/AerialDrop/Models.swift`
  - `Sources/AerialDrop/ContentView.swift`
  - `Tests/AerialDropTests/AppModelWallpaperTests.swift` (new)
- Actions:
  1. Add a narrow main-actor service protocol and default production service using `WallpaperSelectionStore`.
  2. Implement apply: write selection, refresh both processes, bounded wait, semantic verification.
  3. Split import installation from post-install activation so activation errors never enter file/manifest cleanup.
  4. Read the automatic preference at the post-install decision point; disabled mode performs refresh only.
  5. Add cached active ID and refresh it at initialization, reload, app activation, and apply completion.
  6. Add typed activation-failure state carrying retry target and actions; retain generic localized alerts.
  7. Re-read live active ID immediately before single/remove-all mutations and block dangerous removal.
  8. Preserve existing refresh behavior for successful non-active removals.
- Tests: Fake service/preferences cover manual success/failure, retry target, enabled/disabled post-install choice, active refresh, live removal blocking, and non-active removal delegation. Store tests cover process-independent verification.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppModelWallpaperTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WallpaperSelectionStoreTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- Commit message: `feat: activate imported Aerials in app`
- Dependencies: Steps 2 and 3.
- Risks: Main-actor protocol isolation, accidental cleanup of an installed asset, stale active state, and process restart races.
- Rollback: Revert integration commit; the safe store and preference remain unused, and original refresh/Settings flow can be restored.
- Status: [x] Completed in `21f242f` and `2493dce`; activation is separate from installation, active selection is re-read before removals, and failures offer retry/Settings recovery.

### Step 7 — Add Library activation UI and Active badges

- Requirement IDs: FR-012, FR-013, FR-015–FR-020, NFR-008
- Purpose: Expose manual activation, status, retry/fallback, and removal protection clearly.
- Files/modules:
  - `Sources/AerialDrop/Views/LibraryPane.swift`
  - `Sources/AerialDrop/Views/WallpaperCard.swift`
  - `Sources/AerialDrop/Views/WallpaperPreviewView.swift`
  - `Sources/AerialDrop/ContentView.swift` if final alert wiring is needed
- Actions:
  1. Add Set as Wallpaper to card context menus and a prominent preview-sheet action.
  2. Pass active state separately from selected/installed state and render an accessible Active badge.
  3. Disable conflicting actions while work is in progress.
  4. Surface removal-block and activation-failure actions without changing generic error behavior.
- Tests: Existing/new model tests validate actions; UI is compile- and manually-validated.
- Validation commands:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppModelWallpaperTests`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
  - manual Library context/preview/badge/retry/fallback/removal matrix
- Commit message: `feat: add Library wallpaper activation controls`
- Dependencies: Step 6.
- Risks: Badge meaning conflated with installed checkmark or actions callable during another mutation.
- Rollback: Revert Library UI commit; automatic activation remains available.
- Status: [x] Completed in `cafacf3` with card/preview activation actions and separate accessible Active status.

### Step 8 — Update user and maintainer documentation

- Requirement IDs: FR-026, NFR-006, NFR-007
- Purpose: Make the new workflow, private-store risk, recovery, and validation repeatable.
- Files/modules:
  - `README.md`
  - `ARCHITECTURE.md`
  - `TESTING.md`
  - `CHANGELOG.md` only if the maintainer wants an unreleased entry; no release/version section is created automatically
- Actions:
  1. Replace manual-selection-as-normal-flow instructions with default-on automatic activation and Library actions.
  2. Document Settings, preview editor, Active badge, backups, failure fallback, and active removal guard.
  3. Extend architecture with the separate selection store and install/apply commit points.
  4. Add fixture provenance and complete manual Tahoe validation steps.
- Tests: Documentation cross-check against implemented labels and file paths.
- Validation commands:
  - `git diff --check`
  - focused link/path review
- Commit message: `docs: document preview and in-app activation`
- Dependencies: Steps 5–7.
- Risks: Documentation promising behavior not verified manually.
- Rollback: Revert documentation commit without touching production behavior.
- Status: [x] Completed with the current documentation commit.

### Step 9 — Final validation and graph review

- Requirement IDs: All
- Purpose: Prove the complete implementation and detect cross-cutting regressions before completion.
- Files/modules: No planned changes; fixes discovered here receive their own focused commit.
- Actions:
  1. Review all commits and diff against `a37eaab`/`main`.
  2. Run the full validation ladder.
  3. Build/package and manually exercise the approved Tahoe matrix.
  4. Update Code Review Graph and run change detection, affected-flow, impact, and tests-for queries.
  5. Manually inspect Git history/diffs/dependencies where graph coverage is missing.
  6. Confirm no secrets, personal fixture data, unrelated changes, release bump, or remote actions.
- Tests: Full suite and manual matrix.
- Validation commands: Section 5.3 in full.
- Commit message: None unless a verified finding requires a focused fix.
- Dependencies: Steps 1–8.
- Risks: Private `WallpaperAgent` behavior cannot be fully proven by unit tests.
- Rollback: Use the original `Index.plist` backup for manual system recovery if validation reveals a schema problem; revert only focused local commits as authorized.
- Status: [ ]

## 7. Data and migration plan

- No `entries.json` migration and no changes to existing managed asset records.
- Add two injectable paths under `WallpaperPaths`: the system selection store and `Store/AerialDropBackups`.
- The new preference uses an absent-value default of true; no eager defaults migration is needed.
- The active ID is derived ephemeral state and is never persisted by AerialDrop.
- Selection-store mutation is additive/replacement only at approved linked-selection paths. Unknown root, display, Space, and nested values remain untouched.
- Backups are never pruned by this requirement.
- No production data mutation occurs during automated tests.

## 8. Security review plan

- Inspect the captured fixture before commit for real asset IDs, display/Space UUIDs, usernames, file URLs, dates that identify user activity, and unrelated wallpaper choices.
- Keep source preview access read-only and balance every security-scope start with teardown stop.
- Add no network, telemetry, shell interpolation from untrusted values, elevated privileges, or credentials.
- Build process arguments as arrays and retain fixed `/usr/bin/killall` process names.
- Before every commit, inspect staged content for secrets and unrelated personal data.
- Treat malformed property-list values as errors, not commands or paths to execute.

## 9. Observability plan

- Reuse `ImportStage` with wording that distinguishes catalogue installation from wallpaper activation.
- Show an actionable, localized activation failure after a successful install.
- Reflect current linked ID through the Active badge.
- Keep process stdout/stderr suppressed as today; user-facing verification failures are sufficient and avoid leaking system data.
- Use the existing macOS log check in `TESTING.md` for playback regressions.

## 10. Documentation plan

- README: features, Settings default, Import flow, Library activation, fallback, private-format compatibility.
- ARCHITECTURE: install/apply split, `WallpaperSelectionStore`, all-Space transformation, process restart, verification.
- TESTING: sanitized fixture capture, Settings combinations, editor lifecycle, multi-Space/display, active removal, recovery backup, lock/unlock/reboot logs.
- Requirements/design/plan/goal remain workflow artifacts and do not substitute for product documentation.

## 11. Rollout and rollback

- Rollout is local only on the dedicated feature branch.
- No branch push, PR, merge, tag, version bump, or release is authorized.
- The feature defaults automatic activation on for existing users, with a Settings opt-out.
- Each coherent step is a separate commit so code can be reviewed or reverted independently without history rewriting.
- `Index.plist` backup is the system-data recovery point. Automatic rollback after a failed verification is prohibited because newer legitimate system changes could exist.
- If the private schema is not confirmed, stop before Step 2; preview/settings work must not be represented as completing wallpaper activation.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Current selection is Neptune, not an Aerial | Step 1 hard gate; no schema implementation until native Aerial fixture exists |
| Private Tahoe schema changes | Fixture-locked parsing, fail closed, future-version revalidation |
| Unknown wallpaper data is lost | Targeted transform, preservation tests, CAS, backup, atomic write |
| WallpaperAgent rejects an incomplete choice | Ground-truth fields, process restart, semantic verification |
| Per-Space entry overrides globals | Update and verify every existing `Spaces[*].Default` |
| Preview disagrees with encoder | Shared pure output helper and existing crop functions |
| Security-scoped resource leaks | Player owns lifetime start/stop and deterministic teardown |
| Activation failure deletes installed import | Separate commit points and injected failure tests |
| Active badge becomes stale | Refresh on lifecycle/reload/apply and live re-read before deletion |
| Swift 6 concurrency diagnostics | Main-actor UI/service protocol, Sendable-safe callbacks, build each step |
| Code Review Graph misses test edges | Record graph output and manually inspect tests/diffs/history |

## 13. Deviations and user decisions

- User requested all outstanding questions together; all recommended behavior was approved.
- User approved the written requirements by directing the workflow to proceed.
- Current wallpaper provider remained `com.apple.NeptuneOneExtension`; this does not satisfy the approved fixture prerequisite.
- Publication is not in scope because the user did not authorize push or PR creation.
- Existing CI is complete for repository commands, so the template's optional CI-first implementation step is intentionally omitted.

## 14. `/goal` implementation handoff

- Goal title: Implement pop-out preview and in-app Aerial activation
- Goal scope: implementation only through full local and manual validation
- Goal source file: `./docs/implementation-goal.md`
- First execution reference: `references/execute-plan.md`
- Goal checkpoints:
  1. Fixture gate satisfied and sanitized artifact committed.
  2. Safe selection store tested and committed.
  3. Settings and shared output calculations tested and committed.
  4. Pop-out editor built and manually checked.
  5. Activation/model and Library UI tested and committed.
  6. Documentation updated.
  7. Full validation and final graph/manual review completed.

## 15. Definition of done

- All FR-001–FR-026 and NFR-001–NFR-008 have evidence in the coverage matrix.
- Every implementation step is a focused local commit on the target branch.
- The sanitized fixture is traceable to a real Tahoe linked Aerial selection and contains no personal data.
- `swift build`, `swift test`, `swift build -c release`, and `Scripts/build-app.sh` succeed with fresh output.
- The full manual Tahoe matrix succeeds, including all Spaces/displays, Settings on/off, retry/fallback, Active badge, guarded removal, lock/unlock, reboot, and log inspection.
- Final Code Review Graph and documented manual fallback find no unintended changes, missing related changes, inconsistent implementation, architectural conflicts, or unexplained files.
- Working tree and staged state contain no unrelated or sensitive files.
- No remote operation or release action occurs.
