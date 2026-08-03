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

## Compatibility

AerialDrop writes directly to Tahoe's private Aerial catalogue and wallpaper selection store, and restarts `WallpaperAgent` and `WallpaperAerialsExtension`. These data formats and processes are not a public API; a future macOS update may change the manifest or store schema and require an AerialDrop update.

Every write is backed up automatically first: manifest backups under `aerials/AerialDropBackups` and selection-store backups under `Store/AerialDropBackups`. Earlier states can be restored from the Maintenance menu (Restore Latest Manifest Backup / Restore Latest Selection Backup).
