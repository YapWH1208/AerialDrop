# Observed macOS 27 solar Aerial selection

`MacOS27SolarAutomaticSelection.plist` is a sanitized native selection captured
on 2026-10-02, not a synthetic selection fixture.

- OS: macOS 27.0.1, build `26A434`.
- WallpaperAerialsExtension: `313.0.4.401`.
- Native picker: Wallpaper → Landscape → Golden Gate → Automatic.
- Combined subcategory ID: `67512508-D33E-4CBC-8A9E-BE55CEE35C4C`.
- Representative and Day member: `6511D2B5-E185-4886-9505-B4004E920D27`.
- Night member: `86E89C23-C39B-44C8-A985-E56EEA6456FE`.
- Day `variant.solar`: altitude `35`, azimuth `180`.
- Night `variant.solar`: altitude `-35`, azimuth `180`.

The test catalogue retained Apple's 164 assets and their media URLs. It combined
these two existing filmed Golden Gate assets using `combineVariants: true` and
the solar anchors above. Those anchors were deliberately added for the test;
the installed catalogue on this build contains no solar variants. The catalogue
was loaded through a temporary native local-manifest override. The original
selection and both original preference scopes were restored afterward. Independent
post-restart checks verified exact original Index bytes and target content, absent
override keys in both scopes, and a fresh trusted wallpaper agent. Original file
attributes were preserved before restart, with added OS provenance retained.
After restart, the file modification time and quarantine record fields differed;
the original quarantine flags remained unchanged. The user confirmed the original
wallpaper rendered again. Exact metadata persistence after native reload is not
claimed.

The user selected and confirmed rendering of Day, Night, and Automatic. Each
selection was copied while System Settings and AerialDrop were closed, with the
native wallpaper writers held quiescent. The Automatic copy was exported with
`Scripts/capture-dynamic-aerial-fixture.swift`. Only its validated choice,
configuration, and options remain; both binary payloads were decoded and
re-encoded to exclude hidden object-table data. No dates, local paths, display
or Space identifiers, or other selections are included.

The observed Automatic configuration names the **combined subcategory**, with
the native option hierarchy:

```json
{"assetID":"67512508-D33E-4CBC-8A9E-BE55CEE35C4C"}
```

```json
{"values":{"aerialVariant":{"picker":{"_0":{"id":"automatic"}}}}}
```

The separately guarded Day and Night copies each name their corresponding
member in `Configuration.assetID` and in the same picker option's `id`. Their
full private stores are excluded from the repository.

This fixture proves the serialized combined selection and accepted two-member
picker shape on this build. It does not prove a natural solar transition,
continued switching after app quit, lock/unlock playback, multiple targets, or
grouped local AerialDrop media through the default downloaded catalogue.
Those remain runtime acceptance checks. A native catalogue update can replace
the downloaded catalogue; this capture establishes no retention guarantee.
