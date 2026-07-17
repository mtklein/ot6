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
Mesen --testrunner --timeout=600 --enableStdout build/ot6.sfc <composed.lua>
```

(`--timeout=600` overrides the testrunner's default 100-second wall-clock
cap — expiry exits 255 with truncated stdout; `--enableStdout` mirrors the
otherwise-invisible script-window log, where Lua watchdog errors land),
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

### Parallel runs

`run.sh` honors `OT6_WORKER=<id>`: the portable emulator copy, saves dir,
composed file, default log, and artifact dir all move under
`build/test-workers/w<id>/`, so runs with distinct ids (and the default
id-less run) are safe concurrently -- the emulator writes into its profile
on exit, so concurrent instances must never share an app copy.  `suite.sh`
honors `OT6_JOBS=N` (default 4 = the P-core knee; 1 = serial) and fans its
tests out across workers; every suite test is a pure savestate load (the
mints run as Makefile prerequisites first), so order doesn't matter.
Suite logs stay at `build/states/suite_<t>.log` either way, and each test
line reports its worker and wall time.

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
  `battle_doorstep.mss` and walks into the first battle (~30 s wall clock,
  PASS/FAIL on whether the battle engine actually comes up).  This is the
  tight iteration loop for battle/break-system changes.
- `battle_firebeam.lua` - full interaction test: doorstep -> fresh battle ->
  A/A/A drives MagiTek Fire Beam onto a guard; asserts each press visibly
  changes the screen and the action resolves (guard HP drops).  Logs break
  RAM (guard shields $3E44/$3E46, HP $3C00/$3C02, revealed masks
  $3E95/$3E97) and screenshots before/during/after.  (The monster-window
  shield digit is retired -- the under-enemy HUD is the shield display.)
- `probe23.lua` - positive control: input injection still works after
  loadSavestate (A opens the MagiTek submenu, B closes it; fails loudly if
  a press has no visible effect).
- `probe16.lua` - diagnostic: savestate save/clobber/load round-trip
  (validates the exec-callback trampoline and the base64 codec).
- `probe19.lua` - diagnostic: doorstep -> battle with screenshots + RAM
  dumps at +0/+60/+180/+420/+900/+1500/+2400 frames.
- `probe22.lua` - diagnostic: resume `first_battle.mss`, press A/A/B to
  poke the battle menus, screenshot each step (for UI iteration).
- `gen_whelk.lua` - boot the injected save and BFS-navigate the Narshe
  mines to the Whelk fight (see `docs/playing-headless.md`); emits
  `build/states/whelk_doorstep.mss` (field, one tile short of the
  trigger) and a `whelk_battle` screenshot.  PASSes at frame 2813 with
  byte-identical artifacts every run, ~8.5 s wall.
- `probe_canstep.lua` - validates `H.canStep` (the CheckPlayerMove
  port) against real movement at the boot area; renders the model's view
  of the neighborhood as ASCII.
- `battle_banner.lua` - TEMPORAL gate for the banner screen-tear: exec
  callbacks at the battle NMI's entry / flush start / flush end / post-
  INIDISP sample `ppu.scanline` on EVERY frame through a Fire Beam cast
  (named banners: vanilla writes its name scratch at $7E57D5) and assert
  the whole NMI tail stays inside vblank (scanline 225..261), plus
  OT6_FONTDIRTY ($57B9) stays clear and the under-monster HUD cells are
  still painted in VRAM afterwards.  Pre-fix this measured the flush
  ending at scanline 292 (30 lines into active display) on banner
  frames -- the user-visible flash/tear.
- `probe_banner.lua` - the measurement instrument behind battle_banner:
  per-frame scanline table (NMI entry / flush start / flush end / post-
  INIDISP) plus $57D5, large-transfer flag/size, and a 44-frame
  screenshot burst across the banner window.
- `probe_57b9.lua` - write-watcher over $7E57B9-BF (OT6_FONTDIRTY's
  relocated home) with $7E57D5 as positive control; logs writer PCs.
- `battle_whelkwipe.lua` - gate for the monster entry/exit wipe: the
  whelk retract cycle (FADE_DOWN/FADE_UP) sweeps the battle-field BG3
  region with a per-scanline scroll wave, so the field map must hold
  nothing but vanilla's tiles while the effect runs.
  Drives the fight passively (Heal Force) to both transitions, trips an
  exec callback on DoMonsterEntryExit (C2/E668), and asserts every
  animation frame at cell level: no OT6-claimed glyph char anywhere in
  the field map, every live hud line veiled to vanilla's $01ee fill
  (OT6_HUDVEIL $57BE is the wrapper's own end marker).  After each
  transition: hud gone with the head, hud repainted on return,
  glyphCanary.  No pixel compares, so it stays mint-independent.
- `probe_whelkwipe.lua` / `probe_whelkwipe2.lua` - the measurement
  instruments behind battle_whelkwipe: frame-by-frame screenshots of
  both transitions plus BG3 field-map/small-font readback diffs
  (probe_whelkwipe) and per-scanline BG3 scroll-table RLE, full map
  dumps, and whole-font-vs-SmallFontGfx compares (probe_whelkwipe2).
  Run either against build/states/base_rom_for_comparison.sfc for the
  vanilla ground truth (sed the TAG local first so shot names differ).

Generated artifacts land in `build/states/` (savestates, `*.mss` +
`*.mss.lua` sidecar) and `build/states/shots/` (PNG screenshots).
The `.mss` files load fine in the Mesen GUI too.  `build/states/` also
holds `base_rom_for_comparison.sfc` (copy of the FF3us base image) --
running any test against it instead of `build/ot6.sfc` gives an instant
"is it our code or the harness?" A/B, and savestates cross-load between
the two images.

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
    H.assertEq(H.readByte(0x7E3E44), 2, "guard shields")
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
  constants `H.MONSTER_IDS=$3F46`, `H.BATTLE_HP=$3BF4`.
  (Caveat: the six words at $3F46 are a liveness heuristic, not clean IDs --
  monster #0 "Guard" is a valid 0x0000, empty slots read $FFFF, and healthy
  vanilla battles still show one stale word there, e.g. 874B, left over
  from earlier RAM traffic.  Treat `monstersPresent() > 0` as "battle has
  occupants", nothing finer.  For identifying a *specific* fight, match the
  formation species words at $57C0 via `H.formationHas`, gated on
  `battleLoadStarted()`.)
- Field navigation (`H.fieldX/Y`, `H.hasControl`, `H.tileAligned`,
  `H.dialogWaiting`, `H.canStep`, `H.bfsPath`, `H.navTo`, `H.clearBattle`):
  see `docs/playing-headless.md` for the RAM tables and the design.

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
- Input: `emu.setInput(input, port)` applied inside an `inputPolled` event
  callback (setInput's effect lasts until the next poll, so pushing the
  held-button table on every poll makes the ROM latch it each frame).  This
  drives title/menus/field/dialogs reliably; `probe_setinput.lua` asserts the
  injected buttons show up in the CPU-visible `$4218/$4219` registers.
- Savestates: `emu.createSavestate()` returns the state as a binary string;
  `emu.loadSavestate(blob)` takes one back.  BUT both may only be called
  "inside an exec memory operation callback for the main CPU" -- calling
  them from an event callback raises that exact error.  The library wraps
  them in a one-shot trampoline (`H.requestSaveState()` /
  `H.requestLoadState(blob)`): register an exec memory callback over
  $000000-$FFFFFF, do the work on its first fire (the next executed
  instruction), remove the callback from within itself, harvest the result
  a frame later.  The step constructors `H.saveState(name)` /
  `H.loadState(sidecar)` package that dance.  (`saveSavestateAsync`-style
  slot functions from Mesen 1 do not exist in this build.)
- Screenshots: `emu.takeScreenshot()` **works headless** and returns a
  256x224 RGB PNG as a string; it returns an *empty string* during the first
  ~100 frames (before the first decoded frame).
- `emu.getState()` returns a huge table (cpu.*, ppu.*, spc.*,
  internalRegisters.*, frameCount...).  Handy: `cpu.k/cpu.pc` (crash triage),
  `ppu.screenBrightness`, `internalRegisters.enableNmi`.
  **The keys are FLAT dotted strings**: `s["ppu.scanline"]`, `s["cpu.pc"]` --
  `s.ppu` is nil, and indexing it "nested" throws (silently, inside a
  callback: the rest of that callback invocation is skipped with no log).
  It works inside exec-memory and event callbacks too; `ppu.scanline`
  (0-261, NMI fires at 225) is how battle_banner samples vblank timing.
- Narrow exec memory callbacks on ROM code use CPU-bus addresses and DO
  fire for bank C1/C2 (`emu.addMemoryCallback(fn, emu.callbackType.exec,
  0xC10BA7, 0xC10BA7)` fires once per battle NMI); they do NOT fire for
  bank F0 code.  PRG-file-offset forms fire never (0x010BA7) or on the
  wrong thing; use the bus form.
- Reading $2137/$213D via `emu.read(..., emu.memType.snesMemory)` does NOT
  trigger the H/V counter latch side effect -- both return 0.  Sample the
  scanline from Lua via `getState()["ppu.scanline"]`; from 65816 code the
  real register latch works fine (the flush's re-lay budget gate does it).
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

### Determinism (by construction)

Test runs are bit-reproducible: identical scripts PASS at identical frames
with byte-identical artifacts (savestates AND screenshots), serial or
parallel.  Three harness pins make it so:

- `pin_test_saves.py` pins `Snes.RamPowerOnState = "AllZeros"`.  FF6 reads
  uninitialized RAM, so Mesen's default `Random` fed the RNG different
  garbage every boot -- battle-trigger frames drifted (+-frames, extra
  encounters) and minted savestates embedded the garbage.
- `pin_test_saves.py` pins `Snes.DisableFrameSkipping = true`.  Frame-skip
  picks rendered frames by HOST timing, so screenshots (and the framebuffer
  inside savestates) varied run-to-run, worse under parallel load.
- `run.sh` wipes `<saves>/*.srm` before every launch.  The testrunner
  flushes battery on exit and reloads it next boot, so a stale srm is a
  hidden cross-run coupling channel; tests that need a save inject it
  explicitly (SRM sidecars).

Scripts still key off RAM *signals* rather than absolute frame numbers --
not because frames drift at runtime anymore, but because every ROM or
route edit shifts them.
- `emu.createSavestate()/loadSavestate()` round-trip works from Lua, but
  ONLY inside an exec memory callback (see the trampoline above);
  `probe16.lua` is the regression test for the mechanism.

### Input injection

- `H.setPad()` records the held-button set; an `inputPolled` event callback
  pushes it into the emulator with `emu.setInput(input, 0)` on every poll.
- The game polls once per frame via NMI auto-joypad; 4+ frame holds are
  reliably seen, 8 used for title Start presses.
- Dialog/menu-text advancing is EDGE-triggered: a held A yields exactly one
  page; multi-page text needs press-release cycling (4 frames on / 4 off).
- `probe23.lua` is the positive control: after loading `first_battle.mss`,
  A must open the MagiTek submenu and B must close it (screenshot bytes
  compared).  `probe_input.lua` proves held input drives movement across a
  long run.
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
- A 255 exit with truncated stdout means a wall-clock cap expired, not a
  mystery crash: the testrunner defaults to 100 seconds (run.sh passes
  `--timeout=600`) and Mesen's per-Lua-slice watchdog defaults to 1 second
  (`pin_test_saves.py` pins `Debug.ScriptWindow.ScriptTimeout = 30`; its
  kills are silent except in the `--enableStdout`-mirrored script log).
  stdout is block-buffered, so output stops well before the actual death.
- Avoid `emu.getState()` in per-frame polling loops (crash-correlated;
  screenshot size stands in for "is the screen rendering").  One-shot use
  for debugging is fine.
- `emu.stop()` from the initial script body works; from callbacks it works
  too (used everywhere here).
- No `timeout` command on macOS; not needed since `H.run` guarantees exit,
  but `( cmd & pid=$!; (sleep N; kill $pid) & wait $pid )` is the fallback
  pattern if a script without the library must be watchdogged.

### BATTLE-ENTRY STATUS (2026-07-15): ALL GREEN

Two regressions were caught on the break-system ROM and both are fixed:

1. Hard crash at battle init (CPU derailed into RAM, NMI disabled): an
   assembler width desync (.i8 immediates in .i16 battle context) in the
   bank-F0 break module.
2. Battle init hang (screen never unblanked past +2400 frames while battle
   RAM partially filled).  Isolated by A/B: the same `battle_doorstep.mss`
   + identical scripted walk rendered the battle at ~+120 frames on the
   base FF3us image but stayed black on ot6; a base-minted mid-battle
   state resumed fine on ot6, pinning the hang to the init/fade-in path.

On the current build the whole suite passes against ot6.sfc:
`gen_battle_state` mints both states end-to-end, `battle_entry` PASSes in
~460 frames, `battle_smoke` asserts shields 02/02 at $7E3E44/$7E3E46 and
digit glyph $B6 ("2") at $7E3ECB, and `battle_firebeam` drives a full
MagiTek turn -- `shots/fb_firing.png` shows the monster name window
rendering "Guard    2" (name + shield digit), confirmed visually.
