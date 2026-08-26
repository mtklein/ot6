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
```

Run `--check-states` first when a test is red and you did not expect it: a
savestate generated from sources this tree no longer has boots into a ROM
whose timing it does not match, and the result reads like a product bug. It
answers in ~2s, names the shared input that moved, and gives the command to
regenerate just that state.

## The savestate graph

The graph of generated savestates is data: `tools/tests/savestate_graph.py`,
one entry per state. `configure.py` embeds it into `build.ninja` (via
`lib/savestate_ninja.py`). A generated link is a function of the ROM bytes,
its generator `gen_*.lua`, the three lib halves `lib/compose.py` inlines
(`ot6.lua`, `ot6_field.lua`, `ot6_contract.lua`), and, for a segment that
starts from a saved checkpoint, that checkpoint's manifest and SRAM payload.
Every one is a declared ninja dependency routed through a content latch edge
(`cmp || cp` with `restat = 1`), so staleness is decided by content: a
rebuild that bumps timestamps without moving bytes regenerates nothing; a
changed input re-runs every transitive dependent. Editing one generator
regenerates only the states it feeds; editing a lib half regenerates the
whole chain. `lib/savestate_ninja_selftest.sh` checks those semantics
against real ninja on a mock tree in seconds, with no emulator.

`lib/savestate_stamp.sh` covers provenance: each generation stamps
`build/states/<state>.stamp` with

    sha256(GATE_CONTRACT ++ generator ++ ot6.lua ++ ot6_field.lua ++
           ot6_contract.lua ++ extras) <generator> [extras]
    artifact <sha256 of build/states/<state>.mss>
    ancestor <path> <sha256 of that file>

`lib/compose.py` re-verifies all of it at consume time, so the whole chain
is verifiable transitively from files on disk. `GATE_CONTRACT`
(`ot6-provenance/v1`, one constant in `savestate_stamp.sh`) is a fixed sig
input: bumping it deliberately stales every stamp.

The **scenario stack** turns the three opening chains (Locke, Terra, Sabin)
into one lineage: `OT6_STACK=<prefix>` makes `compose.py` rewrite every
`.mss` basename in the script (never in the lib), so the same generator
boots a prefixed predecessor and emits prefixed artifacts. The graph seeds
each stacked hub from the previous chain's ending (`seed=` entries) and
stacks the `t2_`/`s2_`/`t3_` layers up to `reunion_ready`. Details:
`savestate_graph.py`'s SCENARIO STACKING section and `compose.py`'s
docstring.

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

**The input-driven rule.** A test or generator may inject controller input
and read emulated memory. It may never write emulated game state: no HP/MP
pins, no forced kills, no boss clamps, no cursor pokes, no event-flag or
RNG writes. Determinism comes from fixed input-driven fixtures plus
frame-exact input. The property is transitive: a fixture generated by a
poking script is contaminated, and so is everything derived from it.

Enforced twice: `tools/check_state_writes.py` fails the build on any write
token not in `tools/state_write_waivers.txt` (a burn-down list that only
shrinks), and for a file with no waivers `lib/compose.py` arms a runtime
write gate — the global `emu` becomes a proxy whose write surface raises at
the call. The one sanctioned exception is quarantined mechanism tests
(fault injection the game can only produce rarely or never on cue); they
keep their waivers, say so in their header, and may never produce fixtures.

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
