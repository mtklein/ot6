# Playing OT6

OT6 is Final Fantasy VI (Final Fantasy III in the US) with the battle system
of Octopath Traveler. The story, world, characters and maps are FF6's. This
guide is for someone who knows FF6 and has not played OT6. To patch the game,
see the [README](../README.md).

Narshe's Beginner's House teaches the basics in play. This guide covers the
rest. The same material, with pictures and tips for each area, is in the
[instruction booklet](manual/ot6-manual.pdf), a printable PDF.

## What is different at a glance

- Enemies have shields and hidden weaknesses. Hitting a weakness removes a
  shield. At zero shields an enemy is broken: it loses its turns and takes
  double damage.
- Each character has Boost Points. Pressing the R Button while choosing a
  command spends points to make an action stronger, surer, wider or longer.
- Every character has one job and a kit of up to eight skills. Most skills
  cost MP, including Blitz, Tools, SwdTech, Steal, Dance and Rage.
- Spells you cast with an Esper equipped are lent, not learned. The Esper
  also gives lasting bonuses, earned with Magic Points.
- Random battles come half as often and pay double Exp. and GP. A level-up
  fully restores HP and MP.
- Everything else is FF6: the story, the dungeons, the commands, and the old
  bugs. The original Sketch bug is still there, and a missed Sketch can
  corrupt inventory or a save. Save before you Sketch.

## Shields, weaknesses and Break

### Reading the display

Under each enemy is one line:

- a shield icon and a number: how many shields the enemy has left;
- then one cell for each weakness. A grey **?** is a weakness you have not
  found. Once you hit it, the cell shows the icon of the element or weapon
  type.

While an enemy has shields it takes half damage. Each hit that matches a
weakness removes one shield. A hit that matches both an element and a weapon
type removes two, and an attack that strikes several times removes a shield
per hit. At zero the enemy breaks: its shield icon shows broken and its
sprite turns grey, it cannot act for a while, and it takes double damage.
When it recovers, its shields come back.

A weakness you find is remembered for every enemy of that kind, in later
battles and in your save. Scan reveals all of a kind's weaknesses at once.

A few enemies have no shields and show no line.

### Weapon types

A weapon's icon shows its type. Fight uses the type of the weapon in hand.

| Type | Weapons |
|---|---|
| Slashing | swords, katanas, claws |
| Piercing | spears, daggers, thrown blades, bolts, darts, fangs |
| Bludgeoning | fists, staves, rods, flails, boomerangs |
| Special | dice, cards, brushes |

Skills have a type of their own: a Blitz keeps its type whatever Sabin
wears, and Edgar's Chain Saw is slashing. A weapon with an element hits the
weapon's type and its element at once.

### Elements

Fire, ice, lightning, wind, earth, water, holy and poison. A spell hits the
weakness of its element, and the Magic list shows each spell's element as
an icon. A hit on an elemental weakness also does FF6's usual extra damage.

A few attacks take shields without needing a weakness: the Break spell,
Locke's Filch, Sabin's Bum Rush and Cyan's Cleave on a boss.

## Boost Points

### Earning and spending

- Every character starts a battle with 1 Boost Point (BP).
- A character gains 1 BP after each action, up to 5. An action that was
  boosted earns none.
- While choosing a command, the R Button adds a point (up to 3, and no more
  than you hold). The L Button takes one back. Arrows and a glow show how
  many are pending, and the dots after each name show the bank.
- The points are spent when the action happens.
- A Mimic copies the action but pays nothing, and the boost buys what it
  buys on the copied action.

### What a point buys

| Kind of action | Examples | A point buys |
|---|---|---|
| Fight | Fight, Mug, Capture | one more hit with a weapon in hand. With the Genji Glove and two weapons, both hands swing again. No MP. |
| Spell families | Fire, Ice, Bolt, Poison, Cure, Life, Slow, Haste | the next spell of the line: one point casts Fire 2, two points Fire 3. A third point adds nothing. You pay the MP of the spell cast. |
| Damage or healing | Blitz, Tools, Lores, Dances, Esper summons, Drain, Pearl, Quake, Merton, Ultima, items that heal a number | double damage for 1 point, 4x for 2, 8x for 3 |
| Chance | Steal, Slot, Rage, a Dance's start | better odds; the third point removes the gamble |
| Duration | Runic, Morph | more of the character's own turns, or more time |
| Reach | Safe, Shell, Rflect, Vanish (on your party), Bserk, Regen, Antdot, Remedy, Mute, Sleep, Muddle, Stop, Imp, Dispel; Shadow's smoke and exit | one more target per point |
| Shields | the Break spell, Filch | one more shield per point |
| Steps | Dismantle, Debilitator | one more application per point |
| Reading | Scan, Appraise | every enemy at one point or more |
| SwdTech | Cyan's techs | the tech itself (see Cyan) |

Reach spells also cover as many bodies as there are points, skipping anyone
the spell would not change. Each point costs the spell's MP again, even if
nobody is left for it.

Some characters have an ultimate, offered only at 3 BP. It can be used again
whenever the bank holds three.

### What a boost costs in MP

- An action whose damage or healing is multiplied pays 2.5 times its MP per
  point: 1 point 2.5x, 2 points about 6x, 3 points about 16x. The price never
  goes above 99 and never below the unboosted price.
- Fight, Capture, Steal, Rage and Slot are not charged extra for a boost.
  Spells that move up a tier and SwdTech pay for the tier or tech you get.
- Reach spells, Debilitator and Filch pay their base price once per point
  used.
- The Magic list shows the name and price of the spell as you press R. Skills
  you cannot pay for are greyed.

### Actions that take no boost

On these, R does nothing, or a boost raised earlier is dropped before it
costs anything:

- Def., Row, Leap, Revert, Control and Possess;
- spells with no damage or healing number to raise: Doom, X-Zone, Demi,
  Quartr, W Wind, Float, Warp and Quick;
- items that heal a fraction or cure a status: Fenix Down, X-Potion,
  X-Ether, Elixir, Megalixir, Tent, Sleeping Bag, Antidote, Eyedrop, Soft,
  Remedy, Green Cherry, Echo Screen, Smoke Bomb and Warp Stone, and the
  Gravity Rod used as an item;
- Lores with no number: Condemned, Roulette, Big Guard, L.5 Doom, L.3 Muddle,
  Reflect???, ForceField, Dischord, Sour Mouth, Pep Up and Rippler; and
  Revenge, Blow Fish, Pearl Wind, Step Mine and Exploder, whose damage is set
  by something else;
- summons with no damage number, such as Hope Song and Life Guard;
- Edgar's NoiseBlaster, Sabin's Mantra, and MagiTek Confuser and X-fer.

A Sketch that draws an attack with no number to raise drops the boost.

## The characters

Skills come from FF6's own ways of learning, kept for each character. Prices
are in MP. Every character's first skill is theirs from the day they join.

### Terra, Mage (sword, fire)

- **Spells by level.** Fire and Cure from the start; Drain at 12, Life at 18,
  Break at 24, Pearl at 30, Merton at 33. Boost turns Fire into Fire 2 and
  Fire 3, Cure into Cure 2 and 3, and Life into Life 2 and 3.
- **Break** takes no damage and sets no status. It removes one shield, plus
  one per point (four at 3 BP), ignoring weakness. It costs 25 MP at any
  boost.
- **Morph** is learned in Zozo. Each point adds time to it.
- **Ultimate: Trance.** Morph at 3 BP lasts until the battle ends or she
  reverts.
- **Ultima.** After Terra returns in the World of Ruin (Mobliz), casting
  Fire with 3 BP casts Ultima, for 80 MP.
- **Economizer.** Won at the Colosseum with the Gem Box. Every spell its
  wearer casts costs 1 MP at any boost.

### Locke, Thief (dagger)

| Skill | MP | Effect | Learned |
|---|---|---|---|
| Steal | 4 | steals; a boost makes it likelier | from the start |
| Filch | 6 a shield | takes a shield, ignoring weakness, and turns it into 1 BP for Locke | from the start |
| Bestow | 5 | gives an ally the BP pending (1 to 3) | from the start |
| Mug | 4 | a Fight whose hits each steal; a boost adds hits | South Figaro escape |
| Trickshot | 4 | a thrown coin that ignores defense; a boost multiplies it | Lete River |
| Dismantle | 8 | corrodes defense, then stabs; a boost corrodes more | Sealed Gate |
| Appraise | 3 | reads one enemy's weaknesses; a boost reads all | Thamasa, after Strago joins |
| **Master's Mark** | 99 | robs and reads every enemy (3 BP) | Floating Continent (the Air Force battle) |

Steal by boost: with 0 points it is FF6's Steal, unchanged. One point makes
the steal likelier and the rare item likelier. Two points make both a lot
likelier. Three points always succeed and take the rare item if there is one,
the common item if not. A boost never makes up an item the enemy lacks.
Only the first shield Filch takes becomes a point for Locke. His skills are
in the list behind Steal.

### Edgar, Machinist (spear)

Tools are found or bought, as in FF6, and cost MP each use.

| Tool | MP | Learned |
|---|---|---|
| AutoCrossbow | 4 | from the start. Pierces every enemy once. |
| NoiseBlaster | 6 | Figaro shop. Takes no boost. |
| Bio Blaster | 8 | Figaro shop. Poison. |
| Flash | 6 | Figaro's tool merchant and South Figaro's shop |
| Drill | 16 | Figaro Castle, after the sand dive. Two hits, piercing. |
| Chain Saw | 18 | Zozo chest. Slashing. |
| Debilitator | 10 | Vector's weapon shop, during the banquet. Gives an enemy a new weakness and shows it; a boost adds one more per point. |
| **Overclock** | up to 99 | Magitek factory, after the Espers' scene. |

Overclock: a Tool boosted with 3 BP fires twice, each time at 8x. It costs
both firings, up to 99.

### Sabin, Monk (fists)

Blitzes are chosen from a list; there are no button codes. Sabin learns them
by level, as in FF6.

| Blitz | MP | Level |
|---|---|---|
| Pummel | 4 | from the start. Two hits. |
| Aura Bolt | 10 | 6. Holy. |
| Suplex | 13 | 10 |
| Fire Dance | 17 | 15. Fire. |
| Mantra | 16 | 23. Takes no boost. |
| Air Blade | 28 | 30. Wind. |
| Spiraler | 50 | 42 |
| **Bum Rush** | 99 | 70, or from Duncan |

Fists are bludgeoning. Claws make his Fight slashing; his Blitzes keep their
own type. **Bum Rush** is offered only at 3 BP. It is four blows, each at
8x. Each blow removes a shield whatever the enemy is weak to.

### Cyan, Samurai (katana)

The charge gauge is gone. SwdTech opens a list of three techs, for 1, 2 and 3
BP. The three are Cyan's best learned techs, weakest first, so the list
moves up as he learns more. In the field menu, Skills > SwdTech lets you pick
which techs sit in the three slots, or return them to automatic.

| Tech | MP | Level |
|---|---|---|
| Dispatch | 4 | from the start |
| Retort | 10 | 6. A counter stance. |
| Slash | 13 | 12 |
| Quadra Slam | 16 | 15. Four slashing hits. |
| Empowerer | 18 | 24. Drains; two hits. |
| Stunner | 28 | 34. Hits all enemies. |
| Quadra Slice | 50 | 44. Four wind hits. |
| **Cleave** | 99 | the Phantom Train farewell |

**Cleave** is the 3 BP slot once learned. It strikes every enemy: each one
that can die, dies. A boss loses four shields and takes a very heavy cut.

### Celes, Rune Knight (sword, ice)

- **Spells by level.** Ice from the start; Cure at 4, Imp at 13, Scan at 18,
  Safe at 22, Haste at 32.
- **Runic** is hers from the start. It absorbs the next spell as MP and gives
  Celes 1 BP. As in FF6 it also absorbs spells her allies cast. Boosted, it
  stays up for 1, 2 or 3 of her turns, and she acts normally in them. The BP
  from absorbing is limited to one per round.
- **Ultimate: RunicBlade**, learned in the Magitek factory when Celes turns on
  Kefka. Runic with 3 BP also sends each absorbed spell back at its caster.

### Gau, Beast Tamer (fangs)

- **Rage.** Gau learns rages on the Veldt, without limit. Under Skills > Rage
  you choose the eight he can use in battle.
- Choosing a rage costs 8 MP once, and he stays possessed for the battle. On
  each turn the beast either attacks or uses its special, half the time each.
- **Boost** changes the odds of the special: 3 in 4 with 1 point, 15 in 16
  with 2, every turn with 3. It adds no damage.
- **Leap.** On the Veldt, Leap replaces Fight. It is free and takes no boost.
- Gau can wear Espers. He has no ultimate.

### Setzer, Gambler (cards and dice)

Slot opens a short list.

| Skill | Cost | Effect |
|---|---|---|
| Slot | free | the reels. Boost: 1 point removes the rigged miss; 2 points tilt the reels your way; 3 points guarantee a triple of the icon you stop first. |
| Coin Toss | level x 30 Gil | throws Gil at every enemy. A boost adds a toss per point. |
| Hired Help | level x 50 Gil | one hired blow that uses the type the target is weak to. A boost adds a hire per point. |
| **Jackpot** | 99 MP | throws the Fixed Dice twice at one enemy (3 BP). Each roll lands a triple, and a low roll does little. Learned when Setzer rejoins in the World of Ruin, at Kohlingen. |

Coin Toss and Hired Help take Gil, not MP. Each hire walks in as a different
figure.

### Strago, Scholar (rod)

- **Lore.** Strago learns lores by watching monsters cast them, and he equips
  five of them, chosen under Skills > Lore. Aqua Rake, once learned, is in his
  Lore list every battle in addition to the five.
- **Scan** is his from the day he joins, for 3 MP. It marks every weakness of
  a kind of monster, not only one. A boost reads every enemy.
- **Ultimate: Study.** Scan with 3 BP costs 99 MP and teaches Strago every
  lore any monster in the battle could cast, learned at the victory.
- **Bserk.** He learns it the first time a monster berserks someone while he
  is in the battle and standing at the end. The Insecares on Esper Mountain
  and the L.50 Magic in the Fanatics' Tower can teach it.
- Pearl Wind can be learned from the Sprinters in the wood west of the plain
  north-west of Jidoor. Strago learns GrandTrain from Hidon at Ebot's Rock.

### Relm, Painter (brush)

Sketch is her skill. A boost applies to whatever the sketch draws: it
multiplies an attack with a number, and is dropped if the attack has none.
Brushes hit the special type.

### Shadow, Assassin (thrown blades)

Shadow's skill is Throw. He throws the item you pick, and it is used up. A
boost multiplies a damaging throw.

| Item | Where | Effect |
|---|---|---|
| Shuriken, Ninja Star | Thamasa weapon shop, World of Ruin | piercing |
| Tack Star | Colosseum | piercing |
| Fire Skean, Water Edge, Bolt Edge | Maranda weapon shop | piercing and the element, to every enemy |
| Shadow Edge | Maranda weapon shop | casts Image on the thrower |
| Inviz Edge | Maranda weapon shop | casts Vanish on the thrower |

A boosted smoke or exit covers one more ally per point, so 3 points cover a
party of four. Anyone who throws one gets this.

**Ultimate: Assassinate.** With 3 BP, a hit of his that breaks an enemy kills
it, and so does a hit on an enemy that is already broken. A boss is only
broken. Interceptor blocks and counters physical attacks half the time, as
in FF6.

### Mog, Dancer (spear)

Mog learns his eight Dances by fighting on each dance's terrain, as in FF6.

| Dance | Terrain |
|---|---|
| Wind Song | plains and the Veldt |
| Forest Suite | forests |
| Desert Aria | deserts |
| Love Sonata | towns and buildings |
| Earth Blues | mountains |
| Water Rondo | underwater |
| Dusk Requium | caves |
| Snowman Jazz | snowfields |

Dances cost 8 MP, 20 with 1 point, 50 with 2 and 99 with 3, and a boost
multiplies every step. Off its own terrain a Dance may stumble, as in FF6: it
fails half the time. 1 point cuts that to one in four, 2 points to one in 16,
and 3 points to never. A stumble costs no MP, but the points are spent. Mog
has no ultimate.

### Umaro, Berserker (club, fists)

Umaro takes no orders. Each turn he picks Fight, Charge, Throw (with the Rage
Ring) or Storm (with the Blizzard Orb). His Fight, Charge and Throw are
bludgeoning, and Storm is ice on every enemy. Umaro banks a point each turn,
and when he has been hurt, he spends the bank on his next action. With 3
points he always Storms, with or without the Blizzard Orb, at 8x. He has no
MP and cannot wear Espers.

### Gogo, Mime

Gogo joins in the Zone Eater. His Mimic is free, and a boost buys what it
buys on the action he copies. Where it would buy nothing, the points are
kept. Gogo cannot wear Espers.

## Espers

Equip an Esper under Skills > Espers, as in FF6. While it is
equipped, the wearer can cast its spells and summon it once a battle. Take
it off and both go. Nobody learns the spells. An Esper no longer raises or
lowers stats while worn.

The Magic list, in battle and under Skills, shows only the spells the
character can cast now, packed from the top in the spell order chosen in
Config; an Esper's spells sit in their usual places among the wearer's own.

### Magic Points and ranks

- A won battle that pays Magic Points gives them to each living party member,
  for the Esper that member wears. Random battles pay double. A few story
  battles pay none. Characters outside the party earn nothing.
- Each Esper has five ranks per character, at 10, 30, 75, 200 and 500 Magic
  Points. The ranks give lasting stat points and effects. Once reached, a rank
  stays with that character whatever they wear later.
- Odin and Raiden share one count. Umaro and Gogo cannot wear Espers.
- The victory screen shows the points and any new rank. Under Skills >
  Espers, an Esper's page shows the selected character's rank, points and
  what each rank gives. Move the cursor right onto the ranks to read each
  one. A rank whose effect the character already has from another rank says
  "Already held". Max HP and max MP bonuses do not add up; the largest
  applies.
- Magic Points are kept in your save. Loading an older save loses any earned
  since.

### Every Esper

Ranks 1, 2 and 4 are stat points. Ranks 3 and 5 are effects.

| Esper | Spells while worn | Rank 1 (10) | Rank 2 (30) | Rank 3 (75) | Rank 4 (200) | Rank 5 (500) |
|---|---|---|---|---|---|---|
| Ramuh | Bolt, Rasp | Raises Stamina by 1 | Raises Mag.Pwr by 1 | Protects against Dark | Raises Stamina by 2 | Bolt spells break 1 more shield |
| Ifrit | Fire, Drain | Raises Vigor by 1 | Raises Stamina by 1 | Raises max HP by 1/8 | Raises Vigor by 2 | Raises Fight damage by 1/4 |
| Shiva | Ice, Osmose, Shell | Raises Mag.Pwr by 1 | Raises Speed by 1 | Protects against Seizure | Raises Mag.Pwr by 2 | Halves the MP spells cost |
| Siren | Mute, Sleep, Bserk | Raises Speed by 1 | Raises Mag.Pwr by 1 | Protects against Sleep | Raises Speed by 2 | Blocks Berserk and Muddle |
| Terrato | Quake, Quartr | Raises Mag.Pwr by 1 | Raises Stamina by 1 | Sometimes counters an attack | Raises Mag.Pwr by 2 | Raises max HP by 1/2 |
| Shoat | Break, Doom | Raises Speed by 1 | Raises Stamina by 1 | Protects against Petrify | Raises Speed by 2 | Blocks instant death, Condemned |
| Maduin | Fire, Ice, Bolt | Raises Mag.Pwr by 1 | Raises Stamina by 1 | Raises max MP by 1/8 | Raises Mag.Pwr by 2 | Raises magic damage by 1/4 |
| Bismark | Haste, Slow | Raises Vigor by 1 | Raises Stamina by 1 | Casts Safe when HP is low | Raises Vigor by 2 | Raises max HP by 1/4 |
| Stray | Muddle, Imp | Raises Mag.Pwr by 1 | Raises Speed by 1 | Protects against Imp | Raises Mag.Pwr by 2 | Raises the success rate of Steal |
| Palidor | Float, Slow | Raises Speed by 1 | Raises Vigor by 1 | Walks faster outside battle | Raises Speed by 2 | Float in every battle |
| Tritoch | Ice, Bolt, Poison | Raises Mag.Pwr by 1 | Raises Speed by 1 | Raises Speed by 1 | Raises Mag.Pwr by 2 | Blocks Dark and Petrify; max MP +1/2 |
| Odin / Raiden | Meteor, Bserk (Raiden also Quick) | Raises Vigor by 1 | Raises Speed by 1 | Fight always hits | Raises Vigor by 2 | Haste in every battle |
| Bahamut | Flare, W Wind | Raises Mag.Pwr by 1 | Raises Vigor by 1 | Raises max HP by 1/4 | Raises Mag.Pwr by 2 | Fight and magic damage +1/4 |
| Alexandr | Dispel, Safe, Shell | Raises Stamina by 1 | Raises Vigor by 1 | Protects against instant death | Raises Stamina by 2 | Safe in every battle |
| Crusader | Merton, Meteor | Raises all four stats by 1 | Raises all four stats by 1 | Raises max HP by 1/4 | Raises all four stats by 1 | Gauntlet and Genji Glove effects |
| Ragnarok | Ultima, Warp | Raises Vigor by 1 | Raises Mag.Pwr by 1 | Raises max MP by 1/4 | Raises Vigor by 2 | Raises Vigor by half |
| Kirin | Cure, Regen | Raises Mag.Pwr by 1 | Raises Stamina by 1 | Protects against Poison | Raises Mag.Pwr by 2 | Regen in every battle |
| ZoneSeek | Shell, Haste | Raises Mag.Pwr by 1 | Raises Stamina by 1 | Protects against Mute | Raises Mag.Pwr by 2 | Shell in every battle |
| Carbunkl | Rflect, Safe | Raises Stamina by 1 | Raises Mag.Pwr by 1 | Casts Shell when HP is low | Raises Stamina by 2 | 2 Boost Points at battle start |
| Phantom | Vanish, Demi | Raises Speed by 1 | Raises Mag.Pwr by 1 | No back or pincer attacks | Raises Speed by 2 | Starts every battle with Image |
| Sraphim | Cure, Life | Raises Stamina by 1 | Raises Mag.Pwr by 1 | Healing done is 25% stronger | Raises Stamina by 2 | Revives allies at full HP |
| Golem | Safe | Raises Stamina by 1 | Raises Vigor by 1 | Protects against Muddle | Raises Stamina by 2 | Covers weak allies while healthy |
| Unicorn | Pearl, Remedy | Raises Stamina by 1 | Raises Mag.Pwr by 1 | Protects against Zombie | Raises Stamina by 2 | Blocks Dark, Zombie and Poison |
| Fenrir | Stop, X-Zone | Raises Speed by 1 | Raises Mag.Pwr by 1 | Raises preemptive attack rate | Raises Speed by 2 | Blocks Stop and Slow |
| Starlet | Cure, Regen, Remedy | Raises Mag.Pwr by 1 | Raises Speed by 1 | Protects against Berserk | Raises Mag.Pwr by 2 | Raises max MP by 1/4 |
| Phoenix | Life, Antdot | Raises Stamina by 1 | Raises Speed by 1 | Blocks Condemned and Zombie | Raises Stamina by 2 | Starts every battle with Life 3 |

Notes on the ranks:

- Boosting a spell lent by an Esper works as for any spell: Fire becomes
  Fire 2 and Fire 3, and so on.
- Ramuh's top rank adds a shield when a lightning spell hits an enemy weak to
  lightning.
- Crusader's top rank gives the Gauntlet's two-handed grip and the Genji
  Glove's second weapon, with neither worn, and without the Genji Glove's
  damage penalty on a single weapon.
- Sraphim's healing bonus covers Cure, Life, a Blitz, Lore or Dance that
  heals, healing items, and Regen ticks the wearer receives. It does not cover
  MP.
- Sraphim, Golem and ZoneSeek are optional.

## Encounters, Exp. and Gil

- Random battles come half as often.
- Random battles pay double Exp. and GP, so a stretch of walking pays about
  what it did in FF6. Event and boss battles pay as before.
- A level-up fully restores HP and MP.
- The Cursed Shield counts a won random battle twice toward becoming the
  Paladin Shield.

## Things you can miss

- **Mog's Water Rondo.** Mog learns it by fighting underwater. In the World
  of Balance that is the Serpent Trench, reached from Crescent Mountain on
  the Veldt. Mog must be in the party.
- **Mog or the Gold Hairpin.** Mog is recruited during the Lone Wolf chase
  near Narshe. The wolf's ledge holds the Gold Hairpin. Only one of the two
  can be taken.
- **Shadow.** On the Floating Continent, choose "Wait!!" at the ledge until
  Shadow arrives. If you jump before he does, he is gone for the rest of
  the game. Otherwise he stays in the party until the story removes him. If
  you saved him, he is waiting at the Colosseum in the World of Ruin.
- **Umaro** joins in the World of Ruin only if Mog is in your active party
  when you reach the Narshe cliffs.
- **Optional Espers.** Sraphim (a man in the woods near Tzen), Golem and
  ZoneSeek (the Jidoor auction).
- **Gau's rages and Strago's lores** are learned only by meeting the monster.
  Gau learns a rage by Leaping into the Veldt and returning. Strago learns a
  lore by being in the battle when a monster casts it.

## Saves

Saves from v0.28 and later load in the current release. A save from before
v0.44 starts with no Esper progress. A save made in a newer release is not
meant to load in an older one.

The release zip has a `saves` folder: saves at points through the story,
from Narshe to the World of Ruin, in story order. Each is in slot 3. To use
one:

1. Back up your own save file.
2. Copy the `.srm` next to the patched ROM and name it after the ROM:
   `OT6.srm` for the Android patcher, or `Final Fantasy III (USA).srm` when an
   emulator applies the patch.
3. Start the game, choose Continue, and load slot 3.
