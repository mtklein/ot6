# OT6 v0.25

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.25.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.25.apk` and select the folder containing the ROM.

## Changes

- Setzer's Slot command now opens a list with Slot, Coin Toss, Hired Help, and
  Jackpot.
- Coin Toss spends `level × 30` Gil on damage to all enemies. Each Boost Point
  repeats the attack and cost. It can break enemies weak to special weapons.
- Hired Help spends `level × 50` Gil on a physical hit using one of the
  target's weapon weaknesses. Each Boost Point adds another paid hit.
- Jackpot costs 99 MP and can be used once per battle after Setzer rejoins.
  It rolls three dice for one hit. Each Boost Point adds another roll.
- Setzer's commands are greyed out when he cannot pay. Unused extra attacks
  cost nothing.
- Extra hits move to another living enemy after their first target dies. This
  applies to boosted Fight, Pummel, Hired Help, and Jackpot.
- The title screen, Config screen, and internal ROM title show the OT6 version.

## Saves

In-game saves from v0.24 work in v0.25. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
