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

Known blind spots, accepted for v1: damage is attributed by victim
(monster-on-monster muddle damage would count as player damage), and
`$340a` immediate actions bypass the action-count queues — both noted
as TODOs in the lua header.

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

Shipped values (`Ot6HpMulTbl`, 16ths): $20/$20/$10/$10 — band
$00–$5F 2x (swept, above), band $60–$BF 2x (census arithmetic: WoB
mid trash HP 119–495 keeps the same damage:HP shape; stretch
fixtures should confirm), bands $C0–$FF and $100+ 1x (WoR
unmeasured; $100+ additionally guards Doom Gaze's saved-HP reload
from compounding). Gate: full suite green twice at these values,
story-chain fixtures re-minted, Whelk head untouched at 1600 HP.

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
