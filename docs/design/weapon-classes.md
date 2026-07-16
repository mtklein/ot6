# Weapon classes & the break spread — design dive v2 (2026-07-16)

Scope: World of Balance. Locked ✦.

## Three physical classes + null ✦-leaning

v1's six classes had two problems the driver called: fists-as-blade
felt wrong on Sabin, and a one-wielder class (katana) made Cyan feel
mandatory wherever katana locks appeared. v2 goes physical-intuitive:

| Class | What's in it | Wielders (WoB) | Icon |
|---|---|---|---|
| **slashing** | swords, katanas, boomerangs, claws? (open Q1) | Terra, Celes, Cyan, Locke-alt | $d9 |
| **piercing** | spears, daggers, thrown edges, crossbow bolts, darts, fangs | Edgar, Locke, Shadow, Mog, Gau, Setzer-alt | $da |
| **bludgeoning** | fists, staves, rods, flails | Sabin, Strago, Relm-alt | $dc |
| **null-break** | dice, cards, brushes, gambler oddballs | Setzer, Relm | — |

- **Bludgeoning / piercing / slashing covers the basic physicals**
  intuitively — players can guess a body's weakness before probing
  (armored → bludgeon or pierce, plated → slash, soft → pierce…),
  and probing confirms.
- **Null-break is a feature, not a gap ✦**: some attacks are just
  big dumb damage that chips nothing — the physical mirror of
  non-elemental magic. Dice roll huge and teach nothing. This is
  also the pressure valve for oddball weapons that would otherwise
  force a silly classification.
- Cyan is a slashing *specialist* (Flurry ×4 is the best slash chip
  in the game), never the only slashing key — Terra/Celes swords
  cover the class when he's absent. The lopsidedness concern is
  structurally gone, and class-coverage balance stays a standing
  question we re-ask every milestone ✦.
- The 8 elements stay untouched ✦.
- **Row jank preserved ✦**: weapons that ignore row in vanilla
  (boomerangs, dice, cards, darts…) keep ignoring row. That charm
  survives contact with the new system untouched.

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
| Opera → Vector | + null-break Setzer | — | pierce-weak fliers (darts still chip) |
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

1. Claws: slashing (cat-scratch fiction) or bludgeoning (they're on
   Sabin's monk hands)? Current lean: slashing, so monk fists stay
   pure bludgeon and claws become his "reach into slash" purchase.
2. Boomerangs: slashing (blade arc) as listed, or null-break
   (returning oddball)?
3. How many null-break weapons before probing feels unrewarding in
   a Setzer/Relm party? (Their SKILLS still chip — is that enough?)
