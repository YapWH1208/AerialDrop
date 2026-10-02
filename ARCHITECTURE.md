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

The manifest's `initialAssetCount` must be an integer from zero through the number of assets. It need not equal the total: Apple's macOS 27 catalogue declares 4 with 164 assets. Reading and validating a catalogue preserve its bytes; existing managed import, rename and removal operations continue to normalize the count to their resulting asset count.

The macOS 27 Day/Night catalogue adapter registers two distinct imported assets
under one stable, AerialDrop-owned combined subcategory. It reuses their UUIDs
and installed media, with solar anchors at altitude +35° for Day and −35° for
Night (azimuth 180°). The manifest records the registered pair; editable choices
are separate from registration. Import, rename and reimport preserve these roles.
Malformed roles or missing paired media fail validation instead of silently
dissolving the group.

Removing either paired asset requires a fresh selection check and dissolves an
inactive pair while returning its surviving member to the ordinary category.
Selecting the group or either fixed member protects both members. Restore also
protects their role mapping, even when the backup retains both UUIDs. Checks run
again after the catalogue write; a late selection change retains media and the
safety backup and reports the partial outcome. Replacing a registered pair
requires the caller to persist protection for its previous and new members until
a fresh native activation is verified, since native services can cache old roles.

`AerialSelectionRequest` separates ordinary single selection, fixed Day/Night
member selection, and Automatic group selection. `WallpaperSelectionStore`
checks each target's decoded configuration and variant options; raw configuration
references remain visible even when the options are unfamiliar. Its nonmutating
preflight checks target topology and preservation before registering a pair.

Day/Night creation is enabled only on macOS 27+ with an observed Aerial extension
build (initially `313.0.4.401`), a valid catalogue and supported selection topology.
Unrecognized builds retain the ordinary single-wallpaper path. Typed activation
uses a strict reload barrier: identify current-user native processes by executable,
kernel start time and launchd membership; terminate the exact Aerials processes
before the agent; retire extensions started during that transition; then verify a
fresh agent across two catalogue/selection checks. Lookup commands and restart
polling are bounded. Failure keeps backups and cannot release pending member
protection. The legacy best-effort refresh remains separate from this proof.
