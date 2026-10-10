# OT6 v0.23

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.23.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

- Enemies from Tzen through Figaro Castle now have shields and weaknesses
  designed for Celes, Sabin, and Edgar.
- A broken enemy loses any queued turn.
- Dance keeps its boost for every step. A failed Dance spends no MP or Boost
  Points.
- Terra and Celes now learn short spell lists. Equipped Espers grant short
  spell lists. Stronger spell tiers come from boost instead of learning.
- Life becomes Life 2 with one Boost Point and Life 3 with two. Life 3 revives
  a fallen ally at full HP and protects the ally from the next death.
- Shield counts above six are displayed correctly.
- The Beginner's House removes its duplicate Blitz lesson and updates its
  boost lesson.
- Pummel now ends the Vargas fight even when Vargas is broken.
- Boss story events now occur on cue while the boss is broken. Broken bosses
  still lose attacks and turns.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
