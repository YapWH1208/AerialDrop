# Release notes for the website

This file records short, user-facing highlights for the GitHub Pages
**What's new** section. Entries describe what changed in each version; older
entries are historical and may describe behavior that changed again later.
For the complete release history and the notes used by GitHub Releases and
the in-app updater, see [CHANGELOG.md](CHANGELOG.md).

## Maintaining the highlights

1. Add candidate highlights under **Unreleased** as work is completed. Keep
   any compatibility limits and unresolved verification alongside the feature.
2. For a release, turn those candidates into a new versioned entry, newest
   first, and leave an **Unreleased** section ready for future work. Update
   `CHANGELOG.md` as required by the release workflow.
3. When preparing the release, copy its selected highlights into the `#updates`
   section of [docs/index.html](docs/index.html), including the version,
   heading, description, and link to the matching GitHub release. Update the
   section subtitle and any related version-specific hero, metadata, and footer
   text.
4. Check the summaries against the changelog and release status. Coordinate
   publication so the page does not announce a release before it is available.

The website is maintained as static HTML: editing this file does not update
the page automatically.

## Unreleased

## 1.1.11

### Signed in-app updates

Check for compatible updates automatically or manually, then install with one
action. Install 1.1.11 using an existing method first; it can then update to
subsequent releases.

### Safer catalogue and import recovery

AerialDrop checks catalogue compatibility and offers safe repair for eligible
older catalogues without changing conflicting Apple records. Import prepares
video details up front and keeps progress and cancellation visible. Day/Night,
backup restore, and bulk-removal recovery are more resilient.

### Clearer installation guidance

The website highlights macOS 27.0+ while keeping macOS 26 support. It can
detect macOS when the browser provides that information, and offers a manual
selector, clearer signing and quarantine details, and improved keyboard and
narrow-screen navigation.

## 1.1.10

### Compatible release downloads

The website added a selector for compatible Apple Silicon downloads. The install
script and Homebrew tap select the newest published release for your Mac and
verify its checksum. Version pins are validated.

## 1.1.9

### Day/Night wallpaper pairs

On verified macOS 27 builds, choose separate Day and Night videos, then
explicitly apply Automatic selection. You can also select a fixed Day or Night
member. Both videos stay protected during pair changes and recovery.

Unrelated missing media no longer blocks activation or removal. AerialDrop
checks the selected wallpaper's files before applying it, and keeps ordinary
wallpaper activation available during pending recovery.

**Pair playback is still being verified:** imported-video playback, natural
solar transitions after quitting, and lock/unlock checks remain pending.

## 1.1.8

### Safer activation and recovery

Wallpaper activation verifies the selection macOS applied and reports when it
needs attention. Backup restore rechecks the active wallpaper, blocks changes
that would remove it, and preserves concurrent catalogue updates.

Import previews stay aligned when you change videos, rotated-video cropping is
corrected, and conversion progress stays monotonic. Keyboard range selection
starts from the focused wallpaper card, and the installer handles checksums and
arguments more reliably.

## 1.1.7

### Keyboard navigation and clearer import guidance

Move and extend Library selections with the keyboard, apply wallpapers from
card hover controls, and see why Import is unavailable while a video or name
still needs attention. A new Help menu links to support and release notes.

## 1.1.6

### Safer imports and removals

Import checks available disk space before encoding. Library refresh keeps the
existing grid visible, removal offers recovery when the active wallpaper cannot
be verified, and selection follows familiar macOS conventions.

## 1.1.5

### Bulk selection and remembered import settings

Select and remove multiple wallpapers, sort the Library, and reuse your last
import quality and resolution. Import also explains how each source fills the
80-second loop.

## 1.1.4

### More ways to install and manage wallpapers

Install with Homebrew or the checksum-verifying install script. Import gains
progress estimates, while Library operations gain clearer feedback and backup
recovery.

## 1.1.3

### Import progress and accessible previews

Follow import progress in the toolbar and return to an unfinished draft.
Wallpaper actions explain when they are unavailable, and preview controls
support assistive technology and reduced motion.

## 1.1.2

### Catalogue setup and clearer results

Get guidance when Apple's Aerial catalogue needs setup, and see whether an
imported wallpaper was activated, installed without activation, or needs
attention.

## 1.1.1

### Inline import preview

Preview and adjust cropping, quality, and resolution directly in the Import
pane. Replacing a video refreshes the displayed preview and source details.

## 1.1.0

### A native Tahoe interface

The redesigned Library and Import panes use a sidebar, toolbar, and Liquid
Glass. Search wallpaper cards, preview imports, and activate an imported
wallpaper from AerialDrop.

## 1.0.0

### Framing and conversion controls

Preview the full source with a 16:9 crop overlay, adjust ultrawide framing, and
choose import quality and output resolution. Rotated-video previews and
resolution labels match the encoded output.

## 0.6.1

### Simpler native setup

On the Tahoe builds tested at the time, selecting an imported Aerial in System
Settings linked it to Desktop, Lock Screen, and Screen Saver without a separate
Finish Native Setup step.

## 0.6.0

### Designed for macOS Tahoe

The app adopted a split Import and Library interface with Liquid Glass, a
preview-card gallery, toolbar actions, and an empty state.

## 0.5.6

### More reliable unlock playback

HEVC temporal layers and frame-aligned loop boundaries addressed black
wallpapers after unlocking and kept sync samples at repeat boundaries.

## 0.5.5

### More reliable loop playback

Closed-GOP encoding and passthrough repetition gave each source loop a sync
sample, addressing black wallpapers after the lock screen or screen saver.

## 0.5.4

### Native linked wallpaper selection

Updated the Tahoe selection format and verification so the managed Aerial could
be linked across Desktop and Screen Saver without reimporting existing media.

## 0.5.3

### Encoder build fix

Fixed Swift compiler errors in the Main10 encoder validation.
