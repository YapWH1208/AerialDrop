# Testing AerialDrop 0.6.1

1. Build and open AerialDrop 0.6.1.
2. Reimport the video so it is encoded with native temporal sub-layers (0.5.5 files lack them).
3. Select the imported wallpaper in System Settings → Wallpaper and apply it as you would any Aerial.
4. Quit AerialDrop with Command-Q.
5. Test multiple lock/unlock cycles.

Expected:

- No `VideoSampleReadingErrors Code=4` entries in the WallpaperAerialsExtension log during the unlock transition.
- The desktop fades straight back to the static frame (no black window) and the lock screen plays the video at speed.
- Short sources (< 80 s) import without "no sync sample at loop boundary" validation errors.
- The wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) shows a `Type = linked` record for the selected AerialDrop asset without any AerialDrop involvement after import.
