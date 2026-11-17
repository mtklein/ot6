# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

Shadow's throws now slow the enemy they hit. A throw at an enemy that is
already slowed, by a throw or a spell, stops it for about two of its turns
and uses up the slow. Broken enemies are slowed but never stopped, and
enemies that ignore Slow or Stop still do. A small dagger before an enemy's
shield shows it is slowed, and a knife shows it is stopped; they appear with
the hit and go when the status ends. Gogo's Throw and a Mimic of a throw do
the same, so Shadow can slow an enemy and Gogo can stop it. A boost on a
throw still multiplies its damage. An enemy stopped just as its turn comes
up now loses that turn, instead of taking it the moment the stop ends.

Maduin's and Ragnarok's top Esper ranks now count as an Earring. With an
Earring or Hero Ring worn as well, or with both ranks, magic damage rises by
half, the same as wearing two Earrings.

Bahamut's top Esper rank is now Limit Break: everything that character
deals, from attacks and spells to throws, summons and counters, can do up to
42,069 damage instead of stopping at 9999. Healing still stops at 9999, and
everyone else's damage still stops at 9999. Damage numbers now show five
digits when they need them. Bahamut's old top rank, the Hero Ring's boost to
Fight and magic damage, moves to Ragnarok's top rank, which no longer raises
Vigor by half. It still counts as an Earring.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
