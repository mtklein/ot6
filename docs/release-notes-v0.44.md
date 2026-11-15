# OT6 v0.44

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.44.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

Boosting Safe, Shell, Rflect, Vanish, Bserk, Regen, Antdot, Remedy,
Mute, Sleep, Muddle, Stop, Imp or Dispel now spreads the spell to one more
target per point, on the side it was aimed at, skipping anyone it would not
affect. Each point adds the spell's MP cost again, even when there is no one
left for it to reach, up to 99 MP. Vanish boosted at an enemy drops the
boost. Vanish spreads
only to your own party. Imp and Vanish follow the target: aimed at someone
who already has the status, they remove it from the others who have it too.

Boosting Edgar's Debilitator now adds one more weakness per point, each shown
on the enemy as the first one is. Each point costs the Debilitator's price
again.

Boosting Locke's Filch now takes one more shield per point, each point
costing one Filch's MP cost. Only the first shield taken becomes a boost point
for Locke.

Boosting Locke's Bestow now hands over as many boost points as you raised:
two at two points, three at three, as many as the ally can hold. Locke pays
exactly the points handed over.

NoiseBlaster, MagiTek Confuser and X-fer, and the Gravity Rod used as an
item no longer take a boost, since boosting them did nothing. A Sketch that
draws an attack with no damage or healing number for a boost to raise (a
status spell such as Slow or Imp, or Break) no longer uses up the boost
raised for it.

The shield count under each enemy is easier to read: it is drawn in white in
the same numerals as your HP, beside a white shield, and it no longer looks
like one of the weakness icons next to it. A weakness you have not found yet
shows as a grey question mark. A broken enemy now turns
grey until it recovers, and its shield is drawn cracked. In a fight with
several kinds of enemies, a broken enemy may keep its colours; the
cracked shield still marks it.

**Kefka has more shields.** The Kefka at the top of his tower now has 16
shields instead of 12, the most of any boss in the game.

**Espers teach bonuses that stay.** A worn esper still lends its spells and
summon, but no longer raises or lowers stats while worn. Instead, every won
battle that awards them pays Magic Points to each living party member for the esper they
wear, twice as many in random battles (some story fights award none);
members outside the party earn none.
Each esper has five ranks, at 10, 30, 75, 200 and 500 Magic Points: a point in
each of its stats, a small lasting effect such as an immunity, two
more points in its main stat, and at the top an effect on the level of a
relic. A rank once reached stays with that character whatever they wear
later. The victory screen shows the Magic Points and any new rank, and the
esper's page under Skills shows the selected character's rank, points and
every rank's reward, grey until reached. Sraphim is the healer's esper: at
its third rank, the HP that character restores, by spell or by item, is a
quarter more, and at the top, anyone they bring back with Life or a Fenix
Down returns with full HP.

A few top ranks do something no relic does. Ramuh's makes a lightning spell
cast at an enemy weak to lightning take one more shield. Carbunkl's starts every battle
with two boost points, and Phoenix's starts every battle under Life 3, which
revives its wearer once when they fall. Fenrir's protects against
Stop and Slow. Crusader's gives its wearer the Gauntlet's two-handed grip and
the Genji Glove's two weapons at once, with neither worn, and without the
Genji Glove's damage penalty on a single weapon. Odin and Raiden share one Magic Point count. Umaro and Gogo
can't wear espers, so they never earn Magic Points. Magic Points are kept
with your save: loading a save loses any earned since.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.43's, and the characters in them already hold esper
ranks.

## Saves

This release uses the v0.44 save layout. Saves from earlier releases load,
and their characters start with no esper progress.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
