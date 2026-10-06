# The care race: one decision for every command (#415)

Status: design, not built.  Owner and coordinator, 2026-10-06.

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
already makes.  It reads nothing a person could not know.

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

The lever is `M.CARE_RACE`, false by default until it is measured.  While
it is false, the rule stack decides as today.  While it is true, the rule
stack only logs what it would have done beside the race's choice: one
`[race]` line per decision, with each candidate's score, so a lab can
read every disagreement.

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
- **Per-decision cost** is measured in the frame callback: wall time per
  command and the total over a leg.  Candidates or the horizon are capped
  if it shows in leg wall time.
- **Misses and crits.**  A line's and an enemy action's `hit` (0..1)
  scale their damage where the ROM gives the rate cheaply (the spell's
  hit rate, the monster's evade against a Fight).  Otherwise damage is
  deterministic.

Built so far: `M.raceSim`, `M.raceBetter`, `M.raceChoose`, `M.raceItemCost`
(`lib/ot6.lua`), and `tools/tests/care_race_selftest.lua`: the old rules'
cases, 16 checks, each of six mutants of the score caught.
