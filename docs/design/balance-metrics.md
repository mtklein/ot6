# Balance metrics — the measurement harness (2026-07-16)

Scope: measurement, not tuning. Every number below marked *proposed*
is a proposal for the driver; nothing here is locked.

Tuning M3's weakness spread and M6's per-monster shield table by feel
alone won't survive contact with three scenario parties. So before the
knobs, an instrument: `tools/tests/metrics_battle.lua` plays a fight
by policy and emits one greppable `[ot6] [metrics] key=value` line per
stat. Same rig as the acceptance tests (doorstep savestate, headless
Mesen, drive-by-state), but it *plays* instead of asserting.

## What we measure and why

| Measure | Report lines | Why it's the number |
|---|---|---|
| **Turns-to-kill** | `player_actions` at `result=won` | The pace dial. The whole loop is "spend turns probing to earn faster kills" — TTK is where every other knob's effect lands. |
| **Boost throughput multiplier** | baseline TTK ÷ boost3 TTK; `player_dmg / player_actions` ratio | What a BP is worth. If boosting doesn't buy visible pace, R is decoration; if it buys too much, unboosted play feels broken. |
| **Break uptime** | `break_uptime_frames / frames`, `breaks`, `first_break_frame` | The payoff window. Breaks must be earnable mid-trash-fight, not a boss-only spectacle — uptime says whether the ×2 window actually exists in play. |
| Damage through the window | `player_dmg_broken` vs `_unbroken` | Whether breaks carry the damage economy or just decorate it. |
| Danger budget | `enemy_actions`, `enemy_dmg` | Break's defensive half: a broken monster loses turns, so enemy action count is the survivability value of chipping. |
| Probe efficiency | `shield_chips` per `player_actions` | How much of a fight is spent paying the probe tax. |

Policies are swappable functions in the lua (`POLICY` knob):
`baseline` mashes A unboosted, `boost3` banks to 3 BP and spends all
three, `greedy` spends every point the turn it appears. Baseline is
the denominator for everything.

Since 2026-07-18 a policy sets only the **boost discipline**; what a
character actually *does* with the turn comes from a per-character
**kit** table (`KITS`, keyed on the character index at `$3ED9+slot*2`),
so one named policy plays a whole party — Terra probes and exploits with
Fire, Locke opens with Steal then Fights, Edgar's Tools carry
pierce/poison, Sabin inputs Blitz. Every stat fans out per party slot
(`char_actions`, `char_dmg`, `char_chips`, `char_breaks`, `char_boosts`,
`char_bp_*`, `char_dmg_taken`) using the same `sN:value` CSV the monster
lines already used; the aggregate keys are unchanged, so older logs
still tabulate.

## Proposed target bands (for the driver)

| Band | Proposed target |
|---|---|
| Trash TTK, unboosted | **3–5 player actions** |
| Trash TTK, boost3 | **2–3 player actions** (implied multiplier ~1.5–2×) |
| Trash breaks | ≥1 break available when probing a real weakness; first break by the 2nd–3rd player action |
| Boss break windows | **~2 per fight**, telegraphed; break uptime ~20–30% of the fight |
| Trash danger budget | ≤3 enemy actions unboosted; breaking well should shave ≥1 |
| greedy vs boost3 | greedy should *lose* to boost3 on TTK — banking must be a real decision, or L/R is a mash |

Rationale for the headline pair: vanilla Narshe trash dies in ~2–3
attacks, and OT6 adds a probe tax (chips) on top. 3–5 unboosted keeps
trash from becoming a slog while leaving room for boost to buy back
the tax and then some — the Octopath feel is "the fight got longer,
but playing it well makes it shorter than it ever was."

## Running it, now and across formations

Now: two doorstep states exist (`battle_doorstep`, `battle2_doorstep`
— the `STATE` knob), so the matrix is 2 formations × 3 policies. One
run is deterministic (rng phase is frame-driven); distributions come
from the `SETTLE_EXTRA` jitter knob — sweep 0..90 in ~10-frame steps
for ~10 samples per cell. Aggregation is a grep: every stat is one
`key=value` line in `build/states/last_run.log`.

Once post-magitek states exist (M3+): mint one doorstep per stretch
with the `gen_battle2` pattern (win, walk to the next trigger, save),
named `battleN_doorstep`, and run the same matrix. The rows to fill
are exactly the stretch table in `weapon-classes.md` — the coverage
rule ("the story's actual party chips every non-boss encounter")
becomes checkable: per stretch, every formation shows a sane TTK band
and a nonzero break rate *with that stretch's party*. Boss states get
their own band row (break windows, uptime) once a boss is reachable.

Known blind spots. The victim-attribution one is **fixed** as of
2026-07-18: damage, chips and breaks are credited to the entity whose
action is running, read from the battle loop's own action-queue
dequeues, so monster-on-monster muddle damage no longer lands in
`player_dmg` — it is reported separately as `monster_self_dmg`. What
remains:

- **Attribution is action-granular, not hit-granular**, and one frame of
  slack sits at each action boundary. There is no WRAM address carrying
  the attacker at damage-apply time: `ApplyDmg` reads it off the stack
  (`lda $02,s`, `battle_main.asm:2960`), `$32E0,y` is a retaliation
  blacklist written only on death (`:8662`), and `$3406` reads negative
  across the damage frames because `ExecAction`'s `sec / ror $3406`
  (`:194`) invalidates it on entry. The drivers publish a `_residual` per
  metric and `bp_action_skew` as an independent cross-check, and
  `bal_aggregate.py` fails the run on any nonzero residual.
- `$340a` **immediate actions** (battle-start scripts, final attacks)
  bypass all three queues, so they are uncounted *and* leave the actor
  shadow stale. Rare in WoB trash.
- **Menu travel is not modelled.** The driver selects a command by
  writing it into all four command cells and reaches a list entry by
  writing the cursor triple, so the instrument measures "this character
  used this action", not "a human navigated to it".

## Measurement #1 — mines_chase, Terra L5 solo (2026-07-16)

First live numbers, from `bal_mines.lua` (seeded formation draws via
RNG streams `$1fa1`/`$1fa2`, loadState-independent battles, paired
samples across policies; aggregate with `bal_aggregate.py`). 8
battles per policy, full pool coverage, 0 voids, 0 deaths.

Note: the turns published in this table were already real actions (the
drivers' raw dequeue counter ran 2x real until fixed on 2026-07-17; the
drivers now emit real actions directly).

| policy | turns | frames | chips | breaks | verdict |
|---|---|---|---|---|---|
| baseline | 2 | 744 | 0 | 0 | pierce hits nothing in the pool |
| boost3 | 2 | 744 | 0 | 0 | **never boosts — bank hits 2 as the fight ends** |
| greedy | 2 | 840 | 0 | 0 | same kills, +13% time, more damage taken |
| fire | 2 | 1517 | 13 | 0 | chips land; nothing survives its first chip |

Findings against the bands above: intro trash sits BELOW the trash
TTK band (2 real turns vs the proposed 3–5) — every pool member dies
to one action, so neither the BP economy (first 3-boost window =
turn 3) nor a break (two chip-hits on a living target) can express.
This is arithmetic, not variance: boost is a strictly-losing button
here, and that is measured, not felt. Repo Man (6/16 of draws) is
unchippable by this party (poison-only weakness) — the coverage
rule's first live counterexample, tutorial-stretch edition.

Dispositions: the mines pool is tutorial texture, not tuning
material (whether it should *become* tuning material is an M6
design call that trades against vanilla trash jank). The break loop
measures next on `whelk_doorstep` — the authored boss row
(4·pierce) against TekMissile is the first place chips→break→×2 can
actually happen. Trash boost economics want a ≥3-real-turn fixture
(post-split scenarios or Lete River).

## Measurement #2 — Whelk boss, magitek party (2026-07-16)

From `whelkbal_run.lua` (policies: beams-baseline / pierce-probe /
mixed-naive; 5 loadState-independent legit fights each) plus a
simulated-loop lab. Measured BEFORE the $f2 gate fix; tek now chips
(verified 4->3 live post-fix by `whelkbal_tek.lua`).

- As then shipped: 0 chips, 0 breaks, any policy — the $f2 gate bug
  silenced every magitek attack. Since fixed.
- pierce-probe beat beams-baseline by ~30-40% TTK (11.6k vs 16.6k+
  frames) but purely on TekMissile's raw 3.2x damage — nothing on
  screen tied it to the break system. mixed-naive LOST 5/5: MegaVolt
  shell counters are the whole danger budget, and Terra KO = game
  over (her 77 HP is the fight's real HP bar).
- The retract cycle is the fight's true clock: head untargetable
  ~40-53% of wall time, queued attacks retarget into the shell and
  eat counters, and the break timer FREEZES while the head hides (a
  window can span 8.2k wall frames with ~2.2k targetable).
- Arithmetic: pierce-only 4 chips can't happen — three teks (~540
  each) kill the 1600-HP head one chip short. The designed tutorial
  line ("three beams and a TekMissile, broken inside two rounds")
  requires the head's fire-weak ADD, which is therefore load-bearing
  M6 data, not polish. Boss band as shipped: 0 windows; simulated
  best case <1 window/fight — the add (or a shields/HP retune) is
  what buys the ~2-window target.
- R-boost DOES engage inside magitek menus (pending moved 0->2, a
  1-BP boosted beam dealt ~2x) — boost tutorialization can start at
  the Whelk.

## Measurement #3 — difficulty transform sweep (2026-07-17)

The runtime difficulty transform is in: at monster seed time
(`Ot6HpScale`, called from the `Ot6SeedShields` tail), every
non-authored species' battle HP — both cells, `$3bf4` current and
`$3c1c` max — is multiplied by a per-species-band value in 16ths from
`Ot6HpMulTbl` (bank F0). Authored `Ot6ShieldTbl` species (bosses +
tutorial trash) are exempt; `$3a47.7` carried-HP scene changes are
skipped; vanilla ROM data is untouched. Swept the early band
($00–$5F) across 1x/2x/3x/4x on `bal_mines.lua` (same rig as
Measurement #1: seeded draws, 8 loadState-independent battles per
policy per multiplier, identical seeds across multipliers — the table
byte is the only variable). 128 battles, 0 voids, 0 deaths.

Counting note: the dequeue-side action counter emits two queue
entries per real action (verified against BP-regen stamps in the
action traces; Measurement #1's published turns were already real).
Turns below are real player actions.

| mult | policy | turns | frames | dmg taken | chips | breaks | 3-BP spends |
|---|---|---|---|---|---|---|---|
| 1x | baseline | 2.0 | 744 | 4 | 0 | 0 | 0 |
| 1x | boost3 | 2.0 | 744 | 4 | 0 | 0 | 0 |
| 1x | greedy | 2.0 | 840 | 5 | 0 | 0 | 0 |
| 1x | fire | 2.0 | 1517 | 7 | 13 | 0 | 0 |
| 2x | baseline | 3.1 | 1456 | 10 | 0 | 0 | 0 |
| 2x | boost3 | 2.8 | 1284 | 9 | 0 | 0 | 0 (bank reaches 3) |
| 2x | greedy | 2.8 | 1320 | 9 | 0 | 0 | 0 (spends 1s) |
| 2x | fire | 2.0 | 1517 | 7 | 13 | 0 | 0 |
| 3x | baseline | 4.9 | 2609 | 19 | 0 | 0 | 0 |
| 3x | boost3 | 4.1 | 2251 | 19 | 0 | 0 | 3/8 battles |
| 3x | greedy | 3.4 | 1736 | 11 | 0 | 0 | 0 (spends 1s) |
| 3x | fire | 2.0 | 1548 | 8 | 13 | 0 | 0 |
| 4x | baseline | 5.4 | 2923 | 21 | 0 | 0 | 0 |
| 4x | boost3 | 4.4 | 2463 | 20 | 0 | 0 | 5/8 battles |
| 4x | greedy | 3.9 | 2070 | 13 | 0 | 0 | 0 (spends 1s) |
| 4x | fire | 2.4 | 1907 | 8 | 13 | 0 | 0 |

Per-formation baseline TTK (real turns): 2x — Rat,Rat 4 / Repo,Vap 3
/ Vap,Vap 2. 3x — 6 / 4–5 / 4. 4x — 6 / 5–6 / 4. Real enemy actions
(baseline): 1.4 / 3.0 / 6.0 / 6.9 across the four multipliers; Terra
(77 max HP) never ended below 66 at 2x, 45 at 3–4x, no deaths.
Measured damage constants at L5: Fight ≈ 33–35 per swing, unweak
Fire ≈ 112–122, weak Fire ≥ 96 in every observed kill (×2 ⇒ ~230).

Band scorecard: **2x is the only column that clears TTK (3.1, every
formation 2–4) and the danger budget (3.0) together**, and it's where
the 3-BP bank first *reaches* 3 mid-fight. 3x/4x overshoot both
bands (Rat,Rat = 6 real turns, 6–7 enemy actions) in exchange for
boost3's spend window actually firing. greedy *beats* boost3
wherever boosting expresses (3.4 vs 4.1 at 3x) — banking overshoots
sub-150-HP targets, so the "greedy must lose" band is a boss-fight
property, not an intro-trash one (Measurement #2's Whelk shell
counters are where over-commitment costs).

The tradeoff, quantified: breaks stayed 0 in all 128 battles, and
that is arithmetic, not tuning. Formula trash has 2 shields; an
alive-break needs the monster to survive two weak-element hits
(~230 each), i.e. ~460+ HP — Vaporite would need ≥31x, Were-Rat
≥19x, an order of magnitude past the TTK band (2x). "Breakable
intro trash" and "3–5 action fights" are unsatisfiable
simultaneously in the elemental-probe channel. The workable channel
is weapon-class chips: Fight (~35) does NOT one-shot 2x trash
(48–140 HP), so two alive chips fit easily — but formula species
carry no class weaknesses, so trash class-chipping requires M6
authoring class rows onto marked trash (the `Ot6ShieldTbl` flavor
mechanism that already exists). Disposition: intro trash is
TTK-tuned at 2x; the first break stays the Whelk head's authored
4·pierce (verified live by `whelkbal_tek`); trash breaks arrive
with M6 class-weakness data, not with HP multipliers.

Values shipped AT THE TIME (`Ot6HpMulTbl`, 16ths): $20/$20/$10/$10
— band $00–$5F 2x (swept, above), band $60–$BF 2x (census
arithmetic: WoB mid trash HP 119–495 keeps the same damage:HP
shape; stretch fixtures should confirm), bands $C0–$FF and $100+ 1x
(WoR unmeasured; $100+ additionally guards Doom Gaze's saved-HP
reload from compounding). Gate: full suite green twice at these
values, story-chain fixtures re-minted, Whelk head untouched at
1600 HP.

**Superseded — do not read the line above as current.** Measurement
#5 retired the HP dial entirely; the table ships $10/$10/$10/$10
(all 1x) and shielded resistance carries difficulty instead. See
Measurement #5 below and `Ot6HpMulTbl` in ot6.asm for the live
values.

## Measurement #4 — encounter-rate and reward parity (2026-07-17)

Measurement #3 doubled trash HP, and 2x-HP fights run ~2x longer. Two
paired runtime knobs now conserve pace: the per-step encounter danger
increment is scaled by `Ot6DangerMulW` (16ths, shipped $08 = 0.5x) in
both per-step battle checks, and at victory a random encounter's xp
and gil sums are scaled by `Ot6RewardMulW` (shipped $20 = 2x). Random
encounters are identified by a marker the two field/world trigger
paths set and battle init consumes; event and boss battles never carry
it. The knob product is pinned at $100 (1.0): change them as a pair.

Measured by `mines_pace.lua`: the bal_mines fixture and pacing route,
8 paired seeded samples per arm, danger counter zeroed per sample
(vanilla zeroes it at every trigger, so a cold start equals the
steady-state inter-encounter interval; the fixture's warm counter had
masked the knob entirely — paired steps came out identical). The
vanilla arm pokes all three knobs (`Ot6HpMulTbl` band0, danger,
reward) to $10 in the loaded ROM image; the scale routines are exact
at $10, so that arm is vanilla's arithmetic exactly. 16/16 samples
completed, 0 voids, 0 deaths; xp/gil deltas read from save data after
victory (`$1611`/`$1860`), so clamps and AddExp are included.

| arm | steps/enc (mean, min–max) | fight frames | xp/enc | gil/enc |
|---|---|---|---|---|
| vanilla (all 1x) | 25.6 (6–44) | 990 | 45.2 | 51.2 |
| ours ($08/$20/$20) | 42.6 (21–59) | 1713 | 90.5 | 102.5 |

Parity products, ours : vanilla (tolerance 0.8–1.25 for v0.1):

- Combat time per step — (fight frames / steps): 40.2 vs 38.7 =
  **1.04**. Half the encounters at roughly double the fight length
  holds combat time per step at vanilla's value; the mixture helps
  (Vaporite pairs die to the same swing count at 2x HP, Were-Rat
  pairs take the full 2.2x, and the average lands on parity).
- XP per step: 2.12 vs 1.77 = **1.20**. Per-encounter rewards are
  exactly 2x (Rat,Rat 42→84, Vap,Vap 46→92, Repo+Vap 48→96; gil
  44→88, 58→116, 54→108), but the encounter rate measured 0.60x
  rather than 0.50x — the trigger needs the rng byte under the
  counter high byte, and seeds whose stream reaches a low byte early
  fire at the same step on both arms (4 of 8 pairs were identical),
  compressing the rate effect. 0.60 x 2 = 1.20; inside the band,
  leaning generous. Gil per step: 2.40 vs 2.00 = the same **1.20**.

Fight-frame cross-check: this driver clocks from battle-active to
last kill (~246 frames of load/settle included on both arms);
removing that constant gives 1467 vs 744 = 1.97x, matching
Measurement #3's 1456 vs 744 protocol numbers.

## Measurement #5 — co-tune sweep: resistance × HP, and boost pedagogy (2026-07-17)

Two provisional constants shipped together at HEAD 2968c11: SHIELDED
RESISTANCE (`Ot6ShieldedMulW`, damage × mul/16 while a monster has
shields and is not broken; $08 = 0.5x) and the HP-band multiplier
(`Ot6HpMulTbl` band0 $20 = 2x). Both lengthen fights, and stacking
them overshoots the snappy-fight band — 2x HP alone gave ~3.1 baseline
actions (Measurement #3), and halving damage on top pushes toward a
slog. This sweep finalizes both and verifies the boost-pedagogy goal.

The grid was run by poking the two ROM bytes per battle rather than
rebuilding per cell (proven equivalent by Measurement #4's vanilla
arm — the scale routines read the same `f:Ot6HpMulTbl` /
`f:Ot6ShieldedMulW` bytes a rebuild would bake). The shipped values
were then set by a real source edit and verified by the full gate.

### The design goal (from the owner)

Spending BP should feel WASTED when boosting into an unbroken,
non-weak enemy. Correct BP use is: boost to break, boost to wipe an
already-broken enemy, or boost through a trivial fight. The measurable
target is an ORDERING of damage-per-BP by target state:

    broken  >>  shielded-and-weak  >>  shielded-and-unweak

### The metric — damage-per-BP by target state (`bal_dpb.lua`)

The mines pool is too fragile to express boosts (trash dies in ~2
actions) and its formula species carry no class weakness, so the
ordering is measured in a pinned laboratory built on the guard
fixture. Each frame the driver pins two guards into an exact state and
pins the party BP/pending, then records every Fire Beam HP-drop with
the (state, boost) label. Fire Beam base is the same in every phase
(casters pinned level 5 / mag 10), so the per-state multiplier is the
only variable:

    shielded-unweak   base × R              (R = Ot6ShieldedMulW/16)
    shielded-weak     base ×2 × R           (vanilla fire-weak, then shielded)
    broken            base ×2               (shields down, R does not apply)

8 samples per (state, boost). Marginal = boosted − unboosted; per-BP =
marginal / 3. Fire Beam base ≈ 140; a 3-BP boost multiplies it ~8×
(Fire → Firaga potency), identically in every state.

Damage-per-BP, swept across resistance (same lab, resistance poked):

| resistance | unweak /BP | weak /BP | broken /BP | ratio broken:weak:unweak |
|---|---|---|---|---|
| **0.5x ($08)** | 169.6 | 322.5 | 660.6 | **3.89 : 1.90 : 1.00** |
| 0.75x ($0c) | 254.5 | 483.7 | 660.6 | 2.60 : 1.90 : 1.00 |
| 1x/off ($10) | 339.4 | 644.9 | 660.6 | 1.95 : 1.90 : 1.00 |

The ordering holds at every resistance, but its SHAPE is set by the
constant. Broken per-BP is fixed (660.6 — shields are down, so
resistance never applies); unweak and weak both scale up toward broken
as resistance rises. At 1x (off) a shielded-weak hit (644.9) essentially
TIES broken (660.6): with no attenuation a weakness hit already
collects vanilla's ×2, so there is no damage reason to spend the extra
effort to break. At 0.5x the ladder is a clean doubling — broken buys
~2× what a weakness buys, a weakness buys ~2× what an off-weakness hit
buys (4:2:1). **0.5x is the resistance that makes "boost to break" AND
"hit the weakness" both pay, and makes boosting into shielded-unweak
visibly the worst return (a quarter of a broken boost).**

### The bad-player policy and boost logging (`bal_mines.lua`)

A new `badboost` policy banks to 3 BP then dumps a 3-BP boosted FIGHT
at the default target. Fight is pierce and every mines-pool species is
formula (no class weakness), so this boost ALWAYS lands in a
shielded-unweak target — the canonical "boost feels wasted" misplay.
`bal_mines` now also logs every boosted action's target state at cast
(a `boost_states` line): in the pool these read `l3:shielded:wk*:sh2`,
i.e. a level-3 boost into a still-shielded target the weapon does not
match. For this pool `badboost` coincides with `boost3` (Fight matches
no pool weakness either way) — that coincidence IS the finding: when
your weapon matches no weakness, the BP economy IS the bad play.

### The co-tune grid

HP band0 {1x, 1.5x, 2x} × resistance {0.5x, 0.75x, 1x}, 5 policies, 8
battles each, seeded (identical draws across cells). The informative
subset run: the full HP=1x row (all three resistances) and the full
R=0.5x column (all three HP), a cross centred on the winner. Skipped
as dominated (and listed, not silently truncated): 1.5x/0.75x
(partial), 1.5x/1x, 2x/0.75x, 2x/1x — the 1.5x and 2x rows are already
slogs at the ship resistance, and raising resistance only makes the
baseline FASTER (less "noticeably slower"), so none can beat 1x/0.5x.

Real player actions (TTK), baseline enemy actions (danger), and the
bad-player vs baseline:

| cell (HP × R) | baseline TTK | fire TTK | badboost TTK | baseline enemyA | baseline dmg-taken |
|---|---|---|---|---|---|
| **1x × 0.5x** | **3.4** | 2.0 | 2.9 | 3.6 | 14.6 |
| 1x × 0.75x | 2.5 | 2.0 | 2.5 | 2.0 | 7.2 |
| 1x × 1x/off | 2.1 | 2.0 | 2.1 | 1.5 | 6.4 |
| 1.5x × 0.5x | 5.5 | 2.0 | 4.5 | 7.1 | 26.6 |
| 2x × 0.5x (was shipped) | 5.7 | 2.4 | 4.9 | 7.0 | 28.7 |

The last row is the pre-sweep shipped cell: baseline 5.7 real actions, 7.0
enemy actions, and 28.7 damage taken — a heavy fraction of solo Terra's
~80–90 HP, the slog the co-tune fixes. Dropping HP to 1x at the same
resistance takes baseline to 3.4 / 3.6 / 14.6.

Band scorecard (F1 fire loop-player TTK 3–5; F2 baseline 1.3–2× fire,
noticeably slower but not a slog; F3 baseline enemyA ≤3; F4 badboost
within 20% TTK / 25% dmg of baseline; the pedagogy ordering is
resistance-set, measured by `bal_dpb`):

| cell | F1 | F2 | F3 | F4 | pedagogy |
|---|---|---|---|---|---|
| **1x × 0.5x** | ✗ | ✓ (1.69×) | ~ (3.6) | ✓ (0.85×/0.92×) | clean 4:2:1 |
| 1x × 0.75x | ✗ | ✗ (1.25×) | ✓ | ✓ | flatter 2.6:1.9:1 |
| 1x × 1x | ✗ | ✗ (1.06×) | ✓ | ✓ | collapsed 1.95:1.9:1 |
| 1.5x × 0.5x | ✗ | ✗ (2.75×) | ✗ (7.1) | ✓ | clean 4:2:1 |

**No cell satisfies all four bands, and it is not a tuning failure.**
F1 (fire loop-player 3–5 actions) fails in EVERY cell because fire
one-shots the fragile trash (Vaporite ~15 HP, Were-Rat 24 HP, both
fire-weak) — the loop-player is 2 actions everywhere, and no HP
multiplier in the tested range fixes it (Vaporite would need ~22×,
Were-Rat ~14×). This is Measurement #1/#3's "the loop cannot express
vs intro trash," inherited: trash breaks and true loop-expression
arrive with M6 class-weakness authoring, not with an HP dial.

### Shipped values and rationale

`Ot6HpMulTbl` band0 $20 → **$10 (1x)**, band1 $20 → **$10 (1x, tracks
band0)**; `Ot6ShieldedMulW` **$0008 (0.5x, unchanged, finalized)**.
Table now $10/$10/$10/$10.

- Resistance 0.5x is the primary call: it gives the cleanest
  damage-per-BP ladder (4:2:1), which is Measurement #5's whole point.
  0.75x/1x flatten it (at 1x a weakness hit ties a broken one).
- At 0.5x resistance, HP 1x is the only band0 that keeps the baseline
  loop-IGNORER "noticeably slower than the loop but not a slog" (3.4 =
  1.69× fire; 1.5x → 5.5 = 2.75× = slog, F2/F3 fail). It also makes the
  bad-player ≈ baseline (badboost 2.9 vs baseline 3.4, 0.85× TTK; dmg
  13.5 vs 14.6, 0.92×) — the BP is nearly wasted, versus the fire loop
  at 2.0 (0.59×). The one miss is danger (baseline enemyA 3.6 vs ≤3),
  and it is marginal against a SOLO L5 Terra who loses only ~14.6 HP of
  her ~80–90 (she ends every fight above two-thirds); a real party
  spreads that further.
- The multiplier had lengthened fights by inflating EVERY player's HP
  bar equally, which did not reward the loop. Shielded resistance
  lengthens only off-weakness fights — the loop-ignorer runs ~2×
  longer while a weakness-exploiter stays vanilla-fast, which is the
  Octopath feel. So resistance REPLACES the HP multiplier as the
  fight-lengthener; the multiplier stands down to 1x.
- 1x HP + 0.5x resistance puts the baseline fight at ~2× vanilla
  length, which is the regime Measurement #4's danger/reward knobs were
  tuned for — so the pace economy stays valid WITHOUT retuning it.
  **UNSOURCED:** this bullet carried "1703 vs ~744 frames", and 1703
  appears in no grid table and no surviving `build/states/bal_*.log`
  (the one surviving baseline arm logs `frames=736`, whose config is not
  recorded). Every other headline number in this doc traces to a table
  or a driver; this one does not, and it is the sole basis for NOT
  re-sweeping danger/reward after the HP multiplier retired. Re-run the
  1x×0.5x baseline arm of `bal_mines.lua` and read `frames` from the log
  before relying on it. Band1 tracks band0 to 1x so that regime is
  uniform across bands (a mixed 1x/2x table would put mid-trash at ~4×
  length and under-conserve encounters there). Band1 mid-trash stays
  unmeasured — parity extrapolation, stretch fixtures pending.

Gate: full suite green twice at these values, story-chain fixtures
re-minted. No battle-test bound moved: every gate fixture is an
authored (HP-exempt) species or party HP, and the resistance constant
is unchanged, so battle_break's ~4× ratio and battle_bp's boost
numbers stand as-is.

### Whelk re-check at the shipped resistance (`whelkbal_run.lua`)

The Whelk head ($0134) and shell ($0100) are authored species, exempt
from the HP multiplier, so only the (unchanged) 0.5x resistance
touches this fight; the head arrives at its first break window with
more HP because pre-break damage is halved. Tutorial + pierce
policies, boss untouched (shields/HP/fire-add are a separate decision).
The wall-clock cap truncated the runs mid-fight, so n is 3 (tutorial) /
4 (pierce); the tutorial result is consistent across all three:

| policy | windows/fight | uptime | won | TTK (beam/tek casts, won) | notes |
|---|---|---|---|---|---|
| tutorial | **1.0** | ~13% | 3/3 | ~6 beams + 1–2 teks | 4 chips → break every fight; the designed line completes |
| pierce | 0.5 | ~14% | 2/4 | ~3 teks | 2 Terra deaths to shell MegaVolt counters (the Measurement #2 danger) |

Resistance is load-bearing for getting even ONE window: the head arrives
at the break with more HP (pre-break damage halved), so the tutorial's
four chips (three fire beams on the fire-weak head + one TekMissile)
land the break BEFORE the raw damage kills it — Measurement #2 had the
head dying "one chip short" pre-resistance (0 windows). But the party's
broken-window nuke (×2) then finishes the fight INSIDE that first window,
so a second break cycle never happens. So resistance alone moved the
Whelk from 0 → ~1 window, ~13% uptime — still short of the ~2-window /
20–30% boss band. Closing to 2 windows needs a boss HP/shield bump
(more head HP so the broken window can't one-shot it), which is a
separate decision and was NOT done here. The designed tutorial line
completes reliably at the shipped resistance.

## Measurement #6 — the first PARTY numbers, and the instrument that got them (2026-07-18)

Every instrument before this one drove a solo party, so the coverage
rule in `weapon-classes.md` ("the story's actual party chips every
non-boss encounter") was not checkable for any stretch with more than
one character. `metrics_battle.lua` and the new `bal_party.lua` now
drive a party and attribute every stat per member; this section is the
first run of that instrument, and it is a MEASUREMENT, not a tuning
pass. Nothing was changed as a result of it.

**Fixture.** `worldmap_narshe.mss` — LOCKE (battle slot 0, L6,
Fight/Steal/Item) and TERRA (slot 1, L4, Fight/Magic/Item, knowing Fire
and Cure) on the WoB tile `gen_figaro.lua` walks south from. This is the
closest existing state to the Figaro → Kolts stretch and the only
2-character fixture on a map with live random encounters; **it is missing
EDGAR**, whose state is still being minted, so these are two thirds of
the stretch party and the Edgar/Sabin kit rungs are written but
undriven. The pool at that spawn drew one formation in every sample:
species `$0017`, single monster, 33 HP, weak `$81` (fire), 2 shields.

**Protocol.** bal_mines' discipline, unchanged: loadState-independent
battles, `$1FA1` seeded per battle index so battle *k* is the same battle
in every arm (verified — every arm paced identical step counts
89/48/47/35/45/72), danger counter zeroed per sample, phase jitter on
the settle. 4 policies × 2 HP arms × 6 battles = **48 battles, 0 voids,
48 wins, 0 wipes, 0 menu stalls**, and every per-battle identity check
closed to zero.

### Arm A — the pool as it ships

| policy | turns | frames | dmg taken | enemyA | chips | breaks |
|---|---|---|---|---|---|---|
| baseline | 1.7 | 152 | 0 | 0.0 | 0 | 0 |
| boost3 | 2.0 | 361 | 0 | 0.0 | 6 | 0 |
| greedy | 1.5 | 321 | 0 | 0.0 | 6 | 0 |
| badboost | 1.7 | 152 | 0 | 0.0 | 0 | 0 |

Against the bands: TTK **1.5–2.0 vs the proposed 3–5**, danger budget
**0.0 vs ≤3** — the monster never gets a turn at all. Breaks are 0
because the one chip a fire probe lands also kills. This is
Measurement #1's "the loop cannot express vs intro trash" again, one
stretch later and with a party: two characters at L4/L6 delete a 33-HP
world-pool monster before it acts. `badboost` is byte-identical to
`baseline` here for the same reason it was in Measurement #5 — with no
reachable weakness the two policies make the same moves.

### Arm B — the same fixture with monster HP pinned to 400

A synthetic buff (`BUFF_HP`), not a proposal: it exists to make the loop
express so the *instrument* can be read, and it must never be averaged
with Arm A. What it shows is the shape of the loop, not a tuning target.

| policy | turns | frames | dmg taken | enemyA | chips | breaks |
|---|---|---|---|---|---|---|
| baseline | 19.0 | 5711 | 45.7 | 8.5 | 0 | 0 |
| boost3 | 4.0 | 1353 | 7.8 | 1.0 | 12 | **6** |
| greedy | 3.5 | 1343 | 8.3 | 1.0 | 12 | **6** |
| badboost | 12.8 | 4090 | 34.2 | 5.8 | 0 | 0 |

Per character (per-battle averages):

| policy | who | actions | dmg | dmg through break | chips | breaks | BP spent | did |
|---|---|---|---|---|---|---|---|---|
| baseline | LOCKE | 9.5 | 219.8 | 0 | 0 | 0 | 0 | Fight |
| baseline | TERRA | 9.5 | 180.2 | 0 | 0 | 0 | 0 | Fight |
| boost3 | LOCKE | 2.0 | 22.5 | 0 | 0 | 0 | 0 | Steal, Fight |
| boost3 | TERRA | 2.0 | **377.5** | 298.5 | 12 | 6 | 0 | Fire ×2 |
| greedy | LOCKE | 1.5 | 11.3 | 0 | 0 | 0 | 6 | Steal, Fight |
| greedy | TERRA | 2.0 | 388.7 | 161.8 | 12 | 6 | 6 | Fire ×2 |
| badboost | LOCKE | 6.5 | 225.3 | 0 | 0 | 0 | 18 | Fight |
| badboost | TERRA | 6.3 | 174.7 | 0 | 0 | 0 | 18 | Fight |

Findings, stated as measurements:

1. **The loop pays, hugely, and it is the PROBE that pays — not the
   boost.** Weakness-exploiting play is 4.8× faster than ignoring it
   (4.0 vs 19.0 turns) and takes 6× less damage. But `boost3` spent
   **zero** BP in all six fights: the fight ends in two actions per
   character, so the bank never reaches 3. Measurement #1's "boost3 never
   boosts" survives into a party. `boost3` vs `baseline` here therefore
   measures probing, and the boost axis is only isolated by `greedy` vs
   `boost3` (3.5 vs 4.0) and `badboost` vs `baseline` (12.8 vs 19.0).
2. **The break fires but the window never opens.** 6/6 fights broke, and
   `first_break_frame` was the *last* frame of every one of them
   (`break_uptime_frames = 1`). The chip that empties the shields and the
   doubled hit that lands on the newly broken target are the same hit, and
   it kills. Same shape as the Whelk in Measurement #5. The "first break
   by the 2nd–3rd action" band is met; the "uptime 20–30%" band is not
   reachable while the breaking hit is also lethal.
3. **The damage-per-BP ladder reproduces in a live party fight.** A
   traced fight: probe Fire (shielded-weak) 82, Locke's Fight 23, exploit
   Fire (breaks, then doubles) **295**. The 3.6× ratio between a broken
   hit and a shielded-weak one matches `bal_dpb`'s pinned-lab 4:2:1 at
   the shipped 0.5× resistance, now corroborated outside the lab.
4. **greedy again beats boost3** (3.5 vs 4.0), so the "greedy must lose"
   band still fails outside boss fights — consistent with Measurements
   #3 and #5.
5. **`badboost` is worth flagging.** It buys 1.5× TTK over baseline
   (12.8 vs 19.0) by dumping 3-BP Fights into a shielded, unweak target.
   Measurement #5 found badboost ≈ baseline in ~3-turn fights and drew
   the "the BP is nearly wasted" conclusion from it. In a long fight the
   same misplay compounds and pays. Whether "boost feels wasted" is a
   short-fight-only property is a real question for the driver — but note
   this arm is a synthetic 400-HP buff, so it is a question, not a result.
6. **A party spreads damage taken**, as Measurement #5 guessed it would:
   baseline damage is split 25.5 / 20.2 across the two members.

Instrument caveats for whoever reads these numbers next: two thirds of
the stretch party, one formation, a synthetic HP arm, and Edgar/Sabin
kit rungs that have never been driven. Repointing `bal_party.lua` at a
Kolts fixture requires nothing but the `STATE` knob.
