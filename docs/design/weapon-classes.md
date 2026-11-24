# Weapon classes & the break spread

Scope: World of Balance. Locked ✦.

## Six physical classes ✦

Six classes, after Octopath's six (sword, spear, dagger, axe, bow, staff;
owner, 2026-11-23: "katana is axe"; Ranged "gathers together all the ranged
physicals"; "rods and fists could group", as Blunt). 6 physical + 8
elemental = 14 weakness axes (Octopath has 12). Through v0.50 there were
four (slash, pierce, bludgeon, special ¤); "How the four became six" below
says what moved. `tools/six_classes/classes.py` is the grouping as data, and
`ot6_class.asm`'s two tables are written from it: `Ot6WeapClassTbl` gives
every weapon one class, `Ot6SkillClassTbl` every class-bearing skill.

| Class | Weapons | Skills that carry it | Who really holds it | Icon |
|---|---|---|---|---|
| **Sword** | the straight swords (every sword but the five curved ones) | Edgar's Chain Saw | Terra, Celes, Leo (Edgar and Locke when they carry one) | $d9 |
| **Dagger** | daggers, ninja blades; the claws (Mithril Claw, Poison Claw, Dragon Claw, Tiger Fangs); Gau's fangs (his empty hand, and his Fight while he rages) | Locke's Trickshot and Dismantle | Locke, Shadow, Gau, Sabin (with claws) | $d8 |
| **Spear** | spears and lances | Edgar's Drill | Edgar, Mog | $da |
| **Katana** | katanas; the curved swords (RegalCutlass, Flame Sabre, Falchion, Soul Sabre, Scimitar) | every SwdTech that cuts (Dispatch, Slash, Quadra Slam, Stunner, Cleave) | Cyan, Terra and Celes (with a curved sword) | $db |
| **Blunt** | bare fists; the knuckles (MetalKnuckle, Kaiser, Fire Knuckle); rods, brushes; the Flail, Morning Star and Bone Club | Sabin's Pummel, Suplex and Bum Rush; Umaro's Charge and Throw | Sabin, Umaro, Strago, Relm, Banon | $dc |
| **Ranged** | thrown stars; Darts, Doom Darts; Cards, Trump, Dice; the boomerangs and rings (Boomerang, Full Moon, Rising Sun, Hawk Eye, Sniper, Wing Edge) | Edgar's AutoCrossbow and Air Anchor; TekMissile; Shadow's skeans; Setzer's Coin Toss | Setzer, Shadow (Throw), Edgar (AutoCrossbow) | $de |

Spear is thin on purpose: Edgar and Mog. A plan on another branch (#567)
would let the Dragoon Boots' wearer equip a spear; it is not built.

- **The weapon sets Fight's class; abilities carry their own ✦.**
  Sabin with a claw equipped strikes as Dagger when he Fights, and Pummel
  is Blunt whatever he wears, so claws are how the monk holds a second
  class (owner: he "has been very versatile for having slashing and
  pummel"; 2026-11-24: "claws just feels like daggers"). Edgar's Chain
  Saw is Sword with a spear in his hand.
  Ability class bytes are immutable; only the basic attack reads the
  equipped weapon. Locke's Mug is a Fight that steals, so it takes the
  class of the weapon he holds.
- **A holder is who really wields a class.** Owner, 2026-11-23: "we
  don't want just one particular character to be required to get
  through fights", and "it's pretty rare anyone will want to be
  wielding a dagger". So a class's holders are the characters whose
  signature weapon or command carries it (the column above), not
  everyone who could equip into it, and at every story stage a
  species' weapon keys must be really held by two or more characters
  the player can field there, or by one the story forces into the
  party (`split.py`'s holder step, `stages.py`).
- **Null-break stays, as a property rather than a class ✦**: some
  attacks deal damage and chip nothing, the physical counterpart of
  non-elemental magic. It is a per-weapon/per-skill flag. The Fixed
  Dice roll high numbers and reveal nothing, while the ordinary dice
  chip Ranged-weak enemies.
- Cyan is the Katana *specialist* (Quadra Slam ×4 is the best Katana
  chip in the game), but he is not the only Katana key: Terra and Celes
  hold it by choosing a curved sword, at the same power as the straight
  sword of its tier (RegalCutlass 54, Rune Edge 55; Flame Sabre 108,
  Blizzard and ThunderBlade 108). The first is the RegalCutlass in South
  Figaro's weapon shop, before Mt. Kolts. Class-coverage balance is
  re-asked every milestone ✦.
- The 8 elements stay untouched ✦.
- **Row jank preserved ✦**: weapons that ignore row in vanilla
  (boomerangs, dice, cards, darts…) keep ignoring row. The new
  system does not change it.

Where a weapon sits badly in its class (`classes.py` says each once):

- **Chain Saw**: a saw is no sword; Sword is the nearest edge (not a
  katana's cut, not a blow), and it is what "buys Edgar slashing" meant.
- **Air Anchor**: it fires a harpoon: a spear by shape, Ranged by how it
  is delivered (as the AutoCrossbow's bolts).
- **The skeans**: the three damaging skeans are thrown, so Ranged with
  the stars, though they resolve as spells and their elements do most of
  their chipping.
- **Umaro's Throw** hurls an ally: literally a thrown thing, kept Blunt
  as his Charge is (a body's blow).
- **Trickshot** throws a coin but carries Locke's own class whatever he
  holds: Dagger.
- **Brushes**: a brush is no bludgeon; it goes with the rods, the other
  caster's weapon ("rods and fists could group").
- **Claws**: the four claws are Dagger (owner, 2026-11-24: "claws just
  feels like daggers"); the three knuckles strike, so Blunt.
- **Curved swords**: the RegalCutlass, Flame Sabre, Falchion, Soul Sabre
  and Scimitar are Katana (owner, 2026-11-24), every other sword Sword. A
  cutlass is no katana, but Katana is the nearest blade class, and vanilla
  already lets Cyan equip the Scimitar.
- **Hawk Eye and the returning rings** are thrown: Ranged, though vanilla
  drew them with the flails.
- **Dice and cards** are Setzer's thrown things: Ranged (the Fixed Dice
  stay null-break).
- **Gau's fangs**: his bare hand and his raging Fight are Dagger (owner:
  "fangs could be daggers maybe? they're more piercing than blunt");
  everyone else's empty hand is a fist, Blunt.

## How the four became six

Owner, after playing v0.49 to Zozo (2026-11-23, #566): "breaking with
weapons has been pretty easy because there are few types". Under four
classes a party holding slash and pierce weapon-keyed 86% of the species
the game deals; any three classes keyed 91-96%.

Outside the opening's hand-authored rows ([opening.md](opening.md), 22 of
which depart), every monster keeps its *number* of weapon weaknesses (the two rows any
weapon broke, the Intangir's and the Speck's, take all six). Each old
weakness became one class its own weapons went to:

| Was | Is one of |
|---|---|
| slash | Sword or Katana |
| pierce | Dagger, Spear or Ranged |
| bludgeon | Blunt or Ranged |
| special ¤ | Ranged or Blunt |

Which one, in order (`tools/six_classes/split.py`, whose `--report-only`
prints every species' old row, new row and reason):

1. pinned: the opening's rows are authored by hand, and where a World
   of Balance break story names the member whose weapon or skill is the
   key, the weakness becomes the class that weapon carries;
2. Ultros's four records share one row;
3. the holder rule above: a split is refused where nobody fieldable at
   the stage really holds one of the row's classes, or only one
   character the story does not force in;
4. the route's own hands: of the splits left, the one under which the
   parties that met the species (a baseline play's record of what each
   held) keep a key in hand;
5. then what the four-class row's own comment suggests;
6. then an even balance across the six.

Of the 349 species the game deals and gauges, 104 are weak to Sword, 107
to Dagger, 76 to Spear, 99 to Katana, 144 to Blunt and 123 to Ranged.
One class keys 22-41% of them, two classes 45-67%, three 65-84%, four
80-93%, five 93-99% (`tools/six_classes/party_share.py`).

A save from an older release keeps its revealed weaknesses, each shown as
the class that weakness became for that monster
([save-layout.md](save-layout.md)).

## The item icon shows the break class

Each weapon's item icon is its break class icon, on every surface
that renders item names: item menu, shops, equip, battle lists. The
icon byte is the first byte of the item name, so a single data table
covers every surface, and the item menu's type column reads
DAGGER / SWORD / SPEAR / KATANA / BLUNT / RANGED from the same byte.
Classless weapons (Heal Rod) show a small dash. Armor, relic, tool, and
consumable icons are unchanged from vanilla.

The HUD draws the same six glyphs for a revealed weakness, 8×8 and
white, side by side, so each blade is on its own axis
(`tools/six_classes/font.py`):

| Class | Cell | Glyph |
|---|---|---|
| Sword | $d9 | vanilla's sword: a broad blade up and to the left |
| Katana | $db | vanilla's katana, mirrored: a thin blade up and to the right |
| Spear | $da | redrawn: upright, a leaf head on a thin shaft |
| Dagger | $d8 | redrawn: level, the point to the left |
| Blunt | $dc | redrawn: a mallet, a broad head on a short shaft |
| Ranged | $de | vanilla's thrown star |

The first hit on a hidden weakness names it: "Weak against swords",
"daggers", "spears", "katanas", "blunt" or "ranged".

The line under a monster has four weakness cells, elements first, then
classes in the order Sword, Dagger, Blunt, Ranged, Katana, Spear. A body
with more weaknesses than cells has them all the same. A body every class
breaks (the Intangir, the Speck) shows one cell for the six: a '?' until
any weapon chips it, then the any-weapon mark, vanilla's sparkle at $df
(`OT6_ANYWEAPON`; no class wears it).

Rule: if more visual distinction between weapon types is wanted, add
another weapon class rather than a second icon set with no mechanical
meaning. (v0.51 did: the four icons became six classes.)

## How weaknesses spread (the coverage rule)

**Rule ✦: at every stretch of the WoB, the *story's actual party*
must be able to chip every non-boss encounter.** The three-way
scenario split is the stress test:

| Stretch | Physical classes on hand | Elements | Enemies there lean |
|---|---|---|---|
| Narshe intro | (magitek: TekMissile is Ranged) | fire, bolt | beam-weak, tutorial-obvious |
| Figaro → Kolts | **Dagger, Dagger, Spear** going up, Ranged with Edgar's AutoCrossbow (a Sword if he buys the Mithril Blade); Blunt only after Sabin | **fire, poison** (+cure) | authored: poison is the second key ✦ |
| **Locke scenario** | Dagger only | none | *everything* in occupied South Figaro takes a Dagger ✦ |
| **Sabin scenario** | Blunt, and Dagger with a claw from Mobliz (Sabin), Katana (Cyan), Dagger and Ranged (Shadow), Dagger (Gau) | holy, fire, wind | Phantom Train: holy + Katana featured |
| **Terra/Banon scenario** | Sword, Spear and Ranged (Edgar), Blunt (Banon's rod) | fire, ice, bolt, poison | mage-check spread |
| Zozo | reunited | most | first dungeon needing a per-encounter read |
| Opera → Vector | + Setzer (Ranged: cards, dice, darts) | — | fliers that take a point + enemies weak to what is thrown |
| Magitek factory | all | all | armored spread: Blunt and Dagger featured |
| Sealed Gate / Thamasa | + Strago/Relm (Blunt: rods, brushes) | + lores | spirits: elements first |
| Floating Continent | final WoB party | all | final check: every class and element locks once |

- **Elemental weaknesses**: vanilla's bits stay wherever they exist ✦;
  add only where a stretch has a hole.
- **Weapon weaknesses** (the new byte): assigned by body type, so
  a player can guess and then confirm by probing.
- Shields ✦: trash 1–3, minibosses 4–6, bosses 6–12 with telegraphs.

What a party holds, stage by stage (`tools/six_classes/party_share.py`; the
stages are `stages.py`'s, named by the first leg of the line). "Really
held" is each member's signature weapon and commands (`classes.py`), with
nobody re-armed for a key; "widest" adds every class of every weapon the
members can equip; "four classes" is what the same signature kits keyed
through v0.50. The percentages are the share of the gauged species the
party can weapon-key. Where the player can field more than four, the range
is over the parties of four.

| Stage (its first leg) | The player can field | four classes | six: really held | six: widest |
|---|---|---|---|---|
| `battle_entry`, in Magitek armor | Terra | 58% | 35% | 35% |
| `narshe_streets` | Terra | 56% | 55% | 87% |
| `moogle_cleared` | Kamog, Kuku, Kumama, Kupan, Kupek, Kupop, Kurin, Kuru, Kushu, Kutan, Locke, Mog | 0-58% (mean 33%) | 0-51% (mean 17%) | 0-93% (mean 42%) |
| `worldmap_narshe` | Locke, Terra | 86% | 71% | 99% |
| `figaro_intro` | Edgar, Locke, Terra | 86% | 93% | 99% |
| `vargas_entry` | Edgar, Locke, Sabin, Terra | 96% | 99% | 99% |
| `scenario_hub` | Banon, Edgar, Sabin, Terra | 96% | 99% | 99% |
| `locke_scenario` | Locke | 58% | 31% | 89% |
| `sfigaro_escape` | Celes, Locke | 86% | 71% | 99% |
| `sabin_world` | Sabin, Shadow | 96% | 84% | 84% |
| `cyan_defence` | Cyan, Sabin, Shadow | 96% | 92% | 92% |
| `camp_escaped`, in Magitek armor | Cyan, Sabin, Shadow | 0% | 0% | 0% |
| `forest_done` | Cyan, Sabin, Shadow | 96% | 92% | 92% |
| `falls_done` | Cyan, Sabin | 85% | 76% | 76% |
| `gau_joined` | Cyan, Gau, Sabin | 85% | 76% | 76% |
| `rapids_start` | Banon, Edgar, Terra | 96% | 95% | 99% |
| `narshe_battle` | Celes, Cyan, Edgar, Gau, Locke, Sabin, Terra | 85-96% (mean 93%) | 71-99% (mean 89%) | 87-99% (mean 97%) |
| `figaro_submerged` | Celes, Cyan, Edgar, Gau, Locke, Sabin | 85-96% (mean 95%) | 71-99% (mean 91%) | 87-99% (mean 98%) |
| `ultros2_entry` | Cyan, Edgar, Gau, Locke, Sabin | 96-96% (mean 96%) | 76-97% (mean 90%) | 93-99% (mean 98%) |
| `vector_entry` | Celes, Cyan, Edgar, Gau, Locke, Sabin, Setzer | 85-99% (mean 97%) | 71-99% (mean 90%) | 87-99% (mean 98%) |
| `vector_sneak` | Celes, Cyan, Edgar, Gau, Locke, Sabin, Setzer | 85-99% (mean 97%) | 71-99% (mean 90%) | 87-99% (mean 98%) |
| `minecart_entry` | Cyan, Edgar, Gau, Locke, Sabin, Setzer | 94-99% (mean 98%) | 74-97% (mean 88%) | 89-99% (mean 96%) |
| `narshe_mission` | Cyan, Edgar, Gau, Locke, Sabin, Setzer | 94-99% (mean 98%) | 74-97% (mean 88%) | 89-99% (mean 96%) |
| `wob_airship_hunt` | Cyan, Edgar, Gau, Locke, Mog, Sabin, Setzer | 74-99% (mean 96%) | 64-97% (mean 86%) | 85-99% (mean 95%) |
| `gate_cave_save` | Celes, Cyan, Edgar, Gau, Locke, Mog, Sabin, Setzer, Terra | 74-99% (mean 95%) | 64-99% (mean 88%) | 85-99% (mean 97%) |
| `vector_crash` | Cyan, Edgar, Gau, Locke, Mog, Sabin, Setzer, Terra | 74-99% (mean 95%) | 64-99% (mean 88%) | 85-99% (mean 97%) |
| `crescent_landing` | Locke, Terra | 86% | 71% | 99% |
| `thamasa_night` | Locke, Shadow, Terra | 86% | 89% | 99% |
| `fire_out` | Locke, Strago, Terra | 96% | 87% | 99% |
| `wob_esper_mtn_hunt` | Locke, Relm, Strago, Terra | 99% | 87% | 99% |
| `thamasa_done` | Celes, Cyan, Edgar, Gau, Leo, Locke, Mog, Relm, Sabin, Setzer, Strago, Terra | 56-99% (mean 94%) | 55-99% (mean 88%) | 62-99% (mean 96%) |
| `fc_landing` | Celes, Cyan, Edgar, Gau, Locke, Mog, Relm, Sabin, Setzer, Shadow, Strago, Terra | 58-99% (mean 94%) | 62-99% (mean 90%) | 62-99% (mean 96%) |
| `wor_island` | Celes | 56% | 55% | 87% |
| `wor_sabin` | Celes, Sabin | 85% | 87% | 87% |
| `wor_edgar` | Celes, Edgar, Sabin | 96% | 99% | 99% |
| `wor_tomb` | Celes, Edgar, Sabin, Setzer | 99% | 99% | 99% |
| `wor_terra` | Celes, Edgar, Sabin, Setzer | 99% | 99% | 99% |

The share is of every species in the game, not of the species the stage
deals: the rows there were split toward the party that meets them (steps 3
and 4 above), so a stage's own bodies key more often than its line says.

## Weapons as chip carriers

A weapon chips **its class, plus its element if it has one** ✦, so a
Flame Knife is a Dagger probe and a fire probe in one swing. In
vanilla, elemental weapons rotate in and out on raw stats; here every
chest and shop upgrade also changes what the party can chip. Multi-hit
actions chip per hit ✦ (Quadra Slam, boosted Fight).

## The driver reads the class cell ✦

The tactical fight driver plays the class the way a person reads the
HUD: a plain boost-Fight is aimed at the living monster its hand breaks
best, not the engine's default cursor. `Driver:chipAim`
(`tools/tests/lib/ot6.lua`) scores each present slot by the break chips
the hit would land — `fightChips`→`hitChips` over the *revealed* cells
only (`RV_CLASS`/`RV_ELEM`, `$3EA5`/`$3E91`, the same bytes the HUD
draws; a Genji Glove pair counts twice) — and hands the best slot to the
plan, which steers the cursor there. So a Dagger hand takes the
Dagger-keyed monster and a Sword hand the Sword-keyed one, and break is
the rhythm of every random, not only the bosses. Levers, not laws
(`no-nevers`): it reads only what the fight has shown, defers to any
authored or multi-part kill order (that targeting still wins,
byte-identical), and leaves the default cursor where class is irrelevant
— a lone monster, or one revealed key shared by the whole formation.
`opts.aim=false` turns it off. (#161; measured in `battle_classtarget`.)

## Skills carry their own class ✦

The chip check reads the *action's* class byte, never the wielder's:
Trickshot is Dagger with a sword in Locke's hand, the AutoCrossbow is
Ranged from a spear machinist, Suplex is Blunt with claws on.
Shadow's skeans (Fire Skean, Water Edge, Bolt Edge) resolve as their
spells and carry Ranged through them (#383, kits.md "Shadow"), so a
thrown edge chips its class and its element.
(The per-skill class/element byte provides this for free.)

## Multiple weapon classes per character

Base rule: one signature class per character. A character reaches
another class three ways, none needing battle code:

1. **Skills** (above): a kit can reach outside its weapon class.
   Edgar's tools give him Ranged (AutoCrossbow, Air Anchor), Spear
   (Drill) and Sword (Chain Saw); Shadow's Throw is Ranged beside his
   Dagger; Sabin's Blitzes are Blunt beside a claw's Dagger.
2. **Other weapons**: the equip lists are vanilla's, so most characters
   can hold a second family (the table below). The holder rule does not
   count these: they are what a player who re-arms for a key can reach.
3. **Magicite weapon permits**: not built. Kept spare ✦: if six classes
   play too hard, a worn esper could permit one extra weapon type while
   it is worn, rented like its spells, never a kept rank (owner,
   2026-11-23, #566).

Every class each character can equip into, and the skills that bring
one. The first column is the class the character really holds.

| Character | Signature | Can also equip | Skills with a class of their own |
|---|---|---|---|
| Terra | **Sword** (every straight sword) and **Katana** (the curved swords: RegalCutlass, Flame Sabre, Falchion, Soul Sabre, Scimitar) | Dagger (Dirk, MithrilKnife, Man Eater, Graedus); Blunt (Flail, Morning Star) | in Magitek armor, TekMissile: Ranged |
| Locke | **Dagger** (every dagger) | Sword (MithrilBlade, Blizzard, ThunderBlade, Drainer, Excalibur, Illumina, Ragnarok, Atma Weapon); Katana (Flame Sabre, Falchion, Soul Sabre); Ranged (Boomerang, Full Moon, Rising Sun, Hawk Eye, Sniper, Wing Edge) | Trickshot, Dismantle: Dagger whatever he holds. Mug swings his weapon |
| Edgar | **Spear** (every spear) | Sword (every straight sword); Katana (the five curved swords); Dagger (Dirk, MithrilKnife, Man Eater, Graedus) | AutoCrossbow, Air Anchor: Ranged. Drill: Spear. Chain Saw: Sword |
| Sabin | **Blunt** (bare fists; MetalKnuckle, Kaiser, Fire Knuckle) and **Dagger** (Mithril Claw, Poison Claw, Dragon Claw, Tiger Fangs) | — | Pummel, Suplex, Bum Rush: Blunt |
| Cyan | **Katana** (every katana, and the Scimitar) | — | Dispatch, Slash, Quadra Slam, Stunner, Cleave: Katana |
| Shadow | **Dagger** (the ninja blades; Dirk, MithrilKnife, ThiefKnife, Assassin, Man Eater, SwordBreaker, Graedus) | — | Throw: the three stars Ranged, the three skeans Ranged and their element; a thrown weapon keeps its class |
| Celes | **Sword** (every straight sword) and **Katana** (the five curved swords) | Dagger (Dirk, MithrilKnife, Man Eater, Graedus); Blunt (Flail, Morning Star) | — |
| Setzer | **Ranged** (Cards, Trump, Dice, Darts, Doom Darts; the Fixed Dice chip nothing) | Dagger (Dirk, MithrilKnife, Man Eater, Graedus) | Coin Toss: Ranged. Hired Help: a class the target is weak to |
| Strago | **Blunt** (every rod but the Heal Rod, which has no class; Flail, Morning Star) | Dagger (Dirk, MithrilKnife, Air Lancet, Man Eater, SwordBreaker, Graedus) | — |
| Relm | **Blunt** (every brush; the rods, Flail and Morning Star, as Strago) | Dagger, as Strago | — |
| Mog | **Spear** (every spear) | Dagger (Dirk, MithrilKnife, Graedus) | — |
| Gau | **Dagger** (his fangs: his empty hand, and his Fight while he rages) | — | — |
| Umaro | **Blunt** (bare fists, the Bone Club) | — | Charge, Throw: Blunt |
| Gogo | **Blunt** (the rods, Flail and Morning Star, as Strago) | Dagger, as Strago | the kit he mimics |

An empty hand is a fist, Blunt (Gau's is his fangs, Dagger). The Imp
Halberd is a Spear on every equip list but Umaro's. With the Genji Glove
each hand chips its own weapon's class.
