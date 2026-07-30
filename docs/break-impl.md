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

---

## Correction — 2026-07-30: what this spec calls things, and where they live

Before the substantive corrections below: this is the M1 spec and it names
things that no longer exist under those names. None of these are design
errors — a reader just cannot grep for any of them.

| this doc says | the shipped tree |
|---|---|
| "Code lives in `ff6/src/battle/ot6.asm`" (:4) | `ot6.asm` is a **43-line include manifest**. Break code is `ff6/src/battle/ot6_break.asm`. |
| `ot6ShieldCur` / `ot6ShieldMax` / `ot6BrokenFlag` / `ot6Revealed` (:16-19) | `OT6_SHIELD_CUR` / `OT6_SHIELD_MAX` / `OT6_BROKEN_TICKS` / `OT6_REVEALED_ELEM` (`ot6_memory.inc:10-13`). **The addresses in the table are all correct.** |
| `$3E88,X` is a `$00`/`$01` flag (:18) | It is a **countdown**, not a flag: `OT6_BROKEN_TICKS`, loaded with `$10` (`ot6_break.asm:884`) and decremented in `Ot6Gate` (`:1677`). |
| "BP (M2) will claim two of the `$3ECB` bytes" (:21) | BP landed at `$3e9c` (`OT6_BP_CLASS`, `ot6_memory.inc:14`). `$3ecb` became `OT6_DIVINE_USED` plus scratch. |
| `shieldMax = clamp(2 + level/8, 1, 6)` (:27) | The **authored table is consulted first** (`ot6_break.asm:24-38`); the formula is the `@formula` fallback at `:39`, and its floor is 2, not 1. Cap 6 is right. |
| step 5 "hook Stop wear-off" (:47) | No Stop hook. Recovery rides the private timer via `Ot6Tick`. Step 3's inline *SUPERSEDED* note covers step 3 but not this one. |
| test plan `break_chip.lua` / `break_full.lua` / `break_recover.lua` (:69-76) | **None of the three were ever written.** The shipped gate is `tools/tests/battle_break.lua`, plus `battle_breakflash`, `battle_breakfloor`, `battle_breaktbl`, `battle_breakvector` and `battle_brokendeath`. |

## Correction — 2026-07-30: the break window is ~36 seconds, not ~1.5 turn-cycles

This is the M1 spec, and it is mostly still legible as one. Two of its
statements are now measurably wrong about the shipped ROM, and both are
recorded here rather than edited away.

### 1. Step 3's "~1.5 turn-cycles" is off by roughly an order of magnitude

Step 3 sets the break window at *"~1.5 turn-cycles (tune: Stop's vanilla
`#$12` ticks ≈ our baseline)"*. What shipped is `OT6_BREAK_TICKS := $10`
(`ff6/src/battle/ot6_break.asm:1`, armed at `:884` and `:991`, and by
`ot6_kits.asm:2946`) — the intended "a bit under vanilla stop duration",
so the *constant* matches the spec's intent exactly. **The wall-clock it
buys does not.**

Measured on Ifrit & Shiva during the v0.9 work (merge `9f6971c`,
`tools/tests/probe_ifritbreak.lua`): an on-stage broken monster recovered
in **2159 frames**. At ~60 fps that is **~36 seconds** of battle time. The
independent `#60` DOT run measured the same window at ~2170 frames (commit
`3b8313e`), so the number is not a one-off.

For scale, that run also measured a poison DOT tick landing once per ~1048
frames per entity, so a single break window spans about **two full DOT tick
periods**. **UNVERIFIED:** nobody has measured a boss's *turn* cadence
against this window, so "many boss turns" is an inference from the frame
count, not a count of turns. What is measured is 2159 frames, and a "turn
cycle" that long is not what step 3 meant.

**The constant is deliberately NOT changed here.** Whether 36 s is too
generous is a balance question for playtest, and it interacts with the
punish ×2, with Cleave's Broken-only gate, and with the DOT cadence above.
This entry exists so the next person to read step 3 does not budget 1.5
turns' worth of anything.

### 2. Step 2's multi-hit sentence describes a rule with almost nothing behind it

Step 2's *"Multi-hit attacks pass through damage calc per hit → chip per
hit"* is **correct as a rule and now measured** — one boosted Fight chipped
four shields off one guard (`design/multi-hit.md` §1). But the population it
applies to is tiny: an audit of all 256 `MagicProp` and 256 `ItemProp`
records (`tools/audit_multihit.py`) finds **exactly three** multi-hit
abilities in the game — Quadra Slam ×4, Quadra Slice ×4, Empowerer ×2. See
`design/multi-hit.md` for the survey and §10 for the build list that would
widen it.

### Still accurate, for the avoidance of doubt

Step 3's own inline *SUPERSEDED* note (that OT6 does not use vanilla Stop
and runs a private timer at `$3e88,y` gated by `Ot6Gate`) stands, and
`Ot6Gate` is at `ff6/src/battle/ot6_break.asm:1655`, consulted from
`battle_main.asm:1419`. Note that gate is known to leak — a Broken monster
still takes counterattacks and pre-queued turns (issue #66) — so step 3's
"gives us for free: no turns" is the intent, not the shipped behaviour.
