# OT6 v0.47

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.47.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

A boosted attack on one enemy now stays on that enemy. Once it falls, the rest
of the action's hits are lost instead of moving on to the next enemy, so a
boosted Fight, Pummel, Hired Help or Jackpot clears one enemy a turn. Boost
only as far as the enemy you picked needs and keep the other points for later.
Attacks that hit every enemy, like Coin Toss, keep going until they are all
down, and ones that pick at random, like Offering, still do. Fights against
groups run a little longer for it: in our full play-through the party fell 77
times where it had fallen 67 times in v0.46, over about the same playing time.

Relm's Sketch command now opens a list, with Sketch as its first row, and the
rest of the list is for helping the party. Portrait gives an ally a free boost
point for their next boosted action, so two banked points and a Portrait make
a divine. Tint lets her pick an element: for four turns the ally's weapon
attacks carry it, with the damage bonus on a weakness and the shield it takes
off. Varnish makes the next enemy attack on an ally miss. Still Life makes an
enemy's break last twice as long. Underpainting makes the next weakness hit on
an enemy take two shields. Gesture gives an ally their turn at once. Her
ultimate, Masterpiece, gives every other ally a free point. She has Portrait
and Tint when she joins and learns the rest by level and story; a boost on
most rows reaches one more ally or enemy per point. Gogo with Sketch opens her
list too. Wearing the Fake Mustache turns her Sketch into plain Control, with
no list.

Locke's page in the field menu's Skills list is now Treasure Hunter, as he
insists, where it used to say Thief.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.46's.

The zip also holds `ot6-manual.pdf`, an instruction booklet in the style of a
1990s cartridge manual.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
