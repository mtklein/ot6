# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

The hit that breaks an enemy now does the damage of a hit on a shielded
enemy: half. Only hits on an enemy that is already broken do double, so in
an attack that strikes several times, the strikes after the break are the
ones that pay. Each enemy holds out for about one more hit, and when you
strike matters more than before.

A break now plays out with the hit that causes it. The shield count drops,
the shield cracks, the break sounds and a newly found weakness appears as
that hit's damage shows, one strike at a time, instead of before the attack
has played.

The Boost Points beside each name now show what you can spend. Points put on
a command stay shown as arrows until that action starts, and the point a
character gains after an action appears when that character's next turn
comes.

Broken enemies no longer turn grey. The cracked shield under an enemy shows
that it is broken.

Stray black squares no longer appear in battle. A battle could start with
one punched in the scenery, often at the top right, and another in the
menus, most often on the Veldt.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
