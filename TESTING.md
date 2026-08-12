# Testing AerialDrop 1.1.0

Run this matrix on macOS Tahoe 26 with at least one short and one longer MP4/MOV
source. Use a separate test account for the setup-required checks; do not move or
edit a real Aerial catalogue to simulate failure. Reimport sources with this
version before evaluating native playback.

## Onboarding and import UX

1. On a test account that has not downloaded an Apple Aerial, build and open
   AerialDrop 1.1.0. Confirm Library shows **Set Up Apple Aerials**, explains the
   missing catalogue, and offers **Open Wallpaper Settings** and **Check Again**.
   File selection must remain unavailable until setup succeeds.
2. Download an Apple Aerial in System Settings → Wallpaper, return to AerialDrop,
   and choose **Check Again**. Confirm the ready-but-empty Library shows its import
   action without a search field. After at least one import, confirm search appears.
3. Select a valid source. Confirm the Import pane shows a still-frame preview with
   a crop mask matching the source type, and that resolution, duration, and file
   size appear. Change crop, quality, and output resolution; confirm the preview
   mask and controls stay in sync. Confirm the toolbar says **Replace Video…**
   after selection, then replace the source and verify the preview follows it.
4. Confirm the inline **Set as wallpaper after importing** toggle defaults to on,
   explains that activation covers all Spaces and displays, and retains its value
   after relaunch. Turn it off and confirm the copy says the desktop will not change.
5. Focus the wallpaper name and press Return. Confirm editing ends without starting
   an import. Press Command-Return or click **Import Wallpaper** and confirm import
   begins.
6. During validation, encoding, or thumbnail generation, confirm **Cancel** is
   available and cancelling returns to editable state without an error alert. At
   **Updating the Aerial manifest** and later, confirm Cancel is absent and the UI
   states that installation is finishing and cannot be cancelled.
7. With automatic activation enabled, confirm completion says the wallpaper was
   imported and activated everywhere. With it disabled, confirm completion says
   the wallpaper was installed without changing the current wallpaper. In both
   states, verify **View in Library** navigates to Library and **Import Another**
   opens the file chooser.
8. With VoiceOver enabled, confirm meaningful stage changes are announced without
   announcing every percentage update, completion moves focus to the result summary,
   and the activation scope, progress, and completion actions have understandable
   labels.

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
4. Attempt to remove the active managed Aerial and use **Remove All** while a
   managed Aerial is active; both must be blocked. Switch to an Apple Aerial,
   then confirm managed removal is permitted. If an activation failure occurs,
   confirm the imported item stays installed and the alert offers **Try Again**
   and **Open Wallpaper Settings**.
5. Repeat activation with multiple Spaces and displays. Lock and unlock several
   times, quit with Command-Q, relaunch, then reboot and confirm the selected
   Aerial remains usable.

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
