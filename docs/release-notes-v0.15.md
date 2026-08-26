# OT6 v0.15 — Baren Falls

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.15.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

Play from the beginning through the end of the World of Balance — the full
v0.14 range, ending where the game sets you down in the World of Ruin:
Celes alone in a house on a solitary island. Past that point the new
systems may run but are not part of this release's supported, balanced
playtest range.

## What's changed

This is a small tuning release. The playable range is unchanged from v0.14.

**Rizopas backs off one pip.** The boss waiting under Baren Falls drops
from 5 shield pips to 4 (still slash/bludgeon — Sabin's home ground). At 5,
our honest-attempt ledger read one win in nine tries with the party
entering his phase healthy; one pip lands the break a round earlier, and
the fight went back to winnable on the first try. Same dial as every other
retune — the shield count, nothing else.

**Under the hood, the test suite got more honest.** A pass over eleven
checks that could have stayed green while being wrong (a repaint check that
sampled after the screen was allowed to be blank, a fallback that asserted
only what it *didn't* do, and friends), and the falls playthrough now
retries from the boot save like a player reloading, not from a mid-run
snapshot. None of this changes the game; all of it changes how much a green
test run means.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place (see the v0.13 notes for the full house-rule
rationale). When a Sketch misses, the game can rarely corrupt your
inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.

## What we'd like to know

- Rizopas at 4 pips: fair fight on a blind run, or still a wall? He's
  meant to pressure the Sabin-and-Cyan party that arrives at the falls,
  not stonewall it.
- Anything odd anywhere in the WoB — this release touched one number, so
  anything else you notice is worth a report.
