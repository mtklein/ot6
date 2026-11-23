# OT6 v0.50

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.50.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

Pummel, Bum Rush and Drill play their animation once per use (an
Overclocked Drill, once per firing). Each hit still lands on its own, with
its own damage number, one after another once the animation ends; before,
the whole animation played again for every hit, which looked like the move
being used twice.

The boost pips beside a character's name no longer flicker back to the old
count for a moment when that character's command window opens.

Each command you give Gogo now brings its owner's whole kit. Slot opens
Setzer's list (Coin Toss, Hired Help and Jackpot) instead of the bare reels.
With 3 BP his Tools fire twice (Overclock), his Runic sends spells back
(RunicBlade), his Throw kills a broken enemy, or one it breaks, unless it is
a boss (Assassinate), and his Fire becomes Ultima once Terra has rejoined.
With Lore and Magic both he also has Strago's Scan, and Bserk once Strago has
learned it; Scan with 3 BP studies the enemies' lores. His TresHnt, Painter,
Blitz, SwdTech, Rage and Dance lists were already their owners'. Morph and
Leap stay Terra's and Gau's. His Mimic follows the same rules: a copy of a
3 BP Tool, Runic, Throw or Fire gets the same extra, and a copy of Strago's
Scan studies if Gogo has Lore (no test covers the copies yet).

Relm's battle command is now called Painter, like her page in Skills. Sketch
is the first move in its list. The Fake Mustache turns Painter into Control.

## Saves

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.49's.

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.

The zip also holds `ot6-manual.pdf`, an instruction booklet in the style of a
1990s cartridge manual.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
