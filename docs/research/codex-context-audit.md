# The $021f context audit (issue #29)

2026-07-28.  `Ot6CodexActive` (ff6/src/battle/ot6_codex.asm) selects the
per-save codex page by reading `$7e021f` (wSaveSlotToLoad), and all three of
its callers run in battle context (ot6_break.asm:97/:868/:976).  Issue #29
asked, with a measurement behind it, whether any module overlays that cell
between the menu's lifecycle write and the battle's read.  Answer, measured:
**no player-reachable flow overlays it; the overlay in the issue's evidence
was an artifact of the test drive that found it.**  Disposition: document +
regression (`tools/tests/codex_ctx.lua`); no ROM change.

## Instrumentation

Two probes per run, both harness-side (no ROM edits):

* an exec memory callback at `Ot6CodexActive`'s entry (symbol from the .dbg
  via `H.sym`) logging frame, `$021f`, and the jsr return address read off
  the stack — classifying every read by call site (seed :86 / elem-reveal
  :849 / class-chip :949 / the menu-side `Ot6CodexSaveAs` caller);
* a per-frame `$021f` transition sampler (`startFrame` event callback) —
  sampling, not write callbacks, because the issue's own measurement showed
  value changes with no CPU write firing.

## The matrix (module × moment → $021f at the read)

Fresh chain = worldmap_narshe / kolts_cave lineage, never saved (lifecycle
0).  Loaded = cold battery Continue into slot 3 (post-opera-v1 or
n024-doorstep-save-v1 anchors), lifecycle 3.

| context | moment | $021f | codex reads |
|---|---|---|---|
| field, fresh (map 96) | baseline | 0 | — |
| battle from field, fresh, healthy | seed | 0 | seed=0 ✓ |
| field, fresh | menu open / close | 0 / 0 | — |
| battle from field, fresh, post-menu | seed | 0 | seed=0 ✓ |
| field, loaded (map 273) | after cold Continue | 3 | — |
| menu, loaded, on save tile | open / post-save | 3 / 3 | SaveAs caller=3 ✓ |
| field, loaded | after save + menu close | 3 | — |
| battle 72 from field, post-save | seed + chips | 3 | seed=3, class-chip=3 ✓ |
| world, loaded | after cold Continue | 3 | — |
| battle from world, healthy | seed + chips | 3 | seed=3, class-chip=3 ✓ |
| world, loaded | menu open / close (no save) | 3 / 3 | — |
| battle from world, post-menu | seed + chips | 3 | seed=3, class-chip=3 ✓ |
| world, fresh | baseline | 0 | — |
| menu, fresh | real first save into slot 3 | 0→3 at CopyGameDataToSRAM | SaveAs caller=0 (pre-write: correct source page) ✓ |
| world, fresh | after save + menu close | 3 | — |
| battle from world, post-save | seed | 3 | seed=3 ✓ |
| Vector town (map 242), loaded | 900 frames pacing | 3, zero transitions | — |
| battle from factory (map 262), loaded | seed + chips | 3 | seed=3, class-chip=3 ✓ |

Whole-run transition counts: every clean run's sampler logged exactly the
lifecycle writes and nothing else (samples=1 or 2 per run across
2,500–25,000 frames).

The elem-reveal site (:849) never fired in these drives (no
weakness-matching elemental hit landed); its read is established by the
sampler — `$021f` never changed during any battle, so a read at any
mid-battle moment sees the seed's value — not by direct observation.

## Why the cell is stable (mechanism, all read)

* `$021f` has exactly four writers, all menu lifecycle moments:
  menu/menu_common.asm:250 and menu/field_menu.asm:3522 (New Game, `stz`),
  menu/field_menu.asm:3560 (load confirm), menu/save.asm:50 (save — the OT6
  line).  No other reference to the cell exists in the source tree.
* The world module's supposed "block restore over $0200" (the issue's
  hypothesis) does not exist: its direct-page swap covers $0000–$00FF only
  (world/init.asm:1446–1516, PushDP/PopDP, 16-byte stride to `cmp #$0100`)
  and its mode-7 variable block is $0520–$0bff (world/init.asm:1414–1443).
  The world→battle path (world/move.asm:882–922: PushDP,
  CheckBattleWorld_ext, PopDP, `jsl Battle_ext` at :908) never touches it.
* The menu's live clock is the nearest neighbor — wGameTimeHours..Frames at
  $021b–$021e — and ticks 8-bit (menu/menu_common.asm, the NMI clock — the exact lines were re-checked
  2026-07-30 and 3493/3480 land on `sty zWaitCounter` / `lda #$00`, not on
  `IncGameTime`; the mechanism holds, the anchors do not — under the
  `.a8` at :3480), so the tick cannot carry into $021f.

## What the issue actually measured

codex_saveas.lua enters save select by writing ZMENUSTATE=$13 directly,
skipping `SelectMainMenuOption_06`'s companion writes
(field_menu.asm:4238: fade via state 0, `$9e=$13`, `$9f=$04`).  Driving
that same shortcut reproduced the issue's evidence exactly: `$021f` read 5
~24 frames after the save **while still in the menu**, and the corrupted B
exit path then wandered (one run re-fired the world entrance under the
party into a town where the cell oscillated 36/37 — menu tasks still
running over a field map).  With the real entry writes in place, the same
drive start-to-finish never produced any foreign value, five runs.  The "5"
appears without a CPU write callback firing, consistent with a DMA/WMDATA
block operation from a menu task running in a state it was never meant to
run in; its exact source was not chased further because the state is not
player-reachable (it requires an external write to ZMENUSTATE).

Two collateral traps, measured while getting the drive right:

* **Closing a world-map menu re-fires the entrance under the party.**  The
  close path ends in `jmp ReloadMap` (world/world_start.asm:436–438), and
  the reload re-runs the entrance check on the tile the party stands on —
  parked on Narshe's entrance, the close dropped the party into the town.
* **`worldReady()`-shaped predicates are menu-module garbage while a menu
  is up.**  $e0/$e2/$e7/$e8 belong to whatever module owns the zero page;
  with the main menu open they satisfied "world control" while the menu
  was still on screen.  The positive witness that the world module is back
  is the exact parked tile.

## The regression

`tools/tests/codex_ctx.lua` (`@suite frontier=worldmap_narshe slow`): first
save into empty slot 3 through the save-select UI on the world map, stage
FIRE for every species in the slot-3 codex page and ICE in the transient
page, close the menu, walk into a desert encounter, and require every
present monster's revealed-element state to carry FIRE and not ICE at
battle entry.  Fail-before was demonstrated by injecting the feared overlay
(`$021f=5`) after menu close on an otherwise identical drive: the seed
merged the transient page and the FIRE assertion failed by name; the
unsabotaged run passes.

## Residue

* The issue's fourth acceptance box — the #25 entry-contract slot witness
  off `$021f` — was already done before this audit:
  tools/tests/lib/ot6_contract.lua:603–604 reads `$307ff0`.
* HANDOFF.md "trap #1" attributes the overlay to a world-module block
  restore; per the above that mechanism claim is wrong (the trap's
  *practical* advice — witness persistent facts through SRAM — remains
  good).  Not edited here; flagged to the dispatcher.
* codex_saveas.lua still uses the bare-ZMENUSTATE shortcut.  It passes (it
  never closes the menu, and its assertions read SRAM), but the shortcut is
  the proven source of the phantom overlay; migrating it to the
  real-command entry (the codex_ctx.lua drive) would retire the last copy.
