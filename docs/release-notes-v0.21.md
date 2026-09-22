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

**Shadow's Assassinate fires on the break.** Shadow's divine used to kill only
an enemy that was already Broken, and his breaking hit usually killed the enemy
by itself first, so the divine rarely had anything to do. Now the hit of his
that empties an enemy's last shield kills it outright on that hit — break it
and it dies — and his attack on an enemy someone else already Broke still kills
too. Once per battle. A boss is only Broken, never killed, and the divine waits
for a body it can finish.

**Greyed commands are refused, not wasted.** Rage costs Gau a flat 8 MP; when
he has less, every beast in the Rage list is now greyed and picking one buzzes
instead of spending his turn on nothing. The same goes for Locke's Bestow when
he has no boost pip to give, and for a SwdTech tier past Cyan's boost bank.

**More allies spend their boost when provoked.** Since v0.20, an ally the game
is steering — Berserked or Muddled — dumps its banked pips on its next attack
after it's hurt. That now also covers allies an event is driving, like Cyan
holding the line on his own during the siege of Doma, and every one of Umaro's
attacks: his plain swing gains extra hits, Charge and Storm hit harder, and
Throw throws again once per pip.

**Saves carry over.** Saves from v0.20 load and play on in v0.21.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
