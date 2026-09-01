# OT6 v0.17 — Shadow Stays

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

**Shadow no longer freezes the game, and no longer leaves the party.**
Vanilla Final Fantasy VI rolls a 1-in-16 chance after each won battle that
Shadow, fighting as a guest, walks off. In OT6 that roll was jumping into the
wrong bank of code and halting the console — a hard freeze, with the last
frame stuck on screen, that shipped in v0.16 and earlier. Anyone who fought
alongside Shadow could hit it. The roll now runs correctly, and by design it
is a no-op: **Shadow stays for the whole game.** Only the story's own scripted
departures still remove him.

If you were playing v0.16 with Shadow, this is the reason to update.

**Break coverage filled in.** A few areas had encounters with no authored
shields or weaknesses, falling back to a generic formula. Mt. Kolts and the
approach to it, Zozo, and the Sealed Gate cave now carry real break data, so
those enemies shield and break like the rest of the game. A build gate now
refuses to ship any encounter without it.

**Fewer stray encounters** on the Phantom Forest's corridor bridge and the
Zozo climbing shaft. These were a workaround for the freeze above and are now
redundant; they will be removed in a later build once the fix has been tested.

## Patch bytes

As with v0.16, this patch is not byte-for-byte the previous release's. The
source tree was reorganized since v0.16 (the build moved entirely to `ninja`),
and some data is re-encoded a little smaller. The full test suite passed on
the built ROM, which is the evidence that the reorganization changed no
behavior beyond what is listed above.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.

## What we'd like to know

- Whether Shadow behaves correctly now that he stays — across the Sabin
  scenario (the Phantom Forest and the Ghost Train), his later rejoin, and any
  battle where vanilla would have rolled him away.
- Break behavior in the newly-covered areas: Mt. Kolts, Zozo, and the Sealed
  Gate cave.
- Anything that reads as a difficulty cliff or a soft-lock; v0.15's standing
  question — Rizopas at 4 pips on a blind run — still applies.
