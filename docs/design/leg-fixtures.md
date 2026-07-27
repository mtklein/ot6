# Leg fixtures — parallelising the frontier on battery anchors

Status: **proposal**, 2026-07-27. Supersedes nothing; generalises the anchor
model that shipped in #9.

## The problem, measured

The frontier is a ~100-state chain in which each link boots the previous link's
**savestate**. Savestates are tied to exact ROM contents, so any ROM byte,
library edit, or generator change invalidates everything downstream and forces a
replay from power-on.

What that cost on a single day (2026-07-27):

- Four full re-mints, each running well over an hour.
- A wrong predicate in `lib/ot6.lua` hung `gen_moogle` at **rung 1**, blocking all
  100 states behind a failure in the first few minutes of the game.
- A five-instruction ROM change (#18) invalidated every tactical savestate; the
  base gate failed with `battle_kefka` booting to map 7 instead of 22, for
  reasons that had nothing to do with `battle_kefka`.
- Each wrong guess cost a full serial replay to discover, which is what made
  guessing so expensive and iteration so slow.

The pain compounds: v0.7–v0.9 are longer routes than anything minted so far.

## What already exists

This is not a from-scratch design. Three pieces are already in the tree:

- **`mint_anchor`** (`Makefile`) mints a state by cold-loading a tracked in-game
  battery save via `OT6_SRAM_ANCHOR`, rather than by booting a predecessor
  savestate. Built for `post-opera-v1` in #9.
- **Battery saves survive ROM changes.** #9 proved the post-Opera anchor
  cold-loads against a deliberately different ROM hash. The game reconstructs
  transient state on load, so a battery save is not coupled to exact ROM bytes
  the way a savestate is. *This is the property the whole design rests on.*
- **`make -jN frontier` already parallelises** where the graph allows — the three
  scenario branches after `scenario_hub`, and `kolts_pool`/`kolts_cave` beside
  the Vargas rung. Runner isolation (#14) makes concurrent mints safe.

The blocker is that everything up to the hub is a **serial trunk**, because each
link boots the previous doorstep.

## The change

Place a tracked battery anchor at each chapter boundary. Every leg declares an
**anchor** as its input instead of a predecessor state, so legs become mutually
independent and `make -jN frontier` can run them all at once.

```
today:   A --> B --> C --> D --> ...        (one break stops everything)

legs:    [anchor A] --> B      [anchor C] --> D
         [anchor B] --> C      [anchor D] --> E     (all at once)
```

A ROM change still marks every leg stale — the stamp keys on (ROM, generator,
lib) and should keep doing so. The win is that each leg then re-runs **from its
own anchor, in parallel**, instead of replaying the trunk from power-on. N short
concurrent runs instead of one long serial one.

## Leg boundaries

Tie them to **where the game lets the player save**, which is what #10 is adding
anyway for player-facing reasons. Two benefits: a checkpoint we would otherwise
have to invent is one that can drift from anything a player experiences, and an
anchor is only producible where the game's own save routine can run.

Target size roughly one save point to the next — a few thousand frames rather
than today's 20,000+. Expect 15–25 legs across the World of Balance.

## The invariant contract

**This is the correctness core, not a nicety.** Parallel legs can all be green
while the composition is broken: if leg B→C runs from a stored anchor B, and leg
A→B later changes what B *is*, then B→C is testing a fiction — and it passes,
because it never sees A→B's output.

That is the same shape as every fixture bug this project has had: a check that
can only agree with itself. So:

- **Every leg asserts its entry invariants before doing anything** — story
  switches, party roster and levels, inventory, map and position, and the OT6
  persistent state (codex magic, Bushido loadout). Loading a stale or wrong
  anchor must fail loudly, naming what differed. #9 already required this of the
  post-Opera anchor; it becomes mandatory per leg.
- **Every leg asserts its exit state** — the thing the next leg's entry contract
  will check. Entry and exit contracts are written once and shared, so a
  mismatch is a diff between two named things rather than a judgement call.
- **Anchors carry a version.** `manifest.json` already has `persistent_layout`;
  a leg refuses an anchor whose layout string it does not understand.

## Release gating stays serial

Parallel legs are for iteration speed. They do not prove the game is completable
end to end, only that each leg works from a state we asserted.

So `make release-test` keeps a **full serial composition run** — power-on through
the frontier, no anchors — and that is what a tag requires. Fast loop for
development, honest loop for shipping. If the serial run disagrees with the
parallel legs, an anchor is stale and the invariant contract failed to catch it;
that is a bug in the contract and should be fixed there.

## Costs, named

- **Tactical doorsteps cannot be battery saves.** "One A-press from battle 72" is
  mid-map facing an NPC. Those stay as short savestate drives *from* the nearest
  anchor — the hybrid #9 described. Acceptable while the drive is short.
- **An SRAM schema change invalidates every anchor at once.** The codex and the
  Bushido loadout live inside the saved block. `persistent_layout` is the hook;
  it needs a deliberate regenerate-and-migrate path rather than silent breakage.
- **~20 tracked 32 KiB files.** Trivial for git. The real cost is that a stale
  anchor is now a *correctness* risk rather than merely a slow rebuild — which is
  exactly what the invariant contract is for.
- **Anchors must be produced through the game's own save routine**, not
  synthesised, or they stop being evidence that the route is playable.

## Migration

Incremental, and each step is useful alone:

1. Generalise `mint_anchor` from the single `POST_OPERA_ANCHOR` to a keyed set,
   and give anchors a directory convention.
2. Write the entry/exit invariant helper, and retrofit it to the existing
   post-Opera anchor so the contract is exercised before anything depends on it.
3. Cut anchors at the boundaries #10 is already adding, working **backwards**
   from the current frontier — the newest content benefits first and the oldest
   trunk keeps working unchanged.
4. Flip legs to anchor inputs one at a time. Any leg not yet converted still
   boots its predecessor, so the chain never has to be broken to migrate it.
5. Keep the serial composition run as the release gate throughout.

## Open questions

- Does every desired boundary have a legal save point, or do some legs need a
  short savestate drive from the nearest one?
- Should anchors be regenerated automatically when a leg's exit contract changes,
  or always deliberately? #9's discipline says deliberately; automatic
  regeneration risks laundering a regression into the baseline.
- How much of the existing trunk is worth converting versus leaving as-is?
