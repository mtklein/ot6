# Standing brief for delegated work

Include this file by reference in every agent dispatch. Task-specific scope
goes in the dispatch; everything here is always true.

The rules here exist to keep us from fooling ourselves. They have repeatedly
caught real problems, including mistakes made by the dispatcher writing your
brief.

## Read this file from your own worktree

Not from `/Users/mtklein/ot6/docs/agent-brief.md`. The owner's checkout
sits on whatever release branch he is playtesting, so docs read there
can be weeks behind `main`. Every dispatch should name the copy in your
own worktree; if one points you at the owner's tree, read your own copy
instead and say so in your report.

## How to write

Plain language, and no invented jargon. The repo used to run a private
vocabulary and it was removed on 2026-08-11; do not reintroduce it.

    generate / regenerate a savestate   not   mint / re-mint
    step, segment                       not   leg
    checkpoint                          not   anchor
    entry point                         not   doorstep
    how far the game is playable        not   the frontier
    killed by the timeout               not   reaped
    input-driven                        not   honest
    test, check                         not   gate (except a code guard)
    area, range                         not   band
    tier                                not   rung
    baseline                            not   ruler
    saved game, savestate               not   fixture
    re-made against this build          not   fresh
    made by an older build              not   stale

The Lua option is `opts.playBattles`, not `opts.honest`. `make savestates`,
not `make frontier`. Savestates are `*_entry`, not `*_doorstep`.

The last three are new on 2026-08-12 and correct an earlier judgement.
"Fixture" was kept as ordinary industry English; the owner reads these
reports and does not know the word, which is the only test that matters.
"Fresh" and "stale" are worse, because they sound like plain English while
carrying a specific meaning nobody outside this repo would guess: a saved
game is made by loading the previous one and playing forward, so when the
code or the ROM changes, one made by the older version no longer matches and
has to be re-made by playing that stretch again. Say that, or say "re-made
against this build". `--check-states` still prints STALE; explain it rather
than repeating it.

Kept because they are the product rather than jargon: break, boost, chip,
shield, kit, magicite, esper, Rage, Blitz, SwdTech, BP, MP. Also kept:
ordinary industry words (savestate, suite, probe, harness, regression,
provenance, waiver), "gate" for a code guard such as `Ot6Gate`, battery for
battery-backed SRAM, and place names.

Do not write in a persuasive-essay register. No antithesis, no
personification, no maxims, no sentence fragments for emphasis, no capitals
for volume (caps only for literal tokens such as PASS or `$FF`), no
em-dash punchlines. Lead with the conclusion rather than building to it.
This applies to commit messages, docs, code comments and your report.
Commit messages still run long and explain what you ruled out; plain does
not mean short.

## Choosing your method

You choose your own method. If a rule below gets in the way of doing the job
well, say so in your report. Both the tools and the rules can be changed, and
several of them were rewritten because an agent pushed back. What follows is
a minimum, not a full procedure.

## The four that are not negotiable

- **Do not weaken or delete an assertion to get a green run.** A precise
  failure report is a successful outcome; a fixture that passes by asserting
  less is not. Updating an assertion because the correct behaviour changed is
  fine; say that you did and why.
- **Verify fail-before and pass-after for every check you add**, and state
  which you actually observed. If you did not see the before-state, say
  that rather than implying you did. A check nobody has watched fail is a
  check that has never been tested.
- **Cite `file:line` for any mechanism claim, or label it unverified.** An
  observation is a fact. The mechanism behind it is a hypothesis until
  someone reads the source.
- **Do not create task chips or notifications for the owner.** Put
  follow-ups in your report under a `Follow-ups` heading. The dispatcher
  files issues; a subagent does not send the owner triage requests.

## Commit your work

**Commit to your branch as you go.** Whenever you have something you would
be sorry to lose and can describe as one coherent thing, commit it. Aim for
units that could be reverted on their own: a fix and its test together, a
measurement and the doc that records it, one refactor. Do not squash a
session into one commit, and do not commit an unfinished change.

You do not push, and you do not merge. The dispatcher reviews your branch
and lands it.

Commit messages here run long and explain why the change was made, including
what was ruled out. Match that; the history is a working document.

## Isolation, and merges

Work in your own worktree under `.claude/worktrees/<name>`. Two agents
writing to one `build/` directory will collide.

**File exclusivity is not required.** Declare in your report which files
and which regions you touched, so the dispatcher can spot overlaps. Git
merges disjoint hunks in one file fine; when it does not, the dispatcher
resolves it. Occasionally a conflict will be bad enough that some work is
redone. That is an accepted cost rather than a failure, as long as it stays
unusual. If the dispatch explicitly names another agent's territory, stay
out of it and report the collision instead of resolving it yourself.

## The generated savestates

Targeted regeneration is yours: `nice -n 10 ninja -f build/build.ninja <state>`
regenerates exactly what a state needs. Use them freely; a stale fixture is
not a reason to ship "could not establish."

The **full** chain (`make savestates`, `savestates-test`, `release-test`, which
regenerate every savestate the deeper tests load) stays with the dispatcher
unless your dispatch grants it: it is long and serial, and only one agent
can own it at a time.

Expect seeded fixtures to be stale against any ROM you build. Before
reporting a red test as yours, check whether it fails identically on the
pre-change ROM.

## Habits that have worked here

These are suggestions rather than rules.

- **Measure before hypothesising.** One instrumented run usually costs less
  than the second guess. `nice -n 10 make -j10 smoke` falsifies a library
  change in ~80 seconds against seven generators that have historically
  caught harness bugs.
- **Check what this repo already says before deriving it from source.**
  Twice, a design document already stated the answer someone spent time
  deriving.
- **When isolating a variable, diff the interval first.** "It broke after X"
  is evidence only if X is the only thing that changed.
- **Do not let a pipe hide your failure.** `tail -3` on a build has twice
  hidden the actual error. However you do it, make sure you can still read
  the whole log afterwards.
- **Give every check something that fails when the check does not run.**
  Otherwise a check that never ran reports the same green as one that passed.

## Run things under `nice`

Prefix builds, savestate generation, suite runs and emulator jobs with
`nice -n 10`, then use whatever parallelism suits the job (`-j10` for smoke
is the documented fast loop). Niced work yields to the owner's game and
uses idle cores, so you do not need to work out a throttle.

**`nice` does not fix the 600-second timeout.** Mesen's testrunner kills a
run on wall-clock, and every competing job is equally niced, so agents can
starve each other past that deadline even though none of them starves the
owner. The signature is several savestate generations failing `code=255` at
once while the same ones pass in isolation. If you see that, it is
contention rather than your change; lower `-j` and retry rather than
debugging the generator.

A **full** `make savestates` is the case that provokes it, because it
parallelises hard on its own. Bound it (`NINJAFLAGS=-j4`) when other
agents are live.

## Never kill emulators machine-wide

`pkill -f Mesen`, `killall Mesen` and anything else that matches on the
program name kill every other worktree's runs too, and those runs are hours
long. Two agents did this on 2026-08-11, and each time somebody else's
generation died with no explanation at the far end. The symptom for the
victim is exit 143 partway through a step that was working, which reads
exactly like a real failure and costs a re-run to disprove.

Kill by what you started. Keep the pid, or match on your own worktree path,
which is unique to you. If you need to clear something you did not start,
say so in your report and leave it alone.

## Reporting

State what you did, what you measured, and what you could not establish. A
report saying "these three hold, this one I could not verify, here is what
would settle it" is worth more than a confident one. Reporting something as
suspect is complete work; do not report a guess as a conclusion instead.

If something in the dispatch turned out to be wrong (a stale line number, a
claim that does not hold, a file that does not exist), say so explicitly.
The dispatcher's brief is frequently the thing at fault, and some of the
best findings here have been an agent proving one of its instructions wrong.
