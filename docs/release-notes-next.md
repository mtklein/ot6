# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

Boosting Safe, Shell, Reflect, Vanish, Berserk, Regen, Antidote, Remedy,
Mute, Sleep, Muddle, Stop, Imp or Dispel now spreads the spell to one more
target per point, on the side it was aimed at, skipping anyone it would not
affect. Each point costs the spell's price again, even when there is no one
left for it to reach, so a three-point Safe costs four casts. Vanish spreads
only to your own party. Imp and Vanish follow the target: aimed at someone
who already has the status, they remove it from the others who have it too.

Boosting Edgar's Debilitator now adds one more weakness per point, each shown
on the enemy as the first one is. Each point costs the Debilitator's price
again.

Boosting Locke's Filch now takes one more shield per point, each point
costing one Filch's price. Only the first shield taken becomes a boost point for Locke.

Boosting Locke's Bestow now hands over as many boost points as you raised:
two at two points, three at three, as many as the ally can hold. Locke pays
exactly the points handed over.

NoiseBlaster, MagiTek Confuser and X-fer, and the Gravity Rod used as an
item no longer take a boost, since boosting them did nothing. A Sketch that
draws an attack with no damage or healing number for a boost to raise (a
status spell such as Slow or Imp, or Break) no longer uses up the boost
raised for it.

The shield count under each enemy is easier to read: it is drawn in the same
numerals as your HP, yellow on a dark plate beside a shield, and it no longer
looks like one of the weakness icons next to it. A broken enemy now turns
grey until it recovers, and its shield is drawn cracked. In a fight with
several kinds of enemies, a broken enemy may keep its colours; the
cracked shield still marks it.

**Kefka has more shields.** Kefka now has 16 shields instead of 12, the most of any boss in the game.

**Espers teach bonuses that stay.** A worn esper still lends its spells and
summon, but no longer raises or lowers stats while worn. Instead, every won
battle pays Magic Points to each living party member for the esper they
wear, twice as many in random battles; members outside the party earn none.
Each esper has five ranks, at 10, 30, 75, 200 and 500 Magic Points: a point
in each of its two stats, a small lasting effect such as an immunity, two
more points in its main stat, and at the top an effect on the level of a
relic. A rank once reached stays with that character whatever they wear
later. The victory screen shows the Magic Points and any new rank, and the
esper's page under Skills shows the selected character's rank, points and
every rank's reward, grey until reached.

**Saves.** This release uses the v0.44 save layout. Saves from earlier
releases load, and their characters start with no esper progress.
