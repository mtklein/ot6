# OT6 v0.32

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.32.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

**Weak points in the Phoenix Cave.** The cave's monsters have their own weak
points and fewer shields (1 to 4 instead of 6). The Phase is also weak to
holy. Doom Gaze has 8 shields.

**New saves in the Phoenix Cave and after Locke joins.** The `saves` folder
has two new saves: at the Phoenix Cave's save point, with the party split,
and outside Kohlingen after the cave, with Locke in the party.

**A new save outside Narshe, with Ragnarok.** The `saves` folder has a save
outside Narshe after Locke opens the town's locked doors: the elder's treasure
room emptied, Ragnarok taken as magicite and equipped on Relm, and the Cursed
Shld in the bag.

**A golden aura for Boost.** A character with a boost raised glows, more
strongly at each BP, until the boost is spent. When several boost at once,
the one choosing a command wears the halo if boosting, and the others glow.

**Locke's full kit.** His Steal list grows as the story goes. Mug (after
South Figaro) is a Fight that steals on each hit. Trickshot (after the Lete
River) throws a coin that pierces and ignores defense. Dismantle (after the
Sealed Gate) lowers an enemy's defense, then stabs. Appraise
(after Thamasa) reveals an enemy's weaknesses, or every enemy's when boosted.
Master's Mark, his divine (3 BP, 99 MP, after the Air Force), steals the best
item from every enemy and reveals their weaknesses; choosing it and backing out
costs nothing. Filch and Bestow now come when he joins (they came after the
Opera House and Vector). A boosted Capture no longer also raises its steal odds; like a
boosted Mug, it buys extra swings.

## Saves

This release uses the v0.29 save layout.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
