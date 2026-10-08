# The care race: one decision for every command (#415)

Status: bounded acting policy prepared for v0.26 route qualification.
Earlier matched validation did not meet the original all-command/no-regression
acceptance bar; those failures remain retained. No final release qualification
is claimed until the landed-source replay and checks pass.
Owner and coordinator, 2026-10-06; validation updated 2026-10-08.
The owner now accepts a fresh supported-route clear as the practical success
bar, with ordinary preparation and catch-up fights responding to the actual
party. Exact XP parity and a perfect model are not prerequisites to moving on.

## Why

The fight driver decides care with a stack of local rules.  Each one was
written for one fight and measured on 2 to 6 keys:

- the heal policy and its lift (`M.healDecision`, #312);
- the round's one care turn, reopened for an owed top-up (#168) or a
  lift (#312/#402);
- the outpace lever (#402, off);
- the spend rule (#175, `M.spendDecision`) and its see-through (#312);
- the finisher gate (#204);
- the press rule's kill-this-turn (#156, #165);
- the keyed boost (#174);
- the raise rule with wipe risk as hits needed (#374, #395);
- the item choice priced in gil (#370);
- the treadmill (#414, off).

The rules interact, and none of them asks what the turn it takes away
would have done.  #414's review shows the failure: a heal that lifted a
member clear was swapped for a Tools turn that chipped nothing.

A player asks one question at every command: **which action best improves
the race?**  The race is the party's turns-to-kill against the enemy's
turns-to-wipe-or-cripple, with ATB order deciding who acts first.  This
note is that question as code.  Guesses are fine, since players guess from
experience; consistency matters more than precision.

## The estimate

Each `makePlan` builds a small race state from readings the driver
already makes.  It reads live memory and ROM pricing as an informed policy; its actions
use the normal controller inputs.

- **Party, each seated member.**
  - HP, max HP, alive/statue/Doom, MP, BP.
  - The ATB gauge as a time to its next turn, in ticks: from the gauge
    byte and speed, as the round model already reads the enemy's.
  - Its **best damage line** at each boost (0-3): the chip model
    (`bestLine`, `hitChips`, `fightChips`) for shields, and `M.killEstimate`
    with the damage watch (`dmgHit`/`dmgSeen`) for HP.
  - Before anything has landed: the ROM model the round cost already
    falls back on (`M.physHitRange` / `M.magicHitRange`).
- **Enemies, each standing slot.**
  - HP, shields, Broken ticks.
  - Next-turn ETA and period: `M.roundCost`'s enemy table, the same one
    the round cost uses.
  - The priced action:
    - its worst landed hit on each member (`Driver:roundEnemies`);
    - else its script's worst attack, priced on that member (#255 ROM
      pricing);
    - with an AoE flag from the attack's targeting byte.
  - Part roles from `readParts`: a body whose death ends the fight; a
    part whose death arms a switch.
  - The last-stand counters (#401).
- **The fight's end:** every standing body dead, or the formation's ending
  body dead (`partsPlan`).

**Design intent for forward play.** The catalogue and model below describe
the intended destination; Current candidate coverage states what runs today.
From the state, play an event queue forward until
one of these happens: the fight ends, the party wipes, or a horizon of
`M.RACE_HORIZON` enemy opportunities (default 8), including suppressed
opportunities, runs out.

- **Party turns** take the **continuation policy**: the member's best
  damage line at the boost the bank allows under the current bank rule
  (#174 keyed boost).  The candidate under test replaces only the first
  turn, the one being decided.
- **Enemy turns** deal their priced action.
  - A single-target action goes to the member it has hit most often,
    else the lowest-HP member.  This is pessimistic, as a cautious player
    is.
  - An AoE hits everyone.
  - Future Seizure/Poison ticks would come from measured rates; they are
    not currently simulated.
- **A death** removes the member's future turns and banks nothing.
- **A raise** brings a member back at its raise HP (1/8 max for Fenix
  Down) at the queue position the item's execution lands.

**Outputs, per candidate:**

- `kill`: ticks to the fight's end, or nil if it does not end inside the
  horizon;
- `deaths`: members down at the end, and when the first fell;
- `wipe`: whether the party wipes inside the horizon;
- `left`: the enemy's effective HP at the horizon, shields counted as
  the hits they cost.

## The candidates

Every command the window offers, as `rewind_search.lua` already
enumerates them:

- Fight on each standing body, at each boost the bank pays;
- each kit line (Tools, Blitz, SwdTech, Slot rows, Lore), at each boost
  its price allows;
- each attack spell on each body: Magic, nuke, and the summon;
- each heal item on each member it helps;
- each cure on each member;
- Fenix Down / Life on each fallen member;
- Defend, and Row.

**Hard filters stay hard.**  These are vetoes, not scores:

- the cast guards: absorb, null, Reflect, enemy Runic (#99, #156, #413);
- the counter veto (#372);
- the muddle and defer paths (#170, #348);
- the timed scenes' clock rules;
- statues (#362).

## The score

The comparison is lexicographic, best first:

1. **No wipe inside the horizon.**
2. **Fewer deaths.**  Ties go to the later first death.
3. **The fight ends sooner.**  Compare `kill`; where neither ends, the
   lower `left`.
4. **Cheaper**, in gil, using the item pricing (#370):
   - an item at its gil (`M.itemGil`);
   - a cast's MP at the pool's next refill price (a Tincture's gil per MP);
   - BP at zero, since pips are free to spend.  This is how "dying holding
     pips" goes away: a banked pip is worth nothing at the horizon.

A margin keeps a costly action from winning on noise: candidate B must
beat A by `M.RACE_MARGIN` ticks (default one enemy turn) on criterion 3,
or the cheaper one stands.

## The old rules as test cases

Each rule's measured cases become `battle_healpolicy` cases for the race.
They are written as small race states with the decision the rule made, or
the one its review said it should have made.  Where the race disagrees
with a rule, the case says which was right, with its log line.  The
starting set:

- **#312, the lift:** "a 250 Potion on a member at 523 under a 905
  round".  The race should prefer the attack.
- **#175 / #374, the Rizopas and Nerapa spend cases:** spend before
  dying.
- **#402, the Gate's LOCKE:** 144/820 under a 286 round with an X-Potion.
  It lifts and should stand.
- **#402, the Air Force at shift 40:** Potions that lift over an 818
  round, lost again next round.
- **#414, its review case:** 357/1130 with an X-Potion's 773 against an
  838 round.  The heal must stand against a 0-chip line.
- **#204, the finisher gate:** LOCKE at 134/279 against the gate soldier's
  shields.
- **#168, the owed top-up after a raise:** 213/1710 raised, then refused,
  then died.
- **#395, wipe risk as hits needed:** the healerdown fixtures.
- **#412, the Air Force:** the treadmill at key beBC.

## Where it plugs in

`Driver:makePlan` keeps its menu machinery: steering, cursors, the
button walk.  It hands the choice of *what* to do to `M.raceChoose(state,
candidates)`, a pure function that `battle_healpolicy` can drive with
plain tables.

The lever is `M.CARE_RACE`, now defaulting to `"act"` for the bounded
policy being qualified for v0.26. It plays the race's choice where it
disagrees with the rule stack and the command has an enforceable contract.
A rejected scored command uses ordinary rules for the rest of that battle;
unsupported recipes also keep the ordinary choice. Explicit `"act"` uses
the same policy.  `"log"` (or
true) plays the rules and logs the race's choice beside them: one
`[race]` line per decision, with the scores of both choices.  `false` (or
`"off"`) plays the rules alone.  Every run ends with a `[race] mode ...`
line that counts the leg's decisions, disagreements and overrides.

## Measuring it

The broad comparison protocol below remains useful research. It is not an
additional release prerequisite under the owner's 2026-10-08 stopping bar:
a supported-route clear with ordinary preparation, followed by final-source
qualification and release checks. Such a clear is not a success-rate or
forecast-accuracy claim.

1. **Unit:** the cases above, plus mutants of the score's ordering and
   the horizon.
2. **Rewind search (#375) as the lab.**  At the decisions where the race
   and the rule stack disagree, play both out from the same snapshot
   across draws.  That finds where either loses, before any plain-play
   claim.
3. **Plain play across the whole route by distinct battle key:**
   - arms: `CARE_RACE` on vs off, retries off;
   - legs: every generator with fights, from the line's own captures, at
     about 16 seed shifts each;
   - per key: deaths, Fenix Downs, potions and gil, ticks, wipes;
   - the attrition fights named in #415: the Air Force, battle 68, the
     Sealed Gate cave.

   It ships when it is no worse anywhere and better on the attrition
   fights.

## Risks and choices left open

- **Cost per decision.**  The play-forward runs at every command.  A
  horizon of 8 enemy actions over up to 4 members and about 30 candidates
  is small Lua arithmetic, but it runs in the emulator's frame callback,
  so measure its cost.
- **Pessimism.**  The single-target assignment and the worst-hit pricing
  make the race cautious.  It should still choose damage when no member
  is in reach of a kill within the horizon, so check that it does not
  over-heal on the plain WoR stretches.
- **Statuses**, including future poison/seizure ticks, are not simulated faithfully.
  While a standing member is Muddled, asleep, stopped, frozen, Berserk,
  petrified, a Zombie or departed, the rules play the fight. The Gate
  validation below caught the cost of imagining their planned turns.
- **The continuation policy** is the driver's current attack choice.  If
  the race's own choices make later turns better, the one-step estimate
  undervalues setup moves such as Defend into a bank.  That is accepted
  for now; rewind search shows where it matters.

## After the review (coordinator, 2026-10-06)

- **Scarcity, not just gil.**  A consumable costs its gil times a scarcity
  factor from the bag count against the reserve the rest of the leg wants
  (`M.raceItemCost`: x1 above reserve + 1, rising to x4 for the last
  one), so the race does not spend the last Fenix Downs or Elixirs to
  shave ticks.
- **The aftermath counts.**  The cost criterion adds the post-fight care
  bill: missing HP at the shops' rate, and a member down at its raise
  (`deathCost`).  So "ends a tick sooner with the party at 10%" does not
  beat "ends a little later at 80%" when deaths tie.  The tick margin
  stays.
- **The continuation may heal, one level.**  With `contCare`, a
  continuation turn takes the classic lift before its attack: a heal in
  hand that lifts a member who is inside the next hit clear of it.  It
  does not recurse into the race.  The lab watches for over-healing on
  easy World of Ruin fights.
- **Per-decision cost.**  Standalone Lua on the mbp, 4 members, 6
  enemies, 16 candidates, horizon 8, 16 samples plus the worst case: about
  5 ms a decision with `contCare`, 3.7 without (0.2 ms before sampling).
  No cap so far.
- **Hit chance.**  A Fight lands at `M.hitChance(hand hit rate $3B7C,
  target M.Block $3B55)`: hit x block / 256, out of 100, $FF always lands.
  The hit check (battle_main @233f) reads M.Block for every attack; Evade
  is never read there because the carry is always clear.  Kit lines count
  as landing.
- **Pricing.**  A sold item costs its price x scarcity.  An unsold one
  (Elixir) costs bagHeals' `M.itemGil`, its effect at the shops' rates,
  already scarcity-priced.  Cost decides only beyond a 200-gil margin
  (`M.RACE_COST_MARGIN`); inside it, the sooner kill wins.  A heal that
  only trades its gil for the aftermath bill does not buy a turn.

## Calibration (coordinator, 2026-10-06)

The first Air Force log predicted "WIPE, 3 down" in fights the party won.
The cause: every slot's worst landed hit, always aimed at the member it
would leave lowest.  The model is now:

- **Typical hit.**  An enemy action does its typical landed hit, the
  median of that slot's landings on that member (on anyone, if none),
  once the slot has `M.RACE_TYPICAL_MIN` (3) landings.  Short of that it
  uses its worst.
- **Landing share.**  `act.hit` is the share of the slot's actions that
  landed.  An action counts as area when most of its landings hit more
  than one member.
- **Aim.**  The default is uniform among the living; `act.aim` can name a
  fixed target where the script is deterministic.  The driver does not
  read the script's targeting yet, so every action is aimed at random.
- **Sampling.**  `M.raceEval` plays each candidate 16 times
  (`M.RACE_SAMPLES`) on one fixed list of draws shared by every candidate,
  so the candidates are compared on the same luck.  The score uses the
  samples' mean deaths, cost and HP left, their median kill and first
  death, and the share that wipe.
- **Worst case.**  One play at every slot's worst hit, aimed at the member
  it leaves lowest, sets the wipe flag (criterion 1): a line the worst
  case wipes on loses to one it does not.
- **Checking it.**  Each decision's prediction for the plan played is
  logged against what happened over the same horizon of enemy actions
  (`[race-cal]`).

## What the rewind lab changed (stage 3)

The rewind lab (`tools/tests/rewind_search.lua`, which now takes
`REWIND.when` and `REWIND.extra`) branched each decision where the race
disagreed with the rules.  At each one it played the race's own choice
and the rules' plan to the fight's end.  The model changed where the lab
showed it wrong:

- **Swings carry over.**  A single-target line's swings past its target's
  death go on to the next standing body.  Before this, a boosted Fight
  wasted them, so the race banked BP where the rules boosted.  On the WoR
  from Tzen, the rules' boosted Fight ended the fight sooner in all 8
  distinct pairs, for example 1177 frames against 4009.
- **The damage done now breaks ties.**  When the kill time and the HP left
  are tied and the cost is inside its margin, the damage the decision
  itself deals decides.  Later swings may not land as modelled; this
  one's damage is certain.  The WoR's CELES had cast Cure where a Fight
  tied it on paper, and the fight took two more Fights.
- **The per-hit figure is a median.**  A line's per-hit figure is the
  median of its last eight landings, not the last one.  CELES read 83 a
  hit off one swing and 328 off the next.
- **Lifts read the round.**  The continuation lifts against the round
  before the member's next turn, not one hit.  The worst-case play reads
  the worst hits.  Before this, the guard read a wipe into the Cure line,
  so CELES reached for an Elixir 17 rows down and died while the menu
  walked.

Not modelled: menu time.  An item deep in the list takes hundreds of
frames to reach, and the enemy acts meanwhile.

## The slow legs (before default-on)

Act was slower than the rules on two legs of the whole-route run at
aac04024: narshe_mission (100,413 against 77,707 frames) and
wor_tzen_door (47,589 against 37,920).

- **narshe_mission is upstream XP.**  The leg grinds until the party's best
  level reaches 23.  The act chain arrived 1,312 XP a member short, from
  different encounter draws on the legs before it.  It fought 17 battles
  to the off chain's 12, at the same ticks a battle (3,806 against 3,744).
  From the same checkpoint (terra-returned-v1, shifts 0-5) the arms tie:
  458,357 against 460,026 frames, 12 battles each but one.
- **wor_tzen_door was the Sneeze.**  The leg also grinds to a level, and
  in group 00CC slot 1 ($07C) throws Sneeze ($CB) at a hit that leaves one
  monster standing.  The race's boosted Fight carried its swings from a
  dead body into the next, left the Sneezer alone, and CELES was sneezed
  away, losing the fight's XP.  The race now prices a last-stand removal
  from the driver's own last-stand read:
  - the hitter is removed, a death, and the whole party removed is the
    fight lost (a wipe);
  - the worst-case play reads it against a hit 2x as hard
    (`M.RACE_STAND_SLACK`);
  - it is read on the decision's own action only, and not at all when
    every attack the window offers sets it off, or the race stalls on
    heals;
  - the continuation holds back a boost that would set it off.

  Two more fixes came out of the same leg.  Mean deaths now count only
  beyond one play in sixteen (`M.RACE_DEATH_MARGIN`): a Fight that died in
  1 of 16 plays was losing to a Cure that only stalled.  The draws now come
  from splitmix64: the old LCG fed the sixteen plays their draws at stride
  64, and a 1-in-3 random aim fell 1, 9 and 6 times.

## Before default-on: what the full ninja and the labs caught

- **The Sneezer is the rules' fight.**  A last-stand removal is read on the
  decision's own action at a 2x hit, and a carried swing that takes half
  a body counts as taking it.  Even so, the race kept losing time in
  group 00CC.  At 62cb732f, held boosts cost the WoR from Tzen 147,344
  ticks on its shared keys against the rules' 117,523.  The race now does
  not race a fight while a removal stand is up (`M.RACE_DEFER_STAND`), and
  the rules' kill order plays it.
- **Zombies and members who left.**  The race offers no heal and no Fenix
  Down on a ZOMBIE, and nothing on a member who left.  battle_zombieraise
  was red in the full ninja at 963ea402.
- **Aim.**  The race's Fight aims as the rules' Fight does (`chipAim`).
  battle_classtarget was red at 5b46dbd6.
- **Near fatal.**  A member the play leaves at or under max/8 HP counts as
  half a member down.  audit_party_hp was red at 5b46dbd6: falls_done
  shipped CYAN at 5/358 and esper_tubes_entry EDGAR at 71/752.
- **Full gauges.**  A monster's full gauge acts before a member's.
- **Kefka.**  The race raises EDGAR where the rules held the raise and
  CELES healed herself until she died (wt/v026-supply a4e9f966).  That is
  unit case 26.

Built so far: `M.raceSim`, `M.raceEval`, `M.raceBetter`, `M.raceChoose`,
`M.raceItemCost`, `M.hitChance`, `M.median` (`lib/ot6.lua`), and the
driver's `[race]` log, `[race-cal]` lines and `"act"` mode behind
`M.CARE_RACE`.  The unit tests (`tools/tests/care_race_selftest.lua`)
run 71 checks, including synthetic driver candidate vetoes for zombies and
members who left, closed item/cure lines, disabled boost, Doom and statues; 37 negative controls fail. The synthetic reads do not
produce emulator states or constitute gameplay evidence.

## Current candidate coverage

The list above describes intended coverage. Current scoring offers supported
physical lines at available boost, bag heals, individual Cure casts, and
Fenix Downs. Offensive spells and summons selected by rules are excluded
until canonical effect/price/target records exist; alternative spells,
summons, Life, Defend and Row are not generally enumerated. The spell compiler
has focused contracts, which do not themselves establish live discovery.
ACT compilation binds Fight and Tools to their scored initial target masks.
Blitz/Pummel has no steerable target window and therefore remains ordinary
rules play until its initial aim can be enforced. A rejected compilation
leaves the existing rules plan in force; it removes no normal command access.
Items and raises explicitly acknowledge zero pending boost. Strict targets
back out rather than accepting the steering fallback. Any pre-confirmation
scored-command drop conservatively returns to ordinary rules for the rest
of that battle, so an incompatible choice cannot be selected repeatedly.
The next battle boundary resets eligibility; subsequent
engine retargeting after initial acceptance remains allowed.

Decisions before the first measured hit, during removal last stands, or
while a standing member cannot take its modeled turn use the rules. Future
status and speed evolution and actions already in flight remain model gaps.
The race augments the rules. The owner's current acceptance is route-level
progression with actual kit, supplies, care and ordinary catch-up fights,
rather than matching an exact XP history or minimizing all grinding.


## Final validation findings (2026-10-07)

The 5b4cb9f6 Gate comparison failed the acceptance bar. Shared-key totals
were 164,606 ticks and 6 deaths for the race, 163,108 ticks and 4 deaths for
the rules (43 shared keys). The first fight in shifts 8 and 11 was
`be88-g009B-eFEEEEDED`: 10,283 ticks and 4 deaths against 3,563 and 1.
At shift 11 frame 10,439 the race raised EDGAR while SABIN was Muddled;
its simulated continuation still used SABIN's planned attacks. The race
now defers while a standing member cannot take a planned turn, covering
the status class rather than naming that formation. At d567f6f6, both
arms take 3,563 ticks and finish with one member down on that key. The
new Gate sweep passes all segment attempts and improves the aggregate
shared-key results below. Raw old logs:
`build/attempts/wt/v026-race/final-play/gate/`.

The Train generator's battle 68 uses its own local `makePlan`, not this
driver, and now ends through Suplex. Its on/off segment comparison
measures the random battles on the approach, not a race-policy change in
battle 68. It cannot satisfy that part of #415's original acceptance bar.


At d567f6f6, the final matched sweeps use the same legal starting
checkpoint within each segment, seed shifts 0–15, no retries, and eight
claimed emulator slots on px13. The retained provenance records the
library, ROM and emulator, along with the actual starting states. Counts
below are distinct shared battle keys; ticks, deaths and wins are **sums
of per-key means**, not independent attempts or measured probabilities.

| Segment | Shared keys | Race ticks / rules ticks | Race down / rules down | Race wins / rules wins |
| --- | ---: | ---: | ---: | ---: |
| Air Force boss (01CB) | 4 | 34,321 / 36,154 | 0 / 0 | 4 / 4 |
| Sealed Gate | 45 | 164,750 / 169,508 | 3 / 4 | 45 / 45 |
| Train approach | 65 | 107,422 / 106,721 | 0 / 0 | 49 / 49 |
| Tzen Sneezer (00CC) | 22 | 79,408 / 84,468 | 0 / 0 | 19 / 20 |

Raw summaries, per-key rows and all controller-play logs are retained in
`build/attempts/wt/v026-race/final-play/d567/`; the portable archive is
`final-play/d567-final-evidence.tgz`. The table quotes the lines beginning
`keys:` and `shared keys, sum of per-key means:` in the corresponding
`race-d567f6f6-*-keypair.txt` files. The Train comparison contains flee
outcomes; not every observed approach battle is intended to be won.

All race Air Force segments pass; the rules' shift 14 wipes in IAF trash
before the boss. Both arms complete every Gate, Train and Tzen segment.
This does not establish domination on each battle key: the Air Force
`beE0-g01CB-e5E655D5D` race takes 8,008 ticks against 6,633. The Sneezer
`beD0-g00CC-eBD9E95A6` logs `PARTY LEFT` at 2,716 ticks under the race,
against a win at 2,639 under the rules. No race override occurs inside
that lost fight; earlier play changes the arriving resources and timing,
so deferring the Sneezer's decisions does not prove no downstream harm.
A passing segment target can hide an unrewarded fight.

The status guard has a narrow synthetic red/green check: removing it
fails `Muddle contributes no imagined continuation`. Current unit output
begins `care_race_selftest: PASS -- 71 checks:` and all 37 retained negative
controls fail their expected assertions. The earlier boost-continuation
check's first fixture was invalid (both arms died before the next turn);
the corrected fixture and diagnostic are retained, and the correction
was committed without rewriting the published failed attempt.

These results support the Gate fix and faster aggregate Air Force/Gate
play. They leave the original all-command coverage, direct battle 68
improvement, every-key no-regression, and final whole-route matched
comparison open. The historical aac04024 whole-route comparison cannot
qualify later library changes. Independent review and final release play
under the landed release library are still required.


The clean bare branch qualification at d567f6f6 is **red**, not a release
qualification. Its result is `end 2026-10-07T15:40:57Z rc=1 wall=5215s`.
The log reports `FAILED: [code=1]` for `battle_cointoss`,
`battle_setzeraim` and `battle_passside`: respectively a paying pass with
no body hit, zero aimed Hired Help executions, and missing emptied-side
coverage. All three fail the same assertions with `CARE_RACE=false` from
the exact generated `wor-tomb-v1` battery. Coin Toss and the aimed Hire
originally log zero raced decisions and zero overrides. This shows an immediate
race override is not required for the failures. The arriving state and
scripted controller remain to be investigated; the failed checks remain
failed. No assertions, seed
budgets or timeouts were changed, and the qualification was not retried.

The complete qualification log, generated-state logs and original
provenance are retained in `final-play/d567-qualification.tgz`; extracted
terminal logs are in `final-play/qualification/build/`. The original
failing workers and Tomb battery are in
`final-play/race-d567-failure-artifacts.tgz`. Matched rules-only
assertion failures are in `final-play/race-d567-suite-off.tgz`. These
paths are all beneath `build/attempts/wt/v026-race/`. The first archive's
retained tar diagnostic names absent optional screenshot/hash paths;
the separate failure archive supplies the original worker artifacts.
Both tracked-status files are empty. All branch jobs exited before the
report. This remaining coverage failure needs a separate controller or
fixture decision; a green build has not been claimed.

## Holistic revision: executable actions, shared resources, and time

Owner, 2026-10-07: spend another few hours on the big idea, rather than
reduce #415 to its latest local regression. The independent read exposed
one recurring problem: the action scored was not necessarily the action
the controller could play. The model is being revised around three
contracts, before measuring a new strategy.

1. **Executable action.** Freeze verb, actual affordable boost, MP price,
   target, per-body hit chance and shield effect before comparison. The
   same record supplies the controller plan. A requested three-BP tool
   stepped down to zero is one zero-BP action, not a fourfold attack.
   Enumerate the currently supported Fight/Tools/Pummel alternatives
   before the old chip heuristic selects one, deduplicating affordable
   downgrades. Project the rules' actual action, never the different
   `bestLine` that happens to share its boost index. Unknown verbs remain
   unmodelled; they need an explicit effect record, not a guessed stand-in.
2. **Shared resource state.** Every candidate starts with its own copy of
   the party's shared bag and each member's MP/BP. The first command and
   subsequent commands debit those same pools. A Potion is not available
   once per actor; kit and cure turns share MP. When a kit runs out, the
   continuation may take the real free Fight. A pending heal or raise is
   a commitment, not another new care opportunity. Repeated falls count
   separately from members still down at the end, so raising everyone
   does not erase the damage the policy did during the fight.
3. **One event timeline.** The first command resolves at its action's
   delay, with enemy turns and target changes advanced before it. A full
   monster gauge wins the tie. A model must be able to distinguish an
   item reached after the next hit from a cure reached before it. The
   driver records navigation, queue and execution intervals separately from
   the recovery action trace. Execution end is not first-effect time:
   damage can kill a monster during an animation before another actor
   gets a turn. The observer retains those facts but supplies no effect
   latency until an attributed effect observer exists. Unknown timing
   excludes first commands and invalidates required continuations; it
   never implies zero. Consequently this revision observes real play
   without making live race overrides yet.

The new synthetic controls cover these contracts; their results are not
legal play or balance evidence. Raw development failures and mutants are
retained under `build/attempts/wt/v026-race/holistic/`. Older whole-route
and d567f6f6 comparisons describe the old policy and do not qualify this
revision.

Still required: a complete command catalogue (including alternative
spells, summons, Life, Defend and Row with faithful effects), validation of measured
navigation/queue/execution latency across menu and battle states, treatment of actions already in flight, and independent review.
Then branch both commands at disagreements from legitimate coherent
snapshots, and evaluate fixed policies independently across fresh route
attempts. Retain local controls and upstream arrival-state effects: the
Sneezer's lost reward remains in the retained history. The owner's current
acceptance allows that arrival-state variation if ordinary preparation and
catch-up play can continue through the supported route.

Independent review of d7e854df found that execution completion cannot stand
in for effect timing, unknown continuations could still act instantly, and
the final shield chip was applied after its hit's damage. The follow-up
keeps trace stages separate and withholds unobserved effect delays, rejects
unknown continuation timing, and chips before damage as `Ot6HitJoin` does.
The synthetic tie fixture now deliberately has no matching break key;
the old one-shield fixture actually ends on the first Fight under the
correct engine ordering. Raw failures are retained in
`holistic/break-order-first.log` and `break-order-second.log`.

The revision is still an experimental branch. A log/off Gate batch at
d7e854df collects command traces from the same legitimate Narshe battery;
it is observation of the earlier timing approximation, not qualification
of the corrected timing model or an acting policy.


### Attributed effect timing stage

The next observer brackets `ApplyDmg` with read-only CPU hooks. Its entry
identifies the attacker and target; the return reads the changed HP after
healing, damage and lethal clamping. Only a matching accepted/running
menu command owns the effect; an enemy, engine tick or unrelated queued
command cannot supply its sample. Every nonzero HP change retains its
target and time, including multiple targets and boosted passes. Raw
accepted command/attack identity remains distinct from the requested
spell or item (tier folding may change it).

The current simulator aggregates a command's hits at one event. Its
explicit approximation will place that event between the observed first
and last HP-effect times, rather than equating it with animation end.
Using the last effect is conservative about when a whole volley can kill;
using the first bounds the opposite ordering. Both compared commands and
their continuations use the same early/late scenarios. The interval spans
retained observed minima/maxima with one 30-frame controller pulse of
slack; this is an experience-based estimate, not a hard guarantee. Close
calls or a reversal across these scenarios keep the rules. Per-hit event
scheduling remains a later refinement if retained disagreements require
it. No acting or balance claim follows from the observer itself.


The effect stage's timeline uses the engine's `$3A3E` update counter,
modulo 16 bits. `UpdateBattleTime` advances gauges once per two video
frames and can pause under the battle-program/wait mask. Raw video-frame
navigation/queue/execution fields remain diagnostic facts; they are not
added directly to a gauge ETA. Effect estimates span the observed first
and last HP effects in update ticks, with 15 update ticks (one controller
pulse at the unpaused rate) of slack. Before an exact action has landed,
supported commands use a declared coarse pulse/queue/execution estimate,
with minima of 900 video frames each for queue and execution, enlarged by
observed lifecycle update counts. These are bounded experience guesses,
not causal guarantees or hard statistical bounds. The first pulse-count
estimate ignores freezes; its broad range and paired sensitivity are
intended to reveal unstable choices.

Early, central and late estimates apply to both first actions and all
continuations. A candidate must retain material gain and avoid added
sampled wipe/down/fall risk in every scenario. The model still approximates
queued action serialization and aggregates a volley at one event; a full
monster gauge wins ties conservatively. The default remains off while
these assumptions receive legal-play observation and independent review.


### Finite break stage (experimental)

A race body now carries its authored maximum shields separately from its
current gauge and remaining broken window. `Ot6ShieldedDmg` distinguishes
three states: shielded damage is half normal, a naturally shieldless body
takes normal damage, and a broken body takes double normal damage. Race
measurement normalizes those as 1/2/4 shielded equivalents without changing
the existing rules' damage ledger.

Breaking suppresses modeled enemy opportunities until expiry; expiry
restores the authored shield maximum before the next event. The engine's
`DecCounters` visits each entity once per sixteen `UpdateBattleTime` updates
and consumes a broken count when its speed accumulator overflows. Existing
remaining time is read from that accumulator, the next entity phase and
`BROKEN_TICKS`. A newly created break uses bounds covering every phase of
the sixteen-count timer at its current speed; both compared commands use
the same early/central/late duration scenario. Haste or slow changes during
the projected window remain unmodelled.

The enemy timeline still uses estimated periodic opportunities rather than
reproducing the queue: a full gauge held behind the queue-time break gate
may act earlier on recovery than this estimate, and a command already
executing can finish its current hits. These are explicit remaining gaps,
not a claim of faithful queue emulation. The three retained before-fix
contract failures and new arithmetic checks establish suppression, finite
recovery and shieldless damage; they do not establish acting-policy wins.

The model horizon counts enemy opportunities, including suppressed ones;
the historical action-count calibration is not yet a matched observation
of that revised horizon. It must be aligned before it supports acting
claims.

### Accepted execution token observation (experimental)

Every ExecCmd entry creates a fresh execution token, including enemy,
engine, counter and untraced commands. Only a normal party invocation with
matching queued command `$3A7C` can consume that actor's submitted plan.
The token freezes its actor, trace ID, accepted command/attack and stable
queued `$3A7C/$3A7D` identity. ApplyDmg brackets retain the token and queued
identity at entry and require both to remain current at return. Reload and
replacement contexts invalidate ownership; same-actor retaliation cannot
consume a waiting normal action.

Fight rotates `$B6` for the hand, Tools and Pummel rebase ability IDs, and
weapon magic changes `$B5/$B6` within its parent dispatcher. An attributed
HP event therefore retains accepted command/attack separately from raw
`raw_effect_command`/`raw_effect_attack`. The immutable token, stable queue
identity and actor are the attribution guard; raw engine commands remain
excluded. Source references are InitPlayerAction, ExecCmd, Cmd_09, Cmd_0a,
CheckWeaponMagic and ExecRetal in `battle_main.asm`. Synthetic controls
exercise internal children and unrelated/stale contexts. This observation
stage does not authorize the default acting policy or close catalogue and
queue-model gaps.

The token is now tied to an engine queue allocation, rather than merely a
matching opcode. A zero-byte source label observes CreateAction after
Ot6QueueFold stores its actual command/attack and targets. Each store
replaces that slot's provenance with a fresh generation, traced or
untraced. InitPlayerAction supplies the executing slot; ExecCmd must find
that exact trace, generation, actor and stored identity before consuming
it. RemoveAllActions cancels queued traces and clears their bindings.
An automatic same-opcode action therefore cannot steal an earlier user
submission, even when its attack byte is identical. XMagic's second entry
is deliberately untraced; it cannot consume the first entry's provenance.
Synthetic cancellation, reuse, folded spell and collision cases cover
this origin contract. The earlier 8e96d516 Gate observation establishes
physical child identity only; it predates this queue-origin correction.

Production observation rejects absent queue provenance. The captured
InitPlayerAction index is consumed and cleared at every dispatcher entry;
a canceled/no-action dispatcher cannot reuse its predecessor's index.
Token arithmetic tests use an explicitly separate `legacyStart` helper
when they have no engine queue. ApplyDmg brackets live on the trace object,
not a callback-local stack, so the existing H/Driver Lua-heap snapshot
can reach them. Reload clears that stack; this source property is not yet
a measured mid-instruction rewind compatibility claim.


### Supported skill boost arithmetic

Tools and Pummel buy the damage multiplier in `Ot6BoostDmg`: one left shift
per BP, giving x1/x2/x4/x8. Their learned per-hit values are normalized by
that same factor before being reused at another boost. Fight buys extra
swings and keeps each hit's damage unchanged. Tier-family spells require
the resolved tier's own effect; the supported skill multiplier is not a
blanket recipe for those spells. A retained before-fix arithmetic contract
shows Tools at two BP predicted 300 from base100 where the ROM buys400.

### Caster-aware catalogue prices

`battleSpellPrice(actor, menuAbility, totalBoost)` reads the ability's raw
`MagicProp` cost, resolves a family head once, and applies that caster's
relic byte. Economizer wins over Gold Hairpin; Hairpin uses the ROM's
rounded half. Family tiers stop there, while other abilities take the
2.5x price ladder, including the equipped esper's ability record. A live
list price already includes pending boost and cannot be used as a base:
rounding and the cap make inversion ambiguous. The legacy `spellPrice`
unboosted-base API remains unchanged.

This catalogue API has synthetic contracts for all four caster offsets,
boost amounts, relic combinations, family/owned-tier/nonfamily/esper costs
and malformed input. It is not yet connected to candidate discovery or
execution. That connection must preserve total boost, resolved effect,
menu identity and targets, and establish the corresponding controller
acknowledgments. These arithmetic checks are not played spell evidence.

Race attack compilation now marks the copied line plan with its exact
total boost. At command selection the driver presses normal L/R inputs
until pending BP equals that total, including stepping down to zero.
A bank that no longer pays the scored total drops the plan rather than
settling at a different action. Unacknowledged presses remain bounded by
the existing parked-window and plan-pulse watchdogs. Synthetic tests call
the real compiler and button method across actor offsets, banks and
pending totals. This establishes command-window acknowledgment only;
it does not establish final targets or resolved effects for the broader
catalogue, nor improve the retained acting-route outcome claim.

### Spell compilation and initial target contracts

The compiler preserves menu spell identity separately from the resolved
execution ability and caster-aware price. Existing single-ally unboosted
cures receive total boost zero and a single-character mask. Other spell
records require an explicit controller kind, HP effect role and exact
character/monster masks with single/group intent. New offensive/group
spell discovery remains absent; revival, status, summon, mixed-side and
special-layout remapping remain unsupported.

Strict spell plans acknowledge the live list price, usability, caster
price and total boost again before selecting and confirming. Their target
masks override authored focus. A changed mask or failed group latch drops
the scored plan instead of silently becoming another body or a single
cast. Ally groups go through common safety, watch and trace bookkeeping.
A boosted single heal skips the legacy unboosted-menu restore ledger until
learning is keyed by the resolved effect recipe.

The observer retains actual submitted command/attack/targets/boost before
rejecting a mismatched scored contract as unresolved. Folded queue stores
must match the expected ability and initial targets before acquiring
execution ownership; mismatch records retain observed and expected data.
Rejection cannot undo a command already accepted by the engine. Optimistic
confirmation watches retain ordinary settlement behavior. The initial
target contract permits the engine's subsequent carried/retargeted hits.

Compilation currently conservatively checks the live list before changing
pending boost. An expensive or grey pending tier can exclude an affordable
lower-total candidate until replanning. Candidate discovery must eventually
price availability at its desired total rather than inherit that exclusion.
Synthetic contracts establish these mechanisms, not legal spell execution
or whole-policy improvement.

Three retained normal-controller probes at `75fc2a89` establish legal
execution for single Fire (zero boost), Fire2 against two enemies (two
boost), and Cure2 on the party (two boost, two meaningful recipients).
Submitted and queued identities, accepted boosts, initial target masks and
attributed HP effects matched. The initial Fire policy repeatedly offered
a fire-absorbed cast and lost; that failure and an earlier singleton group
cast are retained. These are mechanism examples, not a spell policy rate.
Evidence: `build/attempts/wt/v026-race/holistic/spell-75fc2a89/`.

### Observed reward eligibility

The optional race observer records seated character identities, positive-HP
Zombie and other `$C2` status changes, HP death, removal and restoration
separately. At the UpdateSRAM reward snapshot it records the engine's alive
mask, calculated due XP and actual per-character XP change. A last-watch
fallback is explicitly labelled with its original sample frame and ATB
tick; it must not be reported as a reward-boundary observation. Changed or
missing character identities leave eligibility, status and reference
allocation unknown, while measured XP stays attached to the original seat.

A separate equal-share reference divides the battle's reward pool among
all original seated members, applying their Exp Eggs. A foregone reference
share is counterfactual accounting, not the engine's redistributed due XP.
Later field curing cannot rewrite the finalized record. Each battle gets a
new ledger, including when the route reuses its driver. This observer is
read-only, enabled with the race or explicit `raceEligibility` option;
it changes neither candidate discovery nor scores. Status evolution and
predicted terminal eligibility remain unmodelled. Evidence:
`build/attempts/wt/v026-race/holistic/eligibility/`.

### Elapsed-ATB comparison primitives

Optional `timeHorizon` simulation now stops at an inclusive elapsed-ATB
cutoff, recovering break state at that instant even between events. Its
opportunities, suppressed opportunities and unsuppressed modeled turns
are separate; none is an observed completed-action ledger count. A budget
helper derives one cutoff from the original enemy timetable before either
candidate acts. A sampled global-clock observer handles wrap and paused
menus; early endings, reset/ambiguous jumps and overshoot are censored.

These primitives are not wired into live calibration or acting scores.
The existing opportunity-horizon policy remains unchanged. Its legacy
calibration counts observed closed action units, so it still lacks a
matched horizon. Next: shadow predictions for both original alternatives
at the same predeclared deadline, actual terminal readings before battle
clock reset, and explicit near-fatal penalty versus actual down count.
Queue/in-flight effects and continuation policy remain approximations.
Evidence: `build/attempts/wt/v026-race/holistic/time-window/`.

### Opt-in selected-policy time shadows

`RACE_TIME_DIAGNOSTIC` defaults off. With the race enabled, it evaluates
both original candidates under one predecision elapsed-ATB budget alongside
the existing scores. The extra estimates do not choose or steer an action.
They retain pure HP-down and near-fatal counts separately from the ranking's
fractional penalty. Modeled removal still counts as HP-down; observed removal
is recorded separately and censored rather than claiming matched semantics.

The observer samples the global clock even while gauges are full, saving
initial, changed party and final readings rather than a snapshot every frame.
Its terminal record identifies the selected actor, original frame/tick, bound
first-action trace, accepted/start/resolved facts, and final frame/tick/source.
Only the selected policy is observed; the other candidate is a prediction.
`calibration=false` remains explicit even for an uncensored fixed endpoint.
A valid bound first action is necessary to interpret that endpoint; it does
not establish the modeled continuation or counterfactual outcome as correct.

The UpdateSRAM hook supplies one pre-reset HP/status/identity/clock sample.
Missing end snapshots, early endings, overshoot, resets, identity/status or
removal changes, unverified/canceled first actions, and predictions terminating by the
cutoff are censored. Unsupported/pending alternatives are declined.
Terminal records stay with the outcome when the driver starts another
battle. HP-down is not a comprehensive incapacitation or XP-eligibility
measure: positive-HP Zombie and other status changes remain raw observations.
The original completed-action calibration remains unchanged and unmatched.
Evidence: `build/attempts/wt/v026-race/holistic/time-shadow/`; standalone
synthetic wiring contracts, not a played or general policy claim.

The first live shadow batch exposed over-censoring: production resolution
records carry no `valid` flag, whereas the first synthetic tests invented
one. First-action verification now follows the actual emitter: accepted
ID/actor, strict queue index/generation and execution context at start, then
matching command/attack/queued identity/targets at resolution. The integration
contract drives production plan/submit/queueStore/start/resolve emitters;
legacy arithmetic starts without queue provenance remain censored. The first
batch is retained as evidence of the observer defect, not live calibration.

Prospective Gate shift2 play at `149a4f71` passed scoped independent raw
review. The acting policy with diagnostics off/on produced identical4790
pad entries and six outcomes, both PASS40993 first attempt; the rules
shadow passed40529 first attempt. Acting18/rules19 windows have17 verified
first actions each and five exact deadlines each, with four/five uncensored
views respectively. Trace20 was accepted but unexecuted at the end snapshot
and canceled afterward. Early termination and unsupported status history
remain censored. No calibration accuracy or policy-rate claim follows.
The first `b1b701e8` batch remains a failed observer-integration attempt;
the repaired producer contract does not retroactively change its verdict.
Evidence: `build/attempts/wt/v026-race/holistic/time-shadow-play/`, especially
`fix-149a4f71/independent-review.md` and `comparison.json`.

The prior XP difference still reproduces: Terra earned5311 versus6383 under
rules, others earned6740 versus6383 each. The continued Gate capture has
Terra total XP28143; that accumulated total is distinct from earned5311. The shadow instrument changes no acting scores.
Selected-plan ownership, modeled opportunities and observed closed ledger
units are now separable within one elapsed window. Queue occupancy,
in-flight effects and future status prediction remain the next modeling
work for later refinement. These gaps do not replace the owner's present
supported-route acceptance bar.
