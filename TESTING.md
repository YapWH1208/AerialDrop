# Testing AerialDrop 1.0.0

Run this matrix on macOS Tahoe 26 with an existing Apple Aerial catalogue and
at least one short and one longer MP4/MOV source. Reimport sources with this
version before evaluating native playback.

1. Build and open AerialDrop 1.0.0. Confirm the Library loads without opening
   System Settings or changing the current desktop.
2. Select a valid source. Confirm the Import pane shows a still-frame preview with
   a crop mask matching the source type, and that resolution, duration, and file
   size appear. Change crop, quality, and output resolution; confirm the preview
   mask and controls stay in sync. Replace the source and confirm the preview
   follows it.
3. Leave **Set as wallpaper after importing** enabled (the default), import a
   source, and confirm the new Aerial becomes active across all Spaces and
   displays without System Settings opening. Check that the Library badge marks
   that item **Active**.
4. Disable the setting in AerialDrop Settings, import a different source, and
   confirm the catalogue refreshes without changing the active wallpaper or
   opening System Settings.
5. In Library, use both the card menu and preview-sheet **Set as Wallpaper**
   actions. Confirm the accessible **Active** badge moves to the selected
   Aerial. Change wallpaper externally in System Settings, return to
   AerialDrop, and confirm the badge refreshes.
6. Attempt to remove the active managed Aerial and use **Remove All** while a
   managed Aerial is active; both must be blocked. Switch to an Apple Aerial,
   then confirm managed removal is permitted. If an activation failure occurs,
   confirm the imported item stays installed and the alert offers **Try Again**
   and **Open Wallpaper Settings**.
7. Repeat activation with multiple Spaces and displays. Lock and unlock several
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
