# AerialDrop 0.5.6

AerialDrop imports custom videos into macOS Tahoe's native Aerial catalogue.

## 0.5.6 native temporal-scalable encoding

The 0.5.5 movies (closed GOP, Main10, 30 fps) matched Apple's file shape but still black-screened the desktop after unlock. The unlock transition works by dropping the higher HEVC temporal layer to slow the video ("native slowdown"), and every sample read failed with `VideoSampleReadingErrors Code=4 (noTemporalInfo)` on a single-layer encode.

0.5.6 encodes each imported video with HEVC temporal scalability — two sub-layers (base layer at 15 fps within a 30 fps stream) — so the native file carries the same `tscl`/`tsas` sample groups as Apple's own aerials. Unlock slowdown and the fade back to the static desktop now run natively with no helper processes.

Imported videos before this release must be reimported once.

## 0.5.5 loop-boundary sync samples

Sources shorter than 80 seconds are encoded once and repeated by passthrough export. The loop duration is snapped to a whole number of 30 fps frames so every loop boundary lands exactly on a sync sample; fractional lengths drifted one frame per repeat and failed native-movie validation.

## Compatibility

AerialDrop writes directly to Tahoe's private Aerial catalogue and wallpaper selection store, and restarts `WallpaperAgent` and `WallpaperAerialsExtension`. These data formats and processes are not a public API; a future macOS update may change the manifest or store schema and require an AerialDrop update.

Every write is backed up automatically first: manifest backups under `aerials/AerialDropBackups` and selection-store backups under `Store/AerialDropBackups`. Earlier states can be restored from the Maintenance menu (Restore Latest Manifest Backup / Restore Latest Selection Backup).
