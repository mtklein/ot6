# OT6 guidelines

The owner's standing guidance for anyone working on OT6: people, coding
models, and the agents they launch. These are guidelines, not rules:
judgment applied case by case, levers rather than laws. When a guideline
conflicts with what a thoughtful person would do in the moment, do that and
say why. "Rule" is reserved for mechanical code behaviour and game
mechanics.

[TESTING.md](TESTING.md) is the testing policy (what counts as play and as
evidence); this file does not restate it.

## Playing the game

The harness plays OT6 the way a competent person with a controller would. It may
read anything (memory, the ROM's data, an experienced player's knowledge of
what's ahead) and acts only through the inputs a person has: read with full
power, write like a human (owner, 2026-09-30).

- **Fight rather than flee.** Win with levels, gear, kill order and
  abilities; flee where the game forces it, or from a random battle inside
  a timed scene when the visible clock can't cover another fight (owner,
  2026-09-28).
  Skipped fights are skipped XP, and the debt tends to surface at a later,
  harder fight. Grinding is normal play; "the party is too low for this" is
  a fine finding, and the answer is usually healthy levels at key points.
- **Play the whole game a player might reach**, not just the story route:
  optional characters, areas and sidequests, as much of the Colosseum as is
  practical, and the eight dragons.
- **Aim for competence across the route.** Segments should be played
  confidently; one the party can't reliably win on the first attempt is
  worth a lab until it can.
- **A lost battle is normal.** A person who wipes reloads and goes again.
  Segments can retry from their boot checkpoint on a wipe, bounded and
  counted, with the seed, cause and boosts at death logged. A loss here and
  there is just a line in the retry inventory; repeated losses, or a loss
  rate above the band, suggest a lab. Retry machinery built to re-roll a fight until it passes isn't play.
- **Spend like a person watching their gil.** Choices between supplies
  (a Tent or Potions, which item heals) are best priced in gil from what the
  bag would actually spend, rather than fixed thresholds.
- **A win is a win and a loss is a loss.** A fight won some other way than
  planned (the boss killed before its break, a mechanic not exercised)
  counts as a win, with a tuning note to circle back to. Re-running it
  across draws to learn how often that happens is useful: one fight in five
  and four in five call for different decisions.
- **Classify wipes by boost at death.** An early one-shot usually means the
  party is under-levelled (a level/kit finding); a wipe with pips still
  banked suggests the abilities weren't used fully (a driver/policy
  finding). A member one round from death with boost
  banked would do well to spend it.
- **Heal outside battles** as the default: field care after battles, with
  Tonics (stock about 99; where no shop sells Tonics, Potions sized to what
  the following legs spend). Automatic care leans on items rather than MP;
  a deliberate pre-boss stop may cast, since level-ups restore MP. Timed
  scenes are the exception: no menus inside a live event timer.
- **Turns are the scarce resource in combat.** Heal in battle with Potions
  rather than Tonics, and prefer one strong effect (a boosted Cure on the
  whole party) over several weak turns. About one care action per round;
  ending the fight is often the strongest heal. Needing lots of healing in
  combat is a hint to level up or re-gear.
- **Supply band, roughly:** about level × 5 Tonics and about level Fenix
  Downs (caps near 99 and 20), and about level × 1.5 Potions before a boss
  gauntlet. Below the band, a detour to town makes sense; a town stop tops
  up, buys the scarcest item last, and puts the combat items at the top of
  the bag.
- **Fenix Downs are a signal.** More than one or two in a hard fight, or
  any in a random battle, points to under-levelling or a fight worth a lab.
  An occasional death to a vanilla mechanic is fine; labs are for frequent
  deaths, wipes, or heavy Fenix use.
- **Boost-Fight through random battles** is a good default: unbroken enemies
  take about half damage and everyone starts with one pip, so a one-pip
  boosted Fight restores vanilla pace. Break and boost are levers, not
  rules like "never boost the shield strip" or "never nuke before the
  break"; try the options and measure.
- **Relics matter**, the Genji Glove especially: a pair doubles the hits
  that land on a boosted Fight, so it usually belongs on the main
  boost-Fighter. Readiness-audit flags (an empty relic slot with a spare in
  the bag, a better weapon on offer) are worth acting on.
- **Ribbons are worth going out of your way for** (owner, 2026-10-01), and
  so is gear like them: a detour for a Ribbon is what a player does, and
  it goes on the moment it's in the bag. Route and kit choices follow what
  a player would do; the cost in chain length or re-cuts is ours to absorb.
- **Use the commands the game offers.** A menu the driver doesn't know is a
  verb left on the table (Throw, Rage, Slot, Dance, Sketch, Morph...):
  implement it, measuring the menu on a fixture first.

## Designing the game

- **Boost pays once.** One action's boost buys one payoff. Fight and
  Capture: extra swings (a weapon's own on-hit spell isn't also multiplied).
  Tier spells: the tier. Rage: the special's likelihood. Slot, Steal,
  Bushido: their own ladders. Everything else: the damage multiplier. A
  boost that costs pips and buys nothing is a bug to fix.
- **Design break data for the encounters players meet.** Each species gets
  an authored shield row (shield count and break classes), designed from its
  body, its vanilla elements and the party that meets it there, so the party
  holds a key and the area teaches something. The generated floor is a
  safety net, not a design. Each area gets a design doc like
  [break-coverage-gate.md](design/break-coverage-gate.md) and a suite that
  checks the rows in the built ROM; `tools/audit_break_coverage.py`'s tuning
  claim grows only as play backs it.
- **Special (¤) is a common key.** Setzer's cards and dice and Relm's
  brushes do best with plenty to break: spirits, magical and cursed bodies
  and some bosses can take ¤ beside their other keys, often enough that
  bringing Setzer or Relm is a real choice, without ¤ becoming the answer
  to every fight (owner, 2026-10-01).
- **Every recruit should feel amazing and important on arrival** (owner,
  2026-10-01). The area right after a character joins is a good place to
  show what only they bring: break keys their weapons or skills hold that
  the party lacked, a kit ready to use, and gear worth wearing from the
  first fight. Each arc's route plan can say how its recruit shines, and
  play can measure it (who lands the breaks, whose actions end fights).
- **Prefer not to retune vanilla enemies** (AI scripts, spells, one-shots)
  to dodge a hard fight. OT6 changes battle systems more than individual
  enemy quirks; a hard fight is usually answered with levels, gear, route or
  strategy.
- **Teach OT6 plainly, out of character.** In-game teaching (the Narshe
  school) explains what's new relative to vanilla FF6 in terms that make
  sense to the player: breaking the fourth wall is fine, and mystery or
  coyness doesn't help. Explaining each key mechanic once keeps it clear.
- **Stronger spells come from boosting.** Characters' natural magic and
  Espers grant base spells; boosting is how a player reaches Fire 2, Fire 3
  and the rest, and the rebalances assume that.
- **Mimic is free.** A mimic copies the action, not the price; a boost buys
  what it buys on the copied action.
- **Octopath-style twists on FF6 characters are welcome** (Shadow's break
  that kills). Shadow stays in the party the whole game.
- **The World of Balance / World of Ruin split is a storytelling boundary,
  not a technical one.** What the World of Ruin teaches (driver mechanics,
  kill orders, design fixes) is welcome in the World of Balance too; measure
  it there and say that it applies.
- **MP tension is the target.** Having to choose between spending MP on
  abilities in random fights and saving it for the boss means the
  difficulty is balanced well; keep that choice alive when tuning.
- **Save compatibility becomes a promise at v1.0.** While releases are v0.x,
  keeping older saves loading ([save-layout.md](design/save-layout.md)) is
  nice to have, not a constraint; design for what is current rather than
  adding workarounds for old saves (owner, 2026-09-29). A release is promoted to v1.0
  retroactively once it is fun and solid enough to keep that promise.
- **Priorities, roughly:** release reliability, then labs on fights won by
  attrition or a coin flip (a measured success rate rather than a selected
  win), then fun and the Octopath feel; take the highest of these with a
  checkable unit ready. Quality over time: there are no
  deadlines, and slow protocols, controls or regenerations are worth their
  time.

## Testing and debugging

- **Handle the encounters the game can deal.** A test, generator or driver
  counts as correct when it copes with every encounter, formation and draw
  the game can deal at that point, not just the one its fixture happened to draw. ROM changes
  regenerate the fixture chain and reshuffle encounters; fixing what that
  exposes is routine work. The evidence bar for test changes is in
  [TESTING.md](TESTING.md).
- **Shifting randomness isn't a blocker.** Route changes reshuffle later
  encounters. Segments can retry from their boot snapshot on a
  draw-dependent failure, counted and logged; sweeping across draws finds
  brittleness early, and fixing a failure class at its root pays off.
- **Luck standing in for a precondition** is the most common defect class.
  When a suite goes red after an unrelated change, suspect the suite, then
  prove it. The good fix reaches the precondition and asserts it, rather
  than widening a timeout, re-rolling a seed, or weakening an assertion.
- **A regression ships with its test**: red on the regressed build, green
  after. Tooling defects are simplest to fix
  directly, without tests of the test tooling.
- **Look at the screen.** Scripts watch what they're doing and fail fast
  with the failure frame; reading the frame and the log beats theorizing.
- **Few foreseeable surprises.** FF6's mechanics are finite and documented
  (battle arrangements, statuses, specials, menus, vehicles). Keeping
  [mechanics-coverage.md](design/mechanics-coverage.md) current helps; when
  one member of a class shows up unhandled, enumerate the class. An unknown
  menu firing is a missing verb.
- **Be slow to conclude "impossible"** or that the ROM "diverged" from a
  static model or a partial trace. Check the source's history, trace the
  event scripts and gates, and drive it in the emulator.
- **Take observations literally; measure before theorizing.**

## Releases and the repository

- **The release bar** is a fluid, honest playthrough of the supported route
  with few game-overs. Retry sites in the qualification run are lab
  candidates, and each save point along it gets a checkpoint.
- **Release notes are for players**: what you'll notice, why to update,
  what to watch for, in play terms. Map numbers, addresses, harness and
  test names don't belong there, nor does what was meant to happen but
  didn't.
- **No-op releases are welcome** as progress and cadence markers; their
  notes say plainly that play is unchanged.
- **A version in VERSION or README without a tag and a GitHub release is
  drift.** An unshipped version number is reused rather than skipped.
- **Push early, push often.** Keeping `main` on GitHub current matters: the
  laptop is a single point of failure, and agent worktrees branch from it.
- **Git is the archive.** Stale probes, instruments and superseded scripts
  (with their waiver lines and citations) are better deleted than archived
  in the tree.
- **Plain names.** Boring, self-evident, industry-standard names rather than
  coinages.
