# OT6 v0.16 — Clean Room

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

Play from the beginning through the end of the World of Balance and stop
where the game sets you down in the World of Ruin: Celes alone in a house
on a solitary island. Past that point the new systems may run but are not
part of this release's supported, balanced playtest range.

## What's changed

**Nothing, on purpose — if you are playing v0.15, there is no reason to
update.** The game in this patch is identical to v0.15, Rizopas at Baren
Falls included. This release exercises our release machinery end to end
from a completely clean build: every test fixture regenerated from
scratch by replaying the game, every check re-run, and the whole process
timed. Shipping the result is part of the exercise.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place (see the v0.13 notes for the full house-rule
rationale). When a Sketch misses, the game can rarely corrupt your
inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.

## What we'd like to know

- Nothing new to test here — v0.15's questions still stand, especially
  Rizopas at 4 pips on a blind run.
