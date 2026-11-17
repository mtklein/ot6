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

Maduin's and Bahamut's top Esper ranks now count as an Earring. With an
Earring or Hero Ring worn as well, or with both ranks, magic damage rises by
half, the same as wearing two Earrings.

A boosted spell now casts the tier its list showed. At the target choice, L
and R spread a spell like Fire or Cure over a group, and they also moved the
boost: picking Fire 3 with two points and spreading it with L cast Fire 2 for
one point while the list still said Fire 3, and spreading with R raised it
without showing the new name or price. Now a spell or skill picked from its
list keeps the boost the list showed; L and R there only spread it. In a list,
R also no longer adds a point the character's MP cannot pay for, so a row is
never left greyed by a boost; before, the point was taken and the row could
not be cast until it was taken back.

Locke's Bestow is greyed and refused when no ally can take a point, as when
he fights alone, boosted or not; before, it was usable whenever he held a
point and spent his turn and its MP on nothing. Relm's Portrait and Gesture
are greyed the same way when no ally can take them.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
