# OT6 v0.48

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.48.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

Shadow's throws now slow the enemy they hit. A throw at an enemy that is
already slowed, by a throw or a spell, stops it for about two of its turns.
Broken enemies are slowed but never stopped, and enemies that cannot be slowed
or stopped still cannot be. The stop uses up the slow, so stopping an enemy
again takes two more throws. The merchant at the house where Shadow joins
sells Shuriken. A small dagger before an enemy's shield shows it is slowed,
and a knife shows it is stopped; they appear with the hit and go when the
status ends. Gogo's Throw and a Mimic of a throw do the same, so Shadow can
slow an enemy and Gogo can stop it. A boost on a throw still multiplies its
damage. An enemy stopped just as its turn comes up now loses that turn,
instead of taking it the moment the stop ends.

Maduin's and Bahamut's top Esper ranks now count as an Earring. With an
Earring or Hero Ring worn as well, or with both ranks, magic damage rises by
half, the same as wearing two Earrings.

In our full play-through the party fell 52 times where it had fallen 77 times
in v0.47, in about 2% less playing time.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.47's.

The zip also holds `ot6-manual.pdf`, an instruction booklet in the style of a
1990s cartridge manual.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
