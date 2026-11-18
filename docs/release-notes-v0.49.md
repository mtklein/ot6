# OT6 v0.49

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.49.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

When you pick a spell or skill from its list, the boost you chose now stays
what it was. At the target choice, L and R only spread it over more targets;
before, they could quietly change the boost, so Fire 3 could land as Fire 2.
In a list, R also stops adding a point you cannot pay for in MP.

Locke's Bestow is greyed out when no ally can take a point, for instance when
he fights alone. Relm's Portrait and Gesture are greyed out the same way when
no ally can take them.

Relm now has a Painter page in the field menu's Skills, like Locke's. It lists
her eight moves with their MP prices and shows the ones she has not learned
yet as locked. Each page now has a line at the top telling you what the move
under the cursor does, or where to learn it. Locke's entry in the Skills list
reads TresHnt, like his battle command, and Locke's and Relm's entries are
greyed while they wear the Thief Glove or the Fake Mustache. The Skills list
is back to its original width.

Bahamut's top Esper rank is now Limit Break. Whoever holds it can deal up to
42,069 damage with attacks, spells, throws, summons and counters. Healing and
everyone else's damage still stop at 9999, and damage numbers now show five
digits. Bahamut's top rank no longer gives the Fight and magic damage bonus;
Ragnarok's top rank gives it instead of raising Vigor by half.

Setzer's Hired Help now sends an Imp as the third hire, in place of the figure
it used to be.

A monster that returns to a fight after dying, whether the fight brings it
back or Life raises it, now comes back with all its shields intact instead of
still broken.

Our automated play-through of the whole game lost more characters than in
v0.48, 87 against 52, and took about 3% longer, mostly in a few late fights.
We are looking into why.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress. If a character already holds
Bahamut's or Ragnarok's top rank, they keep it and it works the new way.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.48's.

The zip also holds `ot6-manual.pdf`, an instruction booklet in the style of a
1990s cartridge manual.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
