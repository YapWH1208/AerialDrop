# Architecture

```text
Source MP4/MOV
    ↓ validate H.264 or HEVC input
Build an 80-second video-only composition
    ↓ repeat or trim source; normalize timeline to zero
AVAssetReader: 10-bit full-range YUV
    ↓
AVAssetWriter: HEVC Main10, 30 fps, Rec.709 MOV, temporal sub-layers (base 15 fps)
    ↓ validate duration / codec / bit depth / range / first PTS / frame-zero decode
    ↓ validate a sync sample at every loop boundary
Generate HEIF preview at timestamp zero
    ↓
Register video, preview and UUID metadata in entries.json
    ↓
If enabled, safely update Index.plist linked Aerial selection everywhere
    ↓ backup + compare-before-write + binary atomic write + verification
Restart WallpaperAgent and WallpaperAerialsExtension
    ↓
macOS native pipeline
Screen saver → Lock Screen → native slowdown → static desktop
```

There is no app-managed desktop player. AerialDrop may be quit after setup.

`ManifestStore` owns `entries.json`; `WallpaperSelectionStore` separately owns the private `Store/Index.plist` linked-selection format. Unknown store data is preserved, selection writes are backed up, and each global and Space target is verified after activation. Verification failures deliberately do not auto-restore over newer macOS state. Catalogue restore uses the confirmed backup bytes and refuses to remove an active managed entry (or any managed entry when active status is unknown). If selection validation fails after the restore write, the pre-write safety backup is retained and the UI reloads the current catalogue. A concurrent macOS catalogue update remains untouched; the safety backup can be restored if it still passes the foreign-data checks.
