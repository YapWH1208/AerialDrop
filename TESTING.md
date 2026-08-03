# Testing AerialDrop 0.5.5

1. Build and open AerialDrop 0.5.5.
2. Remove the old 0.5.4 test wallpaper from AerialDrop.
3. Import the original source video again.
4. Select the new item in System Settings → Wallpaper.
5. Close System Settings and click **Finish Native Setup**.
6. Quit AerialDrop completely.
7. Test at least five complete Screen Saver / Lock Screen / unlock cycles.
8. Confirm that macOS plays the video while locked, performs the native slowdown, and leaves a static desktop without a black frame.
9. Run the sample-table collector against the new asset. A short source should produce a sync sample at each repeated source-loop boundary in addition to the regular approximately 1.9-second GOP cadence.
