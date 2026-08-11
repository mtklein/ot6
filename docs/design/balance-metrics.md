# Balance metrics — the measurement harness

Scope: measurement, not tuning. Every number below marked *proposed*
is a proposal for the driver; nothing here is locked.

Tuning M3's weakness spread and M6's per-monster shield table by feel
alone won't survive contact with three scenario parties. So before the
knobs, an instrument: `tools/tests/metrics_battle.lua` plays a fight
by policy and emits one greppable `[ot6] [metrics] key=value` line per
stat. Same rig as the acceptance tests (entry-point savestate, headless
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

A policy sets only the **boost discipline**; what a character actually
*does* with the turn comes from a per-character **kit** table (`KITS`,
keyed on the character index at `$3ED9+slot*2`), so one named policy
plays a whole party — Terra probes and exploits with Fire, Locke opens
with Steal then Fights, Edgar's Tools carry pierce/poison, Sabin inputs
Blitz. Every stat fans out per party slot (`char_actions`, `char_dmg`,
`char_chips`, `char_breaks`, `char_boosts`, `char_bp_*`,
`char_dmg_taken`) using the same `sN:value` CSV the monster lines use.

## Proposed target ranges (for the driver)

| Range | Proposed target |
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

Now: two entry-point states exist (`battle_entry`, `battle2_entry`
— the `STATE` knob), so the matrix is 2 formations × 3 policies. One
run is deterministic (rng phase is frame-driven); distributions come
from the `SETTLE_EXTRA` jitter knob — sweep 0..90 in ~10-frame steps
for ~10 samples per cell. Aggregation is a grep: every stat is one
`key=value` line in `build/states/last_run.log`.

Once post-magitek states exist (M3+): generate one entry-point state per
stretch with the `gen_battle2` pattern (win, walk to the next trigger,
save), named `battleN_entry`, and run the same matrix. The rows to fill
are exactly the stretch table in `weapon-classes.md` — the coverage
rule ("the story's actual party chips every non-boss encounter")
becomes checkable: per stretch, every formation shows a sane TTK range
and a nonzero break rate *with that stretch's party*. Boss states get
their own range row (break windows, uptime) once a boss is reachable.

Attribution: damage, chips and breaks are credited to the entity whose
action is running, read from the battle loop's own action-queue
dequeues, so monster-on-monster muddle damage does not land in
`player_dmg` — it is reported separately as `monster_self_dmg`. The
known blind spots:

- **Attribution is action-granular, not hit-granular**, and one frame of
  slack sits at each action boundary. There is no WRAM address carrying
  the attacker at damage-apply time: `ApplyDmg` reads it off the stack
  (`lda $02,s`, `ApplyDmg` at `battle_main.asm:2975`), `$32E0,y` is a retaliation
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
