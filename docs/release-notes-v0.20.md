# OT6 v0.20 — Off the Leash

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.20.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**Characters you aren't steering now fight back.** A character the game is
steering instead of you — most often an ally an enemy has Berserked or
Muddled — used to be dead weight in the boost economy: it banked its turns
and never spent them.

Now it spends them. It builds boost pips the ordinary way, and the moment
something hurts it, its next swing dumps the whole bank — up to three pips at
once. A boosted Fight buys extra hits that land rather than one bigger hit,
so that dump is up to four connecting blows from a single weapon, eight with
a Genji Glove pair, and each hit that lands is another chance to chip at an
enemy's shield. Hurt it and it hits back harder, and it costs no MP.

**Muddle cuts both ways, on purpose.** A Muddled ally that takes a hit dumps
those same pips — and if the confusion has turned it on you, the extra swings
land in your own front row. That is intended, not an oversight: while the
game is steering an ally, it banks and spends its boost like anyone else,
even when it has been turned against you.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
