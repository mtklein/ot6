# Weapon classes & the break spread

Scope: World of Balance. Locked ✦.

## Four physical classes ✦

The physical trio covers
the logical attacks; **Special (¤)** catches everything the logical
classes don't. It is a real, breakable class, so oddball-weapon
parties keep a chip axis. 4 physical + 8 elemental = 12 weakness
axes, which matches Octopath's count.

| Class | What's in it | Wielders (WoB) | Icon |
|---|---|---|---|
| **slashing** | swords, katanas, claws | Terra, Celes, Cyan, Sabin-alt | $d9 |
| **piercing** | spears, daggers, thrown edges, crossbow bolts, darts, fangs | Edgar, Locke, Shadow, Mog, Gau, Setzer-alt | $da |
| **bludgeoning** | fists, staves, rods, flails, boomerangs (ranged bludgeon) | Sabin, Strago, Relm-alt, Locke-alt | $dc |
| **special ¤** | dice, cards, brushes, any little oddball the logical three don't claim | Setzer, Relm | $df |

- **The weapon sets Fight's class; abilities carry their own ✦.**
  Sabin with claws equipped *slashes* when he Fights, but Pummel is
  still bludgeoning regardless of what is equipped. Ability class bytes
  are immutable; only the basic attack reads the equipped weapon.
  (Claws are how the monk buys into a second class, the same way
  Edgar's Chainsaw buys him slashing.)
- **Bludgeoning / piercing / slashing covers the basic physicals**
  in a way players can guess before probing (armored → bludgeon or
  pierce, plated → slash, soft → pierce…), and probing confirms the
  guess.
- **Null-break stays, as a property rather than a class ✦**: some
  attacks deal damage and chip nothing, the physical counterpart of
  non-elemental magic. It is a per-weapon/per-skill flag. The most
  extreme oddballs (Fixed Dice…) roll high numbers and reveal
  nothing, while ordinary ¤ weapons chip Special-weak enemies.
- Cyan is a slashing *specialist* (Quadra Slam ×4 is the best slash chip
  in the game), but he is not the only slashing key: Terra/Celes swords
  cover the class when he's absent. Class-coverage balance is re-asked
  every milestone ✦.
- The 8 elements stay untouched ✦.
- **Row jank preserved ✦**: weapons that ignore row in vanilla
  (boomerangs, dice, cards, darts…) keep ignoring row. The new
  system does not change it.

## The item icon shows the break class

Each weapon's item icon is its break class icon, on every surface
that renders item names: item menu, shops, equip, battle lists. The
icon byte is the first byte of the item name, so a single data table
covers every surface, and the item menu's type column reads
SLASH / PIERCE / BLUNT / SPECIAL from the same byte. Classless
weapons (Heal Rod) show a small dash. Armor, relic, tool, and
consumable icons are unchanged from vanilla. v1 reuses the vanilla
sword/spear/staff/sparkle glyphs for the four classes. Rule: if more
visual distinction between weapon types is wanted, add another
weapon class rather than a second icon set with no mechanical
meaning.

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
| Zozo | reunited | most | first dungeon needing a per-encounter read |
| Opera → Vector | + special ¤ (Setzer) | — | pierce-weak fliers + the first ¤-weak enemies |
| Magitek factory | all | all | armored spread: bludgeon/pierce featured |
| Sealed Gate / Thamasa | + Strago/Relm | + lores | spirits: bludgeon-immune, arcane-elemental |
| Floating Continent | final WoB party | all | final check: every class and element locks once |

- **Elemental weaknesses**: vanilla's bits stay wherever they exist ✦;
  add only where a stretch has a hole.
- **Weapon weaknesses** (the new byte): assigned by body type, so
  a player can guess and then confirm by probing.
- Shields ✦: trash 1–3, minibosses 4–6, bosses 6–12 with telegraphs.

## Weapons as chip carriers

A weapon chips **its class, plus its element if it has one** ✦, so a
Flame Knife is a piercing probe and a fire probe in one swing. In
vanilla, elemental weapons rotate in and out on raw stats; here every
chest and shop upgrade also changes what the party can chip. Multi-hit
actions chip per hit ✦ (Quadra Slam, boosted Fight).

## Skills carry their own class ✦

The chip check reads the *action's* class byte, never the wielder's:
Trickshot is piercing on a dagger thief, AutoCrossbow is piercing
from a spear machinist, Suplex is bludgeoning regardless of claws.
(The per-skill class/element byte provides this for free.)

## Multiple weapon classes per character

Base rule: one class per character. Two data-driven exceptions, no
new battle code:

1. **Skills** (above) — a kit can reach outside its weapon class.
2. **Magicite weapon permits**: an equipped esper may grant one
   extra weapon-class permit. Kept spare ✦: a small knob rather than
   a system to balance around.

The ¤ icon borrows the vanilla sparkle glyph at $df; every consumer keys on
the code, so a bespoke ¤ can replace the art in place without touching
anything else.
