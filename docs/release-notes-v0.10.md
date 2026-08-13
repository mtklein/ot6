# OT6 v0.10 — Hit count is the break dial

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.10.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

Play from the beginning through the end of the Magitek Research Facility
and Terra's return, then stop.

Past the stop point the new systems may run but are not part of this
release's supported, balanced playtest range.

## What's changed

**Hit count is now the break dial.** A shield chips once per landed hit, not
once per action, so an ability that hits twice chips twice. Three abilities
gained hit counts, with their power divided by the number of hits so nothing
gets free damage:

- **Pummel** hits twice, bludgeoning. It is now the cheapest chip in the
  game, which makes Sabin the fast prober his kit was always described as.
- **Bum Rush** hits four times.
- **Drill** hits twice, piercing.

The point is that the three ability characters now have different jobs
against the same enemy: Sabin opens shields quickly with cheap multi-hits,
Cyan buys single large commitments that pay off once a shield is already
open, and Edgar's Tools sit between them.

**The Phantom Train fight works.** Reported from outside as unwinnable by its
intended strategy, and the report was right: the train has six shields keyed
to bludgeoning, and the shipped game delivered exactly one chip a round
through Sabin alone, so it died before the break could complete. Pummel now
delivers two chips a use, and the ghost merchant stocks Fire Skeans, so
Shadow has the answer the design always assumed he had. Both fit the
scenario's money without foreknowledge.

**A Broken monster stops acting.** Counterattacks and turns queued before the
break used to arrive anyway, so a boss you had just opened up could still hit
back — including casting through its own break window. That is what a punish
window is for, and it is a real difficulty change you should feel.

**Boosting no longer takes your MP and gives you the base spell.** Boosting at
the command window could charge the folded spell's price and then cast the
unfolded one. It depended on which frame your action was picked up, so it was
intermittent and easy to miss.

**Battles no longer slow down after you boost.** Boosting at the command
window left a redraw request standing that cost about ten percent of the
battle loop until the menu closed. It read as the game feeling sluggish
rather than as a bug.

**The kit window keeps up.** It used to draw the BP total it saw when it
opened, so a bank that changed while the window was up showed the old number
until you closed and reopened it.

Also in this release, from earlier work: esper stat bonuses that feel like
gear rather than rounding, kit changes reaching saves that already exist, and
Overclock priced consistently with what it does.

## What we'd like to know

- Does the Phantom Train's break feel reachable now, and does completing it
  feel worth doing rather than something you race past?
- Do Sabin, Cyan and Edgar feel like they have different jobs in a fight, or
  do they still feel like three sources of damage?
- Does anything feel harder than it did? Broken bosses no longer counterattack,
  which cuts both ways: the punish window is real, but so is the fight that
  gets there.
