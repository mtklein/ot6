# OT6 test harness (Mesen 2 headless testrunner)

Automated, GUI-free tests that boot `build/ot6.sfc`, drive the game with
scripted input, assert on RAM, and capture screenshots/savestates.

## Quick start

```sh
ninja build/ot6.sfc                                   # build the ROM
tools/tests/run.sh tools/tests/battle_smoke.lua       # run one test raw
ninja build/results/suite/battle_break.ok             # run one suite test (and what it needs)
ninja build/states/vargas_entry.mss.lua               # generate one savestate (and its chain)
ninja                                                 # everything

python3 tools/tests/lib/compose.py --check-states     # is this red test a stale fixture?
python3 tools/tests/lib/compose.py --adopt-stamps     # upgrade legacy stamps the tree's records can prove
```

Run `--check-states` when a fixture-related test fails unexpectedly. It
names what moved and gives regeneration commands. A fixture is **STALE**
when the ROM this tree builds is not the ROM it was captured on, when its
own generator (or the checkpoint it boots from) changed, or when its
artifact/ancestor bindings fail; **UNBOUND** when its bytes are not the
ones its stamp vouches for; **UNVERIFIED** when the tree has no built ROM
to compare against. A change to the shared lib halves alone (`ot6.lua`,
`ot6_field.lua`, `ot6_contract.lua`) is reported as *provenance drift*:
informational, exit 0, the fixture stays a valid snapshot. That is the
separation [the canonical testing policy](../../docs/TESTING.md) asks for;
do not infer a product bug or an obligation to replay the whole route from
staleness alone. A stamp written before ROM identity was recorded has no
`rom` line and is held to the older conservative whole-sig rule (any lib
edit stales it) until its fixture is regenerated; the report counts these.

Run `--adopt-stamps` **before** the first lib edit after a regeneration run
that left legacy stamps: it upgrades each one to the full format in place,
but only when the tree's own records prove what the missing lines would
say, and refuses (saying why, per fixture) otherwise. The proof is: the
stamp's sig still equals the current sig over generator + lib halves (so the
`generator` and `lib` lines are the current hashes); the `.mss` still
matches its `artifact` line; and ninja's build log (`build/ninja/.ninja_log`)
shows the ROM content latch `build/ninja/src/build/ot6.sfc` last ran before
the state's generate edge started while its copy is byte-equal to
`build/ot6.sfc` (the latch is rewritten only on a ROM content change, and
every generate edge depends on it, so the state was generated on the current
ROM). Nothing is invented: a stamp whose sig already moved, whose ROM latch
ran after the generate, whose artifact moved, or which has no ninja record is
left as it is. The original sig line is kept; children bound by `ancestor`
to the parent's old bytes are rebound to its new bytes; every rewrite keeps
the stamp's mtime so ninja sees no generation. Run it with no ninja alive in
the tree, and re-run `--check-states` afterwards.

## The savestate graph

The graph of generated savestates is data: `tools/tests/savestate_graph.py`,
one entry per state. `configure.py` embeds it into `build.ninja` (via
`lib/savestate_ninja.py`). A generated link's scheduling inputs are its
compatibility inputs: the ROM bytes, its generator `gen_*.lua`, and, for a
segment that starts from a saved checkpoint, that checkpoint's manifest and
SRAM payload. Every one is a declared ninja dependency routed through a
content latch edge (`cmp || cp` with `restat = 1`), so staleness is decided
by content: a rebuild that bumps timestamps without moving bytes regenerates
nothing; a changed input re-runs every transitive dependent. Editing one
generator regenerates only the states it feeds; a ROM content change
regenerates the whole chain. The three lib halves `lib/compose.py` inlines
(`ot6.lua`, `ot6_field.lua`, `ot6_contract.lua`) are **not** generate-edge
inputs: editing one re-runs every suite test, audit and selftest that
latches it, and regenerates no fixture (docs/TESTING.md: a change to
logging, assertions, or controller policy does not by itself make a
legitimately reached snapshot illegitimate). `lib/savestate_ninja_selftest.sh`
checks those semantics against real ninja on a mock tree in seconds, with no
emulator.

`lib/savestate_stamp.sh` covers provenance and compatibility: each
generation stamps `build/states/<state>.stamp` with

    sha256(GATE_CONTRACT ++ generator ++ ot6.lua ++ ot6_field.lua ++
           ot6_contract.lua ++ extras) <generator> [extras]
    rom <sha256 of the ROM the run booted>
    generator <sha256(GATE_CONTRACT ++ generator ++ extras)>
    lib <path> <sha256 of that lib half>              (one per half)
    artifact <sha256 of build/states/<state>.mss>
    ancestor <path> <sha256 of that file>

The `rom`, `generator`, `artifact` and `ancestor` lines decide freshness;
the sig and `lib` lines record exactly which harness sources produced the
fixture and are reported as drift when they move. `lib/compose.py`
re-verifies all of it at consume time (the same `stamp_status()` behind
`--check-states`), so the whole chain is verifiable transitively from files
on disk, and the ninja graph and the checker agree on what is stale.
`GATE_CONTRACT` (`ot6-provenance/v1`, one constant in `savestate_stamp.sh`)
is a fixed input to both sigs: bumping it deliberately stales every stamp
in the checker (the graph does not track it; regenerate by hand).

The scenario split is played on **one pinned lineage** — Locke, then Sabin,
then Terra — the way a single player with one cartridge plays it: scenario
choice is order, not branching.  Each scenario's generators run exactly once;
Sabin's opener boots `locke_done`, Terra's boots `sabin_done`, and Terra's
closer (`gen_terra_done`), booted with all three completions carried in,
rides the reunion cutscene and generates `reunion_ready` directly.  A
generator that emits several states along one run declares them with
`also=[...]` in the graph: one edge, one play-through, all its artifacts
(`compose.py`'s `OT6_STACK` prefix machinery survives for experiments that
replay a route from a foreign boot, but the graph no longer uses it).

## run.sh

```sh
Mesen --testrunner --timeout=$OT6_TIMEOUT --enableStdout build/ot6.sfc <composed.lua>
```

run.sh captures all output to a log (second arg; default
`build/states/last_run.log`), decodes `[b64:...]` artifacts, and exits:

| exit | meaning                                    |
|------|--------------------------------------------|
| 0    | pass                                       |
| 1    | assertion failure / Lua error              |
| 2    | global frame budget exceeded (see `H.run`) |

### Parallel runs

Every `run.sh` invocation creates a unique directory under
`build/test-runs/`; `OT6_WORKER=<id>` is only a readable label, never an
isolation key. Mesen's config home, saves, composed script, working log,
and decoded artifacts live in that directory; completed logs and artifacts
are atomically published under `build/states/` (`OT6_ARTIFACT_DIR`
overrides). Failed workspaces are retained and reported; `OT6_KEEP_RUNS=1`
retains successful ones.

No worker owns a copy of the emulator. Every worker execs one shared
read-only bundle at `~/Library/Caches/ot6/Mesen-test.app`, cloned from
`tools/Mesen.app` once per machine with its `settings.json` stripped, and
each gets its own `CFFIXED_USER_HOME`, so nothing is written inside the app.
Two properties this depends on:

* A `settings.json` beside the binary puts Mesen in portable mode with one
  shared `SaveDataFolder` for every worker to race on; the shared copy must
  never grow one. (`tools/Mesen.app` itself has one — the manual-play
  profile — which is why the copy exists.)
* Mesen is ad-hoc signed, not notarized, so every new bundle path costs a
  multi-second Gatekeeper scan of all 413MB; one stable machine-wide path
  avoids it.

## Writing a test

**The testing rule** is [docs/TESTING.md](../../docs/TESTING.md). The
harness enforces its selective-edit half mechanically:
`tools/check_state_writes.py` checks write tokens against
`tools/state_write_waivers.txt` (a registry of declared mechanism-test
uses), `check_playthrough_honest.py` checks story generators, and for a
script with no waivers `lib/compose.py` arms a runtime write gate on the
raw `emu` write surface. The library's snapshot helpers are not writes.

A test is a list of steps handed to `H.run`:

```lua
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 60000 }, {              -- frame budget failsafe -> exit 2
  H.waitFrames(60),
  H.pressButtons({ "start" }, 8),           -- hold 8 frames, release
  H.hold({ "up" }), H.waitFrames(20), H.release(),
  H.waitUntil(function() return H.battleLoadStarted() end, 5000, "battle"),
  H.call(function()
    H.assertEq(H.readByte(0x7E3E44), 2, "guard shields")
    H.screenshot("my_tag")                  -- -> build/states/shots/my_tag.png
    H.saveState("my_state.mss")             -- -> build/states/my_state.mss
  end),
})
```

`H.log()` goes to stdout (`[ot6]` prefix); plain `print()` also works.

Reference savestates relative to the tree, as
`H.loadState("build/states/x.mss.lua")`, never by absolute path: compose.py
resolves every reference against the running tree's own `build/states/` and
refuses one that resolves only outside the tree.

**Registering it.** A test opts into the suite with a first-line marker in
its own file: `-- @suite` (plain), `-- @suite slow` (a long-runner), or
`-- @suite savestate=<fixture>` (asserts on a generated story fixture).
`configure.py` turns each marker into a `build/results/suite/<test>.ok`
edge whose dependencies include the fixture and its chain. Hand-run
instruments are marked `-- @manual`; `gen_`/`probe`/`shot_` files carry
their status in the name.

### Library reference (abridged)

Step constructors:

- `H.run(opts, steps)` — runner + frame budget (`opts.maxFrames`, default 60000).
- `H.waitFrames(n)`; `H.waitUntil(pred, maxFrames, what [, pollEvery])`
  (raises on timeout); `H.waitUntilSoft(...)` (records in `H.vars` instead).
- `H.pressButtons(buttons, frames)`, `H.hold(buttons)`, `H.release()`.
  Buttons: `a b x y l r start select up down left right`.
- `H.call(fn)`, `H.logStep(msgOrFn)`, `H.repeatN(n, steps)`,
  `H.driveUntil(pred, maxFrames, steps, what)`, `H.cond(pred, then, else)`.

Plain functions:

- `H.readByte/readWord(addr)` — WRAM; `H.writeByte/writeWord`,
  `H.readRomByte/readRomWord` (PRG ROM file offsets).
- `H.assertEq(got, want, what)` — logs and raises on mismatch.
- `H.sym("Name")` — the ca65 symbol's 24-bit SNES CPU address, derived from
  `ff6/rom/ff6-en.dbg` at compose time (string literals only). Mask
  `& 0x3FFFFF` for a file offset. A name the linker emits more than once is
  a compose-time error; qualify with the ca65 segment:
  `H.sym("ExecCmd@battle_code")`. Segment names come from
  `ff6/cfg/ff6-en.cfg`.
- `H.saveState(name)` / `H.loadState(sidecarPath)`.
- `H.screenshot(tag)` — emits PNG via stdout; run.sh writes the file.
- `H.setPad(buttons)` — immediate raw input set.
- Battle signals: `H.monsterIds()`, `H.monstersPresent()`, `H.partyHp()`,
  `H.battleLoadStarted()`, `H.battleActive()`, `H.screenLooksAlive()`.
  The six words at $3F46 are a liveness heuristic, not clean IDs; treat
  `monstersPresent() > 0` as "battle has occupants", nothing finer. To
  identify a specific fight, match formation species words at $57C0 via
  `H.formationHas`, conditioned on `battleLoadStarted()`.
- Field navigation (`H.fieldX/Y`, `H.hasControl`, `H.tileAligned`,
  `H.dialogWaiting`, `H.canStep`, `H.movePress`, `H.bfsPath`, `H.navTo`,
  `H.clearBattle`): see `docs/playing-headless.md`.
- World-map navigation (`H.worldMode`, `H.worldId`, `H.worldX/Y`,
  `H.worldAligned`, `H.worldPassable/worldCanStep`, `H.worldBfs`,
  `H.worldHasControl`, `H.worldNavTo`, `H.route`): see
  `docs/research/world-map-nav.md`.
- `H.phaseWalk(tx, ty, spec)` — crosses a timed-tilemap room by planning
  over (x,y,phase) nodes; `H.chaseTalk(objIdx, maxFrames, what)` — talk to
  a wandering NPC. Both documented at their definitions in
  `lib/ot6_field.lua`.

## Mesen 2.1.1 Lua API facts (verified on this binary)

- Runner: `Mesen --testrunner <rom> <script.lua>`; process exit code is the
  integer passed to `emu.stop(code)`.
- Lua 5.4. `print()` -> stdout. `emu.log()` -> the script log, which no
  headless process reads. `io`/`os` are nil and `dofile()`/`loadfile()`
  raise unless `Debug.ScriptWindow.AllowIoOsAccess` is enabled; the harness
  leaves it off and composes scripts flat.
- Memory: `emu.read(addr, emu.memType.X)`, `emu.readWord`, `emu.write*`.
  Useful memTypes: `snesWorkRam`, `snesPrgRom`, `snesMemory` (CPU bus),
  `snesDebug` (bus, side-effect-free).
- Events: `emu.addEventCallback(fn, emu.eventType.startFrame)`; also `nmi
  irq endFrame reset scriptEnded inputPolled stateLoaded stateSaved`.
- Memory callbacks: `emu.addMemoryCallback(fn,
  emu.callbackType.read|write|exec, startAddr [, endAddr] ...)`. Exec
  callbacks use CPU-bus addresses (bank C1/C2/F0 all fire); PRG-file-offset
  forms do not. Callbacks survive `emu.loadSavestate()`.
- Input: `emu.setInput(input, port)` inside an `inputPolled` callback,
  re-pushed every poll. The game polls once per frame; 4+ frame holds are
  reliably seen. Dialog advancing is edge-triggered (4 on / 4 off).
- Savestates: `emu.createSavestate()`/`emu.loadSavestate(blob)` may only be
  called inside an exec memory callback for the main CPU; the lib wraps
  them in a one-shot trampoline (`H.requestSaveState`/`H.requestLoadState`).
- Screenshots: `emu.takeScreenshot()` works headless, returns a 256x224 RGB
  PNG string; empty during the first ~100 frames.
- `emu.getState()` returns a flat dotted-key table: `s["ppu.scanline"]`,
  `s["cpu.pc"]`; `s.ppu` is nil, and indexing it inside a callback throws
  silently, skipping the rest of that invocation.
- Reading $2137/$213D via `emu.read` does not trigger the H/V latch; sample
  `getState()["ppu.scanline"]` from Lua.

### Getting binary data out

Scripts cannot write files. The harness base64-encodes blobs to stdout as
`[b64:<tag>] <chunk>` lines (`H.emitBlob`); run.sh reassembles them:
`*.mss` tags -> `build/states/<tag>` plus a `<tag>.lua` sidecar; anything
else -> `build/states/shots/<tag>`.

## Determinism (by construction)

Runs are bit-reproducible: identical scripts pass at identical frames with
byte-identical artifacts, serial or parallel. The pins:

- `pin_test_saves.py`: `Snes.RamPowerOnState = "AllZeros"` (FF6 reads
  uninitialized RAM), `Snes.DisableFrameSkipping = true`,
  `Snes.Port1.Type = SnesController`, `Debug.ScriptWindow.ScriptTimeout = 30`.
- `run.sh` wipes `<saves>/*.srm` before every launch; tests that need a
  save inject it (SRM sidecars).

Battery SRAM (the OT6 codex banks $30/$31 included) rides along in Mesen
savestates, so post-load SRAM is a pure function of the fixture's bytes.
Scripts key off RAM signals rather than absolute frame numbers.

## The segment runner: retries, watchdogs, seed sweeps (#178)

Runs are bit-reproducible, so a purely additive route change upstream
(buying more Potions, one more grind lap) reshuffles every later
encounter, NPC walk and back-attack roll; a segment that passed on its one
seed then turns that edit into a red build (#179, #185). `H.run` therefore
runs every script through the **segment runner** at the bottom of
`lib/ot6.lua`:

- **Retry from the boot snapshot.** compose.py wraps everything after the
  `local H = dofile(...)` line in `H.segmentBody(function() ... end)`. The
  runner snapshots the machine on the body's first frame (after a
  fixture load, when the body starts with one) and, on a **seed-dependent**
  failure -- a wipe (the canary), a `navTo`/`worldNavTo` "no path", a step
  timeout, or a watchdog trip -- restores it, re-executes the body from
  source (fresh locals, fresh step objects; the previous attempt's emu
  callbacks go inert through an epoch guard), and replays with the seed
  moved by idle frames at the **boot point** (`H.bootMark`: the fixture
  load, or `assertEntryContract` after a cold Continue). Default 3
  attempts for a `gen_*` script, 1 for everything else; `opts.retries`
  per script, `OT6_RETRIES=<n>` in the environment overrides both. A
  contract failure (`assertEq`, a checkpoint contract, a Lua error) is a
  bug and fails at once. Generators with their own ladders keep them: a
  ladder runs with `allowGameOver`, so its wipes never reach the canary,
  and its exhaustion message classifies as `other`.
- **The count.** Every failed attempt logs
  `[retry] attempt n/N FAILED class=<c> frame=... shift=... phase=... screenshot=<png>: <message>`
  (plus a `wipe context:` line naming the formation and every seat's
  HP/BP), the verdict is `PASS (frame F) attempts=n/N`, and
  `python3 tools/audit_retries.py [logs|dirs]` lists every log that spent
  more than one attempt, by class, so each class becomes an issue. A
  retried pass is a pass with its count; it is not a first-try claim.
- **Watchdogs (look at the screen).** Every 16 frames the runner samples a
  hash of the frame buffer, the control cells (map/position/menu/dialog on
  the field; menu byte, menu state, target masks and cursors in a battle),
  the progress cells (those plus monster HP, party HP and the inventory)
  and the held pad, and keeps a ring of 24. `no-effect`: the pad has been
  down 25% of the last 192 frames (~3 s) at an open control and no control
  cell has read anything new (#185's LEFT into a back-attack target cursor
  trips here in seconds instead of after the 9000-frame budget).
  `no-progress`: neither a progress cell nor the screen has shown anything
  new for 1800 frames (~30 s). Both fail fast with a screenshot named in
  the FAIL line and the ring dumped to the log, and both are seed-dependent
  classes, so they are retried. `H.waitFrames(n >= 240)` stands the
  watchdogs down for its own length; a cutscene step can call
  `H.watchQuiet(frames, why)`. Every run ends with a
  `[watch] ... max quiet: ctl=.. prog=.. screen=..` line, which is how the
  thresholds are measured rather than guessed. Enabled by default for
  `gen_*` scripts, observation-only elsewhere; `opts.watchdog` and
  `OT6_WATCHDOG=1/0` override. `H.recoveryCount(tag, key)` is the
  recovery cap for a driver that drops its plan and backs out: past 3
  drops of the same plan in one battle it fails fast the same way (not yet
  wired into the fight driver; see the note at its definition).
- **Seed sweep.** `python3 tools/tests/seed_sweep.py <state> --seeds K
  [--jobs N]` regenerates one state K times with K different boot seeds
  (`OT6_SEED_SHIFT`, spread over the 60-frame seed period), retries off,
  into `build/sweeps/<state>-<stamp>/` (nothing is published to
  `build/states`), and prints a per-seed table: verdict, frames, failure
  class and message. This is how a segment's brittleness is found before
  a route change exposes it.

`tools/tests/segment_retry.lua` (suite) proves the replay: a `nopath`
raised on attempt 1 passes on attempt 2 with rebuilt locals and steps;
`probe_retry_negative.lua` (manual) shows an assert failing on attempt 1
of 3 with no replay.

## Failure signatures

- A 255 exit with truncated stdout is a wall-clock cap expiry, not a
  mystery crash (testrunner default 100s; run.sh passes
  `--timeout=${OT6_TIMEOUT:-600}`). Any error at script load has the same
  signature: no callbacks register, the emulator free-runs, the cap kills
  it.
- Script errors are invisible headless: `--enableStdout` mirrors the
  emulator message log, not the script log. `print()` is the only channel
  out of a script; a test that goes quiet has told you nothing.
- stdout carries `[CPU] Uninitialized memory read` debug spam from the
  testrunner's force-enabled debugger; filter for `[ot6]`.
- Do not delete `~/Library/Application Support/Mesen2/settings.json`:
  run.sh feeds it to `pin_test_saves.py` as the base config and aborts
  (exit 2) if it cannot be read.

## Recovery action trace

For a diagnostic run, set `OT6_ACTION_TRACE=1` when composing/running a script,
or pass `actionTrace=true` to `H.newFightDriver`. Tracing is off by default;
it adds read-only CPU observers and does not change tactical policy or pad
timing. An already-composed script must be recomposed to change the flag.

Example: replay the existing Ifrit/Shiva route from its tracked battery save
(no long upstream regeneration):

```sh
OT6_ACTION_TRACE=1 OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/mrf-save-room-v1 \
  tools/tests/run.sh tools/tests/gen_ifrit_magicite.lua build/states/ifrit-actions.log
python3 tools/action_trace.py build/states/ifrit-actions.log
python3 tools/action_trace.py --json build/states/ifrit-actions.log
```

The run log carries one canonical `[ot6action] {JSON}` line per event; the
existing live viewer displays these as short action notes. Each recovery plan
has a run-unique ID and records its actor **battle slot** (0–3), requested
spell/item ID, target slot, intended boost, all-target intent, and reason.
Every plan the driver turns into a command is traced (`heal`, `item`,
`fight`, `magic`, `skill`, `summon`, `throw`, `lore`; the first version traced
only `heal`/`item`); `requested` is the spell/item/skill/lore id, 0 for a
Fight or a summon.

- `plan`: the policy chose recovery.
- `confirm`: the controller intends a target-confirm press. Repeated attempts
  are separate events, not separate actions. Backstop presses after the driver
  clears its plan are not counted here.
- `submit`: the engine consumed the pending user command, observed at
  `GetPlayerTargets`. Raw command/attack and target mask are preserved.
- `start`: normal command dispatch at `ExecCmd`, with the actual attack ID
  after spell folding. Queue latency is separate from menu navigation time.
- `resolve`: the normal command returned from execution, observed at
  `SaveForMimic`. A miss, intercepted spell, or zero-effect action can resolve.
- `drop`: a plan was abandoned before any observed submission, with its reason
  and elapsed frames. `new_plan` can mean speculative replanning during a
  menu handoff; it does not by itself establish lost combat time.
- `unresolved`: a submitted/started action lacked a matching completion before
  battle end, driver replacement, state reload, or run end. An abruptly cut
  log is reported as incomplete by the summary instead.
- `death`: a party member's HP reached 0 (#175), outside any plan's
  lifecycle: the entity, the HP the killing action found them at, the pips
  they held (`bp`) and the party's (`party_bp`), and the killer's slot,
  command and attack bytes. The summary lists these; they carry no plan id.

Whether or not the trace is on, the driver logs the same record as a
`[death]` line and one `[wipe]` line per battle with the party's pips and a
classification ("one-shot early" / "died with N BP banked");
`tools/audit_boost.py` (also run by `audit_fenix.py`) tabulates them over
run logs.

The driver also logs one `[layout]` line per battle once the command window
is up: the type of battle the engine set (`$201F`: normal / back attack /
pincer / side attack) and the target group (`$7ACE`), with the directions
the target cursor crosses by -- every steer press is derived from that
reading (`H.battleLayout`), not from a fixed side.  A steer press that
moves none of the target window's cells twice is not pressed again, and
when no derived direction moves the cursor, or one menu state has parked
and dropped three plans in a battle, the driver raises `FIGHT DRIVER
STUCK: ...` (with a `fightdriver_stuck` screenshot) instead of re-planning
until the party dies.

Submission and completion are engine evidence, not inferred from a disappearing
menu or rising HP. Accepted recovery commands remain queued independently of
new speculative plans for the same actor. Matching is by actor and command,
FIFO among traced accepted commands; exotic cancellation/replacement or
non-normal dispatch paths need further instrumentation before drawing balance
conclusions. Retaliations are not independently traced.

`hp_net` is the four party slots' **net HP change across execution**, not an
attributed healing amount: caps, interception, damage, and counter-effects can
all matter. MP/BP deltas cover the same interval; costs paid earlier at queue
time are outside that interval. Requested and executed IDs/targets are both
retained so folding or target fallback is visible. Frame totals describe each
plan's lifetime and may overlap other actors/animations; do not sum them into
"seconds of battle wasted."

A run with missing outcomes or repeated execution failures is diagnostic
material, not clean balance evidence. A log with no plans proves nothing about
execution reliability. The summary consumes **one run log**, not concatenated
runs with colliding IDs.

Fast ledger/parser checks (the standalone ledger check needs Lua 5.4 or newer):

```sh
lua tools/tests/recovery_trace_selftest.lua
python3 tools/action_trace.py --selftest
```
