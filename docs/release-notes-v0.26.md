# OT6 v0.26 — Housekeeping

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.26.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

On Android, install the release's `ot6-v0.26.apk`; it patches your ROM
for you.

## What's changed

**The Phantom Train: four shields, more HP -- and yes, Suplex.** The
train now carries four shields instead of six over more HP, so a party
that spends its Boost Points can break it (and give Cyan his first Cleave)
before it falls. And Sabin's Suplex on the train wins the fight on the
spot, the classic FF6 joke made true; it works on that train and nothing
else.

**A bigger boosted hit is never a smaller one.** A Boost Point's doubling
used to roll over to a lower number when a very strong attack doubled past
the game's internal limit, so against a heavily armored or Shelled enemy a
boosted blow could land for less than a weaker one. Boosted damage now
holds at the top instead; the usual 9,999 cap per hit is unchanged.

**More monsters fear cards, dice and brushes.** Special weapons (Setzer's
cards and dice, Relm's brushes) now break more of the spirits and magical
creatures you meet: the Pm Stalker in Tzen's collapsing house, the
NeckHunter and Dante in the cave to Figaro Castle, the spirits of the
Sealed Gate cave, and the Apokryphos, Misfit and Brainpan of the Floating
Continent. Each keeps every weakness it had.

**A boosted Magicite always calls an Esper worth the boost.** Using a
Magicite with Boost Points no longer wastes them on an Esper that does no
damage (Siren, Golem, Fenrir and the rest), passes over Phoenix (whose
revival gains nothing from boosting), and it no longer
calls Crusader, whose boosted Purifier wiped your own party. A boosted
Magicite now calls an Esper that strikes the enemy, or a healing one,
and the boost multiplies it. Unboosted, Magicite is the same gamble as
ever, Crusader included.

## Saves

This release keeps the v0.25 save layout. The file name the Android app
writes, `OT6.sfc`, never changes, so an emulator keeps finding the same
save file.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
