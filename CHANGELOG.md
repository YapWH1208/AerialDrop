# Changelog

## 1.1.5

- The Import pane now states the fixed 80-second loop contract before encoding — long sources show **First 1:20 of the source, looped** and shorter sources show **Whole video, repeated to fill 1:20**.
- Import quality and output resolution are remembered from your last import and seed the next video; a remembered resolution that would not downscale the new source automatically falls back to **Original**.
- The Library supports keyboard and bulk removal: Delete on a focused card opens the existing removal confirmation, and Command-/Shift-click selects several wallpapers for one confirmed **Remove Selected…** operation with the active-wallpaper guard and per-item backups.
- Alerts now carry workflow- and outcome-specific titles instead of a generic app-name heading, with recovery hints for common failures and no third-party jargon.
- The Library can sort by **Title** or **Recently Added** (the choice is remembered), and renaming to a name that already exists shows the same warn-but-permit duplicate notice as importing.
- The Library now says when the current wallpaper selection cannot be read, so **Active** badges are honestly marked as potentially out of date.
- The wallpaper preview sheet shows loading and failure states instead of a silent black box, and playback-status observation follows the item actually playing.
- Polish: the onboarding icon matches the toolbar, narrow-source center-crop is captioned, removal from inside a multi-selection applies to the whole selection, partial bulk-removal outcomes are reported accurately, and Settings shows the real version and build.

## 1.1.4

- Added two more installation methods: a `brew install --cask yapwh1208/tap/aerialdrop` one-liner (Homebrew tap) and a downloadable `install.sh` that verifies the release checksum, installs to `/Applications`, and clears the quarantine.
- Improved Import feedback: the encoded output size and encode ETA now appear during conversion, and a warning flags a wallpaper name that's already in use.
- Made import progress monotonic across stages and prefer a representative non-black frame for the preview, so the preview no longer freezes on a dark first frame.
- Added feedback to library operations (rename, remove, restore, activation) and highlighted the wallpaper that was just imported.
- Added **Restore Latest Backup** to the Maintenance menu, with removal recovery explained more clearly; backups are now restored deterministically and orphaned repeat-export temp files are swept.
- Guarded the app against quitting mid-import: quit during an import now asks first, and leftover encode temp files are cleaned up.
- The Library pane now accepts video drops directly and follows the dropped file's name when naming the wallpaper; non-video drops are ignored.
- Polish pass: crop presets now report their state honestly, a **Wallpaper Settings** shortcut was added to the completion summary, the toolbar icon and the wallpaper-name placeholder are clearer, and user-facing copy no longer references third-party jargon.

## 1.1.3

- Reworked the toolbar around the import stage: while an import runs, the toolbar shows its progress and a **Cancel Import** action (offered only while cancellation is still safe), and the primary action becomes **Continue Import** when you've left a draft mid-configuration.
- Kept the Import pane stable when the app is switched away mid-import: the chosen video, name, crop and quality settings stay put, and the draft survives until you finish or cancel.
- Gated wallpaper actions on whether they can actually succeed: **Set as Wallpaper**, **Rename** and **Remove** are now disabled with an explanatory tooltip when invalid — for example when the installed video file is missing.
- Added an accessible Play/Pause control to the wallpaper preview sheet, labeled wallpaper cards for assistive access, and made the preview loop respect Reduce Motion — a manual pause is preserved when Reduce Motion is toggled back off.

## 1.1.2

- Added catalogue-readiness onboarding: when the native Apple Aerial catalogue isn't set up yet, the Library shows **Open Wallpaper Settings** and **Check Again** instead of an empty grid, and the Import toolbar action (⌘O) is disabled until the catalogue is ready.
- Modeled import results as an explicit outcome: the completion summary now states whether the wallpaper was activated everywhere, installed without changing the desktop, or installed but activation needs attention.
- Polished completion feedback: a single VoiceOver announcement moves focus to the summary, retrying activation clears a stale "Activation Needs Attention" card, and completion plays a success haptic only when activation actually succeeded.
- Restricted import cancellation to the early, reversible stages; once catalogue installation begins, AerialDrop finishes without offering cancellation.

## 1.1.1

- Removed the pop-out Preview & Adjust window. Preview and conversion tuning now happen inline in the Import pane: a still-frame preview with the live crop mask, plus quality, resolution, and crop controls.
- Fixed the inline preview showing a stale frame, duration, and file size when the source video is replaced.

## 1.1.0

- Redesigned the UI around a native macOS Tahoe sidebar and toolbar: Library and Import are sidebar destinations, with Import, Reload and Maintenance actions in the toolbar (⌘O opens the file picker too; cancelling it returns you to the pane you came from).
- Adopted Liquid Glass materials across the app and removed the custom chrome (aurora background, custom press-scale button style).
- Redesigned the Library as a searchable card grid: double-click or Preview to inspect, hover for quick actions, a context menu for Set as Wallpaper / Rename / Reveal in Finder / Remove, and Active / Installed status badges. Preview and More actions are also reachable with the keyboard.
- Redesigned the Import pane around the chosen source video: a choose/drop card with a live preview, staged conversion progress, and a success card with a shortcut to Wallpaper Settings.
- Added in-app activation: set any imported wallpaper as the active Aerial from the Library or preview sheet, with a retry path (and Wallpaper Settings fallback) if activation fails.
- Added a Settings toggle to opt out of applying the wallpaper automatically after import.
- Added a pop-out Preview & Adjust window for tuning crop and conversion before importing.

## 1.0.0

- The Import preview now shows the entire video fitted (not zoomed), and the crop overlay darkens exactly what the chosen 16:9 window cuts away — left/right for ultrawide sources, top/bottom for portrait and 4:3 sources.
- Crop controls now appear only for ultrawide sources (21:9 and wider).
- Output-resolution options now appear only when they actually downscale, so portrait sources no longer list 2160p/1440p choices that would encode identically.
- The conversion card appears only after a video is selected.
- Capped the import preview box at 440×248 so ultrawide videos fit the window.
- Added ultrawide cropping (Left/Center/Right presets plus a fine position slider) with a live crop preview in the Import pane.
- Shows the source resolution in the Import pane and the encoded resolution on library cards and the preview sheet.
- Added per-import conversion options: quality (Standard/High/Maximum) and output resolution (downscale to 2160p/1440p/1080p).
- Fixed the import preview, crop bands, height caps and resolution badge for rotated (portrait) sources, which now match the encoded output.

## 0.6.1

- Removed the manual **Finish Native Setup** step: on current Tahoe builds System Settings itself writes the native `linked` record when the imported Aerial is applied, so Desktop, Lock Screen and Screen Saver bind without any AerialDrop involvement. Verified on-device (a `Type = linked` record with Tahoe's empty-options payload appeared after selecting in System Settings, with no AerialDrop store backup written).
- Removed the selection-store linking machinery (`WallpaperSelectionStore`), its tests, and the related error cases.
- Made the toolbar title a hero header and extended Liquid Glass materials to the wallpaper cards, progress card, notes card, and primary buttons.

## 0.6.0

- Redesigned the interface as a macOS Tahoe 26 app: a split import/library view with glass drop zone, preview-card gallery with hover-to-remove, toolbar actions, and an empty state.
- Targets macOS 26 (the Swift package now builds against the Tahoe SDK) so `glassEffect` materials are available.
- Removed the legacy “Repair Catalogue Registration” action (only fixed 0.2-era `initialAssetCount` entries) and the “Restore Latest Backup” actions for the manifest and selection stores; automatic backups are still written on every write.
- Kept **Finish Native Setup**, which is the core workflow step that binds the selected asset to Desktop and Screen Saver via Tahoe’s native `linked` record.

## 0.5.6

- Encodes with HEVC temporal scalability (base-layer frame rate 15 at 30 fps) so the native movie carries `tscl`/`tsas` sample groups like Apple's own aerials.
- Fixes the black desktop wallpaper after unlocking: Tahoe's unlock transition drops the higher HEVC temporal layer to slow the video, and without temporal sub-layers every sample read fails with `VideoSampleReadingErrors Code=4 (noTemporalInfo)`.
- Snaps the loop segment to a whole number of 30 fps frames before the passthrough repeat, so every loop boundary lands on a sync sample instead of drifting one frame per repeat and failing the native-movie validation.

## 0.5.5

- Encodes closed-GOP native segments so every source loop repeats with a fresh sync sample instead of one continuous open-GOP stream.
- Repeats the already-encoded segment via passthrough export, matching the working Wallper media shape (1.9-second closed GOPs plus a sync sample at every loop boundary).
- Fixes the black desktop wallpaper that appeared after returning from the lock screen or screen saver, when the native player seeks the video to resume and freeze the desktop frame.

## 0.5.4

- Replaced the incorrect Desktop-to-Idle copy with Tahoe's native `Type = linked` / `Linked` representation.
- Clears Desktop and Idle for the selected managed asset so WallpaperAgent resolves `useAsBoth:true`.
- Uses a forced WallpaperAgent reload after the atomic store write to prevent a stale graceful-termination flush from restoring `individual` state.
- Verifies the linked record after WallpaperAgent restarts and retries once if Tahoe races the first update.
- Does not require re-encoding or reimporting an existing 0.5.3 wallpaper.

## 0.5.3

- Fixed Swift compiler errors in the Main10 encoder validation.
