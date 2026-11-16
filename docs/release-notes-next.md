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

A few esper rank descriptions on the Skills > Espers page are clearer. Ramuh's
top rank now says it takes an extra shield only from an enemy weak to
lightning. Tritoch's top rank says it raises maximum MP, and Maduin's top rank
is named Earrings, after the item.

The Narshe Beginner's House is up to date. It now says a broken enemy's shield
is drawn cracked, that only the hits after the one that breaks it do double
damage, that a new Boost Point shows at the character's next turn and the
arrows stay until the action starts, that a boosted Fight with two weapons
lands two more hits per point, and that boosting a status spell such as Sleep
or Mute spreads it to one more target per point, for its MP again per point.

Saving no longer changes Gau's, Strago's or Cyan's loadouts. If a game was
started before v0.45 on an emulator or console whose memory did not start out
blank, and Gau's Rage list or Strago's Lore list still comes up empty, set that
loadout back to AUTO on its page in the Skills menu. New games are not
affected.

On emulators and consoles whose memory does not start out blank, a new game no
longer depends on what that memory held: the steps to the first random battle,
the event counters a few scenes keep, and the positions of characters off
screen now start the same every time. A boosted Fight that switches to another
enemy after its target falls also no longer behaves differently in the first
battle after turning the console on.

Spell lists are packed. The Magic list, in battle and under Skills, shows only
the spells the character can cast now, from the top and in the usual spell
order, with spells lent by an Esper or a shield in their usual places among
them. Strago's Lore list in battle shows his lores one under another. The
Magic, Lore and Rage lists no longer scroll past their last entry, and the
cursor no longer stops on an empty space. A muddled character can now pick a
spell lent by an Esper, as well as the ones they know. Mog's Dance list and the
list behind Locke's Steal are packed the same way in battle: the dances Mog
knows and the skills Locke has learned sit together from the top, with no gap
for one still to come, and the cursor stays on them.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
