# Testing AerialDrop 0.6.1

1. Build and open AerialDrop 0.6.1.
2. Reimport the video so it is encoded with native temporal sub-layers (0.5.5 files lack them).
3. Verify the default-enabled import applies the new Aerial across all Spaces and displays without opening System Settings. Repeat with the Settings toggle disabled and verify import only refreshes the catalogue.
4. In Library, use both the card menu and preview-sheet **Set as Wallpaper** actions; verify the accessible Active badge changes and removing an active item is blocked.
5. Open **Preview & Adjust** for a source: confirm playback loops, native play/pause/scrubbing work, crop masks match the crop controls, and quality/output controls stay synchronized with Import after closing the window.
4. Quit AerialDrop with Command-Q.
5. Test multiple lock/unlock cycles.

Expected:

- No `VideoSampleReadingErrors Code=4` entries in the WallpaperAerialsExtension log during the unlock transition.
- The desktop fades straight back to the static frame (no black window) and the lock screen plays the video at speed.
- Short sources (< 80 s) import without "no sync sample at loop boundary" validation errors.
- The wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) shows verified native Aerial `Type = linked` records for the selected AerialDrop asset. A recoverable binary backup exists under `Store/AerialDropBackups` for every activation attempt.
