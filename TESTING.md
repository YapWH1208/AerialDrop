# Testing AerialDrop

## Local checks

On macOS Tahoe 26 with the macOS 26 SDK, Swift 6.2+, and an Xcode installation
whose license has been accepted, run `swift build`, `swift test`, and
`swift build -c release`. Run `bash Scripts/test-install.sh` for offline release
metadata, argument, and mocked-install checks, and
`Scripts/check-docs-version.sh` for the website's release fallback. The installer
smoke test uses a temporary directory and never contacts GitHub or installs into
Applications. Wallpaper store and `AppModel` failure/relaunch/race tests use
temporary home directories and test fixtures; they must never modify real
wallpaper data.

Run this matrix on macOS Tahoe 26 with at least one short and one longer MP4/MOV
source. Use a separate test account for the setup-required checks; do not move or
edit a real Aerial catalogue to simulate failure. Reimport sources with this
version before evaluating native playback.

## Onboarding and import UX

1. On a test account that has not downloaded an Apple Aerial, build and open
   AerialDrop. Confirm Library and Import both show **Set Up Apple Aerials**, explain the
   missing catalogue, and offer **Open Wallpaper Settings** and **Check Again**.
   File selection must remain unavailable until setup succeeds. Confirm the initial
   catalogue check has a named loading state instead of an empty pane.
2. Download an Apple Aerial in System Settings → Wallpaper, return to AerialDrop,
   and choose **Check Again**. Confirm the ready-but-empty Library shows its import
   action without a search field. After at least one import, confirm search appears.
3. Select a valid source. Confirm the Import pane shows a still-frame preview with
   a crop mask matching the source type, and that resolution, duration, and file
   size appear. Change crop, quality, and output resolution; confirm the preview
   mask and controls stay in sync. Confirm the toolbar shows **Replace Video…** and
   **Import Wallpaper** after selection, then replace the source and verify the preview
   follows it. Navigate to Library and confirm **Continue Import** returns to the draft.
   With the disclosure collapsed, confirm the Wallpaper Details section always shows
   a **Loop** row: “First 80 seconds of the source, looped” for sources longer than 80 s,
   “Whole video, repeated to fill 80 seconds” for shorter ones. With a portrait or 4:3
   source, confirm the caption “Cropped to a centered 16:9 window. Pre-crop the video
   to 16:9 to control what is kept.” appears under the preview.
   With a fixture whose still-frame generation fails, confirm the preview ends at
   **Preview Unavailable**, announces the failure with VoiceOver, and offers
   **Retry Preview** and **Replace Video…**. Confirm a source that passed validation
   can still be imported while its still preview is unavailable. Replace a source
   while its preview is still loading and confirm late metadata or a late still
   from the old source cannot replace the new preview.
4. Confirm the inline **Set as wallpaper after importing** toggle defaults to on,
   explains that activation covers all Spaces and displays, and retains its value
   after relaunch. Turn it off and confirm the copy says the desktop will not change.
5. Focus the wallpaper name and press Return. Confirm editing ends without starting
   an import. Press Command-Return or click the toolbar **Import Wallpaper** action and
   confirm import begins.
6. During validation, encoding, or thumbnail generation, confirm progress and
   **Cancel Import** remain visible in the toolbar even when the Import form is scrolled.
   Confirm both Escape and the inline/toolbar cancellation actions return to editable
   state without an error alert. At
   **Updating the Aerial manifest** and later, confirm Cancel is absent and the UI
   states that installation is finishing and cannot be cancelled. During the
   first import, switch to the empty Library: its import action must be disabled.
   Returning to Import, pressing Import again or dropping a second source must
   not replace the running source or its committed crop, quality, resolution,
   name, and activation choice. Cancel, retry, and confirm old encode progress
   callbacks cannot change the new attempt's progress.
7. With automatic activation enabled, confirm completion says the wallpaper was
   imported and activated everywhere. With it disabled, confirm completion says
   the wallpaper was installed without changing the current wallpaper. In both
   states, confirm the result is the primary content without an empty source chooser or
   stale configuration above it. Verify **View in Library** navigates to Library and
   **Import Another** opens the file chooser.
8. With VoiceOver enabled, confirm meaningful stage changes are announced without
   announcing every percentage update, completion moves focus to the result summary,
   and the activation scope, progress, and completion actions have understandable
   labels.

## Maintenance and recovery

1. With a managed wallpaper present, open Maintenance -> Restore Latest Backup. Confirm the confirmation shows the backup's date and operation, and that restoring replaces the catalogue (success alert) while the foreign Apple entries stay intact.
   If a newer backup appears after confirmation, the original confirmed backup
   must still be used. If that confirmed file changes, restoration must fail
   without writing a new manifest or backup.
2. Confirm a restore is refused with nothing changed when the catalogue contains foreign changes newer than the backup (e.g. an Apple Aerial was added in System Settings after the backup).
   A backup that omits the currently active AerialDrop wallpaper must also be
   refused. If active status cannot be read, a restore that removes managed
   entries must be refused until status can be verified. A restore that keeps
   the active entry remains available. If an AerialDrop wallpaper becomes
   active after the restore write, confirm the app retains the committed
   catalogue and its safety backup, reports that the restore needs attention,
   and leaves any concurrent catalogue update untouched. If the manifest
   cannot be read after this check, the app reports an unknown restore status
   and retains the safety backup. Restoring the newest
   safety backup should recover the previous catalogue when it still passes
   the foreign-data checks.
3. After removing a wallpaper, restoring the latest backup brings its entry back marked Video missing (its video file was deleted by the removal) and removing it again is permitted.
4. During an import, press Command-Q and confirm a quit confirmation appears. Keep Importing resumes; Quit Anyway quits, and the next launch removes leftover .AerialDrop- temp files from the videos folder.
5. Import a video with an unsupported codec wrapped in a .mov container and confirm
   the alert is titled after the workflow (**Couldn’t Import the Video**) and its
   message explains the H.264/HEVC conversion step. Run Maintenance → Validate Current
   Catalogue and confirm a **Catalogue Valid** success alert, not a generic one.
6. Confirm the Import pane shows the encoded resolution and an estimated file size before importing, and that quality/resolution changes update the estimate live.
7. In a disposable Tahoe VM or test volume with less free space than the displayed
   import requires, start an import. Confirm AerialDrop stops before **Building an
   80-second native HEVC Aerial stream**, reports the required and available space,
   and recommends freeing space or lowering quality/resolution. Confirm lowering a
   setting enough to satisfy the requirement permits a retry.
8. Confirm the Import progress shows an estimated time remaining during the encode stage.
   It must advance monotonically even if encoding pauses and resumes under
   writer backpressure.
9. Confirm a warning appears when the wallpaper name matches an existing wallpaper.
10. After an import completes, View in Library selects and scrolls to the new wallpaper.
11. During Set as Wallpaper, Remove, Remove All, and Restore Latest Backup, confirm a progress banner with a label stays visible until the operation finishes (both in the Library grid and the preview sheet).

## Import and Library polish

1. Confirm the import progress bar never moves backward across stages (the encode start does not drop below the previous stage, and the thumbnail stage continues from a higher value).
   Import portrait recordings rotated 90° in both directions, an upside-down
   recording, a mirrored recording, and a downscaled ultrawide source with the
   crop at left, center, and right. Confirm the encoded frame fills the output
   without displaced black bands and the preview's crop matches it.
2. With a fade-in-from-black source, confirm the Import preview shows a later, visible frame instead of a black box.
3. Confirm the completion card offers Open Wallpaper Settings alongside Import Another and View in Library.
4. Confirm the toolbar's Wallpaper Settings button shows a wallpaper icon (not a gear) and still opens System Settings -> Wallpaper.
5. Drag an MP4/MOV onto the Library pane and confirm the neutral drop highlight says
   **Drop an MP4 or MOV video** and opens the file in the Import flow. Drop another
   file type and confirm an immediate **Couldn’t Use This File** alert explains that
   an MP4 or MOV is required.
6. Choose a video, rename it, then choose a different video; confirm the name field follows the new file.
7. For an ultrawide source, drag the crop slider between presets and confirm no crop segment is highlighted while the position is between presets, and the preview mask matches the slider.
8. Focus a wallpaper card with the keyboard and press Delete: the existing removal
   confirmation appears. Press Delete while typing in the search field and confirm
   nothing is removed.
9. Plain-click a card, Command-click nonadjacent cards, then Shift-click a later card.
   Confirm plain click replaces the selection, Command-click toggles one card, and
   Shift-click selects the inclusive visible range from the anchor. Confirm
   Command-Shift adds a range. Change search/sort and verify hidden selections and
   stale anchors do not affect the next range. The selection banner should offer
   **Remove Selected…**; confirm its dialog names the count, removes exactly the
   selected wallpapers, and is disabled (with help) when one is known to be active.
   With keyboard focus on a card, press Shift-Right repeatedly and then
   Shift-Left; the range should grow and contract from the focused end while
   keeping the original anchor. Repeat vertically and after filtering, and
   confirm arrow keys do not wrap past the first or last visible card.
10. Rename a wallpaper to another wallpaper’s title and confirm the duplicate-name
    warning appears in the rename alert.
11. Switch the Library sort between **Title** and **Recently Added**: the newest
    imports appear first in Recently Added, and the choice survives a relaunch.
12. On the onboarding screen (missing catalogue), confirm **Open Wallpaper Settings**
    shows the same photo icon as the toolbar’s Wallpaper Settings button.
13. Open the Settings window and confirm the AerialDrop version and build number are
    shown at the bottom.
14. Open a wallpaper preview on a slow disk and confirm a loading indicator appears
    before the loop starts; move the installed video away mid-session and confirm the
    preview explains the failure instead of showing a dead player.
15. With an unreadable selection store (test account), confirm the Library shows the
    “Active status may be out of date” note. Start single, selected, and remove-all
    operations. Each must explain that the active wallpaper cannot be verified and
    offer **Check Again**, **Open Wallpaper Settings**, **Remove Anyway**, and a safe
    keep/cancel action. Confirm no deletion occurs without **Remove Anyway**. Restore
    readability with a managed wallpaper active and confirm removal is blocked even
    after the earlier acknowledgement.
16. Give a wallpaper a title long enough to truncate in its card. Confirm hovering the
    title reveals the full native Help text, VoiceOver reads the full card name, and
    the preview-sheet title wraps without truncation.
17. With several wallpapers visible, switch away from AerialDrop and return. Confirm
    the grid and scroll position remain on screen while **Refreshing catalogue…** is
    shown. In a disposable test account with a deliberately unavailable test
    catalogue, confirm the last loaded grid remains visible, a failure banner offers
    **Try Again**, and restoring access lets retry clear the banner.

## Native activation and playback

1. Leave **Set as wallpaper after importing** enabled (the default), import a
   source, and confirm the new Aerial becomes active across all Spaces and
   displays without System Settings opening. Check that the Library badge marks
   that item **Active**.
2. Disable the inline setting, import a different source, and
   confirm the catalogue refreshes without changing the active wallpaper or
   opening System Settings.
3. In Library, use both the card menu and preview-sheet **Set as Wallpaper**
   actions. Confirm the accessible **Active** badge moves to the selected
   Aerial. Change wallpaper externally in System Settings, return to
   AerialDrop, and confirm the badge refreshes.
4. Open an installed wallpaper preview and confirm **Pause Preview** and **Play Preview**
   immediately control the loop. Enable Reduced Motion before opening the preview and
   confirm it starts paused. Confirm Done/Escape closes the sheet and keyboard focus can
   reach every action.
5. Confirm removal of the active managed Aerial and **Remove All** while a managed
   Aerial is active are disabled before confirmation, with help explaining how to
   recover. Confirm **Set as Wallpaper** is disabled for the active item and for a
   degraded item whose installed video is missing. Switch to an Apple Aerial, then
   confirm managed removal is permitted. If an activation failure occurs,
   confirm the imported item stays installed and the alert offers **Try Again**
   and **Open Wallpaper Settings**.
6. Repeat activation with multiple Spaces and displays. Lock and unlock several
   times, quit with Command-Q, relaunch, then reboot and confirm the selected
   Aerial remains usable.
   In a disposable test account, change just one Space or display back to a
   different wallpaper immediately after activation; AerialDrop must report
   activation failure rather than claiming it applied everywhere.

Expected:

- No `VideoSampleReadingErrors Code=4` entries in the
  `WallpaperAerialsExtension` log during unlock transitions.
- The desktop fades back to the static frame without a black window, and the
  lock screen plays the video at speed.
- Short sources (< 80 s) import without loop-boundary sync-sample validation
  errors.
- The wallpaper store
  (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) has
  verified native Aerial `Type = linked` records for the selected AerialDrop
  asset. A recoverable binary backup exists under `Store/AerialDropBackups` for
  each activation attempt.

## macOS 27 Day/Night native acceptance

The Day/Night feature is unreleased. A controlled experiment with the captured
native Apple fixture manually rendered Day, Night, and Automatic, then restored
the prior system selection. This confirms the observed Apple selection contract;
it does not establish custom imported-pair playback. The fixture
`Tests/AerialDropTests/Fixtures/MacOS27SolarAutomaticSelection.plist` and its
companion note record an observed native Automatic solar selection contract.
That validates the captured Apple selection format; it does not establish that
custom imported pairs follow the solar schedule or play correctly through
lock/unlock. Complete this acceptance matrix on a disposable macOS 27 account
with an allowlisted `WallpaperAerialsExtension` build (currently only
`313.0.4.401`) and nonpersonal test videos. Use the default installed catalogue
through the app's owned-entry writer. Do not enable native catalogue override
preferences or simulate solar changes with Light/Dark appearance or a clock
change. Arrange intended Spaces/displays before taking a recovery baseline.

1. Disable **Set as wallpaper after importing**, then import two visibly
   different test videos. In Library, choose them in the Day/Night selectors.
   Confirm distinct imported IDs and persisted draft choices after relaunch.
   Saving choices must leave the catalogue and native selection unchanged;
   editing a draft must not alter any previously registered pair.
2. Choose **Apply Day/Night Wallpaper**. Confirm the default installed catalogue
   contains the owned combined group with the exact member IDs and Day
   `+35/180` and Night `-35/180` solar anchors. Each global/system-default and
   intended Space target must store that group ID with Automatic variant
   options. Verify unrelated catalogue/store data is preserved and the strict
   refresh establishes fresh trusted native actors. Confirm actual playback,
   then relaunch and check saved choices versus actual Automatic status.
3. Use the Day video's **Set as Wallpaper**, then the Night video's action.
   In Automatic, both members' card/menu and preview actions must be enabled
   while removal remains blocked for both. In fixed Day, only Day's Set action
   is disabled; Night remains selectable and both members remain protected.
   Repeat for fixed Night. An unknown selection or pending verification must
   keep an explicit fixed-member retry reachable.
   Confirm each visibly renders/plays and stores its member ID with matching
   fixed variant options. Use **Apply Day/Night Wallpaper** to return to
   Automatic. Where native System Settings exposes the group, also check its
   Day, Night and Automatic choices and the app's external-selection refresh.
4. With Automatic active, quit AerialDrop and wait for a real natural solar
   transition. Confirm macOS changes between the two imported videos without
   AerialDrop running. Reopen the app and confirm it reports the current pair
   and mode accurately.
5. Repeat Automatic playback with multiple Spaces and displays. Lock and unlock
   several times, inspect the lock screen and desktop playback, and check the
   `WallpaperAerialsExtension` log for `VideoSampleReadingErrors Code=4`.
6. Use isolated tests for malformed data, preference failures and post-write
   selection races; never corrupt real wallpaper stores to simulate failure.
   In the test account, check external selection changes and any naturally
   occurring activation failure. Pending protection must survive relaunch and
   block removal of all previous/new members, including Remove Anyway. A fresh
   ordinary wallpaper apply recovers the pending state. Failed changes retain
   media and catalogue/selection backups and must not automatically overwrite
   newer native state. Verify the Library reports actual partial outcomes.
7. On macOS 26, confirm the existing single-wallpaper activation path still
   works and Day/Night application is unavailable. Use injected capability
   tests for any non-allowlisted build, including newer builds; pair application
   must be gated with a clear explanation while ordinary single activation
   remains available. Never modify an installed system extension for this test.
8. Check Library Day/Night menus, Apply, fixed-member actions, and pending/
   recovery messages with keyboard navigation and VoiceOver. Confirm previews
   distinguish the two members and communicate their Day/Night roles.
   Expand and collapse the Day/Night section in a small window, with no draft
   and with both roles selected. Confirm the sidebar, full instructions,
   selectors, Apply button, and cards remain visible or reachable by scrolling.
   Search for a matching title and for a title with no results, then clear the
   search. Confirm the section remains usable, card keyboard navigation and
   post-import scrolling still work, and operation/bulk-selection banners remain
   above the scroll area. Repeat with an empty Library in an isolated account;
   a manually expanded section must stay expanded after the first import.

The following capture helper is read-only. It does not enable switching, alter
preferences, or change the current wallpaper. Use it only to make a minimized
fixture from a native selection already captured in the disposable test account.
Copy the test account's `Index.plist` to a temporary location, then run the
helper from the repository root with explicit input and a new output file:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift Scripts/capture-dynamic-aerial-fixture.swift \
  --input /tmp/copied-Index.plist \
  --output /tmp/native-automatic-selection.plist
```

The helper validates the decoded native `Configuration` and `EncodedOptionValues`
trees, then re-encodes them inside a minimal linked selection. Their fields and
values are preserved; opaque original bytes are excluded because binary plists
can carry hidden, unreferenced objects. It omits dates, Space/display identifiers,
paths, other providers, and unrelated store data. It refuses unsupported or
non-Automatic selections, extra unknown payload fields, symlink/nonregular inputs,
and existing output files. It does not infer the selected group identifier from
the catalogue or manufacture an Automatic payload.

For contract updates, record the OS version/build and selected test subcategory's
ID, `representativeAssetID`, member IDs, and `variant.solar` anchors in a
companion note. Establish whether the captured `assetID` names the subcategory,
representative, or another member. Omit personal titles and paths. Capture after
a natural solar transition with AerialDrop closed. A matching stored ID or
successful fixture parse alone does not establish imported-pair playback; the
manual acceptance matrix above remains required.

Run `bash Scripts/test-dynamic-aerial-fixture.sh` for the helper's offline
validation and privacy checks. Its inputs are synthetic test cases, not captured
native macOS fixtures, and it never accesses real wallpaper storage.

## Website installation flow

Run `bash Scripts/test-install.sh` first. It exercises compact and pretty
release JSON, exact asset names, invalid digests and installer arguments, and
two local mocked installs without downloading a release or touching Applications.

1. Run `Scripts/check-docs-version.sh` and confirm every static/no-JS release fallback
   matches `AppVersion.shortVersion`.
2. Serve `docs/` locally and inspect the page at 320, 390, 768, and 1440 CSS pixels.
   Confirm the document itself never scrolls horizontally. Long terminal commands,
   the install-method rail, and the stepper may scroll inside their own regions, and
   their Copy/action controls must remain reachable.
3. At 320 and 390 pixels, open the mobile menu and reach **Install** by keyboard.
   In the installer, use Left/Right arrows to change methods and confirm the active
   tab, focus, panel, and Copy command stay synchronized.
4. Block the GitHub release request or disable JavaScript. Confirm the page still
   presents the current bundled release version and valid download/install commands,
   with no stale version token in visible copy.
