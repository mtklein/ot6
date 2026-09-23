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

The harness plays OT6 the way a competent person with a controller would.

- **Fight, don't flee.** Flee only where the game forces it. Win with
  levels, gear, kill order and abilities.
- **A lost battle is normal.** A person who wipes reloads the save and goes
  again. A segment retries from its boot checkpoint on a wipe, bounded and
  counted, with the seed, the cause and every member's boost at death
  logged. One loss is a line in the retry inventory. Repeated losses, or a
  loss rate above the band, are a lab. Retry machinery engineered to re-roll
  a fight until it passes is not play.
- **Classify every wipe by boost at death.** An early one-shot means the
  party is under-levelled (a level/kit finding). A wipe with pips still
  banked means the abilities were not used fully (a driver/policy finding).
  A member one round from death with boost banked spends it now.
- **Heal outside battles.** Field care after every resolved battle, with
  Tonics (stock about 99; where no shop sells Tonics, Potions). Timed scenes
  are exempt: no menus inside a live event timer.
- **Turns are the scarce resource in combat.** Heal in battle with Potions,
  not Tonics. Use the strong form of an effect once (a boosted Cure2/Cure3 on
  the whole party) instead of several weak single-target turns. One care
  action per round; ending the fight is the strongest heal. Needing much
  healing in combat is a signal to level up or re-gear, not to budget more
  heal turns.
- **Supply band.** Carry about level × 5 Tonics and about level Fenix Downs
  (caps 99 and about 20). Below the band, detour to a town; every town stop
  tops up.
- **Fenix Downs are a signal.** More than one or two in a hard fight, or any
  in a random battle, points to under-levelling or a fight that needs a
  strategy lab. A rare single death to a vanilla mechanic is fine; a lab is
  for frequent deaths, wipes, or heavy Fenix use.
- **Boost-Fight through random battles** by default: unbroken enemies take
  about half damage and everyone starts with one pip, so a one-pip boosted
  Fight restores vanilla pace. Break and boost are levers: no "never boost
  the shield strip", no "never nuke before the break". Try the options and
  measure.
- **Relics matter**, the Genji Glove especially: keep it on the
  boost-Fighter. Readiness-audit flags are action items.

## Designing the game

- **Boost pays once.** One action's boost buys one payoff. Fight and
  Capture: extra swings, and a weapon's own on-hit spell is not also
  multiplied. Tier spells: the tier. Rage: the special's likelihood. Slot,
  Steal, Bushido: their own ladders. Everything else: the damage
  multiplier. Boost never costs pips while buying nothing.
- **Don't retune vanilla enemies** (AI scripts, spells, one-shots) to dodge
  a hard fight. OT6 changes battle systems, not individual enemy quirks;
  answer a hard fight with levels, gear, route or strategy.
- **Octopath-style twists on FF6 characters are welcome** (Shadow's break
  that kills). Shadow stays in the party the whole game.
- **Save compatibility is a contract.** The SRAM layout
  ([save-layout.md](design/save-layout.md)) must keep loading older
  in-game saves. A release is promoted to v1.0 retroactively once it is fun
  and solid enough to keep that promise for a long future.
- **Priorities:** release reliability, then labs on marginal fights, then
  fun and the Octopath feel. Quality over time; there are no deadlines.

## Testing and debugging

- **Handle any encounter.** A test, generator or driver is correct only if
  it copes with every encounter, formation and draw the game can deal at
  that point, not the one its fixture happens to draw. Every ROM change
  regenerates the fixture chain and reshuffles encounters and history; that
  is routine, and fixing what it exposes is routine work. Details and the
  evidence bar for test changes are in [TESTING.md](TESTING.md).
- **Luck standing in for a precondition** is the most common defect class.
  When a suite goes red after an unrelated change, suspect the suite, but
  prove it. Fix by reaching the precondition and asserting it; never by
  widening a timeout, re-rolling a seed, or weakening an assertion.
- **A regression ships with its test**: red on the regressed build, green
  after. No tests of the test tooling; fix tooling defects directly.
- **Look at the screen.** Scripts watch what they are doing and fail fast
  with the failure frame; read the frame and the log before theorizing.
- **No foreseeable surprises.** FF6's mechanics are finite and documented
  (battle arrangements, statuses, specials, menus, vehicles). Keep
  [mechanics-coverage.md](design/mechanics-coverage.md) current; when one
  member of a class shows up unhandled, enumerate the whole class. An
  unknown menu firing is a missing verb to implement.
- **Never conclude "impossible"** or that the ROM "diverged" from a static
  model or a partial trace. Check the source's history, trace the event
  scripts and gates, and drive it in the emulator.
- **Take observations literally; measure before theorizing.**

## Releases and the repository

- **Release notes are for players**: what you will notice, why to update,
  what to watch for, in play terms. No map numbers, addresses, harness or
  test names, and nothing about what was meant to happen but didn't.
- **No-op releases are welcome** as progress and cadence markers; their
  notes say plainly that play is unchanged.
- **A version in VERSION or README without a tag and a GitHub release is
  drift.** An unshipped version number is reused, not skipped.
- **Push early, push often.** `main` on GitHub is always current; the
  laptop is a single point of failure, and agent worktrees branch from it.
- **Git is the archive.** Delete stale probes, instruments and superseded
  scripts (with their waiver lines and citations) instead of keeping or
  archiving them in the tree.
- **Plain names.** Boring, self-evident, industry-standard names; no
  coinages.
