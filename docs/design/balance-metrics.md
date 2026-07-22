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

## Measurement #7 — the resistance sweep that landed nothing, and the reason the break has never happened (2026-07-19)

This one was commissioned as a tuning pass: the playtester's opening
report was "breaking and boosting just don't really matter — too much
damage is making it through," Measurement #6 agreed from the instrument
side (1.5–2.0 turns against a 3–5 band, boost3 spending zero BP), and the
brief was to sweep `Ot6ShieldedMulW` down until the loop mattered.

**Nothing was landed. `Ot6ShieldedMulW` stays `$0008` (0.5x) and so does
every other tuning constant.** Three more playtest reports arrived while
the sweep ran, and together with the numbers they say the resistance
constant is not the problem. What the sweep found instead is why the
break — the mechanic the whole system is named for — has never once
happened in play, and it is not a dial.

### What the instrument grew

`bal_party.lua` said in its own header that pointing it at a Kolts
fixture "requires nothing but the `STATE` knob." That was wrong by one
thing, the pacer: `worldmap_narshe` is on the WORLD map and every
stretch fixture past it is a FIELD map. Both pacers now live in the
driver behind a `FIXTURES` table. Also added: the `POKE_SHIELD`/`POKE_HP`
knob poke with bal_mines' drift guard (verified against this build —
`Ot6ShieldedMulW` still at `$F0034E`), and three metrics the questions
below needed.

`kolts_doorstep` turned out to be unmeasurable and that is worth
recording: map 95 is Mt. Kolts' ENTRANCE map and carries no encounter
group. A run paced **437 tiles across six samples and drew zero
encounters**, voiding every sample as a timeout. `gen_kolts_pool.lua`
crosses gen_kolts' K1 onto map 100 shelf F and mints `kolts_pool.mss`
there; it asserts an encounter actually fires before it calls the fixture
good, because map 95 passed every other check and was still worthless.
The fixture carries the real stretch three — **EDGAR, LOCKE, TERRA** — so
Edgar's Tools rungs are driven here for the first time.

**Break uptime is now a first-class metric**, because "breaks per fight"
is a misleading number on its own: Measurement #6 broke 6/6 fights and
every break landed on the killing blow. `player_actions_broken` counts
player actions that got to land on a broken target — the window, not the
event. The owner's v0.3 target ("the break is the penultimate round, and
we can easily make the kill on broken enemies") is exactly
`player_actions_broken` ≈ 1.

### The sweep — early pool (`worldmap_narshe`, Leafer `$0017`, 33 HP, fire-weak, 2 shields; LOCKE L6 + TERRA L4)

6 battles per cell, paired seeds, 0 voids, 0 residuals. `mash` =
`baseline`, `loop` = `boost3`.

| resistance | mash TTK | loop TTK | TTK gap | mash taken | loop taken | breaks | actions broken |
|---|---|---|---|---|---|---|---|
| 1x (off) | 1.0 | 2.0 | **0.50x** | 0.0 | 0.0 | 0 | 0 |
| **0.5x (shipped)** | 1.7 | 2.0 | **0.83x** | 0.0 | 0.0 | 0 | 0 |
| 0.375x | 2.5 | 2.0 | 1.25x | 5.0 | 0.0 | 0 | 0 |
| 0.25x | 3.7 | 2.0 | **1.83x** | 7.2 | 0.0 | 0 | 0 |
| 0.1875x | 4.7 | 3.0 | 1.56x | 10.5 | 7.8 | 0 | 0 |
| 0.125x | 7.0 | 4.0 | 1.75x | 15.0 | 7.8 | 1.0 | **0** |

Two things read straight off this table. First, **at the shipped value
the loop LOSES to mashing on the early pool** (0.83x — the probe turn
costs more than the weakness buys), and at 1x it loses twice as badly.
That is the playtester's first report, quantified: on early trash,
breaking and boosting really do not matter, because they are strictly
worse than holding A. Second, **no resistance produces a break window.**
`player_actions_broken` is 0 in all 144 battles; at 0.125x the one break
that fires lands at 100% of fight length — the killing blow, again.

### The Kolts corroboration (`kolts_pool`, all at the shipped 0.5x)

Then three more playtest reports landed: Kolts killed Locke and forced a
grind; then, at L8–9, "hard if i don't boost, but easy if i do... maybe
we've got the balance just right." The Kolts numbers agree, hard:

| policy | TTK | taken | enemy actions | chips | breaks | result |
|---|---|---|---|---|---|---|
| baseline (mash) | 8.2 | **224.7** | 9.0 | 0 | 0 | **3 won / 3 WIPED** |
| boost3 (loop) | 7.3 | 136.3 | 5.8 | 1.0 | 0 | 6 won |
| greedy | 6.2 | 128.2 | 4.2 | 0.5 | 0 | 6 won |
| badboost | 8.0 | 220.3 | 7.5 | 0 | 0 | **3 won / 3 WIPED** |

**Mashing wipes half of all Mt. Kolts encounters; engaging the loop wins
every one and takes 40% less damage.** The gap the driver asked for is
here — it just is not a TTK gap (1.11x), it is a *survival* gap, and a
player feels that as "hard if I don't boost, easy if I do." The shipped
constant is doing its job on this stretch. Lowering it would lengthen the
losing arm and deepen a hole the playtester already fell into.

So the resistance sweep's honest verdict is: **the early pool's problem
is not resistance, and the Kolts stretch does not want it touched.** Held
at 0.5x.

### The break, and why it has never happened

Two Kolts formations, both 3 shields: **Brawler `$000B`** (137 HP, weak
ICE) and **Tusker `$007A`** (270 HP, weak FIRE). The party is Edgar,
Locke, Terra; Terra knows Fire and Cure. So half this pool has *no
reachable weakness at all* — nobody carries ice — and against the other
half only Terra chips. Measured: `shield_chips` peaks at 2 of the 6 a
formation needs, and **breaks are 0 across all 24 battles.**

That is the whole answer, and it is a chip-RATE problem, not a threshold
problem. The proof is the shield arm: re-run with trash shields forced
from 3 to 2 and the mash arm is **byte-identical** to the shipped one
(8.2 TTK, 224.7 taken, 0 chips, 3 wipes). Lowering a bar changes nothing
when nobody can reach it — every non-authored species takes the
`@formula` path, which explicitly *clears* `$3e9c`, so **no formula
species has any class weakness and Locke's Fight and Edgar's
AutoCrossbow can never chip anything.**

The synthetic arm settles what authoring would buy. `BUFF_CLASS` ORs a
class mask into `$3ea4` at battle start — an authored `Ot6ShieldTbl` row
without the row. One PIERCE bit on the Kolts trash, resistance untouched
at 0.5x:

| Kolts arm | policy | TTK | taken | chips | breaks | break at | uptime | **actions broken** | result |
|---|---|---|---|---|---|---|---|---|---|
| as shipped | baseline | 8.2 | 224.7 | 0.0 | 0.0 | — | 0.0% | **0.0** | 3 won / 3 wiped |
| as shipped | boost3 | 7.3 | 136.3 | 1.0 | 0.0 | — | 0.0% | **0.0** | 6 won |
| shields 3→2 | baseline | 8.2 | 224.7 | 0.0 | 0.0 | — | 0.0% | 0.0 | 3 won / 3 wiped |
| **+PIERCE** | baseline | **5.8** | **92.7** | 6.0 | 2.0 | 39% | **62.2%** | **1.0** | **6 won** |
| **+PIERCE** | boost3 | 6.5 | 92.7 | 5.5 | 1.5 | 75% | 28.1% | **1.2** | **6 won** |
| +PIERCE | greedy | 5.2 | 91.3 | 3.8 | 1.0 | 96% | 4.3% | 0.2 | 6 won |
| +PIERCE | badboost | 7.5 | 137.3 | 6.0 | 2.0 | 48% | 53.6% | 1.3 | 6 won |

One authored bit turns the break from never-happening into the shape the
owner asked for: **breaks 0 → 2.0 per fight, uptime 0% → 62%, and
`player_actions_broken` = 1.0 — the kill landing on a broken enemy, which
is the v0.3 target stated exactly.** It also makes the stretch *safer and
shorter*, not harder: TTK 8.2 → 5.8, damage taken 224.7 → 92.7, wipes 3/6
→ 0/6. And the window carries the damage economy the way the design
wanted — 235.5 of Edgar's 302 damage (**78%**) lands through it.

**Why the class channel and not the element channel.** `Ot6ClassChip` is
explicit: "no vanilla x2 on a class-weak hit — the damage bonus for
classes is the break window itself." So the hit that empties the shields
is *4x base* through the element channel (vanilla weak x2, then broken
x2) and only *2x base* through the class channel. That factor of two is
the difference between a monster that survives its own break and one that
does not, and it is why every break measured so far has been a killing
blow: they were all Terra's Fire. The condition, from the measured
numbers, is **HP > (S-1)·c·R + 2c** for a chipper hitting for `c` — with
Locke's Fight at c≈45, R=0.5, S=3 that is HP > ~135. Live: the window
opened on Tusker (270 HP) in 3/3 fights and never once on Brawler (137
HP), which is that threshold landing exactly where the arithmetic puts
it.

### What this rules out, and what it asks for

- **Resistance is not the lever for the early pool.** Leafer has 33 HP
  and one Terra Fire does ~82 base; the breaking hit is 4x that. The
  monster would need ~10x its HP to survive its own break — the same
  order Measurements #3 and #5 computed independently (Vaporite ≥31x,
  Were-Rat ≥19x, ~22x, ~14x). Confirmed live: authoring a class row onto
  the early pool *does* produce breaks (0.7/fight) but they still land at
  **100% of fight length** and `player_actions_broken` stays **0**.
  Early trash cannot express the break window at any setting of any knob
  measured here. It is too small to survive being broken.
- **Shield count is not the lever** while the chip rate is zero — proven
  by the byte-identical 3→2 arm above. It becomes a real lever *after*
  class rows exist, and should be tuned then, not now.
- **The HP dial stays retired.** Nothing here re-opens it: at Kolts the
  HP that matters is already there (270 HP produced the window unaided),
  and at the early pool the required multiplier is ~10x, which
  Measurement #5 already showed is a slog.

**What to author** (the driver asked to be handed species): the two Mt.
Kolts trash species, **`$000B` Brawler** and **`$007A` Tusker**, plus the
world-map trash **`$0017` Leafer** for the Narshe/Figaro stretch — noting
that Leafer buys chips and reveals but *cannot* buy a window at 33 HP.
`$0019` Lobo already has a row (3, PIERCE); these do not.

One design caveat, measured and worth stating before anyone authors:
**the class you choose decides whether the break is discovered or
stumbled into.** PIERCE is what Edgar's AutoCrossbow and Locke's dagger
already swing, so authoring PIERCE made the *mash* arm chip by accident —
which is why the mash-vs-loop gap CLOSES in that arm (1.11x → 0.90x TTK).
Both arms got much better in absolute terms, so this is not a regression;
but a class the party's default attack does not already carry is what
makes the probe a real decision rather than a freebie.

### What remains unmeasured

- **The grind question, untouched.** The playtester reached the good
  Kolts experience at L8–9, but only after dying and backtracking. Nobody
  has measured whether natural progression *delivers* L8–9 by Mt. Kolts,
  and if it lands players at L6–7 the fight is unfair by default and the
  fix is the `Ot6DangerMulW`/`Ot6RewardMulW` pair (product pinned at 1.0),
  not resistance. `mines_pace.lua` is the instrument; this needs a
  stretch-length route, not a per-battle fixture.
- **Vargas and the boss band.** `vargas_doorstep` exists and was not
  driven here; the playtester liked the fight ("managing boosts weaknesses
  was helpful") but reported breaks still not mattering. Vargas is
  authored (5, BLUDG) so he is the one fight where the class channel
  already exists — the natural next measurement.
- **South Figaro.** `south_figaro.mss` is map 75, the town, and carries no
  encounter group; the cave (maps 71/73/70/72) is the pool for that
  stretch and has no fixture.
- The Kolts pool as sampled is two formations from shelf F. Deeper
  shelves (D, B) and the Sabin-era party are unmeasured.
- `greedy` still beats `boost3` on TTK in every cell measured, at both
  pools — the "greedy must lose" band has now failed in Measurements #3,
  #5, #6 and #7 and should probably be restated as a boss-fight property
  or dropped.

## Measurement #8 — the trash weakness pass: the break made reachable (2026-07-19)

Measurement #7 ended by naming three species to author and one caveat
about which axis to author them on. This is that pass, and the first
thing it did was re-derive the pools instead of trusting the three
names — which turned out to matter, because the Mt. Kolts pool is
**four** trash species, not two, and the one Measurement #7 never saw is
the most common enemy on the mountain.

### The enumeration, from the tables rather than from a fixture

The chain is `SubBattleGroup[map]` → `RandBattleGroup[group*8]` (four
formation words, drawn at 31.25/31.25/31.25/6.25%) →
`BattleMonsters[formation*15]` → `MonsterProp[species*32]`, all read
straight out of `ff6/src/field/battle.asm:391-406` and
`battle_main.asm:8005` / `:7316`. Levels and HP from `+16` and `+8`;
weak/null/absorb re-derived at `+25`/`+24`/`+23` (`battle_main.asm:7517`
and `:7564`, the latter a 16-bit load, so `+23` is absorb and `+24` is
null).

**Two map-property corrections fall straight out of it, and one of them
is in this document.** Measurement #7 recorded that Mt. Kolts map 95
"carries no encounter group" after pacing 437 encounterless tiles there.
It carries group 61. What it does not carry is the enable bit: map
properties are 33 bytes at `map_prop.dat[map*33]` and byte 5 bit 7 is
the random-battle enable `CheckBattleSub` tests at `battle.asm:332`
(`lda $0525 / bpl Done`). Map 95 reads `$00`. Same for map 74, which
carries group 59 and cannot draw it either. The observation was right and
the mechanism was wrong; `kolts_pool` was still the correct fixture to
mint.

The stretch the v0.2 demo ships, pool by pool. Shields are the seed
formula 2 + level/8 unless a row says otherwise:

| Where | Map/group | Species | L | HP | Shld | vanilla weak | null | absorb |
|---|---|---|---|---|---|---|---|---|
| WoB north grass/forest | groups 0, 2 | Leafer `$0017` | 5 | 33 | 2 | fire\|water | — | ice |
| " | " | Dark Wind `$0028` | 5 | 34 | 2 | fire | — | — |
| WoB desert (Figaro) | group 1 | Sand Ray `$005C` | 6 | 67 | 2 | **ice\|water** | — | — |
| " | " | Areneid `$005D` | 6 | 87 | 2 | **ice\|water** | — | — |
| S. Figaro cave | maps 72/73, groups 59/60 | Hornet `$002E` | 6 | 92 | 2 | fire | — | — |
| " | " | Bleary `$0063` | 7 | 119 | 2 | fire | — | — |
| " | " | Crawly `$0062` | 7 | 122 | 2 | fire | — | — |
| WoB south grass/forest | groups 3, 4 | Rhodox `$0012` | 7 | 119 | 2 | **none** | — | — |
| " | " | Rhinotaur `$0015` | 8 | 232 | 3 | **none** | — | bolt |
| " | " | GreaseMonk `$00A8` | 8 | 132 | 3 | poison | — | — |
| Mt. Kolts caves | maps 96/97, group 61 | **Cirpius `$0086`** | 10 | 134 | 3 | **none** | — | — |
| Mt. Kolts, everywhere | groups 61/62/63/64 | Tusker `$007A` | 10 | 270 | 3 | fire | — | — |
| Mt. Kolts shelves | map 100, group 63 | Brawler `$000B` | 9 | 137 | 3 | ice | — | **poison** |
| Mt. Kolts Vargas side | maps 98/99/102, group 62 | Trilium `$0032` | 9 | 147 | 3 | fire | — | water |
| Mt. Kolts map 101 | group 64 | Vaporite `$0046` | 5 | 15 | 2 | fire\|pearl | — | bolt |

Formation shapes that matter: group 61 is **Cirpius ×3** at 93.75% of
draws (the fourth slot adds a Tusker), group 63 is Brawler-pair 62.5% /
Tusker-pair 37.5%, group 62 is Trilium-pair 62.5%. None of these fifteen
species had an authored row; `$0019` Lobo (3, PIERCE) is the nearest one
and it belongs to the Narshe intro.

**Six of the fifteen had no key the stretch party could reach.** Cirpius
and Rhodox have no vanilla weakness at all; Sand Ray and Areneid are
ice|water; Brawler is ice; Rhinotaur has none. Measurement #7 reported
Kolts as "half this pool has no reachable weakness"; across the whole
stretch it was worse than that, and the worst single case is Cirpius,
because *three at a time at 93.75%* means the mountain's most common
fight was three unchippable birds.

### The design problem, and why the axis is elements

A weakness only creates a decision if the party cannot hit it by
accident. Measurement #7's synthetic PIERCE arm proved the failure mode:
authoring a class the party already swings made the **mash** arm chip,
and the mash-vs-loop gap closed from 1.11× to 0.90×.

Reading the actual starting equipment says the strict version of that
rule is **unsatisfiable on this stretch by any class row**. Terra carries
a Mithril Knife and Locke a Dirk — both PIERCE (`ot6_class.asm:49,:48`)
— and Edgar a Mithril Blade, SLASH (`:59`); `char_prop.asm:152,:162,:197`.
So the party's three default swings already cover half the class ring,
and the other half has no wielder: bludgeoning arrives with Sabin, who
joins at the *top* of the mountain, and special not until Setzer. Every
class row here is a freebie or a Repo Man.

The element axis is not degenerate, and it is genuinely deliberate:
Terra's Fire costs 4 MP and a Magic menu, Edgar's Bio Blaster costs a
Tools dive, and neither is what the A button does. There are exactly two
live keys — Terra's natural list is Cure 1 / Fire 3 / Antdot 6 / Drain 12
(`field/event.asm:1248`), so fire is her whole offensive ring here, and
poison is the Bio Blaster the Figaro shop sells and `gen_kolts.lua:594`
verifies is still carried at the mountain.

**And only one of those two keys can open a window, which is arithmetic,
not taste.** An element chip that empties the last shield takes vanilla's
weak ×2, then skips `Ot6ShieldedDmg` (shields are already 0), then takes
`Ot6BrokenDmg`'s ×2 — **4× base on the breaking hit itself**. Terra's
Fire is ~110 base here, so her break is ~440 and nothing on this mountain
except Tusker has the HP to survive it. Bio Blaster is power 20 spread
over the whole enemy side (`magic_prop_en.dat` record `$7d`: element
`$08`, targeting `$6a`, 0 MP), so its per-chip damage is a fraction of
that. **Fire is the finisher; poison is the opener.** That is the whole
shape of the pass.

### What was authored, and why, per species

Six `Ot6ElemAddTbl` rows and one `Ot6ShieldTbl` row. Every one was
checked at `+23`/`+24` before authoring, the discipline the boss rows are
held to; five read `$00/$00` and Rhinotaur absorbs bolt, not poison.

- **Cirpius `$0086` → +poison, and an `Ot6ShieldTbl` row `2, $00`.** The
  flagship. It had no weakness of any kind, it is 93.75% of the cave
  draws, and it comes in threes — and Bio Blaster targets the whole enemy
  side, so one deliberate action chips the entire flock. Strictly
  deliberate: no default swing in the party is poison, and Terra's Fire
  cannot touch it either. The shield row carries no class byte at all; it
  exists only to take the count off the formula (see the sweep below).
- **Tusker `$007A` → +poison keeping vanilla fire, and `2, $00`.** 270 HP
  is the widest window on the mountain. Fire stays the burst answer to a
  270-HP wall; poison becomes the break answer; the player picks which.
- **Brawler `$000B` → `Ot6ShieldTbl` row `2, OT6_SLASH`.** The one class
  row on the stretch, and it is here because Brawler **absorbs poison**
  (`monster_prop.dat +$0177 = $08`) — the answer the rest of the mountain
  teaches would *heal* it — while its vanilla ice has no wielder until
  Celes. Slash rather than pierce because slash is the **scarce** key:
  Edgar's Mithril Blade is the party's only slashing weapon, so a Brawler
  is the fight where Edgar closes the Tools menu, a move nothing else on
  the mountain asks for.
- **Sand Ray `$005C`, Areneid `$005D`, Rhodox `$0012`, Rhinotaur
  `$0015` → +poison, element rows only.** Coverage, on the overworld
  either side of South Figaro. Three had no reachable key at all. The
  pedagogy lines up: you buy the Bio Blaster at Figaro and the desert
  immediately outside is where it starts paying. No shield rows — there
  is no fixture on those maps, and setting a count nobody has measured is
  how the HP dial got shipped twice.

### The shield count is the lever, and this is the sweep that set it

Measurement #7 predicted this: "shield count is not the lever *while the
chip rate is zero* — it becomes a real lever after class rows exist, and
should be tuned then, not now." Now is then, and it turns out to be the
lever that decides whether the break is a *window* or a *funeral*.

A break opens a window only if the target still has more HP than the
**breaking hit** — and the breaking hit is large, because the chip that
empties the last shield skips `Ot6ShieldedDmg` (shields are already zero)
and then collects `Ot6BrokenDmg`'s ×2. Through the element channel that
is 4× base; through the class channel 2×. Measured bases for this party:
Terra's Fire ~110, Edgar's Bio Blaster ~87 per target on a poison-weak
body, Edgar's Mithril Blade ~42. So the shield count is really the
question *how late does the break land*, and the party's own damage is
the clock.

Swept live with `bal_party`'s `BUFF_SHIELDS` against the real pools, 6
battles a cell, `boost3`:

| shields | Cirpius ×3 | Tusker ×2 | Brawler ×2 |
|---|---|---|---|
| **3** (the formula) | break at 100%, **actions broken 0** | break at 100%, **0** | break at 71%, **0** |
| **2** (authored) | break at 78%, **actions broken 1.0** | break at 51%, **1.0**, uptime 20.5% | break at 100%, **1.0** |
| **1** | — | break at 53%, **0** | break at 72%, **0** |

The formula's 3 is one chip too many: the party has already spent the
monster by the time the last shield falls, so the break lands on a
corpse. That is what "breaks 6/6, uptime 1 frame" meant in Measurements
#5 and #6, now restated with a cause rather than as a curiosity. And 1 is
one too few for the *element* channel: with no earlier chip to soften it,
4× base (~350) simply exceeds a 270-HP Tusker outright, and the break is
the kill again. **2 is the count at which the loop exists**, on all three
bodies, and it sits inside `weapon-classes.md`'s trash band of 1–3.

**Deliberately left alone, so the next author does not re-litigate.** The
seven already-fire-weak species (Leafer, Dark Wind, Hornet, Bleary,
Crawly, Trilium, Vaporite) satisfy the coverage rule through Terra
already; a second key would make the probe a formality. None of them can
hold a window either — 33 to 147 HP against a 4× breaking hit — and
Measurement #7 proved that directly on Leafer: a synthetic class row
there produced 0.7 breaks a fight and every one landed at 100% of fight
length with `player_actions_broken` still 0. **Intro and cave trash stay
texture, not tuning material**, the disposition Measurement #1 gave the
mines pool. GreaseMonk is already poison-weak in vanilla and an add would
be a no-op `ora` that lies about who authored it.

**The coupling, stated because it is a real cost.** An `Ot6ShieldTbl` row
also exempts its species from `Ot6HpScale`. That is inert today (every
band ships `$10` = 1×) but real if the HP dial ever reopens, and it would
make the three Kolts species that carry rows the only ones that do not
scale with their pool-mates. It is also why the four overworld species
took element rows only: **an `Ot6ElemAddTbl` row carries no such
exemption**, so where a species needs a weakness but not a shield count,
the element table is the cheaper instrument. These three need the count.

### What the instrument grew, and four ways it had been lying

None of the numbers below could be taken until `bal_party.lua` was fixed
in four places. Three of them were latent because no earlier fixture
could expose them; all four are the kind that produce a plausible table
rather than an obvious failure.

1. **The poison rung read the wrong element bit.** Edgar's Bio Blaster
   rung gated on `anyRevealed(0x20)` — that is **pearl**. Poison is
   `$08` (`Ot6Chip` walks the mask from bit 0, ot6.asm:627; the armor
   line's own rows read `$08`). The rung had never been driven, so the
   wrong bit had never cost a measurement. It would have cost this one.
2. **The probe rungs were circular.** `bio` waited for poison to be
   *revealed*, and the only thing in the party that casts poison is the
   Bio Blaster itself, so it could never fire. Edgar now spends probe
   turns the way Terra spends one on Fire and Locke one on Steal — and
   the gate is "nothing **Edgar** can exploit is known", not "nothing at
   all is known", because he can do nothing with a revealed *fire* and
   the board-wide gate let Terra's probe stop his before he opened Tools.
3. **`H.battleLoadStarted()` reads party slot 0's HP** (`M.BATTLE_HP =
   $3BF4`, lib/ot6.lua:301,:336) and calls a zero there "no battle". On
   `kolts_pool` slot 0 is **EDGAR**, and a Tusker pair kills him in four
   enemy actions — so the driver declared `torn_down` and abandoned
   battles that were still being fought: **9 of 48 samples in the first
   sweep**, each cut at the exact frame Edgar fell, with TTK, damage
   taken and the win/loss ledger truncated with it. The teardown probe
   now scans all four slots. Left local to the driver: 24 gate tests call
   the shared helper and none of them has a slot-0 death.
4. **`break_uptime_frames` was counting corpses.** The broken timer is
   `$10` ticks decremented on the monster's own turn (ot6.asm:20, :1140),
   so a monster that breaks and *dies to the breaking hit* never ticks it
   down — the body stays "broken" for the rest of the fight and every
   frame was counted as uptime. It reported **58% uptime on a Brawler
   pair where `player_actions_broken` was 0**, i.e. where the window did
   not exist at all. That is the worst possible failure mode for this
   metric, because break-and-die is precisely the pathology it exists to
   detect. Uptime now requires the broken monster to be alive, as
   `player_actions_broken` always did. **Every uptime figure in
   Measurements #5–#7 should be read as an upper bound.**
5. And one modelling fix: **reveals are now sticky for the battle.**
   `$3E91`/`$3EA5` are per-monster cells, so chipping the first of a pair,
   learning its weakness and killing it made the board read unread again
   — Edgar's exploit rung then failed its gate and dropped him to
   AutoCrossbow for the rest of the fight. No player forgets a weakness
   because the monster that taught it fell over, and the codex does not
   either.

Also new: the `mash` policy (literally hold A — every character Fights
with what is equipped, nobody boosts, nobody opens a menu), because
`baseline` is a fine denominator but is *not* a masher: it lets Edgar
fall through to AutoCrossbow, which swings PIERCE where a masher swings
his Mithril Blade's SLASH. The "does the mash arm chip by accident?"
question cannot be asked of `baseline`. And a fixture: **`kolts_cave`**
(map 96), because `kolts_pool` is map 100 and that is one of Mt. Kolts'
*four* encounter groups.

### The measurement — before and after, on the same mint

Both arms run against the **same savestate**, the same seeds and the same
party; the only difference between them is the authored bytes, switched
off in the loaded ROM image by `bal_party`'s new `POKE_AUTHORING` knob
(the six `Ot6ElemAddTbl` rows hidden behind an early `$FFFF`, the three
`Ot6ShieldTbl` rows made inert with a species id of `$0FFF`). That is a
better experiment than two builds, because the fixture is minted by
*playing the game* and a ROM where the trash has weaknesses is a ROM
where the mint's own fights go differently. Measurement #4 established
the equivalence of poking the loaded image to rebuilding.

Two fixtures, 6 paired battles a cell, **48 battles, 0 voids, 0 nonzero
residuals, 0 menu stalls**. `mash` is the new literal-hold-A policy;
`loop` is `boost3`.

**`kolts_cave` — map 96, group 61. Cirpius ×3 (4 of 6 draws) and
Tusker + Cirpius ×3 (2 of 6).** The mountain's most common fight, never
measured before this pass.

| arm | TTK | **actions broken** | uptime | break at | damage taken | chips | breaks | result |
|---|---|---|---|---|---|---|---|---|
| mash, before | 14.2 | 0.0 | 0% | — | 243.3 | 0.0 | 0.0 | 3 won / 3 lost |
| mash, after | 14.2 | 0.0 | 0% | — | 243.3 | 0.0 | 0.0 | 3 won / 3 lost |
| loop, before | 9.2 | 0.0 | 0% | — | 170.7 | 0.0 | 0.0 | 5 won / 1 lost |
| **loop, after** | **8.0** | **1.2** | **16.7%** | 83% | **117.5** | **4.7** | **1.8** | **6 won / 0** |

**`kolts_pool` — map 100, group 63. Brawler ×2 (3 of 6) and Tusker ×2
(3 of 6).**

| arm | TTK | **actions broken** | uptime | break at | damage taken | chips | breaks | result |
|---|---|---|---|---|---|---|---|---|
| mash, before | 10.0 | 0.0 | 0% | — | 233.3 | 0.0 | 0.0 | 3 won / 3 lost |
| mash, after | 9.2 | 0.0 | 0% | 62% | 210.2 | 1.8 | 0.8 | 3 won / 3 lost |
| loop, before | 7.8 | 0.0 | 0% | — | 151.5 | 1.5 | 0.0 | 6 won / 0 |
| **loop, after** | **7.5** | 0.0 | 2.7% | 57% | **138.3** | **3.0** | **1.0** | 6 won / 0 |

Five things read off those two tables.

1. **The break happens, and it is the shape the owner asked for.** On the
   cave pool `player_actions_broken` goes **0.0 → 1.2**: the kill lands on
   a broken enemy. Breaks 0 → 1.8 a fight, uptime 0% → 16.7%, and 16% of
   the party's damage now arrives through the window. On the four-monster
   draw (Tusker + Cirpius ×3) it is **2.0 actions broken and 27.8%
   uptime** — the widest window measured anywhere outside a boss.
2. **The mash arm does not chip the element rows, and the logs are
   identical line for line.** Diffing the cave's two mash arms, the only
   lines that differ are the ones reporting the *input* — `mon_detail`
   reads `weak00:sh3/3` before and `weak08:sh2/2` after. Every outcome
   metric across all six battles is the same number, with a single frame
   of drift in one of them (`frames=2441` vs `2440`). Note that even the
   shield COUNT changed, 3 → 2, and the masher's fight did not move:
   poison is reachable only through a Tools dive, so a player holding A
   never touches the gauge at all. That is the requirement the PIERCE
   experiment failed, met exactly.
3. **The one class row is chipped by mashing, and it is named rather than
   hidden.** On the shelf pool the mash arm goes 0.0 → 1.8 chips and
   0.0 → 0.8 breaks, because Edgar's Mithril Blade swings SLASH whether
   or not anyone meant it to. It buys the masher 10% off the clock and
   23 HP; it does not save a single Tusker fight. This is the freebie horn
   of the design problem, priced.
4. **The stretch got safer when played well, and no harder when played
   badly.** Loop-arm damage taken falls 170.7 → 117.5 on the cave (−31%)
   and 151.5 → 138.3 on the shelf (−9%); the cave's loop arm goes from 5
   wins and a loss to **6 and 0**. The mash arm's wipe count is unchanged
   in both pools (3/3 and 3/3). Nothing in this pass makes Mt. Kolts
   harder or asks for a grind.
5. **The mash-vs-loop gap WIDENED where the axis is clean, and narrowed
   slightly where it is not.** On the cave — poison only — before: 1.54×
   on time and 1.43× on damage taken; after: **1.78× on time and 2.07× on
   damage**, plus 3 wipes against 0. Mashing did not get worse, the loop
   got better, which is the only direction this system should ever move.
   On the shelf pool, where Brawler's class row leaks chips to the
   masher, the gap goes the other way by a hair: 1.28× → 1.23× on time,
   1.54× → 1.52× on damage. That is the PIERCE experiment's failure in
   miniature, confined to one species out of the seven authored, and it
   is the price of the only body on the mountain whose answer could not
   be an element.

### What is still not right, said plainly

- **Brawler's window does not open.** 137 HP against an 84-point breaking
  hit has the margin in principle, but Terra and Locke spend it before
  Edgar's second swing lands, and against a *pair* his two chips
  frequently land on different Brawlers so neither breaks: 2.0 chips, 0
  breaks in the loop arm. The row still buys the reveal, the chips and —
  when mashed, where Edgar swings every turn — a real break (3.7 chips,
  1.7 breaks). What would close it is a slashing carrier whose per-hit
  damage is small enough to chip twice cheaply: Cyan's Flurry, Edgar's
  Chainsaw. Neither exists at Mt. Kolts. **This is outside the data
  tables and I did not invent a weapon to fix it.**
- **Tusker on the shelf pool gets breaks but almost no window** (2.0
  breaks, 4.7% uptime, 0 actions broken) while the *same species* in the
  cave's four-monster draw gets 2.0 actions broken. The difference is
  focus: with two monsters the party's damage concentrates and spends the
  break margin, with four it spreads. Formation size is a real variable
  in this system and nothing has ever tuned against it.
- **The overworld rows are unmeasured.** Sand Ray, Areneid, Rhodox and
  Rhinotaur have no fixture — the WoB desert and the South Figaro plains
  are not on any minted state. Those four rows are coverage fixes made
  on the same reasoning as the Kolts ones, and they should be measured
  before anyone claims a number for them.
- **The probe ORDER matters more than expected, and the instrument has to
  pick one.** Leading with the blade and leading with the Bio Blaster are
  different fights: tool-first opens every Brawler encounter by *healing*
  both of them (75–86 HP, reported as `monster_heal`) but reaches the
  poison species a turn sooner (Cirpius uptime 21.2% vs 9.8%). A real
  player reads the body and leads correctly per species; the driver
  cannot, so it leads with the free probe. Both orderings were measured
  and the difference is recorded here rather than averaged away.
- The early pool is untouched and **provably so**: `worldmap_narshe`
  (Leafer) runs byte-identical with the authoring on and off, which is
  the regression control for this pass.
- **Fixture provenance, stated.** `kolts_pool` and `kolts_cave` were
  minted from a ROM that differed from the shipped one by the three
  shield-count rows settled at the end of the sweep. The paired design is
  unaffected — both arms of every comparison read the *same* state — but
  the absolute numbers may shift by a little on a fresh mint, which the
  content gate will force the next time anyone runs `make frontier`.

## Measurement #9 — the search-for-Terra → Zozo pass: the town made a loop, the boss left alone, the corridor named (2026-07-21)

Measurement #8 authored the break onto Mt. Kolts with Terra in the party.
This is the same author-then-MEASURE loop one stretch later, and the party
has changed underneath it: **Terra is GONE — she is the search target — and
the stretch runs on LOCKE + CELES + EDGAR + SABIN.** That single fact sets
the whole pass. The two DELIBERATE keys (the ones the A button does not
swing) are **poison** = Edgar's Bio Blaster and **ice** = Celes; there is
**no native fire at all**, so every fire-only body on the route is a dead
weakness for this party — the fire hole, flagged where it bites below.

### What the instrument grew

`bal_party.lua` could not drive this stretch as it stood, in four ways:

1. **No CELES kit.** The KITS table had Terra/Locke/Edgar/Sabin; Celes fell
   to Fight-only, so ice — half the stretch's reachable answers — was never
   cast. Added `[0x06]` CELES: an ice exploit rung and an ice probe rung
   (Ice2 if she owns it, else Ice — natural list Ice 1 / Cure 4 / Ice2 26 /
   Ice3 42), the exact twin of Terra's Fire kit, plus the `weak_ice` gate
   (element bit `$02`).
2. **No boss trigger.** Dadaluma is a talk-fired event battle, not a random
   encounter, so the pacer could never reach it. A `trigger = "talk"` lane
   faces the gentleman NPC and presses A through the dialog to battle 69 —
   gen_zozo4's own trigger, reshaped into the driveUntil/voidReason contract.
   A boss also wants fewer, longer samples (`FX.nbattles`/`battleFrames`).
3. **A latent crash.** `knob_authoring` read `ROM_BRAWLER_ROW`, a name that
   was used but never defined — an undefined-global error on the first
   battle report. Defined it as `ROM_SHIELDROWS_V3[1]`.
4. **Stale ROM offsets.** The `Ot6ShieldTbl` base had drifted `$F01067 ->
   $F00F78` at HEAD (bank F0 grew above it), so the authoring-poke offsets
   were 239 bytes stale; then this pass's own rows slid them again. Re-derived
   both times from `ff6/rom/ff6-en.sfc`.

One instrument caveat found and left standing: at the 240-frame base settle,
battle 1 occasionally arms before the fourth party slot's HP is written, so
that one battle reads a 3-member party. It biases at most one of six samples
by one character and never recurred past b=1; the four-member battles carry
the aggregates. Worth a longer base settle next pass.

### The three pools, enumerated from the tables

- **Zozo town** — `zozo_arrival`, map 221 group 78 (and map 225 group 77, its
  sibling, no fixture). Gabbldegak `$0DF` (350 HP, L15), Harvester `$04E`
  (428, L16), HadesGigas `$053` (1200, L16), SlamDancer `$052` (392, L15) —
  **all poison-weak in vanilla**, none absorbing or nulling poison. The
  weakness is already there; only the shield COUNT is the question.
- **Dadaluma** — `dadaluma_doorstep`, boss `$0107` (3270 HP), authored
  `6, PIERCE|BLUDG` + vanilla poison, revives two `$006C` sidekicks.
- **The corridor** — the western-WoB overworld the party roams SEARCHING for
  Terra before Zozo. No world fixture stands in it. Its no-weakness trash is
  the coverage problem; details below.

### Zozo town: mashing WIPES, and the formula lands the break on a corpse

The headline, measured on `zozo_arrival`, 6 battles a policy:

| arm | won | TTK | taken | chips | breaks | actions_broken | break lands |
|---|---|---|---|---|---|---|---|
| **mash** (hold A) | **0/6 WIPED** | 13.3 | 841.7 | 0 | 0 | 0 | — |
| loop, formula (3–4 sh) | 5/6 | 10.7 | 581.5 | 42 | 7 | ~0.4 | 90–95% |

**The Terra-less party CANNOT mash Zozo.** With no fire and no reachable
class weakness in the pool, holding A chips nothing (0 chips, 6/6 wipe) —
worse than Mt. Kolts, which only wiped 3/6. The loop rescues it (5/6), but
the break lands at 90–95% of the fight, on or beside the killing blow, and
the two L16 tanks (HadesGigas 1200 HP, Harvester) at their formula 4 shields
**never break at all** — the two-tank draw wiped even the loop. This is
Measurement #8's Kolts finding on a bigger body: the formula count is too
high, so the break is a funeral, not a window.

The shield sweep (bal_party `BUFF_SHIELDS`, boost3, 6 battles a cell):

| shields | won | TTK | taken | actions_broken | break lands |
|---|---|---|---|---|---|
| formula (3–4) | 5/6 | 10.7 | 581.5 | ~0.4 | 90–95% (corpse) |
| 3 (all) | 6/6 | 10.3 | 553.5 | 0.17 | 89–100% (corpse) |
| **2 (all)** | **6/6** | **9.8** | **433.0** | **1.83** | **62–84% (WINDOW)** |

Exactly Kolts' answer: **2 is the count where the loop exists.** At 3 (and
the formula's 3–4) the break still lands on the corpse; at 2 it lands
penultimate, the tanks break, the wipe becomes a clean win, and the loop
takes ~48% less damage than mashing. So four **shields-only** `Ot6ShieldTbl`
rows (`2, $00`), the Cirpius/Tusker shape — SlamDancer `$052`, Harvester
`$04E`, HadesGigas `$053`, Gabbldegak `$0DF`. No class byte: the town's
answer is the tool, never the A button. ABSORB/NULL re-checked at
`+$17`/`+$18` — HadesGigas absorbs EARTH (irrelevant to poison), the rest
absorb nothing, none null poison. SlamDancer is the map-225 sibling with no
fixture, authored by interpolation inside the measured `$04E`/`$0DF` bracket.

The authored re-measure, on the rebuilt ROM (every town `mon_detail` now
reads `sh2/2`):

| arm | won | TTK | taken | chips | breaks | actions_broken | break lands |
|---|---|---|---|---|---|---|---|
| loop, **AUTHORED 2** | **6/6** | **9.7** | **414.0** | 32 | 15 | **2.0** | **62–84%** |

It reproduces the synthetic arm (433 → 414 taken, 1.83 → 2.0 actions broken),
which is the confirmation that the rows, not a poke, carry it. **The break is
the penultimate round and the kill lands on a broken enemy — the v0.3 target,
met on a v0.4 party.**

### Dadaluma: the window is right, so the shields are left alone

The boss, `dadaluma_doorstep`, as it ships (6 shields, `PIERCE|BLUDG` +
vanilla poison), sampled for its jitter distribution:

| arm | won | TTK | taken | chips | breaks | actions_broken | uptime | break at |
|---|---|---|---|---|---|---|---|---|
| mash | **0/4 WIPED** | 10.8 | 1337 | 5 | 0 | 0 | 0% | — |
| loop (boost3) | **4/4** | 10.0 | 570 | 24 | 1 | 2.0 | 13.3% | 86% |

Read it and you do not touch his shields. **Mashing wipes 4/4; the loop wins
4/4** and takes 57% less damage, and `player_actions_broken = 2` says the
kill lands inside the window every time. The break comes through the CLASS
channel — Dadaluma is `PIERCE|BLUDG`-weak, which Locke's Dirk, Sabin's fists
and Edgar's AutoCrossbow all swing — so the mash arm *does* chip him (5 freebie
chips), but **6 shields is exactly the count that keeps those 5 freebie chips
one short of a break**, forcing the deliberate boosted play that actually wins.
`monster_heal = 0`: the break lands before he self-heals, and it cancels the
JUMP, which is the whole design of the fight. Uptime (13.3%) sits below the
20–30% boss band for the same reason the Whelk did in Measurement #5 — the
party bursts him inside the first window, so a second cycle never opens. That
is a *strong-loop* property, not a broken window; widening it means more boss
HP, a boss-design decision, not a shield tweak. **Dadaluma unchanged.**

### The corridor: the census was right about the AREA, and it needs a fixture

The brief's corridor census (Stray Cat `$018`, Baskervor `$01d`, Chimera
`$01f`, Red Fang `$078`, Ralph `$07b` as the no-weakness trash; FossilFang
`$023` and Iron Fist `$06c` as the poison absorbers; Bomb `$04f`/Grenade
`$0aa` as the fire absorbers) does **not** match the sectors of a straight
Figaro→Zozo line — decoding `world_battle_group.dat` for those tiles draws
`$078`/`$02A`/`$06C`/`$08C`/`$090` instead. The reconciliation is that
"search for Terra" is not a straight line: the party *roams the western/
southern WoB*, and the census species live exactly there (Stray Cat across
world-idx 17–119, Ralph 140–247, Chimera 8–157, and so on). So the census is
right about the AREA; what is missing is a state that stands in it.

What that decoding settles cleanly, and what it does not:

- **The absorbers are already answered and stay untouched.** Iron Fist `$06c`
  absorbs poison (`+$0D97 = $08`) and wears its `2, PIERCE|BLUDG` class row
  (Locke pierces, Sabin bludgeons). FossilFang `$023` absorbs poison too but
  is **ICE-weak**, which Celes casts — so ice is its key, not the tool. Sand
  Ray `$05c`/Areneid `$05d` are already `+poison` (Measurement #8) AND ice-weak.
  The desert half of the region is covered without a new row, and poisoning any
  of these would be the GhostTrain trap. Left alone.
- **The no-weakness five are the real hole, and they took poison.** Stray Cat
  `$018`, Baskervor `$01d`, Chimera `$01f`, Red Fang `$078`, Ralph `$07b` — no
  vanilla weakness of any element, and a formula species carries no class
  weakness, so the Terra-less party could not chip them at all. Five
  `Ot6ElemAddTbl` rows, `+poison`, every one verified `$00` at `+$17`/`+$18`/
  `+$19` (weak/null/absorb all clear). Element table only, no shield row —
  Measurement #8's overworld discipline: coverage where a species needs a
  reachable key but no measured shield count, and no `Ot6HpScale` exemption
  where none was earned.
- **These five are UNMEASURED, said plainly.** No world fixture stands in the
  search region, exactly as the WoB-desert rows of Measurement #8 were
  unmeasured. Coverage is the claim (a reachable key exists); the break WINDOW
  is not, and Chimera at 2237 HP versus Stray Cat at 156 will behave very
  differently at the tool's per-target damage. The structural fix is a
  `zozo_corridor` world fixture — the gen_kolts_pool move — minted in the
  western WoB; then this table's shield question can be swept the way the town's
  was.
- **The fire hole, flagged and NOT force-fixed.** A few western-WoB bodies are
  fire- or wind-weak ONLY — `$090` (fire, 492 HP), `$08C` (fire|wind), `$02A`
  (wind) — and this party casts neither, so their vanilla weakness is dead for
  it. They are left as-is rather than blindly double-keyed with poison: whether
  they even sit on the walked route is precisely what the missing fixture would
  answer, and inventing a second key for a body you have not seen fight is how
  the HP dial shipped twice. Named here, not papered over.

### What is settled and what is not

- **Settled, measured:** the Zozo town loop exists at 2 shields (mash 0/6 →
  loop 6/6, break penultimate, `actions_broken` 2.0); Dadaluma's window is
  functional and his shields are correct as shipped (mash 0/4 → loop 4/4).
- **Under-levelled party, flagged not fixed.** Every town arm ends with a
  `min_hp_end` of 0 — the loop WINS but a character is KO'd doing it (Locke
  starts these fights on 106 HP). Whether natural progression delivers a party
  that survives Zozo more comfortably is Measurement #7's grind question,
  unanswered here and NOT a data-table lever; if the party arrives too weak the
  fix is the `Ot6DangerMulW`/`Ot6RewardMulW` pace pair, not a shield.
- **Unmeasured:** the five corridor rows (no world fixture); SlamDancer's map
  225 (interpolated); the fire-hole bodies (`$090`/`$08C`/`$02A`); Celes's ice
  against Crawler `$05b` (3200 HP, ice-only) — Crawler did not draw on maps 221
  or 225 in any sample, so it is a Zozo body the town-pool fixture never sees.
- **The mash arm never chipped the town rows** — shields-only, poison-only,
  and a masher never opens Tools — so, as in Measurement #8, the authoring is
  invisible to the player who holds A and pays off only for the one who reads
  the room.

## Playtest verdict — kill-before-break holds (2026-07-22)

Measurement #7 opened on the fear that FF6's damage would let you delete
things before the break loop engaged — the reason `actions_broken` was 0.0
across 168 battles. Measurement #8 authored the trash weaknesses to make the
break reachable. This is the playtest confirmation that the pair landed, on
the very species #7 measured.

The owner asked directly — *"is it still too easy to kill things before
breaking?"* — and the playtester answered **"No, it feels great,"** with two
specifics, both the healthy shape:

- **On-level enemies take +2 boost to one-shot.** Deleting an on-level foe is
  now a choice you pay BP for, not the default — so leaving it alive to break
  stays the attractive line. The one-shot exists, but it is priced.
- **Terra opens Fire2 to wipe the Leafers returning through her scenario.**
  This is the *good* kind of killing-before-breaking: the Leafer (`$0017`,
  fire-weak — Measurement #7's own trash) melts to an AoE aimed at its
  weakness. That the balance still rewards this, rather than making every
  fight spongy, is the proof it was not over-corrected. Exploit-the-weakness
  is the fantasy; trivially-delete-everything was the bug.

Verdict, verbatim: **"It's perfect."** Read forward, this is the kill-vs-break
TTK baseline the #6 break-weakness pass and the WoB route must hold to —
nothing should die faster than this.

## Playtest verdict — progression pull and the grind curve (2026-07-22)

Same session as above. Two more signals, both about progression:

- **The weakness loop is generating demand for the right tools.** The
  playtester "was really feeling the lack of Fire Dance" (Sabin's fire AoE,
  learned at L15; he reached the Imperial Camp at L14) and **"went and
  recruited Shadow because I needed him."** That is the design thesis working
  end to end: enemies wear weaknesses → the player wants the tools that hit
  them → he levels and recruits to get them. The want was created by the
  fights, not by a checklist — including seeking out an *optional* recruit.
- **The grind question, answered.** Measurement #7 flagged "the grind
  question, untouched" as its one open thread — whether natural random-
  encounter EXP delivers a strong-enough party without forcing a grind. The
  playtester, at L14 in the Imperial Camp with Fire Dance one level ahead:
  **"Exp curve from random encounters feels perfect too."** The pace places
  the thing he wants just out of reach, so he plays forward to earn it rather
  than grinding for it. #7's last open thread closes green; the
  `Ot6RewardMulW`/`Ot6DangerMulW` pace pair is delivering as shipped.
