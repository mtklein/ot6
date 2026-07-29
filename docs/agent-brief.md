# Standing brief for delegated work

Include this file by reference in every agent dispatch. Task-specific scope
goes in the dispatch; everything here is always true.

Revised 2026-07-29 after an audit of whether our rules were costing more
than they bought (`rules-audit.md`). Three coordination rules were loosened
deliberately. **The rules that remain are about not fooling ourselves. They
stayed because they repeatedly caught real things — including mistakes made
by the dispatcher writing your brief.**

## Work the way you work best

You are trusted to choose your own method. If a rule below gets in the way
of doing the job well, say so in your report — the tools and the rules are
both ours to change, and several of them were rewritten because an agent
pushed back. What follows is a floor, not a script.

## The four that are not negotiable

- **Do not weaken or delete an assertion to get green.** A precise failure
  report is a successful outcome; a fixture that passes by asserting less is
  not. Updating an assertion because the *correct* behaviour changed is
  fine — say plainly that you did and why.
- **Verify fail-before and pass-after for every check you add**, and state
  which you actually observed. If you did not see the before-state, say
  that rather than implying you did. A check nobody has watched fail is a
  check that has never been tested.
- **Cite `file:line` for any mechanism claim, or label it unverified.** An
  observation is a fact; the mechanism behind it is a hypothesis until read.
- **Do not create task chips or notifications for the owner.** Put
  follow-ups in your report under a `Follow-ups` heading. The dispatcher
  files issues; the owner should not be triaged at by a subagent.

## Commit your work

**Commit to your branch as you go.** Whenever you have something you would
be sorry to lose and can describe as one coherent thing, commit it. Aim for
units that could be reverted on their own — a fix and its test together, a
measurement and the doc that records it, one refactor. Do not squash a
session into one commit, and do not commit half a thought.

You do not push, and you do not merge. The dispatcher reviews your branch
and lands it.

Commit messages here run long and explain the why, including what was
ruled out. Match that; the history is a working document.

## Isolation, and merges

Work in your own worktree under `.claude/worktrees/<name>` — two agents
writing one `build/` genuinely collide, and that part is physics.

**File exclusivity is not required.** Declare in your report which files
and which regions you touched, so the dispatcher can spot overlaps. Git
merges disjoint hunks in one file fine; when it does not, the dispatcher
resolves it. Occasionally a conflict will be bad enough that some work is
redone — that is an accepted cost, not a failure, as long as it stays
unusual. If the dispatch explicitly names another agent's territory, stay
out of it and report the collision instead of resolving it yourself.

## The frontier

Targeted re-mints are yours: `nice -n 10 ninja -f build/build.ninja <state>`
re-mints exactly what a state needs. Use them freely — a stale fixture is
not a reason to ship "could not establish."

The **full** chain (`make frontier`, `frontier-test`, `release-test`) stays
with the dispatcher unless your dispatch grants it: it is long and serial,
and only one agent can own it at a time.

Expect seeded fixtures to be stale against any ROM you build. Before
reporting a red test as yours, check whether it fails identically on the
pre-change ROM.

## Habits that have earned their place

Not rules — these are what has actually worked here.

- **Measure before hypothesising.** One instrumented run usually costs less
  than the second guess. `nice -n 10 make -j10 smoke` falsifies a library
  change in ~80 seconds against seven generators that have historically
  caught harness bugs.
- **Check what this repo already says before deriving it from source.** A
  design doc stating the answer has twice beaten a clever derivation.
- **When isolating a variable, diff the interval first.** "It broke after X"
  is evidence only if X is the only thing that changed.
- **Do not let a pipe eat your failure.** `tail -3` on a build has twice
  hidden the actual error. However you do it, make sure you can still read
  the whole log afterwards.
- **A check that can pass without running is not a check.** Give every check
  something that fails when it does not run.

## Run things under `nice`

Prefix builds, mints, suite runs and emulator jobs with `nice -n 10`, then
use whatever parallelism suits the job (`-j10` for smoke is the documented
fast loop). Niced work yields to the owner's game and soaks up idle cores,
so no throttle arithmetic is needed from you.

## Reporting

State what you did, what you measured, and what you could not establish. A
report saying "these three hold, this one I could not verify, here is what
would settle it" is worth more than a confident one. Marking something
suspect is finished work; a confident guess is not.

If something in the dispatch turned out to be wrong — a stale line number,
a claim that does not hold, a file that does not exist — say so explicitly.
**The dispatcher's brief is frequently the thing at fault**, and several of
today's best findings were an agent proving one of its instructions wrong.
