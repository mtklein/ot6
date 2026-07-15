# OT6 test harness (Mesen 2 headless testrunner)

Automated, GUI-free tests that boot `build/ot6.sfc`, drive the game with
scripted input, assert on RAM, and capture screenshots/savestates.

## Quick start

```sh
make rom                                        # build build/ot6.sfc
tools/tests/run.sh tools/tests/gen_battle_state.lua   # power-on -> first battle -> savestate
tools/tests/run.sh tools/tests/battle_smoke.lua       # load savestate -> assert battle state
```

`run.sh` wraps:

```sh
tools/Mesen.app/Contents/MacOS/Mesen --testrunner build/ot6.sfc <script.lua>
```

captures all output to `build/states/last_run.log` (second arg overrides),
decodes any `[b64:...]` artifacts the script emitted (see below), prints the
`[ot6]` log lines, and exits with the script's `emu.stop()` code:

| exit | meaning                                    |
|------|--------------------------------------------|
| 0    | pass                                       |
| 1    | assertion failure / Lua error              |
| 2    | global frame budget exceeded (see `H.run`) |

Scripts built on the library always terminate on their own; no external
watchdog needed.  A bare hang would only happen if a script bypasses
`H.run()`'s frame budget.

## Files

- `lib/ot6.lua` - harness library (see header comment for full API).
- `lib/decode_b64.py` - decodes `[b64:tag]` stdout payloads into files.
- `gen_battle_state.lua` - title screen -> New Game -> intro -> Narshe ->
  walk into the first guard battle; emits `build/states/battle_doorstep.mss`
  (field, ~5 s before the trigger) and `build/states/first_battle.mss`
  (in battle) plus progress screenshots.
- `battle_smoke.lua` - loads `first_battle.mss` and asserts battle liveness,
  logging monster IDs and party HP.
- `smoke.lua` - original ROM-content smoke test (OCTO name bytes).
- `battle_entry.lua` - FAST battle-entry regression test: loads
  `battle_doorstep.mss` and walks into the first battle (~30 s wall clock).
  This is the tight iteration loop for battle/break-system changes.
- `probe12.lua` - diagnostic: is expanded bank $F0 mapped? (bus vs file bytes)
- `probe16.lua` - diagnostic: savestate save/clobber/load round-trip.
- `probe17.lua` - harness self-test: 18k-frame runner+input longevity.

Generated artifacts land in `build/states/` (savestates, `*.mss` +
`*.mss.lua` sidecar) and `build/states/shots/` (PNG screenshots).
The `.mss` files load fine in the Mesen GUI too.

## Writing a test

A test is a LIST OF STEPS handed to `H.run`; a `startFrame` callback consumes
them, one frame at a time (zero-frame steps like `H.call` chain within a
frame).  **Do not use Lua coroutines** -- they crash this Mesen build (see
WORKING NOTES); the step style below is the stable pattern.

```lua
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

H.run({ maxFrames = 60000 }, {              -- frame budget failsafe -> exit 2
  H.waitFrames(60),
  H.pressButtons({ "start" }, 8),           -- hold 8 frames, release
  H.hold({ "up" }), H.waitFrames(20), H.release(),
  H.waitUntil(function() return H.battleLoadStarted() end, 5000, "battle"),
  H.call(function()
    H.assertEq(H.readByte(0x7E3ECB), 0xBA, "break glyph")
    H.screenshot("my_tag")                  -- -> build/states/shots/my_tag.png
    H.saveState("my_state.mss")             -- -> build/states/my_state.mss
  end),
})
```

`H.log()` goes to stdout (`[ot6]` prefix); plain `print()` also works.

### Library reference (abridged)

Step constructors (compose the script):

- `H.run(opts, steps)` - runner + frame budget (`opts.maxFrames`, default 60000).
- `H.waitFrames(n)`; `H.waitUntil(pred, maxFrames, what [, pollEvery])`
  (raises on timeout -> exit 1); `H.waitUntilSoft(pred, maxFrames, name
  [, pollEvery])` (records true/false in `H.vars[name]` instead of raising).
- `H.pressButtons(buttons, frames)`, `H.hold(buttons)`, `H.release()`.
  Buttons: `a b x y l r start select up down left right`.
- `H.call(fn)` - run arbitrary code (asserts, screenshots, saves) in-frame.
- `H.logStep(msgOrFn)`, `H.repeatN(n, steps)`,
  `H.driveUntil(pred, maxFrames, steps, what)` (loop steps until pred),
  `H.cond(pred, thenSteps, elseSteps)`.

Plain functions (call from `H.call`/predicates):

- `H.readByte/readWord(addr)` - WRAM; accepts `$7E`-prefixed or plain offsets.
  `H.writeByte/writeWord`, `H.readRomByte/readRomWord` (PRG ROM file offsets).
- `H.assertEq(got, want, what)` - logs and raises on mismatch (exit 1).
- `H.saveState(name)` / `H.loadState(sidecarPath)` - see savestate notes.
- `H.screenshot(tag)` - emits PNG via stdout; run.sh writes the file.
- `H.setPad(buttons)` - immediate raw input set (steps use this internally).
- FF6 battle signals: `H.monsterIds()`, `H.monstersPresent()`, `H.partyHp()`,
  `H.battleLoadStarted()` (HP table at $3BF4 populated),
  `H.battleActive()` (load started + monsters present + screen actually
  rendering, judged by screenshot PNG size), `H.screenLooksAlive()`,
  constants `H.MONSTER_IDS=$3F46`, `H.BATTLE_HP=$3BF4`, `H.BREAK_GLYPH=$3ECB`.
  (Note: monster ID 0 = "Guard" is valid; empty slots read $FFFF.)

## Mesen 2.1.1 Lua API facts (all verified empirically on this binary)

- Runner: `Mesen --testrunner <rom> <script.lua>`; process exit code is the
  integer passed to `emu.stop(code)`.
- **Lua 5.4** with `io` and `os` REMOVED (nil).  `print()` -> stdout.
  `emu.log()` -> GUI log window only (invisible headless).  `dofile()` /
  `loadfile()` / `load()` work, which is how binary blobs get back in.
- Memory: `emu.read(addr, emu.memType.X)`, `emu.readWord`, `emu.read16/32`,
  `emu.write*`.  Useful memTypes: `snesWorkRam` (128 KiB WRAM, offset-based),
  `snesPrgRom` (ROM file), `snesMemory` (CPU bus), `snesDebug` (bus,
  side-effect-free).  `emu.getMemorySize(memType)`.
- Events: `emu.addEventCallback(fn, emu.eventType.startFrame)`; eventTypes:
  `nmi irq startFrame endFrame reset scriptEnded inputPolled stateLoaded
  stateSaved codeBreak`.
- Memory callbacks: `emu.addMemoryCallback(fn, emu.callbackType.read|write|exec,
  startAddr [, endAddr] [, cpuType] [, memType])`; a read callback returning a
  value replaces the value the CPU sees.
- Input: `emu.setInput(buttonTable, port [, subport])` and `emu.getInput(port)`
  exist **but are useless headless**: with the default `settings.json` (`{}`)
  no controller device is attached to any port (0-4), `getInput` returns `{}`
  and `setInput` is a silent no-op.  The harness instead intercepts CPU reads
  of the SNES auto-joypad registers `$4218/$4219` with a read memory callback
  and substitutes button bits (`$4219` = B Y Sel St U D L R, `$4218` = A X L R
  0000) while a press is scripted.  This drives title/menus/field/dialogs
  reliably.
- Savestates: `emu.createSavestate()` returns the state as a binary string;
  `emu.loadSavestate(blob)` takes one back.  (`saveSavestateAsync`-style slot
  functions from Mesen 1 do not exist in this build.)
- Screenshots: `emu.takeScreenshot()` **works headless** and returns a
  256x224 RGB PNG as a string; it returns an *empty string* during the first
  ~100 frames (before the first decoded frame).
- `emu.getState()` returns a huge table (cpu.*, ppu.*, spc.*,
  internalRegisters.*, frameCount...).  Handy: `cpu.k/cpu.pc` (crash triage),
  `ppu.screenBrightness`, `internalRegisters.enableNmi`.
- `emu.getScriptDataFolder()` returns `true` (not a path) in this build -
  don't rely on it.

### Getting binary data out (no io library!)

Scripts cannot write files.  The harness base64-encodes blobs to stdout as
`[b64:<tag>] <chunk>` lines (`H.emitBlob`); `run.sh` runs
`lib/decode_b64.py` afterwards to reassemble them:

- `*.mss` tags -> `build/states/<tag>` **plus** `<tag>.lua` sidecar
  (`return "<base64>"`) so a later test can `dofile` the state back in and
  `emu.loadSavestate` it - that is how `battle_smoke.lua` loads the battle.
- anything else -> `build/states/shots/<tag>` (screenshot PNGs).

## WORKING NOTES

### Screenshots headless: YES (key question answered)

`emu.takeScreenshot()` produces valid PNGs under `--testrunner` with no
window/GUI, suitable for visual verification of upcoming UI work.  Proof:
this harness screenshotted the whole intro (title logo, "1000 years have
passed..." narration, Magitek snow walk, Narshe gate) pixel-perfect.
Empty-string result only occurs in the first ~2 s before the video decoder
has a frame.  `emu.getScreenBuffer()` also exists (table of RGB ints) if raw
pixels are ever needed.

### Savestate determinism

- Battle-trigger frame varied by +-2 frames across identical runs
  (16508/16510) - Mesen's default power-on RAM randomization feeds FF6's RNG.
  Therefore scripts key off RAM *signals*, never absolute frame numbers
  (except the wide, forgiving title-screen window).
- The intro is otherwise stable: identical input scripts produced the same
  scene sequence on every run observed.
- `emu.createSavestate()/loadSavestate()` round-trip works from Lua when
  called inside a frame callback (the runner's coroutine qualifies).

### Input injection quirks

- `$4218/$4219` interception is only active while a press is scripted
  (pass-through otherwise), and injected values look exactly like a real
  idle/held standard pad (signature bits 0).
- The game polls once per frame via NMI auto-joypad; 4+ frame holds are
  reliably seen, 8 used for title Start presses.
- FF3us auto-plays its opening from the title screen even with no input;
  pressing Start during the logo also works.  With garbage/absent SRAM the
  save-select is skipped entirely on this path.

### Route timing (measured, 60 fps emulated)

- frame ~300-500: title logo (Start pressed here)
- ~500-15500: opening narration, credits, Magitek snow walk (automatic)
- ~15500: Narshe cliff dialogs (mash A), then player control at the gate
- ~16500: first scripted guard battle triggers (walk north + mash A)
- Wall-clock: the testrunner runs uncapped; a 26k-frame run took ~2-3 min.

### Mesen quirks discovered

- The testrunner only works if `~/Library/Application Support/Mesen2/settings.json`
  exists (even `{}`).  Do not delete it.
- stdout also carries `[CPU] Uninitialized memory read: ...` debug spam from
  FF6's habit of reading uninitialized RAM; filter for `[ot6]` / `[probe]`.
- **Lua coroutines crash this build.**  A coroutine-based runner (script body
  resumed once per frame) died with process exit 255 and truncated stdout on
  4 of 4 long runs -- even with a body of pure-Lua waits and prints.  The
  same work as a callback-driven step machine is stable.  Root cause not
  confirmed (likely Mesen's per-callback instruction-watchdog `lua_sethook`
  interacting with coroutine threads); just avoid coroutines entirely.
- Other intermittent 255s were seen in scripts that polled `emu.getState()`
  every frame or ran with no memory callback registered; the library keeps
  the `$4218/19` read callback always-on and avoids `getState()` in polling
  loops (screenshot size stands in for "is the screen rendering").
  `getState()` is fine for one-shot debugging.  A 255 exit with stdout ending
  mid-boot-spam means the crash happened later but unflushed output was lost
  (stdout is block-buffered); rerun the command.
- `emu.stop()` from the initial script body works; from callbacks it works
  too (used everywhere here).
- No `timeout` command on macOS; not needed since `H.run` guarantees exit,
  but `( cmd & pid=$!; (sleep N; kill $pid) & wait $pid )` is the fallback
  pattern if a script without the library must be watchdogged.

### KNOWN ISSUE CAUGHT BY THIS HARNESS (2026-07-15)

On the current break-system ROM (`build/ot6.sfc`, 4 MiB, `ot6_code` segment
at $F0:0000), entering the first battle **crashes the game**: the battle
module starts loading (party battle-HP at $7E3BF4 fills in, $7E3ECB gets a
digit glyph $BA), then the screen stays black forever; `emu.getState()`
shows NMI + auto-joypad-read disabled, `cpu.k/pc` pointing into RAM and SP
into ROM space - i.e. crashed, not slow.  Bank $F0 *is* correctly mapped
(bus reads at $F0:0000 match ROM file offset 0x300000), so it is a code bug,
not a mapping/expansion problem.  `gen_battle_state.lua` therefore currently
exits 1 after emitting `battle_doorstep.mss`; once the crash is fixed, rerun
it to mint `first_battle.mss`, then `battle_smoke.lua` guards the regression.
