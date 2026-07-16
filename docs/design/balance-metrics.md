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
