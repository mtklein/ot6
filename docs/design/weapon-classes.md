# Weapon classes & the break spread

Scope: World of Balance. Locked ✦.

## Six physical classes ✦

Each class is a weapon family the player can see in a hand. 6 physical + 8
elemental = 14 weakness axes (Octopath has 12). Through v0.50 there were
four (slash, pierce, bludgeon, special ¤); "How the four became six" below
says what moved. `ot6_class.asm` is the truth: `Ot6WeapClassTbl` gives every
weapon one class, `Ot6SkillClassTbl` every class-bearing skill.

| Class | Weapons | Skills that carry it | Wielders | Icon |
|---|---|---|---|---|
| **Sword** | swords | Edgar's Chain Saw | Terra, Celes, Edgar; alt for Locke and Cyan (the Scimitar) | $d9 |
| **Dagger** | daggers, thrown stars and edges, Hawk Eye, darts | Shadow's skeans; Locke's Trickshot and Dismantle | Locke, Shadow; alt for Terra, Celes, Edgar, Setzer, Mog, Strago, Relm | $d8 |
| **Spear** | spears and lances | Edgar's Drill, Air Anchor and AutoCrossbow; TekMissile | Edgar, Mog | $da |
| **Katana** | katanas, ninja blades | every SwdTech that cuts (Dispatch, Slash, Quadra Slam, Stunner, Cleave) | Cyan, Shadow | $db |
| **Fist** | bare hands, claws, the Flail, Morning Star and Bone Club | Sabin's Pummel, Suplex and Bum Rush; Umaro's Charge and Throw | Sabin, Gau, Umaro; alt for Terra, Celes, Strago, Relm (the Flail, the Morning Star) | $e1 |
| **Arcane** | rods, brushes, cards, dice, boomerangs | Setzer's Coin Toss | Strago, Relm, Setzer; alt for Locke (boomerangs) | $df |

- **The weapon sets Fight's class; abilities carry their own ✦.**
  Edgar with a spear in hand cuts as a Sword with the Chain Saw, and
  Pummel is Fist whatever Sabin wears. Ability class bytes are
  immutable; only the basic attack reads the equipped weapon. Locke's
  Mug is a Fight that steals, so it takes the class of the weapon he
  holds. (Claws and fists are one class now, so claws no longer buy the
  monk a second one; the Chain Saw still buys Edgar Sword.)
- **A body's look narrows the guess to a pair, and the probe picks.** A
  thing that is cut takes Sword or Katana, a thing that is stuck Dagger
  or Spear, a thing that is struck Fist or Arcane; a spirit or a magical
  body takes Arcane or Dagger.
- **Null-break stays, as a property rather than a class ✦**: some
  attacks deal damage and chip nothing, the physical counterpart of
  non-elemental magic. It is a per-weapon/per-skill flag. The Fixed
  Dice roll high numbers and reveal nothing, while the ordinary dice
  chip Arcane-weak enemies.
- Cyan is the Katana *specialist* (Quadra Slam ×4 is the best Katana
  chip in the game). The only other Katana key is Shadow's ninja blade,
  so a party without either breaks a Katana-weak body by its other
  weakness. Class-coverage balance is re-asked every milestone ✦.
- The 8 elements stay untouched ✦.
- **Row jank preserved ✦**: weapons that ignore row in vanilla
  (boomerangs, dice, cards, darts…) keep ignoring row. The new
  system does not change it.

## How the four became six

Owner, after playing v0.49 to Zozo (2026-11-23, #566): "breaking with
weapons has been pretty easy because there are few types". Under four
classes a party holding slash and pierce weapon-keyed 86% of the species
the game deals; any three classes keyed 91-96%.

What moved between families: claws were slash and are Fist; ninja blades
were pierce and are Katana; rods and boomerangs were bludgeon and are
Arcane; flails and clubs stay with fists; cards, dice and brushes were
special and are Arcane.

Every monster keeps its *number* of weapon weaknesses. Each old weakness
became one of two:

| Was | Is one of |
|---|---|
| slash | Sword or Katana |
| pierce | Dagger or Spear |
| bludgeon | Fist or Arcane |
| special ¤ | Arcane or Dagger |

Which one, in order (`tools/proto_six/split.py`, whose `--report-only`
prints every species' old row, new row and reason):

1. where a break story or the row's own comment names the member whose
   weapon or skill is the key, that member's new class;
2. else the split that leaves the party the route met the species with
   holding a key;
3. else an even balance across the six.

Of the 349 species the game deals and gauges, 99 are weak to Sword, 111
to Dagger, 104 to Fist, 113 to Arcane, 98 to Katana and 109 to Spear.
One class keys 28-32% of them, two classes 51-62%, three 69-81%, four
84-94%, five 95-98% (`tools/proto_six/party_share.py`).

A save from an older release keeps its revealed weaknesses, each shown
as whichever of the two new classes that monster now has
([save-layout.md](save-layout.md)).

## The item icon shows the break class

Each weapon's item icon is its break class icon, on every surface
that renders item names: item menu, shops, equip, battle lists. The
icon byte is the first byte of the item name, so a single data table
covers every surface, and the item menu's type column reads
DAGGER / SWORD / SPEAR / KATANA / ARCANE / FIST from the same byte.
Classless weapons (Heal Rod) show a small dash. Armor, relic, tool, and
consumable icons are unchanged from vanilla.

The HUD draws the same six glyphs for a revealed weakness, 8×8 and
white, side by side, so each blade is on its own axis
(`tools/proto_six/font.py`):

| Class | Cell | Glyph |
|---|---|---|
| Sword | $d9 | vanilla's sword: a broad blade up and to the left |
| Katana | $db | vanilla's katana, mirrored: a thin blade up and to the right |
| Spear | $da | redrawn: upright, a leaf head on a thin shaft |
| Dagger | $d8 | redrawn: level, the point to the left |
| Fist | $e1 | vanilla's claw |
| Arcane | $df | vanilla's sparkle |

The first hit on a hidden weakness names it: "Weak against swords",
"daggers", "fists", "arcane", "katanas" or "spears".

Rule: if more visual distinction between weapon types is wanted, add
another weapon class rather than a second icon set with no mechanical
meaning. (v0.51 did: the four icons became six classes.)

## How weaknesses spread (the coverage rule)

**Rule ✦: at every stretch of the WoB, the *story's actual party*
must be able to chip every non-boss encounter.** The three-way
scenario split is the stress test:

| Stretch | Physical classes on hand | Elements | Enemies there lean |
|---|---|---|---|
| Narshe intro | (magitek: TekMissile is Spear) | fire, bolt | beam-weak, tutorial-obvious |
| Figaro → Kolts | **Dagger, Dagger, Spear** going up (a Sword if Edgar buys the Mithril Blade); Fist only after Sabin | **fire, poison** (+cure) | authored: poison is the second key ✦ |
| **Locke scenario** | Dagger only | none | *everything* in occupied South Figaro takes a Dagger ✦ |
| **Sabin scenario** | Fist (Sabin, Gau), Katana (Cyan; Shadow's blade), Dagger (Shadow's throws) | holy, fire, wind | Phantom Train: holy + Katana featured |
| **Terra/Banon scenario** | Sword, Spear, Arcane (Banon's rod) | fire, ice, bolt, poison | mage-check spread |
| Zozo | reunited | most | first dungeon needing a per-encounter read |
| Opera → Vector | + Arcane (Setzer) | — | fliers that take a point + the first Arcane-weak enemies |
| Magitek factory | all | all | armored spread: Fist and Dagger featured |
| Sealed Gate / Thamasa | + Strago/Relm (Arcane) | + lores | spirits: elements first, Arcane beside them |
| Floating Continent | final WoB party | all | final check: every class and element locks once |

- **Elemental weaknesses**: vanilla's bits stay wherever they exist ✦;
  add only where a stretch has a hole.
- **Weapon weaknesses** (the new byte): assigned by body type, so
  a player can guess and then confirm by probing.
- Shields ✦: trash 1–3, minibosses 4–6, bosses 6–12 with telegraphs.

What a party holds, stage by stage (`tools/proto_six/party_share.py`).
"Signature" is each member's own weapon family and class-bearing skills,
with nobody re-armed for a key; "widest" adds every class of every weapon
the members can equip. The percentages are the share of the 349 gauged
species the party can weapon-key. Free picks are filled with the members
named.

| Stage and party | Signature classes | keys | widest |
|---|---|---|---|
| Whelk (Terra in Magitek armor) | Spear | 31% | 31% |
| Marshal (Locke, Mog) | Dagger, Spear | 62% | 88% |
| Mt. Kolts to Vargas (Terra, Locke, Edgar) | Sword, Dagger, Spear | 74% | 98% |
| Lete River, Ultros 1 (+ Sabin, Banon) | Sword, Dagger, Spear, Fist, Arcane | 98% | 98% |
| Locke's scenario (Locke alone) | Dagger | 32% | 71% |
| TunnelArmr (Locke, Celes) | Sword, Dagger | 52% | 86% |
| Imperial camp (Sabin, Shadow) | Dagger, Katana, Fist | 70% | 70% |
| Phantom Train (Sabin, Cyan, Shadow) | Dagger, Katana, Fist | 70% | 87% |
| Baren Falls, the trench, the Veldt (Sabin, Cyan, Gau) | Katana, Fist | 52% | 76% |
| Terra's scenario (Terra, Edgar, Banon) | Sword, Spear, Arcane | 73% | 98% |
| Zozo (Locke, Celes, Edgar, Sabin) | Sword, Dagger, Spear, Fist | 87% | 98% |
| Zozo (Locke, Celes, Cyan, Gau) | Sword, Dagger, Katana, Fist | 87% | 95% |
| Opera, Ultros 2 (Locke, Edgar, Sabin, Cyan) | Sword, Dagger, Spear, Katana, Fist | 95% | 99% |
| Magitek factory (Locke, Celes, Edgar, Sabin) | Sword, Dagger, Spear, Fist | 87% | 98% |
| Magitek factory (Locke, Celes, Setzer, Cyan) | Sword, Dagger, Katana, Arcane | 85% | 95% |
| Sealed Gate, Ultros 3 (Terra, Locke, Edgar, Sabin) | Sword, Dagger, Spear, Fist | 87% | 98% |
| Thamasa, FlameEater (Terra, Locke, Strago) | Sword, Dagger, Arcane | 71% | 86% |
| Airship deck (Terra, Edgar, Sabin) | Sword, Spear, Fist | 71% | 87% |
| Floating Continent (Terra, Edgar, Sabin, Shadow) | Sword, Dagger, Spear, Katana, Fist | 95% | 95% |
| Floating Continent (Terra, Setzer, Relm, Shadow) | Sword, Dagger, Katana, Arcane | 85% | 95% |
| WoR: the island to Tzen (Celes) | Sword | 28% | 71% |
| WoR: Tzen to Edgar (Celes, Sabin) | Sword, Fist | 54% | 71% |
| WoR: the Falcon (Celes, Sabin, Edgar, Setzer) | Sword, Spear, Fist, Arcane | 88% | 98% |
| WoR: Mt. Zozo (Celes, Sabin, Edgar, Cyan) | Sword, Spear, Katana, Fist | 84% | 95% |
| WoR: Narshe (Terra, Celes, Cyan, Mog) | Sword, Spear, Katana | 71% | 95% |
| WoR: Thamasa arc (Terra, Celes, Relm, Strago) | Sword, Arcane | 54% | 86% |
| WoR: Phoenix Cave party 1 (Terra, Strago, Sabin, Cyan) | Sword, Katana, Fist, Arcane | 91% | 95% |
| WoR: Phoenix Cave party 2 (Celes, Relm, Mog, Umaro) | Sword, Spear, Fist, Arcane | 88% | 98% |
| WoR: Veldt cave (Celes, Terra, Relm, Gau) | Sword, Fist, Arcane | 75% | 86% |
| WoR: Ebot's Rock, the Zone Eater (Terra, Celes, Strago, Relm) | Sword, Arcane | 54% | 86% |
| WoR: Ancient Castle (Terra, Celes, Relm, Cyan) | Sword, Katana, Arcane | 76% | 95% |

The share is of every species in the game, not of the species the stage
deals: the rows there were split toward the party that meets them (rule 2
above), so a stage's own bodies key more often than its line says.

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
Trickshot is Dagger with a sword in Locke's hand, the Chain Saw is
Sword from a spear machinist, Suplex is Fist bare-handed or clawed.
Shadow's skeans (Fire Skean, Water Edge, Bolt Edge) resolve as their
spells and carry Dagger through them (#383, kits.md "Shadow"), so a
thrown edge chips its class and its element.
(The per-skill class/element byte provides this for free.)

## Multiple weapon classes per character

Base rule: one signature class per character. A character reaches
another class three ways, none needing battle code:

1. **Skills** (above): a kit can reach outside its weapon class.
   Edgar's tools give him Spear and Sword at once.
2. **Other weapons**: the equip lists are vanilla's, so most characters
   can hold a second family (the table below).
3. **Magicite weapon permits**: not built. Kept spare ✦: if six classes
   play too hard, a worn esper could permit one extra weapon type while
   it is worn, rented like its spells, never a kept rank (owner,
   2026-11-23, #566).

Every class each character can equip into, and the skills that bring
one. The first class listed is the signature.

| Character | Signature | Can also equip | Skills with a class of their own |
|---|---|---|---|
| Terra | **Sword** (every sword) | Dagger (Dirk, MithrilKnife, Man Eater, Graedus); Fist (Flail, Morning Star) | in Magitek armor, TekMissile: Spear |
| Locke | **Dagger** (every dagger; Hawk Eye) | Sword (MithrilBlade, Flame Sabre, Blizzard, ThunderBlade, Drainer, Falchion, Soul Sabre, Excalibur, Illumina, Ragnarok, Atma Weapon); Arcane (Boomerang, Full Moon, Rising Sun, Sniper, Wing Edge) | Trickshot, Dismantle: Dagger whatever he holds. Mug swings his weapon |
| Edgar | **Spear** (every spear) | Sword (every sword); Dagger (Dirk, MithrilKnife, Man Eater, Graedus) | AutoCrossbow, Drill, Air Anchor: Spear. Chain Saw: Sword |
| Sabin | **Fist** (bare hands, every claw) | — | Pummel, Suplex, Bum Rush: Fist |
| Cyan | **Katana** (every katana) | Sword (the Scimitar) | Dispatch, Slash, Quadra Slam, Stunner, Cleave: Katana |
| Shadow | **Katana** (the ninja blades) | Dagger (Dirk, MithrilKnife, ThiefKnife, Assassin, Man Eater, SwordBreaker, Graedus) | Throw: the three stars Dagger, the three skeans Dagger and their element |
| Celes | **Sword** (every sword) | Dagger (Dirk, MithrilKnife, Man Eater, Graedus); Fist (Flail, Morning Star) | — |
| Setzer | **Arcane** (Cards, Trump, Dice; the Fixed Dice chip nothing) | Dagger (Darts, Doom Darts, Dirk, MithrilKnife, Man Eater, Graedus) | Coin Toss: Arcane. Hired Help: a class the target is weak to |
| Strago | **Arcane** (every rod but the Heal Rod, which has no class) | Dagger (Dirk, MithrilKnife, Air Lancet, Man Eater, SwordBreaker, Graedus); Fist (Flail, Morning Star) | — |
| Relm | **Arcane** (every brush; the rods, as Strago) | Dagger and Fist, as Strago | — |
| Mog | **Spear** (every spear) | Dagger (Dirk, MithrilKnife, Graedus) | — |
| Gau | **Fist** (bare hands; he holds no weapon) | — | — |
| Umaro | **Fist** (bare hands, the Bone Club) | — | Charge, Throw: Fist |
| Gogo | **Arcane** (the rods, as Strago) | Dagger and Fist, as Strago | the kit he mimics |

Anyone with an empty hand punches as Fist. The Imp Halberd is a Spear on
every equip list but Umaro's. With the Genji Glove each hand chips its
own weapon's class.

Arcane's icon is the vanilla sparkle glyph at $df; every consumer keys on
the code, so custom art can replace it in place without touching anything
else.
