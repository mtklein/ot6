# OT6 v0.16 — Shadow Stays

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.16.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**Shadow no longer freezes the game, and he no longer leaves the party.**
In v0.14 and v0.15, winning a battle with Shadow as a guest could lock the
game up with the last frame stuck on screen. That is fixed. And Shadow now
stays with you for the whole game instead of wandering off after a fight;
only the story itself can take him away.

If you were playing v0.15 with Shadow, this is the reason to update.

**Every enemy can be broken.** The enemies in the cave behind the Sealed
Gate now have proper shields and weaknesses, and there is no longer any
enemy anywhere in the game without at least one way to break it.

## Patch bytes

If you compare this patch to v0.15's, it differs in the changes above and
in some text and music data that is now stored more compactly. The words
and the songs are the same.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.

## What we'd like to know

- Whether Shadow behaves himself now that he stays: through the Phantom
  Forest and the Ghost Train, when he rejoins later, and in any long stretch
  of fighting with him in the party.
- How breaking feels in the cave behind the Sealed Gate.
- Anything that reads as a difficulty wall or a soft-lock. The fish at Baren
  Falls is the fight we most want to hear about.
