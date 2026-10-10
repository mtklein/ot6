# OT6 v0.24

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.24.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.24.apk` and select the folder containing the ROM.

## Changes

- Enemies from Figaro Castle through Darill's Tomb now have shields and
  weaknesses designed for Edgar, Sabin, and Setzer. Dullahan has ten shields.
  The Presenter shell has no shields, and defeating either body ends the
  fight.
- A boosted action that is cancelled by sleep or death no longer spends its
  Boost Points.
- Releases now include OT6 Patcher for Android. It creates `OT6.sfc` beside
  the original ROM. Obtainium can install updates with the APK filter
  `ot6-.*\.apk`.

## Saves

In-game saves from v0.23 work in v0.24. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
