# OT6 v0.17 — Kolts Keys

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.17.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**The Mt. Kolts and Zozo enemies can be broken the way they were meant
to be.** The Cirpius on Mt. Kolts and Zozo's SlamDancers, Harvesters,
HadesGigases and Gabbldegaks used to carry shields that no weapon could
chip; only poison (Edgar's Bio Blaster) got through them. They now also
break to the weapon keys they were designed for: pierce for the Cirpius and the
Gabbldegak, slash or pierce for the SlamDancer and the Harvester, and a
good bludgeoning (Sabin's Pummel) for the HadesGigas. Poison still works
on all of them as before.

**Random encounters return to the Phantom Forest bridge.** v0.16 switched
off encounters on the bridge in the forest after the Phantom Train to work
around a freeze, and said it would put them back once the freeze was
fixed. It is, and the bridge rolls its encounters again, as the game
intended.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
