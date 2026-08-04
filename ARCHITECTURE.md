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
Restart WallpaperAgent and WallpaperAerialsExtension
    ↓ user selects the item in System Settings
Tahoe writes the native `linked` record binding Desktop, Lock Screen and Screen Saver
    ↓
macOS native pipeline
Screen saver → Lock Screen → native slowdown → static desktop
```

There is no app-managed desktop player. AerialDrop may be quit after setup.
