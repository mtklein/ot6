# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

There are six weapon types now, where there were four: Sword, Dagger, Spear,
Katana, Fist and Arcane. With four, almost any party could break almost any
enemy with its weapons; with six, who you bring and what they hold matters
more. Every enemy has as many weapon weaknesses as before. Each old one
became one of two: slashing is now Sword or Katana, piercing Dagger or
Spear, bludgeoning Fist or Arcane, special Arcane or Dagger. The icons under
an enemy, the icon on each weapon's name and the type word in the item menu
show the six, and the first hit on a hidden weakness says which it was
("Weak against swords", daggers, spears, katanas, fists or arcane).

Who holds which:

- **Sword**: swords, and Edgar's Chain Saw. Terra, Celes and Edgar; Locke
  can equip many swords and Cyan the Scimitar.
- **Dagger**: daggers, thrown stars, the Hawk Eye and Darts; Shadow's skeans;
  Locke's Trickshot and Dismantle. Locke and Shadow; Terra, Celes, Edgar,
  Setzer, Mog, Strago and Relm can equip some daggers.
- **Spear**: spears and lances; Edgar's AutoCrossbow, Drill and Air Anchor.
  Edgar and Mog.
- **Katana**: katanas and ninja blades; Cyan's SwdTech. Cyan and Shadow.
- **Fist**: bare hands, claws, the Flail, Morning Star and Bone Club; Sabin's
  Pummel, Suplex and Bum Rush; Umaro's Charge and Throw. Sabin, Gau and
  Umaro; Terra, Celes, Strago and Relm can equip the Flail and Morning Star.
- **Arcane**: rods, brushes, cards, dice and boomerangs; Setzer's Coin Toss.
  Strago, Relm and Setzer; Locke can equip the boomerangs.

Three families moved: claws were slashing and are Fist, ninja blades were
piercing and are Katana, and rods and boomerangs were bludgeoning and are
Arcane. You will meet more enemies that the weapons in hand cannot break. A
second weapon type in the party, a spell of the right element, Locke's
Filch, the Break spell, or Setzer's Hired Help (which swings a type the
target is weak to, Arcane included now) answers them. The guide
(docs/PLAYING.md, "Weapon types") lists every type each character can equip.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress. A save from an older release keeps its
revealed weaknesses, each shown as whichever of the two new types that
monster now has.
