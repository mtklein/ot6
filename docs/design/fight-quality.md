# Fight quality — measuring what makes a fight good (#422)

Scope: measurement, not tuning. The owner's guideline ([guidelines.md](../guidelines.md),
"What makes a fight good"): the party should feel power grow and
resistance overcome, in a challenge that is real but surmountable, with
some drama, won by choices more than by levels or luck. This doc says how
the harness's logs answer each of those, and gives a first report.

## The tool

`tools/fight_report.py [LABEL[@FORMS]=]PATH ...` reads harness logs (a
state's `.log`, a seed sweep's directory) and makes every battle one
fight, from its `[seed]`/`[key]` line to its `[outcome]` or `[wipe]`. It
counts each distinct battle key once per policy ([TESTING.md](../TESTING.md),
"Tests that survive any draw"). `--events` keeps the formations no
random-encounter group in the built ROM can deal (the bosses and story
fights); `--form X` adds a notable random. `--fights FILE` writes one row
per fight with the raw `[outcome]` line and the board at its low point.

It reads lines the harness already wrote, plus one new one:

- **`[board]`** (lib/ot6.lua `Driver:sayTurn`): at every plan, the
  party's HP/max/BP and each standing monster's HP/max/shields. Logs from
  before it fall back to the 300-frame `battle f+N ... partyhp= monhp=`
  lines and the `[open]` line, which see less.

## The five questions

| Question | Column | Reading |
|---|---|---|
| Resistance | `low_med`, `low_worst`, `down_max` | the least party HP fraction seen at a plan in a won fight, and the most members down at once. A fight whose low point stays near 100% offered none. |
| Surmountable | `keys`, `won` | win rate by distinct key. Under one policy, levels and gear, any loss is the draw: a fight with 0 < losses < keys is decided partly by luck. |
| Drama | `doubt_med`, `flips_med` | the lead is party HP fraction minus enemy HP fraction at each plan; doubt turns are plans with the party behind (lead < 0), flips are changes of who leads. |
| Power | `turns_med`, `ticks_med` | party plans and battle ticks to the end of a won fight, read in route order. |
| Agency | the same fight under `naive` (and `nocare`, `noboost`, `noskill`), `paired` | the real driver against the same driver with choices taken away, on the same keys. A fight the naive policy wins as often, in as many turns, is settled by levels and gear, not play. |

A low point is sampled at plans, so a dip that a heal answered before the
next plan is missed; `down_max` and `deaths/fight` (the `[death]` lines)
catch the deep ones.

## The policies

`OT6_POLICY` (a comma list; compose.py passes it to the script like
`OT6_SEED_SHIFT`) changes only `Driver:makePlan`'s result, and each change
is logged as a `[policy]` line:

- `naive`: every plan is a plain Fight at 0 BP on the cursor's default
  target. No skills, spells, items, boosts or break aiming.
- `nocare`: in-battle heals, items and raises become that Fight.
- `noboost`: a boosted Fight goes unboosted (aimed for 0 BP); any other
  boosted plan becomes the plain Fight.
- `noskill`: a non-Fight attack becomes a Fight at the plan's boost.

`OT6_POLICY_FORMS=14B,1B6` limits the policy to those formations, so the
walk to a boss plays as the real driver does and the boss is met with the
same levels, gear, items and, for the same seed shift, the same battle
key: real and naive runs pair key by key. A muddled actor's deferral and
a window with no Fight are left alone. Out-of-battle choices (relics,
kits, field care) are the real driver's in every policy; counterfactuals
that remove one of those (an Esper, a relic) are generator options, not
this switch.

## Running it

    OT6_POLICY=naive OT6_POLICY_FORMS=16F python3 tools/tests/seed_sweep.py \
        wor_storm --seeds 12 --jobs 4 --out build/sweeps/storm-naive
    python3 tools/tests/seed_sweep.py wor_storm --seeds 12 --jobs 4 \
        --out build/sweeps/storm-real
    python3 tools/fight_report.py --events build/sweeps/storm-real \
        naive@16F=build/sweeps/storm-naive

A seed shift moves only in-battle RNG; the encounters a segment meets are
the fixture's. So these are varied-luck sets for the bosses, and the
randoms on the way are whatever the fixture deals.

## First report

Evidence: `build/attempts/wt/v031-fightmeasure-2/` (`report.txt`, the
table; `fights.tsv`, one row per fight with its raw `[outcome]` line and the
board at its low point; `branch-states/`, the 252 logs of the one-line
chain; `sweeps/<boss>-real|naive/`, eight seed shifts each). The party is
whatever the generated line made it, at the commit that merged
`e1f6a173` (v0.31 dev); the numbers describe that route, not the game in
general. Every real row is the driver as it plays with `OT6_POLICY` unset.

**Unset policy is the old play.** The same two segments (`wor_storm`,
`wor_tritoch`, eight seed shifts each) run on this branch and on
`e1f6a173` (same ROM, sha256 `64a87876...5166`, same machine) give
log-for-log the same lines once the new `[board]` lines are dropped (16 of
16 logs, `ab-unset-vs-main.txt`), and the whole 252-log chain built on both
trees loads the same parent states (184 of 184 `state X sha=` lines
equal) and 250 of the 252 logs are equal under the same filter. The two that
differ: `wor_relm` (the assertion's line number in the composed file) and
`mrf_entry`, whose `[survey]` line counts 3042 tiles on the branch and
3046 on main from the same parent state; nothing else in that log differs. Unexplained; the survey reads map tiles, not
anything this change touches, but it is not proven independent.

**Resistance and drama.** Where the party's low point in a won fight sits
(median over keys, the worst key, most members down at once), doubt turns, from the real policy:

| Fight | keys | low (med / worst) | down | doubt | turns |
|---|---|---|---|---|---|
| Storm Dragon `$16F` | 8 | 50% / 16% | 2 | 9 | 31.5 |
| Ice Dragon `$16E` | 5 | 58% / 23% | 3 | 7 | 16 |
| Kefka `$1F9` | 9 | 86% / 73% | 0 | 5 | 23 |
| Dullahan `$1C7` | 8 | 78% / 62% | 0 | 2 | 14.5 |
| Ultros `$183` | 8 | 96% / 68% | 0 | 0 | 19 |
| Phunbaba `$1A5` | 8 | 84% / 80% | 0 | 4 | 10.5 |
| Tritoch `$1E7` | 5 | 96% / 65% | 0 | 0 | 14 |

The Storm Dragon and the Ice Dragon are the two fights that took the party
deep (a member down in most draws, a low point at or under 23%); Ultros and
Tritoch never put the real party behind (doubt 0): their low points are
chip damage. That fits "resistance" being the dragons' business.

**Surmountable.** Real policy, eight shifts per boss: 8/8 on Storm Dragon,
Kefka, Dullahan, Ultros and Phunbaba; the Ice Dragon every one of the 5 keys it met (4
of the 8 shifts never reached it, below). No real loss on any boss in the sweeps, so the
spread across draws shows no luck-driven loss: the Storm Dragon's worst key
sits at 16%, the nearest miss.

**Agency** (same keys, same levels and gear, naive = a plain Fight each
turn at the boss only):

| Fight | real won | naive won | real turns (med) | naive turns (med) | naive low (med) |
|---|---|---|---|---|---|
| Storm Dragon | 8/8 | 6/8 | 31.5 | 29.5 | 14% |
| Kefka | 8/8 | 5/8 | 23 | 36 | 47% |
| Ice Dragon | 4/4 | 4/4 | 16 | 28 | 27% |
| Ultros | 8/8 | 8/8 | 19 | 37 | 76% |
| Dullahan | 8/8 | 8/8 | 14.5 | 19.5 | 75% |

Choices decide Kefka (3 of 8 keys lost without them) and the Storm Dragon
(2 of 8), and the naive party survives the Ice Dragon only at a median low
of 27% against 58%. Ultros and Dullahan are won by levels and gear: naive
wins every key, slower (about twice the turns for Ultros) but never in
doubt. That is the harness's answer to "does the choice matter" for
fights it calls easy; it is not a verdict that Ultros should change
(guidelines: fights players find easy need only reliable passage).

**Power** needs arcs of comparable enemies; the chain holds Sky Armor
(`$0B0` 4.5 turns, `$0AF` 6.5) -> Phunbaba (7 to 12) -> dragons (16 to 31)
only as different fights, so no turns-to-kill trend is claimed yet. The
column is there for a future pair (a kit landing between two reruns of the
same fight).

**What the report set aside.** Phunbaba's first visit (`$1A4`, 60000 HP,
the script's own "scripted loss" line precedes it) and Ultros `$1DD`
(`PARTY LEFT`, the party fled) are not samples; the tool prints them after
the table instead of counting a loss.

**Found on the way** (not tuned here): `wor_tritoch` on this ROM times out
in 4 of 8 shifts driving the relics menu for the Ice Dragon (`CELES
(relics): cursor on the menu row`, 900 frames, `sweeps/tritoch-real/
summary.tsv`); main at `e1f6a173` does the same on the same shifts, so it
predates this change. And `gen_wor_relm` fails on `no swap deadlock` on
both trees (`branch-chain.log`, `main-chain.log`); main has since moved on
that file.

**Not yet done.** The issue asks to validate against the owner's play
("numbers should match how a fight felt"); no record of how the owner
found these fights is attached here, so that comparison is open. The
counterfactuals that remove an Esper, a relic or a kill order need
generator options (this tool's `OT6_POLICY` only touches in-battle plans).
