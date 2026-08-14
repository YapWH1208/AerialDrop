# AerialDrop

[![CI](https://github.com/YapWH1208/AerialDrop/actions/workflows/ci.yml/badge.svg)](https://github.com/YapWH1208/AerialDrop/actions/workflows/ci.yml)

AerialDrop imports your own videos into macOS Tahoe's native Aerial (wallpaper) catalogue, so custom videos play as screen savers and lock screen wallpapers using Apple's own playback pipeline — no helper processes, no app-managed player.

## Features

- **Native catalogue integration** — imports videos as full Tahoe Aerial catalogue entries with HEIF previews, visible under the AerialDrop section in System Settings → Wallpaper.
- **Native-compatible encoding** — re-encodes sources to HEVC Main10, 30 fps, Rec.709 MOV with HEVC temporal scalability (two sub-layers, base layer at 15 fps) matching the `tscl`/`tsas` sample groups of Apple's own aerials. Lock/unlock slowdown and the fade back to the desktop run natively.
- **Loop-safe passthrough repeats** — sources shorter than 80 seconds are repeated by passthrough export, with the loop duration snapped to whole 30 fps frames so every loop boundary lands on a sync sample.
- **Automatic backups** — every write to the Aerial catalogue manifest is backed up first, so the last known-good catalogue state always survives at `aerials/AerialDropBackups`.
- **Inline preview** — the Import pane shows the source with a live 16:9 crop mask, and crop, quality, and output resolution are tuned in place before importing.
- **Controllable Library preview** — installed wallpapers loop in a native preview sheet with a visible Play/Pause control that respects Reduced Motion.
- **In-app activation** — imported Aerials are applied across all Spaces and displays by default; Library also provides a manual Set as Wallpaper action and Active status.
- **Maintenance tools** — validate the catalogue, open the storage folder, or remove all imported wallpapers.

## Requirements

- macOS Tahoe 26 or later
- Swift 6.2 or later with the macOS 26 SDK (Xcode)
- Source videos: MP4 or MOV, H.264 or HEVC

## Installation

### Homebrew (recommended)

```sh
brew tap YapWH1208/tap
brew install --cask aerialdrop
# or in one command:
# brew install --cask yapwh1208/tap/aerialdrop
```

The cask tracks new releases automatically, so `brew update && brew upgrade --cask aerialdrop` gets you the latest version. The app is ad-hoc signed, so the first launch may need right-click → Open if Gatekeeper complains (or install with `brew install --cask --no-quarantine aerialdrop`).

### Prebuilt release

Download `AerialDrop-<version>-macOS.zip` from the [Releases](https://github.com/YapWH1208/AerialDrop/releases) page, unzip, and drag `AerialDrop.app` into your Applications folder. It is ad-hoc signed, so right-click → Open the first time if Gatekeeper complains.

### Build from source

```sh
git clone https://github.com/YapWH1208/AerialDrop.git
cd AerialDrop
swift build -c release
```

The binary is produced at `.build/release/AerialDrop`. To build a proper `.app` bundle (signed ad-hoc, with Info.plist):

```sh
Scripts/build-app.sh
```

This creates `dist/AerialDrop.app`. Open it with:

```sh
open -n dist/AerialDrop.app
```

## Usage

1. **Set up Apple Aerials** — before the first import, open System Settings → Wallpaper and download at least one Apple Aerial wallpaper. If the native catalogue is not ready, AerialDrop shows **Open Wallpaper Settings** and **Check Again** instead of an empty Library.
2. **Choose and configure** — use **Choose Video…** or drop an MP4/MOV in the Import pane, then review the name, crop, quality, and output resolution. The source file is never modified. **Set as wallpaper after importing** is enabled by default and applies the new wallpaper across all Spaces and displays; turn it off inline to keep the current wallpaper. If you visit Library while configuring, **Continue Import** returns to the draft without replacing it.
3. **Import** — use the persistent **Import Wallpaper** toolbar action or press Command-Return. The toolbar keeps progress and safe cancellation visible even when the form is scrolled; press Escape or choose **Cancel Import** before catalogue installation begins. Once installation starts, AerialDrop finishes without offering cancellation. The video is re-encoded into an 80-second, 30 fps HEVC Main10 stream with temporal sub-layers and registered in the native catalogue.
4. **Continue** — the focused completion summary replaces the configuration form and states whether the wallpaper was activated everywhere or installed without changing the desktop. Choose **View in Library** or **Import Another**.
5. **Quit** — AerialDrop can be quit after setup; macOS handles playback natively.

### Maintenance menu

- Open Aerial Storage Folder
- Validate Current Catalogue
- Remove All AerialDrop Wallpapers

## How it works

The pipeline is: validate input → build an 80-second video-only composition → decode via `AVAssetReader` → re-encode as HEVC Main10 with temporal sub-layers → generate a HEIF preview at timestamp zero → register in the catalogue → safely update Tahoe's linked Aerial selection → restart `WallpaperAgent` and `WallpaperAerialsExtension`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full flow.

## Compatibility

AerialDrop writes directly to Tahoe's private Aerial catalogue and restarts `WallpaperAgent` and `WallpaperAerialsExtension`. These data formats and processes are not a public API; a future macOS update may change the manifest schema and require an AerialDrop update.

Every manifest write is backed up automatically first: backups live under `aerials/AerialDropBackups`. Linked-selection writes use separate binary-plist backups under `Store/AerialDropBackups` and refuse concurrent changes.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — processing pipeline
- [TESTING.md](TESTING.md) — manual test procedure
- [CHANGELOG.md](CHANGELOG.md) — release history

## License

[MIT](LICENSE)
