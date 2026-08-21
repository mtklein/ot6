# OT6 v0.13 — Thamasa

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.13.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

Play from the beginning through the Thamasa arc — everything the Sealed Gate
release (v0.12) covered, then the voyage's landing onward: Thamasa town,
Strago joining, the burning house and FlameEater, the Esper Mountain and
Ultros, Kefka's massacre with General Leo, and the flight out — and stop when
the airship sets you down on the world map after the massacre. Past that
point the new systems may run but are not part of this release's supported,
balanced playtest range.

## What's changed

**The playable range extends through the whole Thamasa arc.** This is the
second release of the end-of-World-of-Balance arc (v0.12–v0.14): from the
Crescent Island landing you can now play Thamasa town, Strago's recruitment,
the burning house and its FlameEater, the Esper Mountain with Ultros and
Relm's recruitment, and Kefka's massacre — General Leo's one desperate solo
fight and all — ending beside the repaired Blackjack. The break system's
authored shields and weaknesses run throughout, tuned for how people
actually play.

**Strago joins as a Scholar with a curated Lore bank.** He learns Lore by
observation the way vanilla does, but carries a chosen few into battle:
Skills → Lore in the field menu is a configurator, five slots against
everything he has seen, each priced with the MP the battle actually charges.
Aqua Rake is free at join and, being water, is the burning house's own
answer — one cast chips every Balloon's shield.

**General Leo is playable at the massacre.** His fight against Kefka carries
an authored break row — four shields, weak to the slashing of his Crystal
sword — so the emotional peak of the World of Balance is a real fight you can
win with intent and lose if careless, not a formality. Shock is free.

**The burning house rewards preparation, not grinding.** The ambush and
FlameEater are winnable at the level the route brings you — if you do what a
player does: heal before you go in, put the front line in the back row,
equip an esper that grants ice or water, and lead with the weakness. The
whole arc's difficulty was verified against that, the same tested-like-a-
person discipline v0.12 introduced (and it caught a real one: the fight the
automation kept losing was winnable all along — it just kept walking in
unprepared).

## A warning about Sketch

Relm joins with **Sketch**, and Sketch carries Final Fantasy VI 1.0's most
famous bug, **deliberately left in place**. When a Sketch *misses* — which
happens against enemies of higher level than Relm, and against vanished or
invisible targets — the game can rarely corrupt your item inventory, crash,
or damage your save in ways that surface later. When a Sketch *hits*, the bug
cannot fire.

This is a house rule, not an oversight. OT6 fixes vanilla's destructive bugs
as a matter of course (the save-checksum bug went in v0.6); this one is a
deliberate exception, the 1994 original's behavior kept intact — a bit of
Roman ruins left standing inside the building. **Save before experimenting
with Sketch.** The world map saves anywhere.

## What we'd like to know

- The burning house: does the ambush feel like a fair wall or a brick one?
  Did preparing — back row, an ice/water esper, healing first — carry you
  through, or did it still feel punishing?
- Strago's Lore bank: does picking his five carried Lores feel worth doing,
  and do the field prices match what battle charges?
- Ultros and the Esper Mountain: pacing, the break coverage, the treasure.
- The massacre: does Leo's solo fight land — winnable but tense — and does
  the whole sequence carry its weight?
- Anything odd in the scenes (the fire, the statues, the flight out).
