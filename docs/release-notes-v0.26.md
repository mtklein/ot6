# OT6 v0.26

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.26.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.26.apk` and select the folder containing the ROM.

## Changes

- The Phantom Train now has four shields and more HP. Suplex defeats it
  immediately.
- Boosted damage no longer wraps to a lower value when it exceeds the internal
  limit. The 9,999 damage cap is unchanged.
- More enemies are weak to special weapons, including enemies in Tzen, the
  Figaro cave, the Sealed Gate cave, and the Floating Continent.
- Boosted Magicite now chooses a damaging or healing Esper. It excludes
  non-damaging Espers, Phoenix, and Crusader. Unboosted Magicite is unchanged.

## Saves

This release uses the v0.25 save layout. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
