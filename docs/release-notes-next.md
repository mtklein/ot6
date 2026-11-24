# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

**A break cancels a boss's announced move.** A boss that announces a big
move loses it if you break the boss first. While the move is pending a
yellow **!** stands in front of the boss's shield icon; a break while it is
up cancels the move, and after it recovers the boss has to earn the move
again the way it did the first time (Kefka, whose move comes from how hurt
he is, announces it again on his first turn back). Before, a break only
delayed the move. This applies to AtmaWeapon's Flare Star, Atma's Ultima,
the Gold Dragon's Bolt 3 and Kefka's Goner. Hitting the Gold Dragon with
Fight while it is broken no longer counts toward its stored Bolt 3.

Celes is a spellblade. Her command, now RuneKnt, opens a list. Runic is its
first row and works as before, and a spell with an element that it absorbs,
an enemy's or an ally's, leaves that element on her blade for the rest of
the battle. Her weapon's hits then carry it onto any enemy weak to it, for
double damage and a shield a hit; on other enemies it does nothing. The list
also has a blade row for each element she can cast, her own spells and her
Esper's, which arms her blade for her turn and that spell's MP. Boosting a
blade works as boosting the spell does: a Fire 2 Blade or Fire 3 Blade, for
that spell's MP, bites for 3x or 4x where the plain blade bites for 2x. Her
swing takes the element's colour when it bites, and its icon stands beside
her name. Her ultimate is now Break Blade, learned on the Floating Continent: at
3 BP and 99 MP, every hit of her weapon takes a shield for three of her
turns. Runic at 3 BP still sends spells back. Gogo's Runic opens the same
list. While Muted she cannot arm a blade or Break Blade, though a blade she
already holds keeps working and Runic still works. In the field menu, Skills
has a RuneKnt page that lists her rows with
their MP and a line of help for each.

Celes learns Break at level 13 where she used to learn Imp. A save in which
she is already past 13 has Break when it loads, and keeps the Imp she
learned. Stray still lends Imp.

**Boosted Dances open on their rare step.** Each of Mog's Dances has four
steps, and the rarest (Cokatrice, Wombat, Kitty, Tapir, Whump, Wild Bear,
Pois. Frog or Ice Rabbit) comes one turn in 16. A boosted Dance now starts
on it 1 time in 4 with 1 point, 1 in 2 with 2, and always with 3. Later
turns of the dance keep the usual odds. Gogo's Dance works the same way.

The Dragoon Boots now let anyone who wears them equip a spear (Umaro
excepted); taking the boots off takes the spear off too.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
