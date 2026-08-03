# AerialDrop 0.5.4

AerialDrop imports custom videos into macOS Tahoe's native Aerial catalogue.

## 0.5.4 native-link correction

The 0.5.3 diagnostic showed that the generated media already matched the working Wallper media class, but Tahoe still stored the active wallpaper as two independent presentations:

- Desktop: the selected AerialDrop asset
- Idle: an older Wallper asset
- Type: `individual`

That produces `useAsBoth:false` in WallpaperAgent and breaks native Aerial continuity.

0.5.4 converts the selected AerialDrop presentation to Tahoe's native `linked` store form. It also force-reloads WallpaperAgent so the process cannot overwrite the new plist with its stale in-memory `individual` state, then reopens the store and verifies that the linked state survived.

You do not need to reimport an existing 0.5.3 wallpaper. Select it in Wallpaper settings, close System Settings, and click **Finish Native Setup** in AerialDrop 0.5.4.
