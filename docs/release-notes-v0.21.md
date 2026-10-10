# OT6 v0.21

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.21.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

- Once per battle, Shadow kills a normal enemy when his hit breaks it or hits
  it while broken. Enemies immune to instant death are only broken.
- Rage is greyed out when Gau cannot pay its 8 MP cost. Bestow is greyed out
  when Locke has no Boost Point to give. Refused commands do not spend a turn.
- Cyan now spends stored Boost Points when the game controls him in the
  Imperial Camp.
- Boosted Throw now raises damage for every throwable weapon.
- Weapon spells no longer receive the Fight boost in addition to its extra
  hits. Boosted Rage improves its special chance without also raising damage
  or hit count.

## Saves

In-game saves from v0.20 work in v0.21. Save states do not transfer between
versions.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
