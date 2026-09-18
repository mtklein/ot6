# Pressing R is a claim — the private fighters and the boost they could not pay for (#230)

Authored 2026-09-18 from `tools/tests/privatefighterslab.py` (the lab; its
docstring carries the policies) and a six-seed spread of six generators
over two policies. Every number below is quoted from a retained log under
`build/lab/private-fighters/` — the lab keeps every attempt, failures
included. `python3 tools/tests/privatefighterslab.py aggregate` prints
them all.

This is the class behind [narshe-descent.md](narshe-descent.md), which is
the lab that found it. Read that one first for the mechanism; this one is
about how far it reached and what the fix is.

## The class

Since #219 a boosted Blitz, Tool or non-tier cast costs escalating MP —
`min(99, round(base * 2.5^boost))`, `Ot6BoostPriceFor` — so a row the pool
covers unboosted prices out the moment pips go on it.

When #228 found this, an unaffordable kit row was **greyed but still
committable**: `Ot6AbilityGrey` had shipped the visual half of the
affordance and the only refusal was `CalcAttackEffect`'s universal
insufficient-MP gate, which runs at *execution* — after the turn and the
banked boost points are spent (`battle_main.asm:8424`).

**v0.19 closed that.** `Ot6KitConfirmMP` now refuses the row at the
confirm: it buzzes, the list stays open, and the turn, the pips and the MP
are all kept (`battle_kitrefuse`, and `mp-economy.md` ruling 2 for the
ruling it completes). That is the right answer for a person, who reads the
grey — and it makes this unit **more** necessary, not less:

> A fighter that does not read the price used to lose one turn quietly.
> Now it presses A at a row that buzzes and stays open, and if it keeps
> asking it sits there until a watchdog fires. The symptom moves from an
> invisible wasted turn to a **timeout that says nothing about why.**

A person reads the grey. A fighter has to read the price.

The library's fight driver learned to (`M.affordBoost`, #219). But a
generator with its **own private fighter** never went through that door:
it read the bank, pressed R that many times, named a costed ability, and
never asked what the boost cost. `gen_narshe_battle` did that sixteen
times in one descent and lost the segment three attempts running (#228).
Eight more generators were named in #230 as having the same shape.

The useful invariant, and what this branch lands:

> **Pressing R is a claim that the caster can pay, and that claim is
> checked once, in one place.**

## What the list turned out to be

The eight were read line by line and played. Boosting **Fight** is free —
cmd `$00` is in `Ot6BoostDmg`'s gate, so the boost buys swings and the row
costs nothing — so a fighter that only boosts Fight has no claim to check.

| generator | presses R for | needed the change |
|---|---|---|
| `gen_scenario` | EDGAR Tools, SABIN AuraBolt (`$5E`) | **yes — and it was already failing today** |
| `gen_kefka_won` | EDGAR Tools | yes (latent) |
| `gen_opera7_blackjack` | EDGAR Tools, SABIN Pummel (`$5D`) | yes (latent) |
| `gen_rapids` | EDGAR Tools | yes (latent) |
| `gen_zozo4_dadaluma` | EDGAR Tools, SABIN Pummel | yes (latent) |
| `gen_sabin_train` | Fight only | no |
| `gen_sabin_gau` | Fight only | no |
| `gen_vargas` | Fight only | no |

Two the list did not have:

| generator | presses R for | needed the change |
|---|---|---|
| `gen_thamasa_fire` | TERRA/LOCKE **Ice**, a boosted cast that folds Ice → Ice 2 → Ice 3 | **yes** |
| `lab_zozo4_j39_snap` | EDGAR Tools, SABIN Pummel (a verbatim copy of `gen_zozo4_dadaluma`'s fighter) | yes (latent) |

`gen_thamasa_fire` is the one the list missed and the most interesting of
them: its `makePlan` *does* check affordability — `spellCellA(actor,
ICE_SPELL, true)` refuses the plan when the pool is under the list row's
price and when the row is greyed. But that is the **unboosted** price. The
boost is what turns that row into Ice 2 (20 MP) or Ice 3 (51), each
charged at its own vanilla MP through `Ot6QueueFold` → `Ot6SpellMP`. The
check proved it could pay 4 and the turn claimed 51.

Three free-looking verbs were checked against the ROM rather than assumed:

- **Runic** (cmd `$0B`) — `GetMPCost` prices only magic/lore/summon/x-magic
  and `Ot6AbilityCost`'s chain hands every other command vanilla's own
  cost back, which for Runic is 0. Free.
- **Health** (cmd `$1A`, BANON's) — the same two reads. `Cmd_1a` queues
  attack `$2E` (Cure 2), but the *command* is `$1A`, which `GetMPCost`
  falls through at 0 and `Ot6QueueFold`'s `$02/$17/$0c/$19` gate does not
  admit. Free, and a boosted Health keeps the bank's whole boost.
- **Fight** and **Capture** — in `Ot6BoostDmg`'s gate, so the boost buys
  swings. Free.

## The fix

**One door: `H.boostPlan` (`M.boostPlan`, `lib/ot6.lua`).** It takes the
caster's slot, the ability the turn will name, the boost the bank would
spend, and an optional reserve and ration, and returns the boost the pool
can actually pay for, whether the verb survives at all, and one line saying
why. It is `M.affordBoost` — the lib's copy of `Ot6BoostPriceFor` — wearing
the two clothes the callers wear: `M.abilityCost` for a kit verb,
`M.spellPrice` for a cast, because a family head's boost buys a **tier**
and pays that tier's own vanilla MP rather than 2.5x.

Their policies really were the same decision wearing different clothes.
All five `seqFor` fighters are the same twenty lines (bank to 2, dump up to
3, dispatch on the actor's character id and the attempt tier); they differ
only in *which* verbs are in the table and, on the rapids, in the bank
threshold at tier 3. So they all call the one function and keep their own
verb tables. The library's driver now calls it too: `skillBoost` and
`castBoost` are three-line wrappers that keep the driver's nil-on-drop
contract.

Rationing is **not** uniform, and the measurement is why. The descent
rations one turn to a quarter of max MP because it has no shop, no inn and
no save point between the staging tile and KEFKA, and its only refill is a
level-up. None of the six here has that shape: each either ends at a boss
and stops, or passes a care stop or a town. Measured unrationed, none of
them exhausts a pool it could not refill, so none of them rations. The
knob is `o.ration` and it is one word to add if a segment ever needs it.

### Two cuts it took to get the id right

The first cut priced EDGAR's line against **AutoCrossbow** (`$AA`, 4 MP),
because that is what every one of these generators' comments said the
sequence picks. It does not:

| segment | tool actually named, every turn |
|---|---|
| the Narshe descent | `$AA` AutoCrossbow, 4 MP — 16 of 16 |
| `gen_scenario`'s river | `$A4` Bio Blaster, 8 MP — 21 of 21 |

Pricing a boost against a name the turn will not use is the same unchecked
claim one level down, and it showed: the scenario's first priced cut still
fizzled 23 times over the spread, stepping Bio Blaster's boost down to
AutoCrossbow's price
(`build/lab/private-fighters/scenario-run1/priced/`).

The second cut guessed the other way — *the dearest tool in the bag*, a
ceiling that can never under-claim — and had a plain bug: it stopped its
bag scan at the first `$FF`. `$FF` marks an **empty slot**, not the end of
the table (the driver's own `battInvIdx` walks all 252 entries for that
reason), so it found no tools at all, handed `boostPlan` a nil id, and the
crossbow read as a free verb. The descent's fizzle count went straight back
to the control's, **16 on seed 0, exactly**, which is what named the bug
(`build/lab/private-fighters/descent-regression.txt`).

What shipped reads the list the ROM's way instead of guessing at all.
`MakeToolsList_00..03` (`set_buf_item`, `btlgfx_main.asm:13065`) fills
`wItemList` by walking the battle bag **in bag order** and appending every
entry whose usage byte carries the tools flag `$40`. So cell *N* of the
window is the *N*th such entry, and the kit and the item ids decide
nothing. `M.namedTool(slot)` walks that same scan and takes the cell this
actor's own persistent cursor sits on (`$8963` col / `$8967` row, a
2-column grid) — which is the cell a "down, A, A, A" sequence confirms.
When the cursor does not resolve to a row it falls back to the dearest in
the list, because over-claiming only costs boost depth while under-claiming
costs the turn. A fighter that **does** steer (gen_scenario's SABIN walks
right to AuraBolt; the Blitz grid otherwise opens on cell (0,0), which is
Pummel at every level) names its id outright.

The check that it is right: with `M.namedTool`, the descent's `ration`
policy prices against `$AA` again, the ROM names `$AA` on every Tools turn,
0 fizzles — and seed 0 passes at **frame 33361**, the exact frame
`narshe-descent.md` records for the shipped generate edge.

### The descent, re-measured through the one door

`gen_narshe_battle` now makes the same call as the other six, with
`ration = 4` where they have none. Its own lab, six shifts on the v0.19 ROM
(`build/lab/private-fighters/descent-v019.txt`, logs under
`build/lab/narshe-descent/ration/`):

| seed | verdict | frames | fights | turns | fizzles | confirm refusals | wipes |
|---|---|---|---|---|---|---|---|
| 0 | PASS | 33,361 | 7 | 78 | 0 | 0 | 0 |
| 5 | PASS | 29,275 | 7 | 73 | 0 | 0 | 0 |
| 10 | PASS | 28,095 | 7 | 65 | 0 | 0 | 0 |
| 15 | PASS | 27,774 | 7 | 69 | 0 | 0 | 0 |
| 20 | PASS | 32,627 | 7 | 75 | 0 | 0 | 0 |
| 25 | FAIL | — | 11 | 62 | 0 | 0 | 3 |

Five of six, **no fizzle and no refusal on any of them** — the priced
fighter never even asks for a row the confirm would buzz. Seed 25 is the
failure `narshe-descent.md` already names and classifies: it is not an MP
failure (0 fizzles, 0 refusals, 14 priced step-downs all going through),
it is a bad draw, and the segment's own three-attempt ladder is what that
is for.

## Making it loud

Both halves of the claim are named out loud now, on every run
(`lib/ot6.lua`, in the exec observers, which were moved from the fight
driver's frame to the runner's so they reach the generators with private
fighters).

### The fizzle

The reason #228 needed a lab is that a fizzled boost looks exactly like a
turn that did nothing: the menu closed, the gauge emptied, the pips went,
and no number came up.

```
[fizzle] f36110 slot1 char4 Tools($09) atk=$AA boost=2 cost=25 pool=21 --
the pool could not pay it: CalcAttackEffect refused the action, the turn
and 2 boost point(s) are gone and the pool is still 21.  Pressing R is a
claim the caster can pay (M.boostPlan, #230).
```

and the tally sits beside the verdict with the other watch lines:

```
[watch] fizzles: 16 costed action(s) refused for MP, 28 boost point(s)
burned on them -- char4 Tools=16; the [fizzle] lines name each one
```

The predicate is the ROM's own arithmetic on the ROM's own operands, not a
guess from the outcome. `InitPlayerAction` parks the queued action's MP
cost in `$3A4C` before the command runs (`battle_main.asm:429`);
`CalcAttackEffect`'s gate is `lda $3c08,x / sbc $3a4c / bcs paid`
(`battle_main.asm:8424`). A cost in `$3A4C` larger than the pool at
`ExecCmd` is a refusal the engine has already decided on, and
`SaveForMimic` confirms it by the pool not having moved — both halves, so
a verb whose body clears its own cost (the Imp arm, a mid-dance step,
Slot's espers) cannot be mistaken for one.

Two falsifications:

- `battle_mpcost`'s refusal arm manufactures exactly one fizzle (Cyan's
  Dispatch, 4 MP, against a 1 MP pool). The observer reports exactly one,
  and reports none on the same test's charge arm.
- The Narshe descent's `control` policy on seed 0: the library counted
  **16**, and `narshedescentlab`'s independent observer — which asks the
  outcome question instead (a costed command that spent no MP and moved no
  monster) — counted **16**. Different predicates, same number, and they
  are the sixteen #228 named.

`tools/audit_boost.py` counts them too, beside the pips-at-death report it
already ran: a fizzle is boost left on the table in the most literal form
there is, turns *and* pips spent to buy nothing.

On the v0.19 ROM the kit windows no longer *reach* this gate by hand — the
confirm refuses first — so the fizzle line is now the backstop it was
always meant to be: the magic path, an AI- or Mimic-issued action, and a
pool that moves between the commit and the resolve. It stays on, because
those are exactly the cases nobody is watching.

### The refusal

The confirm's own "no" is the other half, and for a blind fighter it is now
the *first* thing to happen. The library names it the same way:

```
[refused] f2051 slot3 char5 list $30 -- the confirm buzzed and the list
stayed open (pool 80/84, bank 2, pending 2).  The turn, the pips and the MP
are kept; a fighter that keeps asking for this row stalls on it
(M.boostPlan, #230).

[watch] kit/magic confirm refusals: 6 confirm(s) buzzed inside a list
window -- char5 $30=2 char4 $30=2 char1 $30=2
```

The buzz is magic's own error sound, `inc $95`, which `battle_kitrefuse`
asserts on and which the kit confirm now raises too; direct-page stores
land in bank $00, so both views are watched. A buzz inside a list window
(`$7BC2` = `$30`, the tools shell that serves Blitz, Tools, SwdTech and the
thief submenu; `$0E`, the magic list) is the confirm saying no. It is not
*exclusively* the MP refusal — an empty cell buzzes too — so the line
reports what it saw and prints the caster's pool, bank and pending boost
beside it rather than guessing why. Falsified against `battle_kitrefuse`,
which stages exactly three refusals: it reports SABIN's priced-out Blitz,
EDGAR's priced-out Tool and LOCKE's drained Steal, and nothing else.

## The spread

Six `OT6_SEED_SHIFT` values, 0 through 25 in steps of 5 — idle frames the
segment runner inserts at the boot point — with the lib's retries **off**
(`OT6_RETRIES=1`), so every seed reports its first try, and nothing
published to `build/states`. Two policies per segment:

- **control** — the fighter as it stood before this branch: the bank's
  whole boost, pressed without asking what it costs. This is HEAD's code
  for all six, which is what makes them a class and not a bug.
- **priced** — the generator as it ships today, verbatim, its claim routed
  through `H.boostPlan`.

The lab derives both from the shipped generator by substituting one region
and asserts every substitution matched exactly once, so a generator edit
that moves an anchor fails the derivation rather than silently measuring
something else.

One caveat on the absolute numbers. The ROM gained `Ot6KitConfirmMP` while
this branch was in flight, and every tracked savestate fixture in the tree
is a snapshot of the ROM before it (`compose.py --check-states`: 94 of 94
STALE, one cause). Regenerating them is the route regeneration the
coordinator sequences, not this unit's to run. The A/B below is still
sound — both policies boot the *same* fixture on the *same* ROM, and the
only difference between them is the substituted line — but the frame counts
are not the numbers the regenerated fixtures will produce, and should be
re-taken after that lands.

One suite test fails in this tree on the v0.19 ROM and is **not** this
unit's: `battle_healerdown` trips the recovery cap on the driver's Gau
`switch` plan at frame 3727. It fails identically with `origin/main`'s
`lib/ot6.lua` swapped in, at the same frame with the same message, and its
run writes no `[boost]`, `[refused]` or `[fizzle]` line at all
(`build/lab/private-fighters/validate/healerdown-mainlib.log` beside
`battle_healerdown.log`). It belongs to the confirm change or to the stale
fixture, not here.

## Results

`python3 tools/tests/privatefighterslab.py aggregate`, retained verbatim at
`build/lab/private-fighters/aggregate.txt`; the run's own output is
`run-v019.txt` and every log is under `<segment>/<policy>/seedNN.log`.
72 runs, **all 72 PASS**, on the v0.19 ROM.

| segment | policy | pass | turns | fizzles | confirm refusals | mean frames |
|---|---|---|---|---|---|---|
| `kefka_won` | control | 6/6 | 113 | 0 | 0 | 17,635 |
| | **priced** | **6/6** | 113 | 0 | 0 | 17,635 |
| `blackjack` | control | 6/6 | 37 | 0 | 0 | 22,651 |
| | **priced** | **6/6** | 37 | 0 | 0 | 22,651 |
| `rapids` | control | 6/6 | 144 | 0 | 0 | 9,904 |
| | **priced** | **6/6** | 144 | 0 | 0 | 9,904 |
| `scenario` | control | 6/6 | 544 | 0 | **334** | 38,654 |
| | **priced** | **6/6** | **515** | 0 | **0** | **36,117** |
| `dadaluma` | control | 6/6 | 398 | 0 | 0 | 53,890 |
| | **priced** | **6/6** | 398 | 0 | 0 | 53,890 |
| `thamasa_fire` | control | 6/6 | 471 | 0 | 0 | 77,136 |
| | **priced** | **6/6** | 471 | 0 | 0 | 77,136 |

Read the table honestly. **On five of the six the change is a no-op on
today's play** — control and priced are frame-for-frame identical on every
seed, because on these seeds those fighters never reach a boost they cannot
pay for. That is not a disappointment, it is the issue's own claim
measured: *they pass today because their pools happen to last the fights
they play.* The claim they make is still unchecked; what this branch buys
there is that it stops being unchecked, and `H.boostPlan` logs nothing
because there is nothing to say.

**`gen_scenario` is the one that already bites**, and its two columns are
the whole unit in miniature:

| seed | control frames / refusals | priced frames / refusals |
|---|---|---|
| 0 | 36,503 / 64 | **34,655 / 0** |
| 5 | 38,215 / 48 | **34,327 / 0** |
| 10 | 39,155 / 62 | **36,723 / 0** |
| 15 | 41,671 / 64 | **38,567 / 0** |
| 20 | 37,971 / 48 | **34,779 / 0** |
| 25 | 38,411 / 48 | **37,651 / 0** |
| | **334 over the spread** | **0** |

EDGAR walks the Lete river on a 77 MP pool that Bio Blaster's boost-2
price (50) outruns by battle three. Unpriced he asks for it anyway, about
**fifty-six times a run**, and every one of those is now an A press that
buzzes and does not commit — he backs out, the fighter rebuilds the same
plan, and he asks again. Priced, `H.boostPlan` steps him down (88 logged
step-downs over the spread) or drops him to Fight, and he never asks for a
row that buzzes: **0 refusals on every seed**, 29 fewer turns and **2,537
fewer frames a run**.

### The symptom really did move

This matters more than the frame count, and it is the coordinator's
prediction measured. The same fighter on the **pre-v0.19 ROM**, over the
same six shifts (`build/lab/private-fighters/scenario-run1/`):

| | fizzles | confirm refusals | verdicts |
|---|---|---|---|
| `scenario` control, pre-v0.19 | **40** | n/a | 6/6 PASS |
| `scenario` control, v0.19 | **0** | **334** | 6/6 PASS |

Forty silently wasted turns became three hundred and thirty-four buzzes.
The turns and the pips are no longer thrown away — that is v0.19 working —
but the fighter now *stalls* on each one instead, and the only reason
these six still pass is that every one of these private fighters happens
to carry a back-out: a sequence that leaves the menu open taps A twice,
presses B, and rebuilds. A fighter without that back-out would sit there
until a watchdog fired, and the run would report a **timeout that says
nothing about why**. That is the failure mode this unit removes, and it is
why the `[refused]` line exists.


## Options not taken

- **Steer the Tools cursor.** These fighters take whatever row the cursor
  is already on. `M.namedTool` answers *which* row that is, off the ROM's
  own list order, which is enough to price it — but a fighter that wanted a
  particular tool would have to walk there, and that is a rewrite of five
  sequence machines that are deliberately dumb (one button per 30-frame
  pulse). Worth doing if a segment ever wants a specific tool rather than
  whatever is first in the bag.
- **Press R inside the window.** `probe_bushido` measured that R still
  raises the pending boost from inside the SwdTech window, which would let
  a fighter read the list *first* and then price exactly. Not measured for
  the Tools window, and it changes the sequence rather than the decision.
- **Refuse an unaffordable kit row at the confirm.** Taken, by someone
  else, while this branch was in flight (`Ot6KitConfirmMP`,
  `battle_kitrefuse`). It does not replace this unit: it converts the
  class's symptom from a silent wasted turn into a stall, which is a
  timeout the run cannot explain. The two land together.
- **Assert rather than check.** #230's option 2: let the fighters stay
  private and give them a cheap assertion, so a boost pressed without
  pricing is a build failure. The loud `[fizzle]` line is the run-time
  version of that and costs nothing; an assertion would need every fighter
  to declare its intent up front, which is the routing this branch did
  anyway.
- **The escalation rate.** Unchanged and not proposed: 2.5x, the 99 cap
  and the chance-verb exemptions are the owner's locked design. This
  branch is about the fighters.

## The lab

`tools/tests/privatefighterslab.py`, narshedescentlab's shape. Each
policy is a derived copy of the shipped generator — the generator verbatim
plus one read-only observer pair, plus (for `control`) the region of the
fighter being measured replaced by its pre-#230 body. `write` derives,
`run` plays each variant once per seed, `aggregate` prints the table above
and `table <log>` the per-run who-spent-what-on-what.

The observers are the descent lab's: `ExecCmd@battle_code` parks the
acting entity's MP, banked BP, revealed boost, queued cost and every
monster's HP; `SaveForMimic` settles them. They read, they never write.
The library's own `[fizzle]` line is independent of them, which is what
lets the two counts be compared rather than merely agreed with.
