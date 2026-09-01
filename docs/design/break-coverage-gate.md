# Break coverage — the Sealed Gate cave (maps 382–386)

Authored 2026-09-01, from the ground-truth fighting lineage's measurements.
`tools/tests/battle_breakgate.lua` re-verifies the rows from the shipped ROM.

## Why this area needed authoring

The fled lineage never fought here, so the cave shipped on generated floor
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
| `$06E` | ninja | 20 | 781 | **ice\|holy** | **fire**\|poison | 2 · pierce\|slash |
| `$0E5` | spirit | 20 | 590 | **holy** | fire\|poison | 2 · slash\|bludg |
| `$0B3` | soft flier | 20 | 480 | **ice** | fire | 2 · slash |
| `$048` | shelled tank (×3 stacks) | 21 | 1100 | **holy\|water** | fire\|poison | 3 · pierce\|bludg |
| `$082` | brute | 21 | 1991 | **fire\|holy** | poison | 4 · bludg\|slash |

- **Vanilla's element bits stay untouched ✦** and carry the area's real
  language: **holy on four of five species** — AuraBolt, which the story
  party holds from L6, is the master key. Fire burns the brute but feeds
  the ninja: the area's absorb lesson, kept.
- The authored classes give every body a key in the forced party's own
  hands: LOCKE's daggers and EDGAR's AutoCrossbow (pierce — the crossbow
  sweeps the `$048` trio), TERRA/EDGAR blades (slash), SABIN's fists
  (bludg).
- Shields follow the house curve: 2 for trash, 3 for the stacked tank,
  4 (miniboss-grade) for the 1991-HP brute.

## The play that answers it (measured)

Enter topped (care 0.85), heal only under 45, and lead SABIN with
**AuraBolt** (`blitz = 0x5E` — the driver's blitz override was added for
exactly this); TERRA carries Fire for the brute fights behind the absorb
guard (#99 refuses it wherever a ninja stands); RAMUH/SHIVA summons open
the stacks once per battle; the Genji pair chips the pierce axis twice a
swing. The plains grind (engine-censused pacing at boundary F's (24,121))
covers the level gap the fled route hid and pre-pays part of the
documented FC gap.
