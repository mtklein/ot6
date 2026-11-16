# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

The hit that breaks an enemy no longer gets the broken bonus. It does what
any hit on a shielded enemy does, half damage, where before it did about four
times that. Only hits on an enemy that is already broken do double, so in an
attack that strikes several times, the strikes after the break are the ones
that pay. Fights are somewhat tougher: in our full play-through the same
fights ran about 5% longer, and the party fell 67 times where it had fallen
50 times in v0.45.

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

Stray black squares no longer appear in battle. A battle could start with one
punched into the scenery near the top right, or into the menus.

The Magic list, in battle and under Skills, is packed: it shows only the
spells the character can cast now, from the top, in the spell order chosen in
Config, with spells lent by an Esper or a shield among them. Strago's Lore
list in battle shows his lores one under another. The Magic, Lore and Rage
lists no longer scroll past their last entry, and the cursor no longer stops
on an empty space. A muddled character's random spell can now be one lent by
an Esper, not only one they know.

Mog's Dance list and the list behind Locke's Steal are packed the same way in
battle: the dances Mog knows and the skills Locke has learned sit together
from the top, with no gap for one still to come.

Three esper rank descriptions on the Skills > Espers page are clearer.
Ramuh's top rank now says Bolt cuts 2 shields on a weak foe; Tritoch's spells
out No Dark or Petrify and that it adds to max MP; Maduin's top rank is named
Earrings, after the item.

The Narshe Beginner's House is up to date on breaking and boosting: the
cracked shield, the hits after a break doing double, when Boost Points and
their arrows show, a boosted Fight with two weapons, and a boosted status
spell reaching one more target per point.

On emulators and consoles whose memory does not start out blank, a new game
no longer depends on what that memory held: the steps to the first random
battle and a few hidden counters now start the same every time, and the first
battle after turning the console on plays like any other.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.

v0.45 said a game started on a console whose memory did not start out blank
would have its Rage, Lore and SwdTech loadouts corrected when you saved. This
release does not do that: saving never changes your loadouts. If you started
such a game before v0.45 and did not save it in v0.45, and Gau's Rage list,
Strago's Lore list or Cyan's SwdTech list comes up empty or wrong, set that
loadout to AUTO on its page in the Skills menu. A game v0.45 already
corrected stays corrected, and new games are not affected.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.45's.

The zip also holds `ot6-manual.pdf`, an instruction booklet in the style of a
1990s cartridge manual.
