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
make test    # full headless gate: the self-registering suite (a few minutes),
             # discovered from each test's `-- @suite` marker -- see
             # `tools/tests/suite.sh --list`.  Frontier-gated tests join once
             # `make frontier` has minted their fixtures; `make frontier-test`
             # does both
make run     # launch the built ROM in Mesen (GUI)
```

`make test` must be green before anything lands. It runs entirely headless
under Mesen's testrunner — no window, no clicking.

## Where the code is

Nearly all OT6 code lives in feature modules emitted from
[ff6/src/battle/ot6.asm](ff6/src/battle/ot6.asm) into expanded bank `$F0`;
[ot6_memory.inc](ff6/src/battle/ot6_memory.inc) owns the shared WRAM/SRAM map.
Vanilla banks carry only
minimal `jsl` hook shims, because bank `$C1` is 100% full and `$C2` has a few
hundred bytes of slack. `ff6/` is a vendored copy of the everything8215/ff6
disassembly (GPL-3.0) — treat everything under it except our hack files as
upstream, and prefer adding to bank `$F0` over editing vanilla banks.

- [docs/DESIGN.md](docs/DESIGN.md) — the mechanics design
- [docs/ROADMAP.md](docs/ROADMAP.md) — milestones and the "playable frontier"
- [docs/research/](docs/research/) — reverse-engineering notes
- [tools/tests/README.md](tools/tests/README.md) — the test harness

## House rules

**Vanilla's quirks stay; vanilla's destructive failures do not ship in a
supported frontier.** Useless stats, row jank, animation oddities — the
original game not being quite right is part of its charm, and none of it
gets modernized unless an OT6 mechanic actually requires it. That bias is
deliberate and it is not going away.

But it is a bias against *cleanup*, not against *reliability*. A vanilla
defect that can crash the game, corrupt or lose a save, corrupt persistent
state, or soft-lock progression is a different thing from charm, and
before a release advertises a frontier, every known defect of that class
reachable inside it is fixed, mitigated, or explicitly accepted in the
release notes — never shipped silently. The save-slot checksum-`$0000`
save-loss bug cleared this bar and was fixed (issue #18).

**The Sketch bug stays, by explicit owner decision (reaffirmed
2026-07-28).** It is named here so the question does not get re-litigated:
an earlier policy revision (issue #13) scoped a Sketch fix as a v0.8
release gate, which reversed the owner's standing call without their
sign-off, and was itself reversed (issue #28). Sketch is the canonical
"charm" example — destructive on paper, beloved in practice — and the
"explicitly accepted in the release notes" branch of the policy above is
how v0.8 will ship it: documented, not fixed. If playtesting ever changes
the owner's mind, that decision is theirs to reopen, not this document's.

The inventory lives in
[docs/research/vanilla-destructive-bugs.md](docs/research/vanilla-destructive-bugs.md):
each entry carries source evidence and the frontier where it becomes
player-reachable, including the below-the-bar list kept so those defects
are not rediscovered and re-argued. A defect joins the fix list only with
a reproduction or instruction-level source basis — this is not a
folklore-driven bug sweep — and a fix lands the way every OT6 change
lands: narrowly scoped, with a positive-control regression that fails on
the unfixed ROM.

**The FF3-US translation is our vocabulary — on screen and in prose.**
Owner decision, 2026-07-29: the Woolsey-era names are part of what makes
this feel like the game people remember, so they stay, quirks included.
**SwdTech**, not Bushido. **Dispatch / Retort / Slash / Quadra Slam /
Empowerer / Stunner / Quadra Slice / Cleave**, not Fang / Sky / Tiger /
Flurry / Dragon / Eclipse / Tempest / Oblivion. Where a design document
or a code comment reaches for the Japanese or retranslated name, it is
creating a second vocabulary a reader has to convert against the screen
— write the name the player sees.

This is a naming rule, not a lore rule: the internal *symbol* names in
the vendored disassembly are upstream's and stay as they are. It governs
what we write.

It also governs what we *coin*. A worked example: `kit-gau.md` proposed
renaming Gau's **Leap** to *Capture* — but FF3-US already prints Capture
as a battle command (`$06`, the Thief Glove's steal-and-strike). Taking a
name the game already uses for something else is the same crime as using
a name the game never uses: it makes the screen and the vocabulary
disagree. **Leap keeps its name** (ruling, 2026-07-29). Before coining
any player-facing word, grep the shipped text data — `bushido_name_en`,
`item_name_en`, `battle_cmd_name_en`, `magic_name_en`, `attack_name_en`
— and pick something the game is not already saying.

**Don't change the past.** Records stay as they were: shipped release
notes, playtest ledgers, dated design decisions, and git history. When
something in a *living* document turns out to be wrong, append a dated
correction rather than silently rewriting the claim — `bosses-wob.md`'s
Ultros ③ block and `banquet-decode.md`'s withdrawn §5.2 are the pattern.
A reader should be able to see both what we believed and what we learned;
a doc that has been quietly fixed teaches nothing about how it went
wrong, and this project's worst failures have all been someone trusting a
confident-looking statement.

Concretely: **never rebase or force-push a shared branch**, never edit a
released `release-notes-vX.Y.md`, and never restate history to match a
later decision. New rules apply going forward. (Owner ruling,
2026-07-29.)

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

Marking something suspect is a finished piece of work. A confident guess is
not.

**Your job is not to write correct code. It is to prove the code is correct.**

- **A check that can pass without running is not a check.** "Everything is
  fine" and "nothing ran" come out the same green, so give every check
  something that fails when it does not run. Three in the tree:
  `probe_shadow_overlap.lua` first came back clean because the command-list
  drawer never ran, and nearly buried a HUD-corruption bug — it now asserts
  the drawer ran. `gen_vector_arrival` asserted the party's position after
  driving to a hard-coded map id, so it could only agree with itself; it
  passed green for a week standing in Albrook. `battle_loadgate.lua` writes
  an all-`$FFFF` table and requires the gate to still answer no, which is the
  clause that would catch a gate hardcoded to `true`.
- **State the citation before the claim, not after someone doubts it.** "Locke
  fights Number 128 solo" and "the game is wedged" were both asserted from
  suggestive-looking memory dumps, defended once, and then disproved — the first
  by a design doc in this repo that said the opposite on four separate lines,
  the second by a screenshot whose byte count contradicted the very note being
  cited for it. If a mechanism claim has no `file:line`, it is a hypothesis and
  must be written as one.
- **Check what this repo already says before deriving it.** `bosses-wob.md`
  recorded the correct Magitek Factory party the entire time it was being
  derived wrongly from `event_main.asm`. One grep beats a clever derivation, and
  the derivation was clever — it was also invalid, because that file is a dump
  of separately-addressed scripts and adjacency in it means nothing.
- **When isolating a variable, diff the interval first.** "It broke after X" is
  evidence only if X is the only thing that changed. A `navTo` fix was blamed
  for a hang that two later commits had actually caused, because the isolation
  run compared against a tree that carried all three.
- **Failing before and passing after does not prove the fix is the right
  shape.** `battle_loadgate.lua` failed for exactly the right reason before
  the battle-gate fix, then passed against two different repairs — one of
  which hung the frontier at `gen_moogle` for 30,000 frames. A regression
  pins the case you thought of. Run the thing it is a proxy for.

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
