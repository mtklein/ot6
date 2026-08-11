# Segment fixtures — parallelising the savestate chain on battery-save checkpoints

## The problem

The generated savestates form a ~100-state chain in which each link boots the
previous link's **savestate**. Savestates are tied to exact ROM contents, so any
ROM byte, library edit, or generator change invalidates everything downstream and
forces a replay from power-on. A single wrong guess costs a full serial replay to
discover, which is what makes guessing expensive and iteration slow.

The pain compounds: the later routes are longer than anything generated so far.

## What already exists

This is not a from-scratch design. Three pieces are already in the tree:

- **`mint_anchor`** (`Makefile`) generates a state by cold-loading a tracked
  in-game battery save via `OT6_SRAM_ANCHOR`, rather than by booting a
  predecessor savestate. The `post-opera-v1` checkpoint is the worked example.
- **Battery saves survive ROM changes.** The post-Opera checkpoint cold-loads
  against a deliberately different ROM hash: the game reconstructs
  transient state on load, so a battery save is not coupled to exact ROM bytes
  the way a savestate is. *This is the property the whole design rests on.*
- **`make -jN frontier` already parallelises** where the graph allows — the three
  scenario branches after `scenario_hub`, and `kolts_pool`/`kolts_cave` beside
  the Vargas step. Runner isolation makes concurrent generation safe.

The blocker is that everything up to the hub is a **serial trunk**, because each
link boots the previous entry point.

## The change

Place a tracked battery-save checkpoint at each chapter boundary. Every segment
declares a **checkpoint** as its input instead of a predecessor state, so
segments become mutually independent and `make -jN frontier` can run them all at
once.

```
today:      A --> B --> C --> D --> ...      (one break stops everything)

segments:   [checkpoint A] --> B     [checkpoint C] --> D
            [checkpoint B] --> C     [checkpoint D] --> E    (all at once)
```

A ROM change still marks every segment stale — the stamp keys on (ROM, generator,
lib) and should keep doing so. The win is that each segment then re-runs **from
its own checkpoint, in parallel**, instead of replaying the trunk from power-on.
N short concurrent runs instead of one long serial one.

## Segment boundaries

Tie them to **where the game lets the player save**. Two benefits: a checkpoint
we would otherwise have to invent is one that can drift from anything a player
experiences, and a checkpoint is only producible where the game's own save
routine can run.

Target size roughly one save point to the next — a few thousand frames rather
than today's 20,000+. Expect 15–25 segments across the World of Balance.

## The invariant contract

**This is the correctness core, not a nicety.** Parallel segments can all be
green while the composition is broken: if segment B→C runs from a stored
checkpoint B, and segment A→B later changes what B *is*, then B→C is testing a
fiction — and it passes, because it never sees A→B's output.

That is the same shape as every fixture bug this project has had: a check that
can only agree with itself. So:

- **Every segment asserts its entry invariants before doing anything** — story
  switches, party roster and levels, inventory, map and position, and the OT6
  persistent state (codex magic, Bushido loadout). Loading a stale or wrong
  checkpoint must fail loudly, naming what differed. This is mandatory per
  segment.
- **Every segment asserts its exit state** — the thing the next segment's entry
  contract will check. Entry and exit contracts are written once and shared, so a
  mismatch is a diff between two named things rather than a judgement call.
- **Checkpoints carry a version.** `manifest.json` already has
  `persistent_layout`; a segment refuses a checkpoint whose layout string it does
  not understand.

## Release testing stays serial

Parallel segments are for iteration speed. They do not prove the game is
completable end to end, only that each segment works from a state we asserted.

So `make release-test` keeps a **full serial composition run** — power-on through
the whole chain, no checkpoints — and that is what a tag requires. Fast loop for
development, complete loop for shipping. If the serial run disagrees with the
parallel segments, a checkpoint is stale and the invariant contract failed to
catch it; that is a bug in the contract and should be fixed there.

## Costs, named

- **Tactical entry points cannot be battery saves.** "One A-press from battle 72"
  is mid-map facing an NPC. Those stay as short savestate drives *from* the
  nearest checkpoint. Acceptable while the drive is short.
- **An SRAM schema change invalidates every checkpoint at once.** The codex and
  the Bushido loadout live inside the saved block. `persistent_layout` is the
  hook; it needs a deliberate regenerate-and-migrate path rather than silent
  breakage.
- **~20 tracked 32 KiB files.** Trivial for git. The real cost is that a stale
  checkpoint is now a *correctness* risk rather than merely a slow rebuild —
  which is exactly what the invariant contract is for.
- **Checkpoints must be produced through the game's own save routine**, not
  synthesised, or they stop being evidence that the route is playable.

## Migration

Incremental, and each step is useful alone:

1. Generalise `mint_anchor` from the single `POST_OPERA_ANCHOR` to a keyed set,
   and give checkpoints a directory convention.
2. Write the entry/exit invariant helper, and retrofit it to the existing
   post-Opera checkpoint so the contract is exercised before anything depends on
   it.
3. Cut checkpoints at the save-point boundaries, working **backwards**
   from the current end of the chain — the newest content benefits first and the
   oldest trunk keeps working unchanged.
4. Flip segments to checkpoint inputs one at a time. Any segment not yet
   converted still boots its predecessor, so the chain never has to be broken to
   migrate it.
5. Keep the serial composition run as the release test throughout.

## Open questions

- Does every desired boundary have a legal save point, or do some segments need a
  short savestate drive from the nearest one?
- Should checkpoints be regenerated automatically when a segment's exit contract
  changes, or always deliberately? Automatic regeneration risks laundering a
  regression into the baseline.
- How much of the existing trunk is worth converting versus leaving as-is?
