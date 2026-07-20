# OT6 test harness (Mesen 2 headless testrunner)

Automated, GUI-free tests that boot `build/ot6.sfc`, drive the game with
scripted input, assert on RAM, and capture screenshots/savestates.

## Quick start

```sh
make rom                                        # build build/ot6.sfc
tools/tests/run.sh tools/tests/gen_battle_state.lua   # power-on -> first battle -> savestate
tools/tests/run.sh tools/tests/battle_smoke.lua       # load savestate -> assert battle state
make frontier                                   # mint the deep story states (slow)
```

`make test` mints only the three states the suite asserts on.  The
STORY CHAIN past the whelk -- arvis_wake, narshe_streets,
moogle_doorstep, moogle_cleared, worldmap_narshe, figaro_doorstep,
figaro_intro, figaro_matron, figaro_cleared, south_figaro,
kolts_doorstep, vargas_doorstep, vargas_won -- lives behind
`make frontier`, which
nothing in the gate depends on: each link is a multi-minute scripted playthrough that
consumes the previous link's savestate, and the suite's remint cost has
to stay what it was.  The links use the same ROM-content gate as the
suite's states, so a rebuild that changes no bytes re-mints nothing.

TWO suite tests are FRONTIER-GATED: `battle_vargas` asserts on
`vargas_doorstep.mss`, and `battle_kefka` on `kefka_doorstep.mss` (the
Battle for Narshe -- deeper still, since its boot needs the REUNION: all
three scenarios completed in one playthrough via the Makefile's scenario
STACK, which waits on Sabin's chain's back half).  suite.sh adds each the
moment its fixture exists and reports it as `skip` when it does not --
never silently drops it -- so `make test` costs what it always did and
`make frontier-test` (mint the chain, then run the same suite) is the
command that always runs whatever is mintable.

`run.sh` wraps:

```sh
Mesen --testrunner --timeout=600 --enableStdout build/ot6.sfc <composed.lua>
```

(`--timeout=600` overrides the testrunner's default 100-second wall-clock
cap — expiry exits 255 with truncated stdout; `--enableStdout` mirrors the
EMULATOR message log, which is not where Lua errors land — see "Script
errors are invisible headless" below),
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

`run.sh` honors `OT6_WORKER=<id>`: Mesen's **config home**, saves dir,
composed file, default log, and artifact dir all move under
`build/test-workers/w<id>/`, so runs with distinct ids (and the default
id-less run) are safe concurrently.  `suite.sh`
honors `OT6_JOBS=N` (default 4 = the P-core knee; 1 = serial) and fans its
tests out across workers; every suite test is a pure savestate load (the
mints run as Makefile prerequisites first), so order doesn't matter.
Suite logs stay at `build/states/suite_<t>.log` either way, and each test
line reports its worker and wall time.

**No worker owns a copy of the emulator.**  Every worker on the machine
execs one shared, read-only bundle at
`~/Library/Caches/ot6/Mesen-test.app` -- cloned from `tools/Mesen.app`
once per machine, with its `settings.json` stripped so it is *not* in
portable mode -- and each is given its own `CFFIXED_USER_HOME`.  That
sends its settings, its battery saves and its `Debugger/*.cdl` into
`build/test-workers/w<id>/home/`, so nothing is ever written inside the
app and there is no per-worker emulator state left to race on.  The
shared copy is rebuilt automatically when `tools/Mesen.app` changes (a
size+mtime stamp beside it); `make clean` does not remove it, and it
should not -- see the Gatekeeper note below.

Two things that replaced, both easy to re-break:

* Workers used to each get a private 413MB copy of the bundle, because a
  `settings.json` beside the binary puts Mesen in **portable mode** and
  that file then *is* the config -- so a shared bundle meant one shared
  `SaveDataFolder` for everyone to race on (`2bf5045` has the forensics).
  Portable mode wins over every other mechanism, which is why the shared
  copy must never be allowed to grow a `settings.json`.  It is also why
  the copy exists at all rather than exec'ing `tools/Mesen.app` directly:
  the user's manual-play profile (`make run`) lives in that bundle as
  exactly such a file.
* Mesen is ad-hoc signed but **not notarized**, so macOS runs a
  first-launch Gatekeeper assessment on every *new bundle path*: a
  user-visible "Verifying Mesen…" dialog and a multi-second scan of all
  413MB (measured 4.7s and 6.1s on fresh paths, against 0.3-0.5s once the
  path is known).  The old scheme minted four of those per tree and four
  more for every agent worktree.  Clearing quarantine does **not** help --
  `xattr -cr` before first launch still cost 5.5s, and the kernel puts
  `com.apple.provenance` straight back on exec -- because the trigger is
  the new path, not the flag.  Keeping the shared copy at one stable
  machine-wide location is the whole fix.

(The testrunner does NOT write settings back -- `DisableSaveSettings` is
set -- and never creates `SaveStates/`.)

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
- `gen_whelk_poweron.lua` - the suite's whelk mint: COLD POWER-ON ->
  intro -> Narshe streets -> mines -> BFS to (42,6); emits
  `build/states/whelk_doorstep.mss` (field, one tile short of the
  trigger) plus a positive-control `whelk_battle` screenshot.  Needs no
  save file at all, so it works on a fresh clone; byte-identical every
  run.  The state is CAPTURED, then VALIDATED, then emitted: a sweep
  replays it at four spread frame phases and requires of each that the
  Whelk fight comes up, a battle command menu opens, and a command list
  actually draws.  A run that fails leaves no `whelk_doorstep.mss` at
  all rather than an unvalidated one.  The sweep exists because the
  doorstep's frame phase seeds the battle RNG (`lda $021e / asl2 /
  sta $be`, battle_main.asm:6092-6094) and therefore picks whose menu
  opens first — but the mint cannot steer that for anybody, because the
  seed is set at BATTLE init and each consumer adds its own walk length
  first (measured on one identical fixture: probe_shadow_overlap 264
  frames, battle_whelkwipe 266, battle_dlgmenu 267 — three walks, three
  seeds, and on one ROM three different menu owners).  So the mint
  proves the fixture works across rolls instead of tuning a settle to
  chase one.
- `gen_whelk.lua` - the retired SRM-based ancestor: boot an injected
  play save and BFS the mines to the same doorstep (see
  `docs/playing-headless.md`).  Kept because probe_slots and the
  balance instruments still consume `make_srm_sidecar.sh` saves;
  requires a pre-Whelk save, which no longer exists locally.
- `gen_edgar.lua` - THE WHOLE FIGARO CHAPTER, gate to world map: walks
  `figaro_doorstep.mss` in, buys the BioBlaster + NoiseBlaster from the
  tool merchant (the ONLY window - the merchant refuses once EDGAR or
  SABIN is in the party), takes Edgar's audience, crosses the
  castle to the MATRON and rides her flashback, which is what puts
  Edgar back on his throne ($0308), then returns for the second audience
  and KEFKA's arrival, works the confrontation (BOTH troopers, then
  Kefka), LOCKE's regroup, the burning night and the submerge, and rides
  the chocobos out.  Emits `figaro_intro.mss` (frame 5804),
  `figaro_matron.mss` (10433) and `figaro_cleared.mss` (32071 - world
  map, TERRA + LOCKE + EDGAR, tools carried, party on a chocobo).
  Its header documents four measured mechanisms the
  entrance/NPC tables do not give you: event switches $01F0..$01FF are
  per-map scratch (`LoadMap` zeroes $1EBE/$1EBF), NPC activation is
  decided by the party FACING byte and a two-frame turn press does not
  set it, castle doors are walls until `CheckDoor` so every crossing is
  navTo-a-neighbour plus one hold, and the shop menu must be driven by
  state ($7E0026) not by timing.  It also documents the castle's
  disconnected walking regions, the diagonal staircases that join them
  (BFS plans those itself now - the four `pushUntil` hand-holds an
  earlier pass needed are retired), why map 55's row y=43 must stay off
  every route (it is a world-exit trigger, not a wall), and maps the
  beats it stops short of.
- `gen_kolts.lua` - rung 2's last route leg: figaro_cleared (world map,
  ON A CHOCOBO) to the Vargas doorstep on Mt. Kolts.  Mints
  `south_figaro.mss` (frame 6699), `kolts_doorstep.mss` (8133) and
  `vargas_doorstep.mss` (20240).  Its header documents three mechanisms
  no table in the ROM gives you: the CHOCOBO DISMOUNT (InitChoco never
  writes $E0/$E2, so worldNavTo cannot plan until a held B walks the
  LandAirship -> descent -> ExitVehicle -> ReloadMap -> InitWorld chain),
  that the FIGARO DESERT CANNOT REACH SOUTH FIGARO ON FOOT (1165 tiles
  bounded at y<=95 versus a separate 422-tile southern region -- the link
  is the South Figaro cave, and its mouth is walled by two NPCs who only
  move when talked to), and that MT. KOLTS'S MAP 100 IS SIX DISCONNECTED
  SHELVES whose way in is a LONG entrance (map 96 (12,8) -> map 102) --
  the short table's advertised (7,48)->98 is the way OUT, which is why
  Vargas's walk-on parks him on it.  Also: the crossing settle must not
  wait on `hasControl`, because the caves' async cutscenes flip the
  party's movement-type byte every few frames.
- `gen_vargas.lua` - the fight, and the frontier's last rung-2 link:
  boots vargas_doorstep, clamps Vargas under his own script's second
  threshold so `battle_event $07/$08` put SABIN on the field, kills him
  with a real PUMMEL input, rides the reunion and mints `vargas_won.mss`
  (frame 11426, SABIN level 9 in the party for good).
- `battle_vargas.lua` - FRONTIER-GATED gate for rung 2's boss: Vargas
  seeds 5/5 with class row $04 (OT6_BLUDG) and Ipoohs 2/2 slash-weak,
  his weak byte reads exactly $28 = poison|holy (the poison bit is
  vanilla, the HOLY bit is Ot6ElemAddTbl's row -- this is the assertion
  that fails if that row is dropped), AuraBolt's holy chips a shield and
  reveals $20, Pummel's bludgeon chips another and reveals $04, and the
  same Pummel ends the fight through `if_attack PUMMEL -> battle_event
  $09 / kill_monsters ALL`.  Both Blitzes are driven as real pad EDGES
  into the code window, not poked.
- `probe_vargas.lua` - the instrument behind both: dumps the seeded
  formation, gauge, element and class rows and SABIN's join level, and
  answers the two questions the sources do not -- that SABIN gets NO
  turns until the script's phase-two transition (measured: 9000 frames
  of entities 0/1/2 taking turns and entity 3 never), and what the
  harness's kill-bit idiom does to a boss whose death is scripted (it
  ends the fight cleanly in 117 frames -- `if_self_dead / boss_death`
  sits ahead of the Pummel branch -- but the scripted finish is the one
  the fixtures are minted through).
- `probe_dismount.lua` - the measurement instrument for getting off the
  chocobo: records the whole B -> $19=3 -> descent -> $11FA=0 ->
  InitWorld state machine frame by frame, asserts $E0/$E2 come back live
  from $1F60/$1F61, and plans (without walking) both rung-2 world legs.
- `probe_canstep.lua` - validates `H.canStep` (the movement-model port)
  against real movement, in two parts, one per engine branch.  Part 1,
  CARDINAL (`CheckPlayerMove`): four directions x two rounds at the mines
  boot area, plus a wall case; renders the model's view of the
  neighborhood as ASCII.  Part 2, DIAGONAL (`player.asm:379`): boots
  `figaro_matron.mss` and sweeps the matron's own staircase - all four
  presses on each of its tiles, comparing the exact displacement the model
  predicts against the exact displacement the engine produces.  A tile
  whose prop byte has `$c0` set turns a left/right press into a diagonal
  move, which is what every Figaro staircase is made of.  The part-2
  assertions demand the sweep actually produced all three outcomes the
  branch can have (a diagonal, a diagonal-refused-to-cardinal fallback,
  and a refused press), so it cannot pass by exercising nothing.
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
- `battle_bushido.lua` - gate for BP-Bushido: boost points pick Cyan's
  tech and vanilla's charge gauge is gone.  Cyan is not recruitable
  until v0.3, so he is INSTALLED into the opening guard fight the way
  the balance labs pin state -- CHAR::CYAN into $3ED8, a Bushido-only
  command list at $202E (stride 12), the weapon SWDTECH flag in
  $3BA4/$3BA5 (without it UpdateCmd_02 greys the command out), and a
  pinned $2020 standing in for his level.  Asserts the clock is dead
  (150 settled in-window frames, one bar value -- vanilla stepped every
  4 frames), the whole tier ladder including its learn-clamped rows,
  that Oblivion stays out of reach, the 3-BP spend cap, and that the
  chosen tech resolves: Flurry's $58 reaches $3410, chips a
  slashing-weak guard, reveals the slash class, and consumes the boost
  with no regen.
- `probe_bushido.lua` - the measurement instrument behind it: logs the
  menu state, w7e7b82, pending boost and $3410 across the same install,
  and answers the questions the source alone does not (does one A press
  reach menu state $37, does L/R still move the boost inside that
  window, what does the bar actually do per frame).
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
frame).  The step style below is the house pattern.  (An older note here
claimed coroutines crash this build; that was the exit-255 wall-clock cap
misread as a crash -- see WORKING NOTES.  Coroutines work.  The step machine
stays because the whole suite is written in it, not because it has to.)

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
  `H.dialogWaiting`, `H.canStep`, `H.movePress`, `H.bfsPath`, `H.navTo`,
  `H.clearBattle`): see `docs/playing-headless.md` for the RAM tables and
  the design.  Moves are the four cardinals plus the four diagonals a
  left/right press produces on a `$c0` tile; `H.movePress(move)` gives the
  button that executes one.
- World-map navigation (`H.worldMode`, `H.worldId`, `H.worldX/Y`,
  `H.worldAligned`, `H.worldPassable/worldCanStep`, `H.worldBfs`,
  `H.worldHasControl`, `H.worldNavTo`, and `H.route` -- the field/world
  handoff driver): see `docs/research/world-map-nav.md` for the RAM
  tables and every measured mechanism claim.

## Mesen 2.1.1 Lua API facts (all verified empirically on this binary)

- Runner: `Mesen --testrunner <rom> <script.lua>`; process exit code is the
  integer passed to `emu.stop(code)`.
- **Lua 5.4**.  `print()` -> stdout.  `emu.log()` -> the SCRIPT log, which
  no headless process ever reads (invisible; not mirrored by
  `--enableStdout`).  `load()` (from a string) works.
  `io` / `os` are nil and `dofile()` / `loadfile()` RAISE -- but that is a
  SETTING, not a property of the sandbox:
  `Debug.ScriptWindow.AllowIoOsAccess` (default false;
  `ScriptingContext.cpp:66`, `Lua/lauxlib.c:776`).  Flip it and all four
  work; Mesen's own error text names the setting.  `pin_test_saves.py`
  already writes that config section.  We leave it off and compose scripts
  flat (see compose.py) -- that is a choice for hermetic runs, not a
  constraint we are forced into.
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
  0xC10BA7, 0xC10BA7)` fires once per battle NMI).  They fire for bank F0
  too -- `battle_reveal`, `battle_reveal_poweron` and `probe_reveal_trace`
  all hook $F00000 and pass.  (This bullet used to claim F0 never fires,
  contradicting three tests in the suite.)  PRG-file-offset forms fire
  never (0x010BA7) or on the wrong thing; use the bus form.
- Memory callbacks SURVIVE `emu.loadSavestate()`; nothing in the load path
  clears them (`SaveStateManager.cpp` only raises `StateLoaded`).
  `battle_banner` relies on this -- it registers four exec callbacks before
  its `H.loadState` and records through to a PASS.
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

- Do not delete `~/Library/Application Support/Mesen2/settings.json`.  The
  reason is OURS, not Mesen's: `run.sh` feeds that path to
  `pin_test_saves.py` as the BASE it pins on top of, and it opens it
  unconditionally and would raise.  run.sh checks that exit code and aborts
  (exit 2) rather than running against whatever settings.json the worker
  home already held.
- **`$HOME` does not move Mesen's config folder on macOS; `CFFIXED_USER_HOME`
  does.**  Mesen picks its home folder one of two ways: a `settings.json`
  beside the binary puts it in portable mode and fully determines the home
  (`ConfigManager.cs:177`), and otherwise it is
  `~/Library/Application Support/Mesen2`.  That second path is
  `Environment.GetFolderPath(SpecialFolder.ApplicationData)`, which on macOS
  .NET resolves through `NSSearchPathForDirectoriesInDomains` and takes the
  home from the **password database**, not the environment -- the binary
  carries the giveaway `GetHomeDirectory:TryGetHomeDirectoryFromPasswd`.
  Proof: run the testrunner with `HOME` pointed at a scratch dir and it
  still writes its `.srm` and `Debugger/*.cdl` into the real profile;
  add `CFFIXED_USER_HOME` (Core Foundation's own home override) and
  everything -- settings, saves, cdl, even the ~29MB of native libs Mesen
  seeds into a fresh home -- lands in the scratch dir instead.  Portable
  mode still beats both, so a bundle with a `settings.json` ignores
  `CFFIXED_USER_HOME` entirely.  This is what `run.sh` uses to keep
  parallel workers apart without copying the emulator.
- stdout also carries `[CPU] Uninitialized memory read: ...` debug spam;
  filter for `[ot6]` / `[probe]`.  It is *read-before-write* tracking (the
  debugger flags any address read before it has ever been written this
  power-on) and says nothing about the RAM fill -- it appears under
  `AllZeros` just as it does under `Random` (89 vs 145 lines over 600
  frames, measured).  It only shows up headless because the testrunner
  force-enables the debugger via Mesen's `ConsoleMode` flag.
- **A 255 exit with truncated stdout means a wall-clock cap expired, not a
  mystery crash.**  The testrunner defaults to 100 seconds (run.sh passes
  `--timeout=600`) and Mesen's per-Lua-slice watchdog defaults to 1 second
  (`pin_test_saves.py` pins `Debug.ScriptWindow.ScriptTimeout = 30`).
  stdout is block-buffered, so output stops well before the actual death.
  ANY error at script load has the same signature: no callbacks register,
  the emulator free-runs, the cap reaps it.  A bare syntax error looks
  identical to a "crash".
- **Script errors are invisible headless.**  `--enableStdout` mirrors the
  EMULATOR message log (`MessageManager`); Lua errors and watchdog kills go
  to the SCRIPT log, a separate 500-row buffer only the GUI script window
  ever reads.  There is no bridge.  `print()` is the only channel out of a
  script, so a test that goes quiet is telling you nothing -- add prints.
- Retired claims, all one misdiagnosis: this section used to say coroutines
  crashed the build, that runtime `dofile` crashed it, and that
  `emu.getState()` in a poll loop was crash-correlated.  All three were the
  255 cap above.  Coroutines run clean 4/4 at 20k frames; `dofile` raises a
  tidy error naming the setting that enables it; `battle_banner` calls
  `getState()` four times a frame in production and passes.
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
