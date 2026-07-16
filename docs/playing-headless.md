# Playing the game headlessly

The harness can load a real save, read where the party is, and walk it
around — so routes toward specific encounters are coordinate-aware
instead of blind timed button-holds (which desync on any map). This is
the tooling that lets automated tests reach arbitrary points in the
game for balance measurement.

## Save decoupling (manual play vs. repeatable testing)

Two save worlds, physically separated so manual play can never be
corrupted by a test run (it was zeroed twice before this split):

- **Your manual-play save** lives in Mesen's normal profile
  (`~/Library/Application Support/Mesen2/Saves/ot6.srm`). Tests never
  read or write it directly.
- **Repeatable-testing saves** live in `build/mesen-test-saves/`. The
  portable test Mesen (`build/mesen-test.app`) is forced there every
  run by `tools/tests/lib/pin_test_saves.py` (it rewrites the portable
  `settings.json` with an explicit `SaveDataFolder` override), so the
  two directories can't share a file even if your Mesen settings later
  grow their own override.

Copy from your play save into the testing world on demand:

    tools/tests/make_srm_sidecar.sh   # snapshot the live save -> sidecar

This writes `build/states/playthrough_srm.mss.lua`, the front 8 KB of
your battery save (the slots; the upper SRAM banks hold the OT6 codex)
as an embeddable base64 blob. It's under gitignored `build/`, so save
data is never committed.

## Booting a save headless

Headless Mesen always boots SRAM zeroed (battery loading is GUI-only),
so the harness *injects* the save into SRAM at boot and drives the
title's Continue. In-game saves are pure vanilla-layout data with no
code dependency, so a sidecar made once keeps loading across ROM
rebuilds — unlike savestates (`.mss`), which snapshot RAM+CPU and break
when code moves.

    tools/tests/probe_srmboot.lua   # inject, Continue, land on the field
    tools/tests/probe_slots.lua     # survey all three save slots

The inject idiom (front 8 KB to cpu `$30:6000`):

    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end

## Field navigation

Addresses (from the vendored disassembly, `src/field/player.asm` /
`battle.asm`):

| RAM | meaning |
|---|---|
| `$1FC0` / `$1FC1` | party tile X / Y |
| `$1F64` | map index (word) |
| `$0743` | party facing |
| `$1EB9` bit 7 | **user has no control** (cutscene/event) |
| `$0084` / `$0059` | map loading / menu opening |

Harness API (`tools/tests/lib/ot6.lua`):

- `H.fieldX()`, `H.fieldY()`, `H.mapId()` — read position/map.
- `H.hasControl()` — true only when the party can actually be walked
  this frame (control bit clear, not loading, not in a menu, not in
  battle). Any navigation must gate on this.
- `H.navTo(tx, ty, opts)` — walk toward a tile. Targets may be numbers
  or thunks (resolved each tick, for runtime-known coords). Movement is
  **self-calibrating**: it learns which button moves which axis and
  sign by observing deltas (corridors bend — never assume up = −y),
  wall-follows around blocked directions, and clears any encounter that
  fires mid-walk. `opts.arrive` is an extra terminator predicate (e.g.
  stop on a map change or a battle); `opts.stuckCap` bounds blocked
  direction-changes before it errors.
- `H.clearBattle()` — win the current fight headlessly by setting each
  monster's dead-status bit and advancing the victory text.
- `H.navDump()` — the directions calibrated so far (debugging).

### What it can and can't do

navTo is greedy + wall-following, not a full maze solver. On open-ish
maps it reaches arbitrary tiles; on tight mazes it needs **waypoints** —
observe the corridor coords and script a sequence of `navTo` hops around
the corners (the speedrun-route approach). The primitive handles
tile-by-tile with calibration and encounter-clearing; you supply the
high-level path by looking at the map. `probe_navto.lua` demonstrates
the full loop end to end (boot save → calibrate → walk → hit encounter →
clear it).

### Reaching a balance fixture

The demo doorstep is the mech-suit intro — beam party, no clean
weakness/break loop, unfit for balance numbers. The fastest path to a
real balance fixture is a **fresh save-point save past the mech-suit
intro** (into the scenario split — normal-command parties vs.
weakness-having enemies): make it in the GUI, run
`make_srm_sidecar.sh`, and `metrics_battle.lua` measures it with zero
extra setup.
