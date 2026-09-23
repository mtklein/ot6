# Testing policy

Owner-approved, 2026-09-06. This is the canonical testing-method guideline for
OT6 contributors and coding models. It supersedes conflicting older wording
in session memory, coordinator prompts, source comments, and historical docs.

> Start from a legitimately reached state. Advance the game through
> human-executable inputs. Freely snapshot, restore, inspect, and branch
> that state for experiments.

## Legal play, accelerated experiments

“Play like a human” applies to what happens within a played attempt. It does
not require a human-speed test setup, replaying the approach every time, or
using only the game's save points.

- Read emulated memory freely for observation, diagnosis, assertions, menu
  navigation, and precise acknowledgment of inputs and command execution.
- Capture and restore complete emulator snapshots aggressively, including
  mid-battle and inside menus. Restore a coherent machine state (CPU, memory,
  timers, RNG and relevant emulator state), not selected RAM cells.
- Branch one legitimately reached snapshot into many experiments. Compare
  actions, controller implementations, and policies from exactly the same
  starting state. Repeated identical seeds are desirable for controlled A/B
  comparisons; varied seeds and entry states answer robustness questions.
- Fast-forward emulation and use feedback-driven controller inputs. The
  resulting action sequence must be executable through the game's normal
  controls; bypassing menus or injecting commands directly is not play.
- Retain and reuse legitimate checkpoints. A successful explored branch can
  supply a later checkpoint, provided its ancestry and selection are recorded.
  Reachability does not imply a typical or first-try result.

Restoring a snapshot restarts an experiment. Restoring only HP, MP, inventory,
status, a cursor, an event flag, or RNG while retaining the rest of the current
attempt manufactures a different continuation. Such edits, forced kills, and
resources replenished by the harness are not permitted as gameplay evidence.

## Match the evidence to the question

**Execution debugging:** repeat a local checkpoint as often as useful. Inspect
all memory and distinguish plans, button attempts, accepted commands, and
resolved actions. A controller failure is not evidence that combat is too hard.

**Strategy discovery:** explore alternatives and replay branches freely. Keep
the failures and report how a successful route was selected. A discovered
winning continuation establishes possibility, not its success probability.

**Balance and robustness:** evaluate a declared policy from appropriate fresh
attempts and varied states/seeds, retaining all outcomes. Do not splice chosen
successful branches into an apparent uninterrupted clear, first-try win, or
inflated success rate. Test the discovered strategy separately from its search.

Memory access itself is unrestricted, but a blind-player policy must not
silently use unrevealed weaknesses, exact hidden enemy HP, future RNG outcomes,
or knowledge obtained by exploring alternate futures. Label informed or
privileged-information experiments explicitly. Reading cursor positions or
command acceptance to implement an intended input is normal control machinery.

Cold boots, in-game save/load checks, long-route runs, and uninterrupted clears
remain useful for the properties they exercise. They are not prerequisites for
every local experiment. Name which kind of run supports a release claim.

## Provenance and compatibility

Preserve the original capture provenance: ROM identity, emulator/state format,
producer and ancestor records, and any branch selection. Separately establish
whether the snapshot is compatible with the experiment consuming it.

A change to logging, assertions, or controller policy does not by itself make
a legitimately reached snapshot illegitimate or require replaying its ancestry.
Changed ROM code/layout can invalidate a machine snapshot. A verified complete
battery save loaded through Continue can be a suitable cross-build entry point
when its persistent layout remains compatible; test that compatibility rather
than assuming it.

The Ninja graph and stamp checker implement that separation. Each generated
fixture's stamp records the ROM it was captured on, its generator's own
signature, its artifact and ancestor bindings (compatibility), and the
signature and per-file hashes of the shared harness sources that produced it
(provenance). A fixture is stale when the ROM or its generator changed or a
binding fails; a change to the shared harness sources alone is reported as
provenance drift and regenerates nothing. A stamp written before ROM identity
was recorded stays on the older conservative whole-signature rule until its
fixture is regenerated, or until `compose.py --adopt-stamps` proves the
missing lines from the tree's own records (the current sources still hash to
the recorded signature, the artifact verifies, and ninja's build log shows
the ROM copy-if-changed step last ran before the generate edge with its copy equal
to the current ROM) and appends them; no ROM identity is invented for it,
and a fixture the records cannot prove is refused. This describes
the implementation, not an additional owner restriction. Improve
dependency/compatibility handling when needed; do not forge stamps, discard
provenance, or silently disable checks. Use `H.requestSaveState`,
`H.requestLoadState`, `H.saveState`, and `H.loadState` for coherent
snapshots, and the versioned SRAM checkpoint path for battery saves. Prefer
these existing supported paths during iteration.

Evidence must outlive the tree it was produced in. Write evidence you will
cite under `build/attempts/<branch>/` and cite it by that path. In an agent
worktree, `tools/worktree-setup.sh` makes `build/attempts` a link to the
main tree's, so the file lands in the main tree as it is written and the
cited path is the same in both trees; nothing needs copying when the
worktree is removed. Scratch output (`build/lab/`, `build/sweeps/`) stays in
the worktree; for anything cited from there, run `python3
tools/retain_evidence.py <worktree> <branch>` before `git worktree remove`
and cite the retained path. A citation whose log was lost says so at the
citation rather than dropping the number.

## Tests that survive any draw

A test, generator or driver must cope with every encounter, formation and
draw the game can deal at its point in the route, not the one its fixture
happens to hold. Every ROM change regenerates the fixture chain, and with it
the RNG, the encounter history, levels, MP and what earlier fights taught or
inflicted. Derive choices from the fixture's live state and the ROM's data;
assert the true precondition early, with a message that names it. No
hardcoded formation ids, draw indices, "the Nth battle", levels, or
knowledge an earlier fight happened to produce. Take a baseline at the
moment the property under test begins, and attribute a change (an MP
charge, a hit, a revive) to the action that made it rather than to the
first change seen.

A seed shift does not re-draw encounters. `OT6_SEED_SHIFT` moves in-battle
RNG only. When an encounter comes and which formation it is are save data
(counters at `$1fa1`-`$1fa5`; the formation pick advances once per
encounter), so replays and retries from one fixture meet the same
formations. To vary the draw, use up
encounters before the body (fight or run them), not idle frames or seeds.
Budgets for "within N encounters" come from the map's decoded pool odds, not
from one run.

A new or changed test is ready to merge when its evidence shows:
1. the old version failing where the draw or history moves (when fixing
   fragility), by varying encounters, not only seeds;
2. the new version passing across those variations;
3. a negative control or mutant proving each changed assertion can fail
   (a price off by one, the rule switched off, the reviver dead);
4. no widened timeout, re-rolled seed, weakened or log-only assertion
   standing in for the property.

## Synthetic mechanism tests

Explicitly isolated mechanism tests may retain declared state-write waivers
for fault injection or synthetic setup. They establish the narrow property
under test, not legal play, balance, or ordinary player experience. They may
produce isolated unit fixtures, but those fixtures and their descendants must
never enter the legitimate gameplay/checkpoint history. The waiver registry
is not a ban on complete snapshot restoration and is not a mandatory countdown
to zero. This policy adds no authorization to fabricate gameplay state.

See [the harness guide](../tools/tests/README.md) for commands and
[headless play](playing-headless.md) for navigation and checkpoint mechanics.
