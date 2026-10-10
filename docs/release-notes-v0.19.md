# OT6 v0.19

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.19.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

- Boosted abilities now cost more MP. Each Boost Point multiplies the base
  cost by 2.5, up to 99 MP. This applies to Blitz, Tools, Dance, Lore,
  summons, and spells outside a tier family.
- Fight remains free. Steal, Rage, and Slot keep their normal MP cost because
  boost changes hits or odds instead of damage.
- Tiered spells and SwdTech keep their existing costs. Boost selects a more
  expensive spell or technique.
- An unaffordable Blitz, Tool, SwdTech, Steal, or Dance is refused. The turn,
  Boost Points, and MP are not spent.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
