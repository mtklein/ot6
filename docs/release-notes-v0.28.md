# OT6 v0.28

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.28.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.28.apk` and select the folder containing the ROM.

## Changes

**Cyan learns Cleave on the Phantom Train.** He learns it as his wife and
son board the train, instead of at level 70. From then on the 3-point row of
his automatic SwdTech list is Cleave (99 MP), and the 1- and 2-point rows are
his two best other skills. If you continue a save from after the Phantom
Train, Cyan learns Cleave in his dream in the World of Ruin instead.

**SwdTech weak points.** Retort and Empowerer no longer hit weak points.
Quadra Slice is wind: it hits wind weak points and deals wind damage, so it
heals monsters that absorb wind.

**Mog's Water Rondo needs all 3 Boost Points** (99 MP). With fewer, the dance
is greyed out. Danced with 3 points it never stumbles, wherever the battle
is. A confused Mog no longer picks it.

**Umaro.** When he is hurt with all 3 Boost Points banked, his next action is
always Storm, with or without the Blizzard Orb. His Charge and Throw hit blunt
weak points.

**Weak points on Mt. Zozo and the plains around Zozo.** The monsters met
there and the Storm Dragon now have their own weak points instead of the
default ones, wherever they appear. Blades break most of them; Crawlers need
blunt or piercing blows, and Reach Frogs blunt ones. The Storm Dragon has 14
shields that blades and piercing attacks break.

## Saves

This release uses the v0.27 save layout. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
