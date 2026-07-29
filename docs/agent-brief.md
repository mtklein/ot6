# Standing brief for delegated work

Include this file by reference in every agent dispatch. It exists because
briefs written from scratch each time silently lose rules — a dropped
"no chips" line reached the owner's UI twice in one day, and the same failure
mode applies to every rule below.

Task-specific scope goes in the dispatch. Everything here is always true.

## Never

- **Do not commit.** Report what you changed; the dispatcher reviews and lands
  it. This is not ceremony: two agents working in parallel worktrees today were
  merged by hand, and a commit from inside one of them would have made that
  merge worse.
- **Do not create background task chips or notifications for the owner.** Put
  follow-up work in your final report under a `Follow-ups` heading. The
  dispatcher files issues; the owner should not be triaged at by a subagent.
- **Do not run `make frontier`, `make frontier-test`, or `make release-test`**
  unless the dispatch explicitly grants the frontier chain. Minting takes hours
  and only one agent may own it at a time.
- **Do not weaken or delete an assertion to get green.** A precise failure
  report is a successful outcome. A fixture that passes by asserting less is
  not.
- **Do not edit files another agent owns.** The dispatch names yours.

## Always

- **Capture command output to a file, never through `tail` or `head`.** Piping
  a build through `tail -3` has twice hidden the actual failure and forced a
  re-run. Write the log, then grep it.
- **Verify fail-before and pass-after for every test you add**, and say plainly
  in your report which you observed. If you did not see the before-state, say
  that instead of implying you did.
- **Cite `file:line` for any mechanism claim, or label it unverified.** An
  observation is a fact; the mechanism behind it is a hypothesis until read.
- **Check the repo's own documents before deriving something from source.**
  A design doc stating the answer beats a clever derivation, and has twice been
  right where the derivation was wrong.
- **When isolating a variable, diff the interval first.** "It broke after X" is
  only evidence if X is the only thing that changed. Check `git log` between the
  two states before attributing.
- **Measure before hypothesising.** One instrumented run usually costs less than
  the second guess. `make -j10 smoke` falsifies a library change in ~80 seconds
  against the seven generators that have historically caught harness bugs.

## Run everything under `nice`

**Prefix every build, mint, suite run and emulator job with `nice -n 10`.**

    nice -n 10 make -j10 smoke
    nice -n 10 ninja -f build/build.ninja <state>
    nice -n 10 tools/tests/run.sh tools/tests/<gen>.lua

The machine is a fast laptop (10 performance cores + 4 efficiency, run
plugged in) and Mesen is effectively single-threaded, so an emulator job
costs about one P core for its whole run. Rather than hand-tuning job
counts against however many agents happen to be live and whether the
owner is playing, hand the problem to the scheduler: niced work yields to
his game and to anything interactive, and soaks up whatever is idle
otherwise.

So: **do not do throttle arithmetic.** Use the natural parallelism for
the job (`-j10` smoke is the documented fast loop), niced. The one thing
`nice` cannot fix is two agents writing the same `build/` — that is what
worktrees are for, and it is still binding.

## Reporting

State what you did, what you measured, and what you could not establish. A
report that says "these three things hold, this one I could not verify, here is
what would settle it" is worth more than a confident one. Marking something
suspect is a finished piece of work; a confident guess is not.

If something in the dispatch turned out to be wrong — a stale line number, a
claim that does not hold, a file that does not exist — say so explicitly. The
dispatcher's brief is frequently the thing at fault.
