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

FIRST_REPORT
