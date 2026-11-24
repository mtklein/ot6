# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

There are six weapon types now, where there were four: Sword, Dagger, Spear,
Katana, Blunt and Ranged. With four, almost any party could break almost any
enemy with its weapons; with six, who you bring and what they hold matters
more. Most enemies have as many weapon weaknesses as before, each old one
now a type its own weapons went to: slashing is now Sword or Katana,
piercing Dagger, Spear or Ranged, bludgeoning Blunt or Ranged, special
Ranged or Blunt. The enemies from the Narshe mines to Zozo were set by hand
for the party you have when you meet them, so each new member's type
matters soon after they join (Locke's daggers, Edgar's AutoCrossbow,
Sabin's fists, Cyan's katana, Gau's fangs). The Narshe school's weapon
advisor explains the six. The icons under an enemy, the icon on each weapon's name
and the type word in the item menu show the six, and the first hit on a
hidden weakness says which it was ("Weak against swords", daggers, spears,
katanas, blunt or ranged).

Who holds which:

- **Sword**: swords but the curved ones, and Edgar's Chain Saw. Terra and
  Celes; Edgar and Locke can equip swords.
- **Dagger**: daggers, ninja blades and claws; Locke's Trickshot and
  Dismantle; Gau's fangs (his bare hands, and his Fight in a rage). Locke,
  Shadow, Gau, and Sabin with a claw on; Terra, Celes, Edgar, Setzer, Mog,
  Strago and Relm can equip some daggers.
- **Spear**: spears and lances; Edgar's Drill. Edgar and Mog.
- **Katana**: katanas, and the curved swords (RegalCutlass, Flame Sabre,
  Falchion, Soul Sabre, Scimitar); Cyan's SwdTech. Cyan, and Terra or Celes
  with a curved sword; Edgar can equip them too. The first is the
  RegalCutlass in South Figaro's weapon shop.
- **Blunt**: bare fists, the knuckles (MetalKnuckle, Kaiser, Fire Knuckle),
  rods, brushes, the Flail, Morning Star and Bone Club; Sabin's Pummel,
  Suplex and Bum Rush; Umaro's Charge and Throw. Sabin, Umaro, Strago and
  Relm; Terra and Celes can equip the Flail and Morning Star.
- **Ranged**: what is thrown or shot. Thrown stars, Darts, cards, dice,
  boomerangs and the Hawk Eye; Edgar's AutoCrossbow and Air Anchor; Shadow's
  skeans; Setzer's Coin Toss. Setzer, Shadow (Throw) and Edgar
  (AutoCrossbow); Locke can equip the boomerangs.

What to watch for: ninja blades are Dagger and Shadow's throws Ranged, so he
holds two types; Edgar's AutoCrossbow is Ranged and his Drill Spear; Sabin's
claws are Dagger and his Blitzes Blunt; Terra and Celes hold Sword or Katana
by the sword they choose; rods and brushes are Blunt. You will meet more
enemies that the weapons in hand cannot break. A second weapon type in the
party, a spell of the right element, Locke's Filch, the Break
spell, or Setzer's Hired Help (which swings a type the target is weak to)
answers them. The guide (docs/PLAYING.md, "Weapon types") lists every type
each character can equip.

**A break cancels a boss's announced move.** A boss that announces a big
move loses it if you break the boss first. While the move is pending a
yellow **!** stands in front of the boss's shield icon; a break while it is
up cancels the move, and after it recovers the boss has to earn the move
again the way it did the first time (Kefka, whose move comes from how hurt
he is, announces it again on his first turn back). Before, a break only
delayed the move. This applies to AtmaWeapon's Flare Star, Atma's Ultima,
the Gold Dragon's Bolt 3 and Kefka's Goner. Hitting the Gold Dragon with
Fight while it is broken no longer counts toward its stored Bolt 3.

**Early bosses announce their big move.** The Whelk ("It draws in!",
then it draws into its shell), the Marshal ("Strike as one!", then two
strikes with both Lobos acting at once), Vargas ("Feel the wind!", then
Gale Cut), Ultros at the Lete River ("Squirm, BANON!", then his Tentacle
on Banon), TunnelArmr ("Laser charges!", then TekLaser on both), Telstar
("It radios in!", then its backup), the GhostTrain ("Whistle blows!",
then Evil Toot two turns later), Rizopas ("Waters swell!", then El Nino)
and Kefka at Narshe ("Frost creeps!", then Ice on the squad) say what is
coming ahead of time, with the yellow **!** in front of the shield icon.
Break the boss before the move and it is cancelled. Against some of them
you will usually win the race; against Vargas, Ultros and TunnelArmr the
line is mostly a cue to brace. Break the Whelk's head while it is
drawing in and it stays out, broken, for the whole break. The Marshal
announces only while a Lobo stands. Celes's Runic takes TekLaser or
Kefka's Ice whole, aimed at everyone, if her stance is still up when it
lands: it ends when she next acts unless you boost it. Telstar has 3
shields instead of 4, and Shadow's blade breaks it as well as Sabin's
blows.

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
starts with no esper progress. A save from an older release keeps its
revealed weaknesses, each shown as the new type that weakness became for
that monster.
