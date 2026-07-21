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
- **Repeatable-testing saves** live in `build/mesen-test-saves/`. Tests
  run the shared read-only emulator against a private Mesen config home
  (`build/mesen-test-home/`, selected with `CFFIXED_USER_HOME`), and
  `tools/tests/lib/pin_test_saves.py` writes that home's `settings.json`
  with an explicit `SaveDataFolder` override every run — so the two
  directories can't share a file even if your Mesen settings later grow
  their own override. Worker runs (`OT6_WORKER=<id>`, see the tests
  README) repeat the same scheme under `build/test-workers/w<id>/`.

`run.sh` also wipes `<saves>/*.srm` before every launch: the testrunner
flushes battery on exit and reloads it next boot, so a stale srm is a
hidden cross-run coupling channel. Tests that need a save inject it
explicitly (next section); the disk srm is residue.

Copy from your play save into the testing world on demand:

    tools/tests/make_srm_sidecar.sh   # snapshot the live save -> sidecar

This writes `build/states/playthrough_srm.mss.lua`, the front 8 KB of
your battery save (the slots; the upper SRAM banks hold the OT6 codex)
as an embeddable base64 blob. It's under gitignored `build/`, so save
data is never committed.

## Booting a save headless

Headless tests boot SRAM zeroed by construction (the pre-launch srm
wipe above), so the harness *injects* the save into SRAM at boot and
drives the title's Continue. In-game saves are pure vanilla-layout data with no
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

- On maps with ambient NPC activity (a stove flame, a wanderer) the event
  PC at `$E5`-`$E7` reads `$80xxxx` for one frame at a time, every few
  frames, forever (measured in Arvis's house: `$800000` one frame in
  four). `H.eventRunning()` therefore requires the PC to be inside banks
  `$CA`-`$CC`; treating any non-idle value as "event running" starves
  every consecutive-calm-frames predicate.
  An earlier note here explained the `$80` as NPC object scripts running
  "through the same interpreter out of their RAM queue". That mechanism is
  wrong: object scripts use a separate interpreter with its own pointer in
  `$2A`/`$2C` (`field/obj.asm:4516`), seeded from event-script ROM, and no
  field-module write to `$E5`-`$E7` ever sets bank `$80`. The likely truth
  is duller — `$E5`-`$E7` are shared direct-page scratch that 30+ files
  write, so a non-`$CA` bank just means some other subsystem parked a
  pointer there. The true source of `$80` is UNVERIFIED; the bank gate is
  correct either way, so this is a comprehension hazard, not a bug.
- A stood-on **event trigger re-fires every 4 frames**. Once its switch
  makes it a no-op, the cycle is 3 frames of event (movement type 4) and
  1 frame of control, forever. Routes must step OFF a trigger tile (a
  raw held direction lands in the 1-frame windows) before waiting for
  calm; no calm predicate can be satisfied while parked on one.

Dialog advancing is **edge-triggered**: one held A yields exactly one
page. Advancing multiple pages takes press-RELEASE-press (4 frames on /
4 off works).

Harness API (`tools/tests/lib/ot6.lua` for the battle core and the shared
field-state reads; `tools/tests/lib/ot6_field.lua` for the navigation
stack -- compose inlines both, so scripts see one `H`):

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
- `H.canStep(x, y, move)` — true passability for one step, from RAM (next
  section). `move` is one of the eight: `up right down left` plus
  `upright downright downleft upleft`.
- `H.movePress(move)` — the button that executes a move (a diagonal is
  pressed `left` or `right`; the tile decides which diagonal).
- `H.bfsPath(tx, ty [, blockedEdges])` — BFS over `canStep` edges from
  the party's current tile (z-level tracked along each candidate path);
  returns a list of move names or nil.
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
| `$7F0000` | BG1 tilemap, `row*256 + col` (one tile-type byte per position); coordinates wrap at `$86`/`$87`, the map's own size masks, **not** at 256 (`player.asm:1387-1412`) |
| `$7E7600[tile]` | tile properties: bits 0/1 z-level, bit 2 bridge, `& 7 == 7` counter/wall, bits 6/7 diagonal movement |
| `$7E7700[tile]` | directional exit bits: up `$08`, right `$01`, down `$04`, left `$02` |
| `$7E2000[row*256+col]` | object map; bit 7 **set = free**, clear = an NPC/object stands there |

`UpdatePlayerMovement` (`player.asm:325`) reads the d-pad and takes one
of **two** branches, and `H.canStep` ports both.

#### The cardinal branch (`player.asm:456` → `CheckPlayerMove`)

A step from `cur` toward a direction is allowed iff **all** of:

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
than assuming the live `$B2` stays valid.

#### The diagonal branch (`player.asm:379`)

The engine tests the party's **own** tile before reading the d-pad
(`player.asm:368-377`). If `$7600(cur) & $c0` is set — and it is not a
bridge tile the party is standing on the lower z-level of — then a
**left or right press moves the party diagonally**, one tile in each
axis. Which diagonal is a property of the tile, not of the press:

| `$7600(cur)` bit | right press | left press |
|---|---|---|
| bit 7 `$80` (`\` tiles) | down-right (dir `$06`) | up-left (dir `$08`) |
| bit 6 `$40` (`/` tiles) | up-right (dir `$05`) | down-left (dir `$07`) |

Bit 7 wins when both are set. The destination test is the whole of it:
`$7600(dst)` must carry the **same** diagonal bit and must not be
exactly `$f7`. This branch consults nothing else — not the exit bits,
not the counter rule, not the z-level rules, not the object map — and
never calls `CheckDoor`. `_c04f8d` (`player.asm:1286`) maps directions
`$05`–`$08` to exactly those four neighbours, and `CalcObjMoveDir`
(`obj.asm:5521`) drives both axes at the cardinal rate, so a diagonal
step costs the same 16 frames as a straight one.

Up and down presses are not handled by this branch at all
(`player.asm:380`/`:405` test only the right/left bits) and fall through
to the cardinal path — as does a left/right press whose diagonal
destination is refused (`:396`, `:400`, `:417`, `:426` all jump into the
cardinal code). So on a diagonal tile the diagonal is **tried first**,
and the cardinal move of the same press happens only when the diagonal
is refused. That is why `canStep(x, y, "right")` is *false* where the
engine would turn a right press into a diagonal.

Every staircase in Figaro Castle is built from these tiles. While the
model knew only the cardinal branch they read as solid wall: map 55 fell
into three regions BFS could not join, a DFS over the real door graph
visited 14 rooms without reaching the castle ring, and `gen_edgar.lua`
had to hand-hold four staircases with raw held presses. Those hand-holds
are retired.

`probe_canstep.lua` validates both branches against real movement
(predict, press, compare) — the cardinal one at the mines boot area
including a blocked press, the diagonal one by sweeping all four presses
across each tile of the matron's staircase in Figaro and asserting the
sweep produced a real diagonal, a real cardinal fallback and a real
refusal. It renders the model's view of the neighborhood as ASCII.

### Executing a route: navTo

A step is one tile per press (up=−Y, down=+Y, left=−X, right=+X), plus
the four diagonals above; the engine reads *held* direction bits and
processes a party action every 4 frames; a walk step is 16 frames
(1px/frame) and always completes once started. A press turns *and* steps
in the same action when the step is allowed; a blocked press just turns.

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
`0x0134` — match on those (`$57C0` is battle scratch: whatever
`RamPowerOnState` filled it with before the first fight — zeros under the
pinned test profile — and stale words after one, so gate any read on
`battleLoadStarted()`). The whelk-done event switch is `$1EA6` bit
`$20`; once set, the trigger is inert — the script asserts it clear at
boot. Full run: PASS at frame 2813, ~8.5 s wall, byte-identical
artifacts every run (the harness pins power-on RAM and frame
rendering — see Runtime limits).

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
  slow frame callback (a big BFS, say) *silently* under `--testrunner`.
  Nothing surfaces it: the error goes to the script log, which only the GUI
  script window reads. `--enableStdout` mirrors the *emulator* log, not
  that one. Script errors are invisible headless — `print()` is the only
  channel out, so a test that goes quiet is telling you nothing.

`pin_test_saves.py` also pins the test profile for determinism —
`Snes.RamPowerOnState = "AllZeros"` (FF6 reads RAM it has never written,
and Mesen's SNES default is `Random`, so runs diverged — three `Random`
boots give three different WRAM hashes, two `AllZeros` boots are
byte-identical; the pin is what makes runs bit-stable),
`Snes.DisableFrameSkipping = true` (frame-skip picks rendered frames by
host timing, so screenshots and savestate framebuffers varied), and
`Audio.EnableAudio = false` (inert headless; hygiene). Test profiles
deliberately diverge from the play profile here: runs are bit-reproducible
by construction.

Frame budgets (`H.run`'s `maxFrames`) remain the per-script failsafe;
the gen_whelk route budgets 9000 frames and completes at 2813 ≈ 8.5 s
wall.
