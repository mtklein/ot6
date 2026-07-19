# Weapon classes & the break spread — design dive v2.1 (2026-07-16)

Scope: World of Balance. Locked ✦.

## Four physical classes ✦

v1's six classes had two problems the driver called: fists-as-blade
felt wrong on Sabin, and a one-wielder class (katana) made Cyan feel
mandatory wherever katana locks appeared. The physical trio covers
the logical attacks; **Special (¤)** catches everything the logical
classes don't — and it's a real, breakable class, so oddball-weapon
parties keep a chip axis. 4 physical + 8 elemental = 12 weakness
axes: Octopath's exact count.

| Class | What's in it | Wielders (WoB) | Icon |
|---|---|---|---|
| **slashing** | swords, katanas, claws | Terra, Celes, Cyan, Sabin-alt | $d9 |
| **piercing** | spears, daggers, thrown edges, crossbow bolts, darts, fangs | Edgar, Locke, Shadow, Mog, Gau, Setzer-alt | $da |
| **bludgeoning** | fists, staves, rods, flails, boomerangs (ranged bludgeon) | Sabin, Strago, Relm-alt, Locke-alt | $dc |
| **special ¤** | dice, cards, brushes, any little oddball the logical three don't claim | Setzer, Relm | $df |

- **The weapon sets Fight's class; abilities carry their own ✦.**
  Sabin with claws equipped *slashes* when he Fights — but Pummel is
  still bludgeoning, whatever is on his hands. Ability class bytes
  are immutable; only the basic attack reads the equipped weapon.
  (Claws are how the monk buys into a second class, the same way
  Edgar's Chainsaw buys him slashing.)
- **Bludgeoning / piercing / slashing covers the basic physicals**
  intuitively — players can guess a body's weakness before probing
  (armored → bludgeon or pierce, plated → slash, soft → pierce…),
  and probing confirms.
- **Null-break stays, as a property, not a class ✦**: some attacks
  are just big dumb damage that chips nothing — the physical mirror
  of non-elemental magic. A per-weapon/per-skill flag: the wildest
  oddballs (Fixed Dice…) roll huge and teach nothing, while ordinary
  ¤ weapons chip Special-weak enemies.
- Cyan is a slashing *specialist* (Flurry ×4 is the best slash chip
  in the game), never the only slashing key — Terra/Celes swords
  cover the class when he's absent. Class-coverage balance stays a
  standing question we re-ask every milestone ✦.
- The 8 elements stay untouched ✦.
- **Row jank preserved ✦**: weapons that ignore row in vanilla
  (boomerangs, dice, cards, darts…) keep ignoring row. That charm
  survives contact with the new system untouched.

## The item icon shows the break class

Each weapon's item icon is its break class icon, on every surface
that renders item names: item menu, shops, equip, battle lists. The
icon byte is the first byte of the item name, so a single data table
covers every surface, and the item menu's type column reads
SLASH / PIERCE / BLUNT / SPECIAL from the same byte. Classless
weapons (Heal Rod) show a small dash. Armor, relic, tool, and
consumable icons are unchanged from vanilla. v1 reuses the vanilla
sword/spear/staff/sparkle glyphs for the four classes. Rule: if we
ever want more visual distinction between weapon types, that is a
reason to consider another weapon class, not to add a second
icon set with no mechanical meaning.

## How weaknesses spread (the coverage rule)

**Rule ✦: at every stretch of the WoB, the *story's actual party*
must be able to chip every non-boss encounter.** The three-way
scenario split is the stress test:

| Stretch | Physical classes on hand | Elements | Enemies there lean |
|---|---|---|---|
| Narshe intro | (magitek) | fire, bolt | beam-weak, tutorial-obvious |
| Figaro → Kolts | **pierce, pierce, slash** going up; bludgeon only after Sabin | **fire, poison** (+cure) | authored: poison is the second key ✦ |
| **Locke scenario** | pierce only | none | *everything* South Figaro pierces ✦ |
| **Sabin scenario** | bludgeon, slash (Cyan), pierce (Gau) | holy, fire, wind | Phantom Train: holy + slash featured |
| **Terra/Banon scenario** | slash, pierce, bludgeon (Banon rod) | fire, ice, bolt, poison | mage-check spread |
| Zozo | reunited | most | first "read the room" dungeon |
| Opera → Vector | + special ¤ (Setzer) | — | pierce-weak fliers + the first ¤-weak enemies |
| Magitek factory | all | all | armored spread: bludgeon/pierce featured |
| Sealed Gate / Thamasa | + Strago/Relm | + lores | spirits: bludgeon-immune, arcane-elemental |
| Floating Continent | final WoB party | all | the exam: every class and element locks once |

- **Elemental weaknesses**: vanilla's bits stay wherever they exist ✦;
  add only where a stretch has a hole.
- **Weapon weaknesses** (the new byte, M3): assigned by body reading —
  guessable, then confirmed by probe.
- Shields ✦: trash 1–3, minibosses 4–6, bosses 6–12 with telegraphs;
  per-monster table authored in M6 against this spread.

### The Figaro → Kolts row, audited (2026-07-19)

The row above used to read "slash, pierce, bludgeon (full trio by
Sabin)". Decoding the actual encounter tables and the actual starting
equipment corrected it in both columns, and the correction is why this
stretch's weaknesses are authored on the **element** axis:

- **The class ring is degenerate here.** Terra carries a Mithril Knife
  and Locke a Dirk — both **piercing** (`ot6_class.asm:49,:48`) — and
  Edgar a Mithril Blade, **slashing** (`:59`); see
  `char_prop.asm:152,:162,:197`. So two of the four classes are what the
  A button already swings and the other two have no wielder at all until
  Sabin (bludgeoning) and Setzer (special). Every class row on this
  stretch is therefore a freebie or a Repo Man. Exactly one is authored —
  Brawler's slash, because Brawler *absorbs* the poison answer — and it
  is deliberately the **scarce** class: Edgar's blade is the party's only
  slashing weapon, so the answer to a Brawler is "close the Tools menu".
- **The element ring is two keys wide, not three.** Terra's natural list
  is Cure 1 / Fire 3 / Antdot 6 / Drain 12 (`field/event.asm:1248`), so
  **fire** is her whole offensive element until Drain. The second key is
  **poison**, and it is Edgar's Bio Blaster — a Figaro-shop buy the
  frontier verifies is still carried at the mountain
  (`gen_kolts.lua:594`).
- **The pool was not a "generous mix" — it had four holes.** Of the
  species this stretch actually draws, Cirpius ($086) and Rhodox ($012)
  had *no* vanilla weakness at all, and Sand Ray ($05c) / Areneid ($05d)
  are ice|water, which nobody here casts. Cirpius is the worst: 93.75% of
  the draws on Mt. Kolts maps 95/96/97, three at a time. Six
  `Ot6ElemAddTbl` rows close all four holes with poison and give the
  stretch's two keys a roughly even split (fire opens 8 species, poison
  7, slash 1). Full derivation and the per-species reasoning:
  `balance-metrics.md` Measurement #8.

## Weapons as chip carriers

A weapon chips **its class, plus its element if it has one** ✦ — a
Flame Knife is a piercing probe and a fire probe in one swing. In
vanilla, elemental weapons rotate in and out on raw stats; here every
chest and shop upgrade is a tactical acquisition. Multi-hit actions
chip per hit ✦ (AutoCrossbow, Flurry, boosted Fight).

## Skills carry their own class ✦

The chip check reads the *action's* class byte, never the wielder's:
Trickshot is piercing on a dagger thief, AutoCrossbow is piercing
from a spear machinist, Suplex is bludgeoning regardless of claws.
(M3's per-skill class/element byte provides this for free.)

## Multiple weapon classes per character

Base rule: one class per character. Two data-driven exceptions, no
new battle code:

1. **Skills** (above) — a kit can reach outside its weapon class.
2. **Magicite weapon permits** (M5): an equipped esper may grant one
   extra weapon-class permit. Kept deliberately spare ✦ — a knob to
   gesture with, not a system to balance around.

## Open questions for the driver

1. ¤-weak density: how many Special-weak enemies per stretch keeps a
   Setzer/Relm party probing happily without making ¤ a skeleton key?
   (First instinct: rare before the Opera, steady after.)
2. The ¤ icon needs a font cell — draw a little sparkle/asterisk in
   the same family as the element icons, or borrow a vanilla glyph?
   (v1 borrows the vanilla sparkle at $df; a bespoke ¤ can replace
   the art in place later — every consumer keys on the code.)
