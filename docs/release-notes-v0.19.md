# OT6 v0.19 — The Price of Power

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.19.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**Boosting now costs extra MP.** Boost still doubles, quadruples and
octuples what an ability does — but where it used to be free, the MP price
now climbs with it: two and a half times the usual cost per level of boost,
and nothing a two-digit price can show goes past 99. A Blitz that costs 10
costs 25 at one pip and 63 at two.

That covers **Blitz, Tools, Dance, the Lores, summons, and every spell
outside a tier family** — Break, Drain, Scan, Osmose, Ultima and the rest.
A boosted Ifrit costs 26 normally, 65 at one pip and 99 at two, so calling
an esper down is a real decision instead of a reflex.

So boosting is a decision generally. Early on a full three-pip boost is
simply out of reach for most characters, and the interesting question each
turn is whether this fight is worth one pip, two, or none.

**What stayed free, and why.** Boosting **Fight** costs no MP at all, and
it is the tool for breaking shields and clearing ordinary encounters
quickly — each pip buys another swing that lands. **Steal**, **Rage** and
**Slot** are unchanged as well: boosting those buys better odds rather than
bigger numbers, and the BP is price enough.

**Tier-family magic and SwdTech are unchanged for a different reason** —
they already charged you more. Boosting Fire folds it up to Fire 2 and
charges Fire 2's own MP, as it always has, and boosting a SwdTech picks a
higher tech and charges that tech's price. They escalate by climbing a
ladder rather than by paying a multiplier.

**An ability you cannot afford is now refused instead of wasted.** Pick a
greyed-out Blitz, Tool, SwdTech, Steal or Dance and the game buzzes and
leaves the list open, the way it always has for magic. Your turn, your
banked pips and your MP all stay yours. Previously it let you commit, and
the attack simply did nothing.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
