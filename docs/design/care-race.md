# The care race: one decision for every command (#415)

Status: implemented, default-on; final matched validation in progress.
Owner and coordinator, 2026-10-06; validation updated 2026-10-07.

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

**The forward play.**  From the state, play an event queue forward until
one of these happens: the fight ends, the party wipes, or a horizon of
`M.RACE_HORIZON` enemy actions (default 8) runs out.

- **Party turns** take the **continuation policy**: the member's best
  damage line at the boost the bank allows under the current bank rule
  (#174 keyed boost).  The candidate under test replaces only the first
  turn, the one being decided.
- **Enemy turns** deal their priced action.
  - A single-target action goes to the member it has hit most often,
    else the lowest-HP member.  This is pessimistic, as a cautious player
    is.
  - An AoE hits everyone.
  - Seizure/Poison ticks come from the measured tick rate.
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

The lever is `M.CARE_RACE`, and its default is `"act"`: where the race
disagrees with the rule stack, the race's choice is played.  `"log"` (or
true) plays the rules and logs the race's choice beside them: one
`[race]` line per decision, with the scores of both choices.  `false` (or
`"off"`) plays the rules alone.  Every run ends with a `[race] mode ...`
line that counts the leg's decisions, disagreements and overrides.

## Measuring it

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
- **Statuses** beyond death and the ticks (Muddle, Sleep, Stop) enter
  only as "this member loses its turns until cured".  The cure candidates
  score through that.
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
run 62 checks, including synthetic driver candidate vetoes for zombies and
members who left, closed item/cure lines, disabled boost, Doom and statues; 36 negative controls fail. The synthetic reads do not
produce emulator states or constitute gameplay evidence.

## Current candidate coverage

The list above describes the intended coverage. The implementation offers
`bestLine` at each available boost, bag heals, individual Cure casts, and
Fenix Downs. It can score a measured offensive spell or summon selected by
the rules, but does not generally enumerate alternative offensive spells,
summons, Life, Defend or Row. Decisions before the first measured hit, while a removal last stand
remains, and while a standing party member cannot take a planned turn
(Muddle, Sleep, Stop, Frozen, Berserk, Petrify, Zombie or departure) use
the rules. It therefore augments
the rule stack rather than replacing every decision. Menu time is also
still outside its estimate. The issue's no-regression and attrition
improvement bar requires final matched evidence before closure.


## Final validation findings (2026-10-07)

The 5b4cb9f6 Gate comparison failed the acceptance bar. Shared-key totals
were 164,606 ticks and 6 deaths for the race, 163,108 ticks and 4 deaths for
the rules (43 shared keys). The first fight in shifts 8 and 11 was
`be88-g009B-eFEEEEDED`: 10,283 ticks and 4 deaths against 3,563 and 1.
At shift 11 frame 10,439 the race raised EDGAR while SABIN was Muddled;
its simulated continuation still used SABIN's planned attacks. The race
now defers while a standing member cannot take a planned turn, covering
the status class rather than naming that formation. New matched Gate
validation is required before counting that fix as effective. Raw logs:
`build/attempts/wt/v026-race/final-play/gate/`.

The Train generator's battle 68 uses its own local `makePlan`, not this
driver, and now ends through Suplex. Its on/off segment comparison
measures the random battles on the approach, not a race-policy change in
battle 68. It cannot satisfy that part of #415's original acceptance bar.
