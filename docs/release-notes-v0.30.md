# OT6 v0.30

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.30.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.30.apk` and select the folder containing the ROM.

## Changes

**Aqua Rake no longer takes a lore slot.** Once Strago knows it, Aqua Rake
is in his Lore list in every battle, beside the five lores he equips. If a
saved lore slot held Aqua Rake, that slot is now empty.

**Strago knows Scan from the day he joins, and Scan shows every weak point.**
Scan now marks all of the target's weak elements and weapon types at once,
for that monster and every monster of its kind, and they stay marked in
later battles. Boosted by one point or more, it reads every enemy on the
field. Celes still learns Scan at level 18.

**Strago's Scan at three Boost Points teaches him lores.** He learns every
lore the monsters in the battle could use, without being hit by them. The
lores are learned when the battle is won. It costs 99 MP. Scan aimed at a
party member reads nothing, so it costs 3 MP and keeps its Boost Points.

**Weak points around Jidoor and Thamasa in the World of Ruin.** The monsters
in Owzer's house and on Thamasa's plain, and Chadarnook, now have their own
weak points instead of the default ones. Chadarnook's demon (6 shields)
breaks to blades and piercing weapons and to fire and holy; the goddess has
no shields. Relm's brushes now also break the Mantodea. The Fanatics'
Tower's monsters, the Holy Dragon and MagiMaster also have weak points, but
this release has not been played through the tower yet.

## Saves

This release uses the v0.29 save layout. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.

The included saves now reach the Falcon outside the Fanatics' Tower, after
Relm and Strago join.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
