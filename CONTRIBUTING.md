# Contributing to OT6

Thanks for looking. This is a mechanics-overhaul ROM hack of Final Fantasy VI;
[README.md](README.md) covers what it is and how to build it.

## Getting set up

You supply your own ROM: `Final Fantasy III (USA).sfc`, SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`. Drop it at the repo root. The build
verifies the hash and refuses anything else.

`brew bundle` installs the Homebrew tools (cc65, sdl2). Mesen and Flips are
not brew-installable; [docs/TOOLING.md](docs/TOOLING.md) has those steps.

```sh
make rom     # build build/ot6.sfc
make test    # full headless run: the self-registering suite (a few minutes),
             # discovered from each test's `-- @suite` marker.  See
             # `tools/tests/suite.sh --list`.  Tests that load a deep story
             # savestate join once `make savestates` has generated it;
             # `make savestates-test` does both
make run     # launch the built ROM in Mesen (GUI)
```

`make test` must be green before anything lands. It runs entirely headless
under Mesen's testrunner, with no window and no input from you.

## Where the code is

Nearly all OT6 code lives in feature modules emitted from
[ff6/src/battle/ot6.asm](ff6/src/battle/ot6.asm) into expanded bank `$F0`;
[ot6_memory.inc](ff6/src/battle/ot6_memory.inc) owns the shared WRAM/SRAM map.
Vanilla banks carry only
minimal `jsl` hook shims, because bank `$C1` is 100% full and `$C2` has a few
hundred bytes of slack. `ff6/` is a vendored copy of the everything8215/ff6
disassembly (GPL-3.0). Treat everything under it except our hack files as
upstream, and prefer adding to bank `$F0` over editing vanilla banks.

- [docs/DESIGN.md](docs/DESIGN.md) — the mechanics design
- [docs/ROADMAP.md](docs/ROADMAP.md) — milestones and how far the game is playable
- [docs/research/](docs/research/) — reverse-engineering notes
- [tools/tests/README.md](tools/tests/README.md) — the test harness

## House rules

**Vanilla's quirks stay. Vanilla's destructive failures do not ship in the
stretch of game we call playable.** Useless stats, row jank, and animation
oddities are part of the original game's charm. None of it gets modernized
unless an OT6 mechanic requires it. That preference is deliberate and it is
not going to change.

The preference covers cleanup only; it does not cover reliability. A vanilla
defect that can crash the game, corrupt or lose a save, corrupt persistent
state, or soft-lock progression does not count as charm. Before a release
claims a stretch of game is playable, every known defect of that class
reachable inside that stretch is fixed, mitigated, or accepted in the release
notes. None of them ship undocumented.

**The Sketch bug stays, by owner decision.** It is named here so the question
does not get raised again. Sketch is destructive on paper and popular in
practice, and it ships under the "accepted in the release notes" branch of
the policy above: documented, not fixed. If playtesting changes the owner's
mind, reopening that decision is his call, not this document's.

The inventory lives in
[docs/research/vanilla-destructive-bugs.md](docs/research/vanilla-destructive-bugs.md):
each entry carries source evidence and the point in the game where it
becomes player-reachable. It includes the below-the-bar list, which is kept
so those defects are not rediscovered and argued over again. A defect joins
the fix list only with a reproduction or an instruction-level source basis;
a report without one does not qualify. A fix lands the way every OT6 change
lands: narrowly scoped, with a positive-control regression that fails on the
unfixed ROM.

**Use the FF3-US translation's names, on screen and in prose.** Owner
decision: the Woolsey-era names are part of what makes this feel like the
game people remember, so they stay, quirks included. Write **SwdTech**, not
Bushido. Write **Dispatch / Retort / Slash / Quadra Slam / Empowerer /
Stunner / Quadra Slice / Cleave**, not Fang / Sky / Tiger / Flurry / Dragon /
Eclipse / Tempest / Oblivion. A design document or a code comment that uses
the Japanese or retranslated name sets up a second vocabulary the reader has
to convert against the screen. Write the name the player sees.

This rule governs what we write, not the lore: the internal symbol names in
the vendored disassembly are upstream's and stay as they are.

It also governs what we coin. Taking a name the game already uses for
something else causes the same problem as using a name the game never uses:
the screen and the vocabulary disagree. Gau's **Leap** keeps its name for
that reason, because FF3-US already prints *Capture* as a battle command
(`$06`, the Thief Glove's steal-and-strike). Before coining any player-facing
word, grep the shipped text data (`bushido_name_en`, `item_name_en`,
`battle_cmd_name_en`, `magic_name_en`, `attack_name_en`) and pick something
the game is not already saying.

**Before 1.0, saves are not forward-compatible.** Owner ruling: supporting
saves from older pre-1.0 builds is not worth engineering for. Where new
content only reaches a fresh game, say so in the release notes. Character
command slots are the known case, since `CharProp` is copied into the save
record at join time and never re-read. Do not build migration machinery for
it.

This rule expires at 1.0, after which a player's save is something they are
entitled to keep. The codex's O7→O8 migration shows that migration is
possible when it matters; before 1.0 it does not.

**Documents say what is true now; git history says what we used to think.**
Owner ruling: the tree carries live design and reference, not a record of how
it got that way. When something in a document turns out to be wrong, fix the
claim in place. Do not stack a dated correction on top of it, and do not
leave the superseded wording standing for contrast. When a document's subject
is finished — a plan whose steps all landed, an investigation whose findings
are in the code, a status log — delete it rather than leaving it to go stale.
A reader should be able to trust every sentence in front of them without
checking its date.

So: **never rebase or force-push a shared branch.** History is the one place
the past is kept, so it has to stay intact, and that is what allows the
working tree to carry only what is currently true.

**Read the source; do not infer a mechanism.** The failure pattern is always
the same: something is absent — no writes in a trace, no output from a
script — and rather than find out why, someone writes a mechanism down as
fact and it propagates. That is how this repo acquired "coroutines crash the
emulator" (it was a testrunner timeout), "the sandbox has no `io`" (it was a
sandbox setting), and a buffer annotated "trace-verified free" that sat
inside live vanilla RAM and corrupted the HUD whenever a player opened the
Item menu. So:

- If you write a comment explaining why something behaves a certain way,
  cite the file and line that proves it, or say that it is unverified. An
  observation is a fact. The mechanism behind it is a hypothesis until
  someone reads the source.
- The authoritative sources are the vendored disassembly under `ff6/`,
  `ff6/rom/ff6-en.map` for space questions, and Mesen's own source for
  emulator questions (it is open, and the binary embeds the commit it was
  built from).

Reporting something as suspect is a complete piece of work. Do not report a
guess as a conclusion instead.

**Prove the code is correct.** Writing it is only part of the job.

- **Give every check something that fails when the check does not run.**
  "Everything is fine" and "nothing ran" produce the same green result.
  `probe_shadow_overlap.lua` asserts the command-list drawer ran;
  `battle_loadgate.lua` writes an all-`$FFFF` table and requires the gate to
  still answer no, which is the clause that would catch a gate hardcoded to
  `true`. A check that drives to a hard-coded map id and then asserts
  position can only agree with itself.
- **State the citation with the claim, not after someone doubts it.** If a
  mechanism claim has no `file:line`, it is a hypothesis and must be written
  as one. Memory dumps that looked suggestive have produced confident,
  defended, and false claims more than once.
- **Check what this repo already says before deriving it.**
  `bosses-wob.md` is authoritative on party composition; deriving it from
  `event_main.asm` is invalid, because that file is a dump of
  separately-addressed scripts and adjacency in it means nothing.
- **When isolating a variable, diff the interval first.** "It broke after X"
  is evidence only if X is the only thing that changed.
- **Failing before and passing after does not prove the fix is the right
  shape.** A regression test pins the case you thought of, and the same test
  can pass against two different repairs, one of which hangs a real
  playthrough. Run the thing it is a proxy for.

## Claiming RAM

If you need battle RAM, do not trust a gap in the labels and do not trust a
single trace. `btlgfx_ram.inc` only labels what the battle-graphics module
uses; battle logic uses bare hex addresses, and block moves (`mvn`) are
invisible to any `sta` grep. Verify at least two ways: the vendored maps in
`ff6/notes/`, plus a runtime write-watch across a battle that opens a command
list. Record the evidence at the symbol. The block comment at `OT6_SHADOW`
shows the expected level of detail.

## Pull requests

- Keep `make test` green; add a test for behavior you change.
- Commit messages here run long and explain why the change was made,
  including what was ruled out. Match that.
- Comment density and naming should match the surrounding code.
