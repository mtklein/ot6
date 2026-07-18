# Break system — implementation spec (M1)

Design: [DESIGN.md](DESIGN.md). Verified addresses: [research/battle-code-map.md](research/battle-code-map.md).
Code lives in `ff6/src/battle/ot6.asm` (bank $F0), reached via `jsl` shims
at the hook sites below. Vanilla behavior must be reachable by reverting
the shims only.

## Per-entity state (monsters only need it, but tables are 10-entity wide)

Candidate homes (agent confirming they're unreferenced): the blank
per-entity byte tables at $3E38/$3E39/$3E88/$3E89 and the 9 free bytes at
$3ECB–$3ED3. Entity index X = $00..$06 chars, $08..$12 monsters (stride 2).

| Name | Home (tentative) | Meaning |
|---|---|---|
| `ot6ShieldCur` | $3E38,X | current shield points; 0 = broken or shieldless |
| `ot6ShieldMax` | $3E39,X | seeded at battle init; restore target |
| `ot6BrokenFlag` | $3E88,X | $00 normal / $01 broken (drives ×2 dmg + display) |
| `ot6Revealed` | $3E89,X | discovered-weakness bitmask (8 elements) |

BP (M2) will claim two of the $3ECB bytes per character later — chars and
monsters don't overlap needs, so tables can be shared if space gets tight.

## Rules (exact)

1. **Seed** (battle init, after monster props load): for each monster slot,
   `shieldMax = clamp(2 + level/8, 1, 6)` for now (real per-monster table in
   M6 tuning; bosses get hand values then). `shieldCur = shieldMax`,
   `brokenFlag = 0`, `revealed = 0`. Characters: all zeros (no shields).
2. **Chip** (per hit, in the elemental-modifier block, only when the hit
   lands and target is a monster): if `attackElements & weakElements($3BE0)
   ≠ 0` and `shieldCur > 0` and `brokenFlag = 0`: `shieldCur -= 1`;
   `revealed |= (attackElements & weakElements)`. Multi-hit attacks pass
   through damage calc per hit → chip per hit, matching Octopath.
3. **Break** (when chip drives shieldCur to 0): set `brokenFlag = 1`; apply
   vanilla **Stop** status to the monster (gives us for free: no turns, ATB
   frozen, attacks never miss it, timers pause) with the Stop counter set to
   ~1.5 turn-cycles (tune: Stop's vanilla #$12 ticks ≈ our baseline);
   queue break feedback (message/flash).
   *SUPERSEDED BY WHAT SHIPPED:* every claim about vanilla Stop here is
   correct, but OT6 does not use it — the shipped break runs a private
   broken timer at `$3e88,y` gated by `Ot6Gate`. Read this file as the
   original spec, not as a description of the code.
4. **Punish**: in the post-calc damage-mod routine, if target `brokenFlag`,
   damage ×2 (asl with 16-bit clamp to $270F cap handling — copy how the
   routine's other doublers clamp).
5. **Recover** (hook Stop wear-off): when Stop expires on an entity whose
   `brokenFlag = 1`: clear flag, `shieldCur = shieldMax`. If something else
   dispels Stop early (Dispel etc.), same path runs — acceptable.
6. **Interactions**: a monster that is shieldless (`shieldMax = 0` — some
   scripted fights) never breaks. Real Stop cast on a monster: brokenFlag
   stays 0, so no ×2/no reset — clean separation. Zombie/undead: no special
   case in M1.

## Display (M1-critical)

- Monster-list window: append shield count after each living monster's name
  (e.g. `Guard    ◈3`); redraw when it changes. Broken: show `BREAK` or a
  distinct glyph in place of the count.
- Target-select: show revealed weaknesses as element glyphs beside the
  count, `?` for undiscovered slots (Octopath shows total weakness count —
  we know it from weakElements popcount).
- Font: 8 element glyphs added to the battle font (weapon glyphs already
  exist for M3).
- Polish later: OAM pips over sprites, break flash/palette tint.

## Test plan (Lua harness)

- `break_chip.lua`: load battle state; read a monster's weakElements from
  ROM/RAM; force-cast a matching spell via scripted input (or set up party
  state), assert shieldCur decremented; assert revealed bit set.
- `break_full.lua`: chip to 0; assert Stop status bit set + brokenFlag;
  assert a damage packet doubles (compare same attack pre/post break with
  RNG state pinned if feasible, else assert flag+status only).
- `break_recover.lua`: advance frames until Stop expires; assert shieldCur
  restored to max and flag cleared.
- Screenshot checks for the display work once the harness confirms
  screenshot support.
