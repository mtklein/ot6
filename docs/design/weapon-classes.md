# Weapon classes & the break spread — design dive v1 (2026-07-16)

Scope: World of Balance. Status: **proposal for review** — locked ✦.

## Six classes, not eight

DESIGN.md floated eight; six is better. Every class needs enough
wielders and enough weak enemies that "weak to X" is a decision, not
trivia. Merges (per the driver's instinct):

| Class | Weapons folded in | Wielders (WoB) | Icon |
|---|---|---|---|
| **sword** | swords, greatswords | Terra, Celes, (Edgar alt) | $d9 |
| **katana** | katana | Cyan | $db |
| **spear** | spears, lances | Edgar, Mog | $da |
| **blade** | dirks/daggers, claws, thrown edges | Locke, Shadow, Sabin | $d8 |
| **ranged** | cards, dice, darts, boomerangs, crossbow bolts | Setzer, Locke (Trickshot), Edgar (AutoCrossbow) | $e0 |
| **arcana** | rods, brushes | Strago, Relm, Gau (innate fangs read as arcana? **no — see open Q1**) | $dc |

- Claws + daggers merge into **blade** ✦-leaning: it gives the
  Locke/Shadow/Sabin trio one shared identity ("fast close steel"),
  which matters because trash coverage comes in trios per scenario
  split (below).
- Katana stays its own class: Cyan is one character, but bushido is
  multi-hit-rich, and "weak to katana" enemies make him the answer
  somewhere — a one-character class is a *spotlight*, not waste.
- The 8 elements stay untouched ✦ (vanilla bits, richer than
  Octopath's 6).

## How weaknesses spread (the coverage rule)

**Rule ✦: at every stretch of the WoB, the *current possible party's*
kit must be able to chip every non-boss encounter.** Not "some party"
— the party the story hands you.

The scenario split is the stress test and the proof of the design:

| Stretch | Party classes on hand | Elements on hand | So enemies there are weak to… |
|---|---|---|---|
| Narshe intro | (magitek) | fire, bolt, heal-as-probe | fire/bolt beams — tutorial-obvious |
| Figaro → Kolts | sword, blade, ranged, spear | fire, cure, poison | any two of those, generously |
| Lete River | + arcana (Banon) | + holy-ish | water beasts weak to bolt (fiction) + spear |
| **Locke scenario** | blade, ranged only | none | *every* South Figaro enemy weak to blade or ranged ✦ |
| **Sabin scenario** | blade, katana, (arcana via Gau) | holy, fire, wind | Phantom Train: holy + katana featured |
| **Terra/Banon scenario** | sword, spear, arcana | fire, ice, bolt, poison | classic mage-check spread |
| Zozo | reunited | most | mixed — first "read the room" dungeon |
| Opera → Vector | + Setzer: ranged | — | ranged-weak fliers around the southern continent |
| Magitek factory | everyone | all | armored spread: spear/katana featured, bolt-immunes appear |
| Sealed Gate / Thamasa | + Strago/Relm arcana | + lores | arcana-weak spirits; Analyze becomes the scout tool |
| Floating Continent | final WoB party | all | the exam: every class and element gets one lock |

- **Elemental weaknesses**: keep vanilla's bits wherever they exist ✦
  (fire beasts fear ice, undead fear holy/fire — the fiction already
  wrote them); *add* bits only where a stretch would otherwise have a
  hole.
- **Weapon weaknesses** (the new byte, M3): assigned by *body
  reading* — armored → spear (pierce), plated/segmented → katana
  (slash), soft/quick → blade, flying/small → ranged, spectral/
  construct → arcana, big dumb muscle → sword. Players should be able
  to *guess* before they probe; probing confirms.
- Shields ✦: trash 1–3, minibosses 4–6, bosses 6–12 with telegraphs
  (DESIGN.md); the per-monster table is authored in M6 against this
  spread.

## Weapons as chip carriers

Vanilla already ships elemental weapons (Flame Knife, Blizzard,
ThunderBlade…). In OT6 a weapon chips **its class, and its element
too if it has one** ✦ — a Flame Knife is a blade probe *and* a fire
probe in one swing. That makes shop upgrades and chest finds read as
tactical acquisitions, not stat ticks, all the way through the WoB.

Multi-hit actions chip per hit ✦ (DESIGN.md): AutoCrossbow ×4,
Flurry ×4, boosted Fight +1/BP — the shredder roles.

## Multiple weapon classes per character (engine integration)

Base rule: one class per character (the table above). Two sanctioned
exceptions, both data-driven, no new battle code:

1. **Skills carry their own class** — Trickshot is ranged on a blade
   character; AutoCrossbow is ranged on a spear character. The chip
   check reads the *action's* class byte, not the wielder's. (M3
   already needs a per-skill class/element byte; this falls out
   free.)
2. **Magicite weapon permits** (M5): an equipped esper may grant one
   extra weapon-class permit (e.g. Ramuh permits spears on Terra).
   Engine-wise this is menu-bank equip-legality only: the battle side
   always reads the class of the *item actually equipped*. No battle
   code changes at all.

## Open questions for the driver

1. Gau's innate attack: arcana (feral-as-magic), blade (fangs =
   fast close), or his own hidden 7th class that only rages use?
2. Should "ranged" ignore row? (Vanilla back-row halving; Octopath
   has no rows. Leaving row jank intact ✦-leaning, but ranged
   ignoring it is one bit of dignity for Setzer.)
3. Katana spotlight density: how many katana-weak enemies per stretch
   keeps Cyan shining without making him mandatory?
