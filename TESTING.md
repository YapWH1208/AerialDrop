# Testing AerialDrop 0.5.4

1. Build and open AerialDrop 0.5.4.
2. Keep the existing 0.5.3 imported wallpaper; no reimport is required.
3. Select that wallpaper in System Settings → Wallpaper.
4. Close System Settings completely.
5. Click **Finish Native Setup** in AerialDrop.
6. Wait for the success message confirming that Tahoe retained a linked `useAsBoth` record.
7. Quit AerialDrop with Command-Q.
8. Test three lock/unlock cycles.

Expected store state:

- `Type = linked`
- `Linked` references the selected AerialDrop asset
- no separate Desktop/Idle records for that asset
- WallpaperAgent resolves `useAsBoth:true`
