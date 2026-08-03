# Changelog

## 0.5.5

- Encodes one source loop as a closed-GOP HEVC Main10 segment, then repeats the encoded segment with passthrough rather than encoding all 80 seconds as one continuous stream.
- Matches the working Wallper sample table more closely: 57-frame / 1.9-second GOP cadence and a new sync sample at every source-loop boundary.
- Validates that every repeated loop boundary has a sync sample before installing the wallpaper.
- Keeps the native linked Desktop/Idle setup introduced in 0.5.4.
- Existing 0.5.4 movies must be reimported because the fix changes the MOV sample table.

## 0.5.4

- Replaced the incorrect Desktop-to-Idle copy with Tahoe's native `Type = linked` / `Linked` representation.
- Clears Desktop and Idle for the selected managed asset so WallpaperAgent resolves `useAsBoth:true`.
- Uses a forced WallpaperAgent reload after the atomic store write to prevent a stale graceful-termination flush from restoring `individual` state.
- Verifies the linked record after WallpaperAgent restarts and retries once if Tahoe races the first update.
- Does not require re-encoding or reimporting an existing 0.5.3 wallpaper.

## 0.5.3

- Fixed Swift compiler errors in the Main10 encoder validation.
