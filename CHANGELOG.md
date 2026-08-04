# Changelog

## 0.5.6

- Encodes with HEVC temporal scalability (base-layer frame rate 15 at 30 fps) so the native movie carries `tscl`/`tsas` sample groups like Apple's own aerials.
- Fixes the black desktop wallpaper after unlocking: Tahoe's unlock transition drops the higher HEVC temporal layer to slow the video, and without temporal sub-layers every sample read fails with `VideoSampleReadingErrors Code=4 (noTemporalInfo)`.
- Snaps the loop segment to a whole number of 30 fps frames before the passthrough repeat, so every loop boundary lands on a sync sample instead of drifting one frame per repeat and failing the native-movie validation.

## 0.5.5

- Encodes closed-GOP native segments so every source loop repeats with a fresh sync sample instead of one continuous open-GOP stream.
- Repeats the already-encoded segment via passthrough export, matching the working Wallper media shape (1.9-second closed GOPs plus a sync sample at every loop boundary).
- Fixes the black desktop wallpaper that appeared after returning from the lock screen or screen saver, when the native player seeks the video to resume and freeze the desktop frame.

## 0.5.4

- Replaced the incorrect Desktop-to-Idle copy with Tahoe's native `Type = linked` / `Linked` representation.
- Clears Desktop and Idle for the selected managed asset so WallpaperAgent resolves `useAsBoth:true`.
- Uses a forced WallpaperAgent reload after the atomic store write to prevent a stale graceful-termination flush from restoring `individual` state.
- Verifies the linked record after WallpaperAgent restarts and retries once if Tahoe races the first update.
- Does not require re-encoding or reimporting an existing 0.5.3 wallpaper.

## 0.5.3

- Fixed Swift compiler errors in the Main10 encoder validation.
