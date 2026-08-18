# OT6 v0.12 — The Sealed Gate

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.12.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

Play from the beginning through the Sealed Gate arc — Terra's return, the
Narshe mission, the Cave to the Sealed Gate, the Esper attack on Vector, the
Imperial banquet, and the voyage — and stop when you land on Crescent
Island. Past that point the new systems may run but are not part of this
release's supported, balanced playtest range.

## What's changed

**The playable range extends through the whole Sealed Gate arc.** This is
the first release of the end-of-World-of-Balance arc (v0.12–v0.14): from
Terra's return you can now play the Narshe mission handoff, the Cave to the
Sealed Gate, the Esper attack, the Imperial banquet, and the sea voyage to
Crescent Island, with the break system's authored shields and weaknesses
throughout. The cave is worth exploring: its treasure includes gear that
matters for what's ahead.

**Locke has a Thief page in the field Skills menu.** His battle submenu
(Steal, Filch, Bestow) arrived in v0.9; the field half of it was the one
piece missing. The Skills list now shows an eighth row, Thief, white for
anyone who owns Steal and grey otherwise, and the page lists the three
abilities with their MP prices — the same numbers the battle actually
charges, read from the same tables.

**Under the hood, this release was tested the way a person plays.** The
automated playthrough that gates every release now opens every treasure
chest a player would see on screen — 51 of them across the supported game —
walks to each one, faces it, and presses A, exactly like you do. Fights,
supplies, and levels along the whole route were re-verified against that
richer, more honest baseline. You shouldn't notice anything except that the
game's difficulty is tuned for how people actually play.

## What we'd like to know

- Does the Sealed Gate cave's pacing feel right — the encounter rate, the
  break coverage, the treasure?
- The banquet: does the timed window feel fair, and did your score match
  what the dinner conversation deserved?
- Anything odd on the voyage's scenes (the pier, the night, the sails)?
- Does Locke's Thief page show the prices you were actually charged?
