# OT6 v0.21 — Break It and It Dies

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.21.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**Shadow's break is a kill.** Shadow has a once-per-battle instant kill. It
used to work only on an enemy that was already Broken, and his breaking hit
usually killed the enemy by itself first, so it rarely came up. Now the hit of
his that empties an enemy's last shield kills it outright — break it and it
dies — and it still works on an enemy that's already Broken. Enemies immune to
instant death, most bosses among them, are only Broken, and the kill waits for
a body it can finish.

**Greyed commands are refused, not wasted.** Rage costs Gau a flat 8 MP; when
he can't pay it, every beast in the Rage list is now greyed and picking one
buzzes instead of spending his turn on nothing. The same goes for Locke's
Bestow when he has no boost pip to give.

**More allies spend their boost when provoked.** Since v0.20, an ally the game
is steering — Berserked or Muddled — spends all its banked pips on its next
attack after it's hurt. Now Cyan does too in the Imperial Camp fights, where
he fights on his own beside Sabin and Shadow.

**A boost pays off once.** Shadow's boosted Throw now hits harder with every
throwable weapon; nineteen of them, the Dirk and MithrilKnife among them, used
to take the pips and throw no harder. The same rule trims two double payoffs.
A boosted Fight buys extra swings, so the spell a weapon casts off one of them
(Blizzard's Ice, Tempest's Wind Slash) now lands at its normal strength
instead of multiplied as well. A boosted Rage buys the certainty of the
beast's special, and no longer also hits harder or more often.

**Saves carry over.** In-game saves from v0.20 load in v0.21. Emulator save
states don't carry across versions, so load from an in-game save.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
