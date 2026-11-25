# Break coverage — the Sealed Gate cave (maps 382–386)

> **Class names.** Written under the four weapon classes (slash, pierce, bludgeon,
> special ¤). Since v0.51 (#566) there are six (Sword, Dagger, Spear, Katana, Blunt,
> Ranged): slash became Sword or Katana, pierce Dagger, Spear or Ranged, bludgeon Blunt
> or Ranged, special Ranged or Blunt, each species keeping its number of weapon
> weaknesses. Each table's row column and the hands named with their weapon below are in the
> six classes' names, as `ot6_hud.asm` ships them; a "floor" column and the dated
> reasoning keep the names of the day.

Authored 2026-09-01, from the ground-truth fighting run's measurements.
`tools/tests/battle_breakgate.lua` re-verifies the rows from the shipped ROM.

## Why this area needed authoring

The run that fled never fought here, so the cave shipped on generated floor
rows nobody had answered. Measured (14 rounds of honest play, the mission
party TERRA/LOCKE/EDGAR/SABIN): at L18 the 4-stacks out-damage the party
~2:1 with the full kit; after the sanctioned plains grind, an **L23** party
dealt the `$082+$048×2` trio **~150 of its 4,191 HP in five rounds** while
taking ~800/round. No physical class moved a shield; the floor rows were
junk for every species here. That satisfies level-curve.md's own retune
rule.

## The species, decoded (`monster_prop.dat`)

| id | body | L | HP | vanilla weak | absorbs | authored row |
|---|---|---|---|---|---|---|
| `$06E` | ninja | 20 | 781 | **ice\|holy** | **fire**\|poison | 2 · sword\|dagger |
| `$0E5` | spirit | 20 | 590 | **holy** | fire\|poison | 2 · blunt\|ranged\|katana |
| `$0B3` | soft flier | 20 | 480 | **ice** | fire | 2 · sword |
| `$048` | shelled tank (×3 stacks) | 21 | 1100 | **holy\|water** | fire\|poison | 3 · dagger\|blunt |
| `$082` | brute | 21 | 1991 | **fire\|holy** | poison | 4 · sword\|ranged |

- **Vanilla's element bits stay untouched ✦** and carry the area's real
  language: **holy on four of five species** — AuraBolt, which the story
  party holds from L6, is the master key. Fire burns the brute but feeds
  the ninja: the area's absorb lesson, kept.
- The authored classes key the bodies from the forced party's own
  hands: TERRA's and EDGAR's blades (Sword) the ninja and the brute,
  LOCKE's daggers the ninja and the `$048` trio, EDGAR's AutoCrossbow
  (Ranged) the spirit and the brute, SABIN's fists (Blunt) the spirit and
  the trio. The soft flier takes the blades (Sword) and ice (Shiva).
  It was Katana, keyed by SABIN's claw, until claws became Dagger
  (2026-11-24); the mission's blades are straight (the ThunderBlade, the
  Blizzard), so its row went to Sword (battle_breakgate).
- **The spirit takes Ranged** too: a Setzer brought on the mission (he
  can be, from the Opera on) keys it with cards or dice.
- Shields follow the house curve: 2 for trash, 3 for the stacked tank,
  4 (miniboss-grade) for the 1991-HP brute.

## The play that answers it (measured)

Enter topped (care 0.85), heal only under 45, and lead SABIN with
**AuraBolt** (`blitz = 0x5E` — the driver's blitz override was added for
exactly this); TERRA carries Fire for the brute fights behind the absorb
guard (#99 refuses it wherever a ninja stands); RAMUH/SHIVA summons open
the stacks once per battle; the Genji pair chips the dagger axis twice a
swing (pierce through v0.50). The plains grind (engine-surveyed pacing at boundary F's (24,121))
covers the level gap the fled route hid and pre-pays part of the
documented FC gap.
