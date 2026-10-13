# OT6 v0.29

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.29.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.29.apk` and select the folder containing the ROM.

## Changes

**Terra's Morph works at any boost.** Boost Points set how long it lasts:
with 0 it lasts about two of her turns, longer with 1 or 2, and with 3 it
lasts until the battle ends or she reverts. Morph no longer uses up a gauge
that carries over between battles, so it is never greyed out. A confused
Terra's Morph lasts the shortest time.

**Revert no longer spends Boost Points.** A boosted Revert used to spend
the points and gain nothing. Now the points stay banked, and Terra gains one
as on any unboosted turn.

**Weak points around Narshe in the World of Ruin.** The monsters in the
town, the mines, the cliffs, the moogle cave and Umaro's cave, and the Ice
Dragon, Tritoch and Umaro, now have their own weak points instead of the
default ones. Of weapons, only piercing ones break Test Riders. The Ice Dragon (6
shields) breaks to piercing and blunt weapons, Tritoch (10) and Umaro (6) to
blades and piercing weapons, and all three to fire.

**The Flame, Ice and Thunder Shields lend Fire, Ice and Bolt while worn.**
They used to teach Fire 2, Ice 2 and Bolt 2. Now, like magicite, the
wearer can cast the base spell only while wearing the shield. Fire 2, Ice 2
or Bolt 2 that a shield already taught stays learned.

## Saves

This release uses the v0.28 save layout. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.

The included saves now reach Narshe in the World of Ruin, after Umaro
joins. From Nikeah on, Mog has joined in the World of Balance and knows
Water Rondo.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
