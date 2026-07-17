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

## The icon IS the class

Weapons wear their break class as their item icon, everywhere names
render — item menu, shops, equip, battle lists. One taxonomy,
propagated by data: the icon byte leads every item name, so every
surface follows for free, and the item menu's type column reads
SLASH / PIERCE / BLUNT / SPECIAL off the same byte. Classless (Heal
Rod) shows a small dash. Armor, relic, tool, and consumable icons
stay vanilla. v1 borrows the vanilla sword/spear/staff/sparkle
glyphs for the four classes. Corollary: wanting more icon
distinction is a signal to expand the class system — never to grow a
second, flavor-only taxonomy beside it.

## How weaknesses spread (the coverage rule)

**Rule ✦: at every stretch of the WoB, the *story's actual party*
must be able to chip every non-boss encounter.** The three-way
scenario split is the stress test:

| Stretch | Physical classes on hand | Elements | Enemies there lean |
|---|---|---|---|
| Narshe intro | (magitek) | fire, bolt | beam-weak, tutorial-obvious |
| Figaro → Kolts | slash, pierce, bludgeon (full trio by Sabin) | fire, cure, poison | generous mix |
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
