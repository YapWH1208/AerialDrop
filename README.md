# AerialDrop

[![CI](https://github.com/YapWH1208/AerialDrop/actions/workflows/ci.yml/badge.svg)](https://github.com/YapWH1208/AerialDrop/actions/workflows/ci.yml)
[![Website](https://img.shields.io/badge/website-yapwh1208.github.io%2FAerialDrop-0a84ff)](https://yapwh1208.github.io/AerialDrop/)

AerialDrop imports your own videos into macOS Tahoe's native Aerial (wallpaper) catalogue, so custom videos play as screen savers and lock screen wallpapers using Apple's own playback pipeline — no helper processes, no app-managed player.

## Features

- **Native catalogue integration** — imports videos as full Tahoe Aerial catalogue entries with HEIF previews, visible under the AerialDrop section in System Settings → Wallpaper.
- **Native-compatible encoding** — re-encodes sources to HEVC Main10, 30 fps, Rec.709 MOV with HEVC temporal scalability (two sub-layers, base layer at 15 fps) matching the `tscl`/`tsas` sample groups of Apple's own aerials. Lock/unlock slowdown and the fade back to the desktop run natively.
- **Loop-safe passthrough repeats** — sources shorter than 80 seconds are repeated by passthrough export, with the loop duration snapped to whole 30 fps frames so every loop boundary lands on a sync sample.
- **Automatic backups** — every write to the Aerial catalogue manifest is backed up first, so the last known-good catalogue state always survives at `aerials/AerialDropBackups`.
- **Inline preview** — the Import pane shows the source with a live 16:9 crop mask, and crop, quality, and output resolution are tuned in place before importing.
- **Findable Library actions** — Preview is visible on every card; activation and more actions stay available when a card is selected or keyboard-focused. The sort menu shows its current order.
- **Controllable Library preview** — installed wallpapers loop in a native preview sheet with a visible Play/Pause control that respects Reduced Motion.
- **Visible import status** — the Library shows the current stage, progress, available encode estimate, safe Cancel, and a way back to Import while an import runs.
- **In-app activation** — imported Aerials are applied across all Spaces and displays by default; Library also provides a manual Set as Wallpaper action and Active status.
- **Native Day/Night pairs** — on supported macOS 27 systems, choose two distinct imports as Day and Night and explicitly apply native Automatic solar selection. Custom-media native playback acceptance is still pending.
- **Maintenance tools** — validate the catalogue, open the storage folder, or remove all imported wallpapers.

## Requirements

- macOS Tahoe 26 or later
- Swift 6.2 or later with the macOS 26 SDK (Xcode)
- Source videos: MP4 or MOV, H.264 or HEVC
- Day/Night controls require verified macOS 27 and an observed `WallpaperAerialsExtension` build. The current allowlist contains only `313.0.4.401`; unfamiliar builds and unverified macOS releases disable pair application. macOS 26 retains the single-wallpaper workflow.

## Installation

### Homebrew (recommended)

```sh
brew install --cask yapwh1208/tap/aerialdrop
```

The cask selects the newest published release compatible with your macOS version
and processor. Run `brew update && brew upgrade --cask aerialdrop` to receive
compatible updates. The tap's scheduled updater refreshes these selections when
the release compatibility policy changes.

> **⚠️ Disclaimer — unsigned app:** AerialDrop is **ad-hoc signed and not notarized by Apple**. To make the app open, this cask automatically removes the macOS download quarantine (`com.apple.quarantine`) after install, which disables Apple's malware check for this app — you are trusting the publisher instead of Apple. Only install from the official [YapWH1208/AerialDrop](https://github.com/YapWH1208/AerialDrop) repository, and audit the open-source code if you have concerns. The only way to get Apple's own verification is Developer ID notarization (paid Apple Developer account, $99/year).

### Install script (alternative)

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/YapWH1208/AerialDrop/main/install.sh
bash install.sh
```

Downloads the newest compatible published release, verifies its SHA256 checksum
against the official release metadata, installs `AerialDrop.app` into
`/Applications`, and clears the download quarantine (same unsigned-app caveat as
above). Useful options: `bash install.sh 1.1.10` (pin a compatible version),
`--open` (launch after install), `--force` (replace without asking), and
`--install-dir <path>`.

To print the compatible version without installing or opening anything:

```sh
bash install.sh --print-version
```

Unknown or incompatible pins, unavailable compatibility metadata, and missing
verified release assets stop installation before replacing the existing app.
Automatic selection refuses to downgrade a newer installed version; use an
explicit compatible version pin if you intend to downgrade.

### Prebuilt release

Choose your macOS version on the [download website](https://yapwh1208.github.io/AerialDrop/#install)
to get a compatible `AerialDrop-<version>-macOS.zip`, unzip, and drag
`AerialDrop.app` into your Applications folder. A ZIP downloaded directly from
the [Releases](https://github.com/YapWH1208/AerialDrop/releases) page does not
choose a compatible version for you; check the compatibility policy or use
`bash install.sh --print-version` first. It is ad-hoc signed, so if Gatekeeper
complains the first time, right-click → Open once, or clear the download
quarantine with `xattr -dr com.apple.quarantine /Applications/AerialDrop.app`.

### Build from source

For a fresh source checkout, resolve a compatible release first using the
downloaded installer above:

```sh
if VERSION="$(bash install.sh --print-version)"; then
  git clone --branch "v$VERSION" --depth 1 https://github.com/YapWH1208/AerialDrop.git &&
    cd AerialDrop &&
    swift build -c release
else
  echo "Could not resolve a compatible AerialDrop release."
fi
```

This checks out the selected release tag in a new clone. For an existing
checkout, review and preserve your local work before switching to that tag.
Source builds also need the Swift toolchain and SDK required by that release;
the selector establishes app compatibility, not toolchain availability.

The binary is produced at `.build/release/AerialDrop`. To build a proper `.app` bundle (signed ad-hoc, with Info.plist):

```sh
Scripts/build-app.sh
```

This creates `dist/AerialDrop.app`. Open it with:

```sh
open -n dist/AerialDrop.app
```

For a clean build and launch, run `./build-and-open.sh`. Both packaging scripts
use your selected Xcode, or `/Applications/Xcode.app` when Command Line Tools
is selected. Set `DEVELOPER_DIR` to use another Xcode installation. They check
for full Xcode and its macOS SDK before removing previous build output.

## Usage

1. **Set up Apple Aerials** — before the first import, open System Settings → Wallpaper and download at least one Apple Aerial wallpaper. If the native catalogue is not ready, AerialDrop shows **Open Wallpaper Settings** and **Check Again** instead of an empty Library.
2. **Choose and configure** — use **Choose Video…** or drop an MP4/MOV in the Import pane, then review the name, crop, quality, and output resolution. The source file is never modified. **Set as wallpaper after importing** is enabled by default and applies the new wallpaper across all Spaces and displays; turn it off inline to keep the current wallpaper. If you visit Library while configuring, **Continue Import** returns to the draft without replacing it.
3. **Import** — choose **Import Wallpaper** in the toolbar or press Command-Return. The Import pane shows the current stage and progress; when you switch to Library, its status remains visible with an available encode estimate, **View Import**, and safe cancellation. Press Escape or choose **Cancel** before catalogue installation begins. Once installation starts, AerialDrop finishes without offering cancellation. The video is re-encoded into an 80-second, 30 fps HEVC Main10 stream with temporal sub-layers and registered in the native catalogue.
4. **Continue** — the focused completion summary replaces the configuration form and states whether the wallpaper was activated everywhere or installed without changing the desktop. Choose **View in Library** or **Import Another**.
5. **Quit** — AerialDrop can be quit after setup; macOS handles playback natively.

The Library sort menu labels its current order (**Title** or **Recently Added**). Every wallpaper card keeps **Preview** visible; the activation and more actions remain available when a card is selected or keyboard-focused.

On a supported macOS 27 system, the compact **Day/Night Wallpaper** summary shows the registered pair and any different saved choices. Choose **Edit** to open the selectors and **Done** to close them. A first or incomplete setup and pending recovery open the editor when attention is needed; a manual collapse is remembered. Changing selectors saves a draft. **Apply Day/Night Wallpaper** registers that pair and requests Automatic selection across all Spaces and displays. To select a fixed member, choose **Use Day only** or **Use Night only** on that video's card; applying an ordinary imported wallpaper replaces the active pair. Apply Day/Night again to return to Automatic.

Automatic mode uses the native sun-position format and is intended to continue after AerialDrop quits. It follows solar position rather than Light/Dark appearance; exact transition times are not established. Custom-pair playback, natural switching after quit and lock/unlock remain unverified for this unreleased feature; see [TESTING.md](TESTING.md).

If a wallpaper change cannot be verified, previous and new pair videos remain protected across relaunch. Retry **Apply Day/Night Wallpaper** or apply another imported wallpaper in AerialDrop. Protection clears only after a verified native reload; **Remove Anyway** cannot bypass it. The Library distinguishes saved choices from actual native Automatic or fixed-member selection.

### Maintenance menu

- Open Aerial Storage Folder
- Validate Current Catalogue
- Restore Latest Backup (uses the backup shown in the confirmation; refused if that backup changes, newer Apple catalogue data would be lost, or a currently active AerialDrop wallpaper would be removed. If active-wallpaper verification fails after the catalogue write, AerialDrop keeps the safety backup and reloads the Library. A concurrent catalogue update remains untouched; the safety backup can be restored if it still passes the foreign-data checks.)
- Remove All AerialDrop Wallpapers

## How it works

The pipeline is: validate input → build an 80-second video-only composition → decode via `AVAssetReader` → re-encode as HEVC Main10 with temporal sub-layers → generate a HEIF preview at timestamp zero → register in the catalogue → safely update Tahoe's linked Aerial selection → restart `WallpaperAgent` and `WallpaperAerialsExtension`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full flow.

## Compatibility

[`docs/release-compatibility.json`](docs/release-compatibility.json) is the shared
installation policy. Each stable version declares a minimum macOS major
version, an optional inclusive maximum, and supported processor architectures.
The installer, website, and Homebrew updater combine this policy with published
GitHub releases and their exact ZIP assets. Versions are compared numerically;
drafts, prereleases, undeclared releases, and assets without a valid official
checksum or URL are excluded. Missing or malformed policy data stops selection.

Currently v1.1.10 supports macOS 26 and later on Apple Silicon. macOS 26 users
therefore receive v1.1.10. If a later release requires macOS 27, macOS 26 users
remain on the newest eligible release. Day/Night feature checks remain separate
from whole-app installation compatibility.

Before publishing a release, add its compatibility record alongside the normal
version and changelog changes. CI checks the source version and package minimum
OS; release CI additionally checks the tag, bundled Info.plist, and binary
architectures. Update older records only when compatibility evidence warrants
it. Removing a record makes that version unavailable to selectors, including
explicit pins. The Homebrew updater publishes static selections, so users need
`brew update` after the tap has refreshed. These repository changes take effect
for public installations after the main repository, Pages site, and tap changes
have been published.

AerialDrop writes directly to Tahoe's private Aerial catalogue and restarts `WallpaperAgent` and `WallpaperAerialsExtension`. These data formats and processes are not a public API; a future macOS update may change the manifest schema and require an AerialDrop update.

Every manifest write is backed up automatically first: backups live under `aerials/AerialDropBackups`. Linked-selection writes use separate binary-plist backups under `Store/AerialDropBackups` and refuse concurrent changes.

Day/Night support is gated by the observed extension-build allowlist above. The Automatic fixture records Apple's observed native selection payload; it does not establish end-to-end solar playback for imported media. Apple may replace the downloaded catalogue during a system update, which can require reimporting or reapplying owned entries.

## Documentation

- [Website](https://yapwh1208.github.io/AerialDrop/) — interactive landing page (source: `docs/`, published to GitHub Pages)
- [ARCHITECTURE.md](ARCHITECTURE.md) — processing pipeline
- [TESTING.md](TESTING.md) — manual test procedure
- [CHANGELOG.md](CHANGELOG.md) — release history

## License

[MIT](LICENSE)
