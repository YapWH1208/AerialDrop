# AerialDrop 0.5.5

AerialDrop imports custom videos into macOS Tahoe's native Aerial catalogue.

## 0.5.5 sample-table correction

The sample-table diagnostic compared a working Wallper movie with the AerialDrop 0.5.4 movies. All three were 80-second, 30 fps, HEVC Main10 full-range files, but their GOP layouts differed:

- Wallper: regular sync samples about every 1.9 seconds **and** a fresh sync sample at every source-loop boundary.
- AerialDrop 0.5.4: one continuous 80-second encode with sync samples every 2 seconds, so repeated source-loop boundaries were not independently decodable.

Tahoe's native ramp-down reader can reopen or seek around those loop boundaries. A stream without a closed, independently decodable boundary can play normally and still fail when macOS transitions from the Lock Screen to the static desktop.

0.5.5 therefore encodes one normalized source loop first, using closed GOPs and the observed 57-frame / 1.9-second cadence. It then repeats that already-encoded segment to 80 seconds using passthrough. Every repeated loop starts with the segment's first sync sample.

## Upgrade from 0.5.4

Reimport the original source video. **Finish Native Setup alone cannot repair an existing 0.5.4 MOV**, because this fix changes the encoded sample table.
