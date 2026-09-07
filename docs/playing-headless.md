# Playing the game headlessly

The harness loads a real save, reads where the party is, and walks it
around, so routes are coordinate-aware rather than blind timed
button-holds. This is what lets automated tests reach arbitrary points in
the game.

What counts as play, and what a snapshot may be used for, is
[docs/TESTING.md](TESTING.md).

## Save decoupling

Two sets of saves in separate directories, so a test run cannot corrupt
manual play:

- **Manual-play save**: Mesen's normal profile
  (`~/Library/Application Support/Mesen2/Saves/ot6.srm`). Tests never touch
  it.
- **Test saves**: each invocation's private `build/test-runs/<run>/saves/`,
  selected via `CFFIXED_USER_HOME`; `tools/tests/lib/pin_test_saves.py`
  writes that home's `settings.json` with an explicit `SaveDataFolder`
  override every run. `OT6_WORKER` is a diagnostic label, not an isolation
  key.

`run.sh` wipes `<saves>/*.srm` before every launch; tests that need a save
inject it explicitly. `tools/tests/make_srm_sidecar.sh` snapshots the live
play save to `build/states/playthrough_srm.mss.lua` (front 8 KB, the
vanilla slots, as an embeddable base64 blob; the OT6 bank-31 pages are not
included).

## Booting a save headless

Use the versioned full-battery checkpoint path below to boot an existing
save through the game's Continue menu. For repeated experiments on the same
compatible build, use the harness's complete emulator snapshot helpers,
including inside a battle or menu. A machine snapshot captures execution
state and can become incompatible when ROM code moves; a battery save instead
requires compatibility with its declared persistent layout.

The old front-8-KiB SRAM injection recipe omitted OT6's extra save pages and
is not the supported path for new gameplay fixtures. Complete snapshot
restoration is authorized; selectively transplanting RAM into a running
attempt is not. See the testing policy for the distinction.

## Versioned SRAM checkpoints

Durable shortcuts deep into the game use a complete 32 KiB Mesen `.srm`:
`tools/tests/checkpoints/<key>/` holds a manifest plus a hashed payload.
`sram_checkpoint.py validate <dir>` rejects unknown schemas, unsafe payload
names, wrong sizes, and hash mismatches. `run.sh` installs a verified
checkpoint into the invocation-private save folder when
`OT6_SRAM_CHECKPOINT` is set; Mesen takes its ordinary cold-load path and no
Lua writes SRAM. To capture a new payload, `OT6_CAPTURE_SRM=<path>` copies
Mesen's complete battery file after emulator shutdown and records provenance.
Seal it with `python3 tools/tests/lib/sram_checkpoint.py seal <dir>` and
validate before committing; preserve the capture provenance.

## Field navigation

Addresses (from the vendored disassembly):

| RAM | meaning |
|---|---|
| `$086A` / `$086D` | party pixel X / Y (word); **tile = `>> 4`** |
| `$0869` / `$086C` | sub-pixel X / Y |
| `$1FC0` / `$1FC1` | party tile X / Y — a lazily-updated cache, stale mid-walk |
| `$1F64` | map index (word) |
| `$0743` | party facing (0=up 1=right 2=down 3=left) |
| `$087C` low nibble | party movement type: **2 = user-controlled**, 4 = event-controlled |
| `$1EB9` bit 7 | user has no control (cutscene/event) |
| `$0084` / `$0059` | map loading / menu opening (`$0059` stays `1` for a whole event-opened menu) |
| `$E5`-`$E7` | 24-bit event script PC; idle = `$CA0000`, real scripts run in banks `$CA`-`$CC` |
| `$BA` / `$D3` | both `1` = a dialog is open, waiting for a keypress |
| `$B2` | party z-level (bit 0 upper, bit 1 lower) |

Events can walk the party while `$1EB9`/`$0084`/`$0059` all read normal, so
`H.hasControl()` tests the movement type and event PC too. Two event-PC
details:

- On maps with ambient NPC activity the event PC reads `$80xxxx` for one
  frame at a time, every few frames, forever; `H.eventRunning()` therefore
  requires the PC to be inside banks `$CA`-`$CC`.
- A stood-on event trigger re-fires every 4 frames. Once its switch makes
  it a no-op, the cycle is 3 frames of event and 1 of control, forever;
  routes must step off a trigger tile before waiting for calm.

Dialog advancing is edge-triggered: one held A yields exactly one page;
multiple pages take press-release-press (4 on / 4 off).

Harness API (`tools/tests/lib/ot6.lua` for the battle core and shared
field reads; `tools/tests/lib/ot6_field.lua` for the navigation stack;
compose inlines both, so scripts see one `H`):

- `H.fieldX()`, `H.fieldY()`, `H.mapId()` — live position (pixel `>> 4`;
  never navigate on the `$1FC0` cache) / map.
- `H.tileAligned()` — at rest exactly on a tile: `$0869`, `$086C` and the
  low 4 bits of both pixel words all zero. Position samples are only valid
  here.
- `H.hasControl()` — true only when the party can be walked this frame.
- `H.eventRunning()`, `H.dialogWaiting()` — the checks above.
- `H.canStep(x, y, move)` — true passability for one step, from RAM.
  `move` is one of `up right down left upright downright downleft upleft`.
- `H.movePress(move)` — the button that executes a move (a diagonal is
  pressed `left` or `right`; the tile decides which diagonal).
- `H.bfsPath(tx, ty [, blockedEdges])` — BFS over `canStep` edges,
  z-level tracked along each candidate path; returns move names or nil.
- `H.navTo(tx, ty, opts)` — BFS-driven verified-step walker. Targets may
  be numbers or thunks.
- `H.clearBattle(maxFrames, spare)` — legacy synthetic mechanism helper that
  writes monster death flags. Never use it to advance a legitimate gameplay
  fixture or as balance evidence; complete snapshot reuse is the shortcut.
- `H.advanceStory(pred, maxFrames, opts)` — advance a story stretch, including
  dialogs and battles. Gameplay callers must explicitly select
  `opts.playBattles="tactical"` (or another human-executable battle mode).
  The legacy flag-writing path is not legitimate play.
- `H.navDump()` — one-line navigator state.

### True passability (the engine's own rules, from RAM)

| RAM | meaning |
|---|---|
| `$7F0000` | BG1 tilemap, `row*256 + col`; coordinates wrap at the map's own size masks (`$86`/`$87`), not at 256 |
| `$7E7600[tile]` | tile properties: bits 0/1 z-level, bit 2 bridge, `& 7 == 7` counter/wall, bits 6/7 diagonal movement |
| `$7E7700[tile]` | directional exit bits: up `$08`, right `$01`, down `$04`, left `$02` |
| `$7E2000[row*256+col]` | object map; bit 7 set = free, clear = an NPC/object stands there |

`UpdatePlayerMovement` takes one of two branches, and `H.canStep` ports
both.

A cardinal step from `cur` toward a direction is allowed iff all of:

1. `$7700(cur)` has the direction's exit bit;
2. `$7600(dst) & 7 ≠ 7` (counter/wall);
3. the bridge/z rules pass — with `c = $7600(cur)`, `d = $7600(dst)`,
   `z = $B2`: on a bridge (`c & 4`), upper-z forbids `d & 2`, lower-z
   forbids `d & 1`; off a bridge, `d & 3 == 3` is always allowed,
   `c & 3 == 3` allows everything except a bridge tile, and otherwise
   `((c&3) XOR 3) & (d&3)` must be zero;
4. the destination's object-map bit 7 is set.

Stepping off a non-bridge tile sets the party z-level from that tile's z
bits, so `bfsPath` carries a z-level along each candidate path.

The diagonal branch: the engine tests the party's own tile before the
d-pad. If `$7600(cur) & $c0` is set (and it is not a bridge tile the party
stands on the lower z-level of), a left or right press moves diagonally,
one tile in each axis; which diagonal is a property of the tile:

| `$7600(cur)` bit | right press | left press |
|---|---|---|
| bit 7 `$80` (`\` tiles) | down-right | up-left |
| bit 6 `$40` (`/` tiles) | up-right | down-left |

Bit 7 wins when both are set. The destination must carry the same diagonal
bit and must not be exactly `$f7`; this branch consults nothing else. Up
and down presses fall through to the cardinal path, as does a refused
diagonal. A diagonal step costs the same 16 frames as a straight one.
`canStep(x, y, "right")` is false where the engine would turn a right press
into a diagonal. `probe_canstep.lua` validates both branches against real
movement.

### Executing a route: navTo

A step is one tile per press; the engine reads held direction bits and
processes a party action every 4 frames; a walk step is 16 frames and
always completes once started. A press turns and steps in the same action
when the step is allowed; a blocked press just turns.

`H.navTo(tx, ty, opts)` BFS-plans on `canStep` and executes one verified
step at a time: hold the direction until the tile coord changes, release,
wait for alignment, check the landing against the plan. A press that never
moves the party blocklists that edge for this `navTo` and re-plans; any
other deviation re-plans from the live position. For gameplay routes pass
`playBattles="tactical"` so encounters are fought through the real controls;
never rely on a legacy force-kill path. It edge-taps dialogs, goes hands-off
for other control loss, and debounces those states over 3 consecutive frames. `opts.arrive` is an
extra terminator predicate; `opts.maxFrames` (default 20000) errors on
timeout.

## Runtime limits

Two wall-clock caps apply to every headless run:

- `run.sh` passes `--timeout` (default 600 s, `OT6_TIMEOUT` overrides;
  generation edges in the ninja graph run at 1800 s). Past it the process
  exits −1 with truncated, block-buffered stdout.
- `pin_test_saves.py` sets `Debug.ScriptWindow.ScriptTimeout = 30`
  (seconds), the per-Lua-slice watchdog. Script errors are invisible
  headless — the error goes to a log only the GUI script window reads —
  so `print()` is the only channel out, and a test that goes quiet has
  told you nothing.

`pin_test_saves.py` pins the test profile for determinism:
`Snes.RamPowerOnState = "AllZeros"` (FF6 reads RAM it has never written),
`Snes.DisableFrameSkipping = true`, `Audio.EnableAudio = false`. Runs are
bit-reproducible by construction. Frame budgets (`H.run`'s `maxFrames`)
are the per-script failsafe.
