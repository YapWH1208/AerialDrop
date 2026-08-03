# Architecture

```text
Source MP4/MOV
    ↓ validate H.264 or HEVC input
Build an 80-second video-only composition
    ↓ repeat or trim source; normalize timeline to zero
AVAssetReader: 10-bit full-range YUV
    ↓
AVAssetWriter: HEVC Main10, 30 fps, Rec.709 MOV
    ↓ validate duration / codec / bit depth / range / first PTS / frame-zero decode
Generate HEIF preview at timestamp zero
    ↓
Register video, preview and UUID metadata in entries.json
    ↓ user selects the item in System Settings
Finish Native Setup
    ↓ copy the selected AerialDrop Desktop choice to Idle in Store/Index.plist
Restart WallpaperAgent and WallpaperAerialsExtension
    ↓
macOS native pipeline
Screen saver → Lock Screen → native slowdown → static desktop
```

There is no app-managed desktop player. AerialDrop may be quit after setup.
