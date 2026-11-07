# OT6 v0.39

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.39.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

**Ribbons stay with the party in the World of Ruin saves.** When the party changes members on the Falcon, anyone left behind now hands over their Ribbon first, and it goes on someone in the new party. Before, a Ribbon could stay on a character waiting on the airship, and the party reached the Colosseum and Maranda with only one of its three Ribbons on the members it was using.

**Kefka's Tower has its own shields and weak points.** The tower's monsters and bosses on the way to Kefka now have shields and weapon weaknesses chosen for them. Swords don't break the shields of the machines in the tower's factory; spears, knives and clubs do. Each of the three statues can be broken with dice, cards or a brush, plus one other kind of weapon that differs from statue to statue. The Guardian you finally fight in the tower now shows a shield gauge. The Colosseum's opponents that come from the tower get the same new weak points.

**Saves through Kefka's Tower.** Eight new saves follow the three parties up the tower: at the factory's save point before and after Inferno, behind Atma, behind the Guardian, after each of the three statues, and last, with two parties standing on the plates and the third at the save point, ready for Kefka.

## Saves

This release uses the v0.29 save layout.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
