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
`battle.asm` / `event.asm`):

| RAM | meaning |
|---|---|
| `$086A` / `$086D` | party pixel X / Y (word); **tile = `>> 4`** |
| `$0869` / `$086C` | sub-pixel X / Y |
| `$1FC0` / `$1FC1` | party tile X / Y — a lazily-updated *cache*, stale mid-walk |
| `$1F64` | map index (word) |
| `$0743` | party facing (0=up 1=right 2=down 3=left) |
| `$087C` low nibble | party movement type: **2 = user-controlled**, 4 = event-controlled |
| `$1EB9` bit 7 | **user has no control** (cutscene/event) |
| `$0084` / `$0059` | map loading / menu opening (`$0059` stays `1` for a whole event-opened menu, e.g. the naming screen) |
| `$E5`-`$E7` | 24-bit event script PC; **idle = `$CA0000`**, real scripts run in banks `$CA`-`$CC` |
| `$BA` / `$D3` | both `1` = a dialog is open, waiting for a keypress |
| `$B2` | party z-level (bit 0 upper, bit 1 lower) |

Events can walk the party with `$1EB9`/`$0084`/`$0059` all looking
innocent, so control gating checks the movement type and event PC too —
that's `H.hasControl()`. Two event-PC subtleties, both load-bearing:

- Ambient NPC **object scripts** (a stove flame, a wanderer) execute
  through the same interpreter out of their RAM queue — the PC reads
  `$80xxxx` (WRAM mirror) for one frame at a time, every few frames,
  forever on such maps. `H.eventRunning()` therefore requires the PC to
  be inside banks `$CA`-`$CC`; treating any non-idle value as "event
  running" starves every consecutive-calm-frames predicate.
- A stood-on **event trigger re-fires every 4 frames**. Once its switch
  makes it a no-op, the cycle is 3 frames of event (movement type 4) and
  1 frame of control, forever. Routes must step OFF a trigger tile (a
  raw held direction lands in the 1-frame windows) before waiting for
  calm; no calm predicate can be satisfied while parked on one.

Dialog advancing is **edge-triggered**: one held A yields exactly one
page. Advancing multiple pages takes press-RELEASE-press (4 frames on /
4 off works).

Harness API (`tools/tests/lib/ot6.lua`):

- `H.fieldX()`, `H.fieldY()`, `H.mapId()` — live position (pixel `>> 4`;
  never navigate on the `$1FC0` cache) / map.
- `H.tileAligned()` — at rest exactly on a tile: `$0869`, `$086C` and the
  low 4 bits of both pixel words all zero. Position samples are only
  valid here — the tile coord flips ~1px into a step moving up/left but
  only at completion moving down/right.
- `H.hasControl()` — true only when the party can actually be walked
  this frame (control bit clear, not loading, not in a menu, movement
  type 2, event PC idle, no battle loading). Cheap RAM reads only.
- `H.eventRunning()`, `H.dialogWaiting()` — the event-PC and dialog
  checks from the table above.
- `H.canStep(x, y, dir)` — true passability for one step, from RAM (next
  section).
- `H.bfsPath(tx, ty [, blockedEdges])` — BFS over `canStep` edges from
  the party's current tile (z-level tracked along each candidate path);
  returns a list of direction strings or nil.
- `H.navTo(tx, ty, opts)` — BFS-driven walker, below. Targets may be
  numbers or thunks (resolved each tick, for runtime-known coords).
- `H.clearBattle(maxFrames, spare)` — win the current fight headlessly:
  set each present monster's dead-status bit (`$3AA8` bit 0 →
  `$3EEC` bit 7) and edge-tap A through the victory text. Formations
  whose species words appear in `spare` are never kill-bitted — clearing
  the fight a route exists to reach is a script bug, so it errors.
- `H.advanceStory(pred, maxFrames, opts)` — ride out a non-interactive
  story stretch (long automatic events, intermittent dialogs, scripted
  battles) until `pred()`: battles are kill-bitted and edge-tapped,
  dialogs edge-tapped, everything else gets a neutral pad. A formation
  in `opts.spare` is a set-piece: never kill-bitted, hands off for its
  first 300 frames (A during the load queues player actions that starve
  the battle event that ends it), then edge-tapped (its battle dialogs
  stall without A). This is how the esper-zap scene is crossed.
- `H.navDump()` — one-line navigator state (debugging).

### True passability (the engine's own rules, from RAM)

The collision data is in RAM, so passability is *computed*, not
discovered. From the vendored disassembly (`src/field/map.asm`,
`player.asm`):

| RAM | meaning |
|---|---|
| `$7F0000` | BG1 tilemap, `row*256 + col` (one tile-type byte per position) |
| `$7E7600[tile]` | tile properties: bits 0/1 z-level, bit 2 bridge, `& 7 == 7` counter/wall |
| `$7E7700[tile]` | directional exit bits: up `$08`, right `$01`, down `$04`, left `$02` |
| `$7E2000[row*256+col]` | object map; bit 7 **set = free**, clear = an NPC/object stands there |

`H.canStep` is an exact port of the engine's step check,
`CheckPlayerMove` (`src/field/player.asm`). A step from `cur` toward a
direction is allowed iff **all** of:

1. `$7700(cur)` has the direction's exit bit;
2. `$7600(dst) & 7 ≠ 7` (counter/wall);
3. the bridge/z rules pass — with `c = $7600(cur)`, `d = $7600(dst)`,
   `z = $B2`: on a bridge (`c & 4`), upper-z (`z & 1`) forbids
   `d & 2`, lower-z forbids `d & 1`; off a bridge, `d & 3 == 3` is
   always allowed, `c & 3 == 3` allows everything *except* a bridge
   tile, and otherwise `((c&3) XOR 3) & (d&3)` must be zero;
4. the destination's object-map bit 7 is set (no NPC there — the engine
   also allows crossing *under* an occupied bridge tile; the port skips
   that case, conservatively).

Stepping off a non-bridge tile sets the party z-level from that tile's
z bits, so `bfsPath` carries a z-level along each candidate path rather
than assuming the live `$B2` stays valid. `probe_canstep.lua`
validates the port against real movement (predict, press, compare —
including a blocked press) and renders the model's view of the
neighborhood as ASCII.

### Executing a route: navTo

Movement is **cardinal** (up=−Y, down=+Y, left=−X, right=+X, one tile
per step); the engine reads *held* direction bits and processes a party
action every 4 frames; a walk step is 16 frames (1px/frame) and always
completes once started. A press turns *and* steps in the same action
when the step is allowed; a blocked press just turns.

`H.navTo(tx, ty, opts)` BFS-plans on `canStep` and executes one
verified step at a time. Each iteration (only when user-controlled and
tile-aligned): hold the next direction until the tile coord changes,
release, wait for tile-alignment, and check the landing against the
plan. A press that never moves the party proves the model wrong for
that edge (an NPC wandered in, a z quirk): the edge is blocklisted for
this `navTo` (it persists across re-plans) and the route re-BFSes. Any
other deviation — an event force-move, post-battle drift — just
re-plans from the live position. Along the way it:

- clears random encounters with the kill-bit idiom, edge-tapping A
  through the victory text — but **never** a formation listed in
  `opts.spare` (the goal fight: pad released, `opts.arrive` sees it);
- edge-taps A through dialogs (`dialogWaiting`);
- goes hands-off (neutral pad) for any other control loss and lets the
  event play out;
- debounces those three states over 3 consecutive frames first — the
  battle/dialog signal bytes live in RAM the field module also
  scribbles on, and acting on a one-frame ghost would tap A on the
  open field.

`opts.arrive` is an extra terminator predicate checked every frame;
`opts.maxFrames` (default 20000) errors on timeout. Termination:
`arrive()`, or standing on the target tile user-controlled and
tile-aligned.

### The Whelk fixture

`gen_whelk.lua` runs the whole stack deterministically: boot the
injected save (party at (33,22), map 41, Narshe mines), `navTo(42, 6)`,
mint `whelk_doorstep.mss` there, then take one deliberate step north.
The Whelk event trigger is the single tile **(42,5)**; stepping onto it
tile-aligned while user-controlled fires the event, which force-walks
the party down to (42,7), shows dialogs `$0B6E` / `$0B6F` (edge-tapped
through), and starts the Whelk battle (formation `$01B0`). During the
fight the formation species words at `$57C0` read `0x0100` and
`0x0134` — match on those (`$57C0` is battle scratch: power-on garbage
before the first fight, stale words after one, so gate any read on
`battleLoadStarted()`). The whelk-done event switch is `$1EA6` bit
`$20`; once set, the trigger is inert — the script asserts it clear at
boot. Full run ≈ 2800 frames, ~15 s wall.

### Reaching a balance fixture

The demo doorstep is the mech-suit intro — beam party, no clean
weakness/break loop, unfit for balance numbers. The fastest path to a
real balance fixture is a **fresh save-point save past the mech-suit
intro** (into the scenario split — normal-command parties vs.
weakness-having enemies): make it in the GUI, run
`make_srm_sidecar.sh`, and `metrics_battle.lua` measures it with zero
extra setup.

## Runtime limits

Two wall-clock caps apply to every headless run, both configured by the
harness:

- `run.sh` passes `--timeout=600`. Mesen's testrunner defaults to a
  **100-second** wall-clock cap; past it the process exits −1 (shell
  255) with truncated, block-buffered stdout.
- `pin_test_saves.py` sets `Debug.ScriptWindow.ScriptTimeout = 30`
  (seconds). This per-Lua-slice watchdog defaults to **1 s** and kills a
  slow frame callback (a big BFS, say) *silently* under `--testrunner` —
  the error only reaches the script-window log, which run.sh's
  `--enableStdout` mirrors to stdout.

Frame budgets (`H.run`'s `maxFrames`) remain the per-script failsafe;
the gen_whelk route fits in 9000 frames ≈ 15 s wall.
