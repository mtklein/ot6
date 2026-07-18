# Contributing to OT6

Thanks for looking. This is a mechanics-overhaul ROM hack of Final Fantasy VI;
[README.md](README.md) covers what it is and how to build it.

## Getting set up

You supply your own ROM — `Final Fantasy III (USA).sfc`, SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`. Drop it at the repo root. The build
verifies the hash and refuses anything else.

`brew bundle` installs the Homebrew tools (cc65, sdl2); Mesen and Flips are
not brew-installable — [docs/TOOLING.md](docs/TOOLING.md) has those steps.

```sh
make rom     # build build/ot6.sfc
make test    # full headless gate: 22 tests + pixel goldens (a few minutes)
make run     # launch the built ROM in Mesen (GUI)
```

`make test` must be green before anything lands. It runs entirely headless
under Mesen's testrunner — no window, no clicking.

## Where the code is

Nearly all OT6 code lives in expanded bank `$F0`
([ff6/src/battle/ot6.asm](ff6/src/battle/ot6.asm)); vanilla banks carry only
minimal `jsl` hook shims, because bank `$C1` is 100% full and `$C2` has a few
hundred bytes of slack. `ff6/` is a vendored copy of the everything8215/ff6
disassembly (GPL-3.0) — treat everything under it except our hack files as
upstream, and prefer adding to bank `$F0` over editing vanilla banks.

- [docs/DESIGN.md](docs/DESIGN.md) — the mechanics design
- [docs/ROADMAP.md](docs/ROADMAP.md) — milestones and the "playable frontier"
- [docs/research/](docs/research/) — reverse-engineering notes
- [tools/tests/README.md](tools/tests/README.md) — the test harness

## House rules

**Vanilla's bugs stay.** Useless stats, the Sketch bug, row jank — the original
game not being quite right is part of its charm. Only touch vanilla behavior
where an OT6 mechanic actually requires it.

**Read the source; don't infer a mechanism.** This is the big one, learned the
hard way. An audit in July 2026 found a cluster of confidently-worded
explanations in this repo that were simply invented — a testrunner timeout
misread as "coroutines crash the emulator", a sandbox setting misread as "the
sandbox has no `io`", and a buffer annotated "trace-verified free" that sat
inside live vanilla RAM and corrupted the HUD whenever a player opened the
Item menu.

The pattern in every case: something was **absent** — no writes in a trace, no
output from a script — and rather than find out why, a mechanism got written
down as fact and then propagated. So:

- If you write a comment explaining *why* something behaves a certain way,
  cite the file and line that proves it, or say plainly that it is unverified.
  An observation is a fact; the mechanism behind it is a hypothesis until read.
- Ground truth lives in the vendored disassembly under `ff6/`, in
  `ff6/rom/ff6-en.map` for space questions, and in Mesen's own source
  (open, and the binary embeds the commit it was built from) for emulator
  questions.
- **A quiet test is not a passing test.** If a check can come back clean
  because it never exercised the thing it meant to exercise, it needs a
  positive control that fails loudly instead. `probe_shadow_overlap.lua` is
  the worked example — it asserts that a command-list drawer actually ran,
  because the first version of that probe came back clean for exactly that
  reason and nearly buried a real bug.

Marking something suspect is a finished piece of work. A confident guess is
not.

## Claiming RAM

If you need battle RAM, do not trust a gap in the labels and do not trust a
single trace. `btlgfx_ram.inc` only labels what the battle-graphics module
uses; battle logic uses bare hex addresses, and block moves (`mvn`) are
invisible to any `sta` grep. Verify at least two ways — the vendored maps in
`ff6/notes/`, plus a runtime write-watch across a battle that *opens a command
list* — and record the evidence at the symbol. The block comment at
`OT6_SHADOW` shows the standard.

## Pull requests

- Keep `make test` green; add a test for behavior you change.
- Commit messages here run long and explain the *why*, including what was
  ruled out. Match that.
- Comment density and naming should match the surrounding code.
