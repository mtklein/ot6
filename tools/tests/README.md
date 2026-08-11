# OT6 test harness (Mesen 2 headless testrunner)

Automated, GUI-free tests that boot `build/ot6.sfc`, drive the game with
scripted input, assert on RAM, and capture screenshots/savestates.

## Quick start

```sh
make rom                                        # build build/ot6.sfc
tools/tests/run.sh tools/tests/gen_battle_state.lua   # power-on -> first battle -> savestate
tools/tests/run.sh tools/tests/battle_smoke.lua       # load savestate -> assert battle state
make savestates                                   # generate the deep story savestates (slow)

python3 tools/tests/lib/compose.py --check-states      # is this red test a stale fixture?
```

Run `--check-states` first when a test is red and you did not expect it.  A
savestate that was generated from sources this tree no longer has boots into
a ROM whose timing it does not match, and the result is a red test that has
nothing to do with your change, usually a timeout on some innocent step,
which reads like a product bug.  This is common in a fresh worktree:
`tools/worktree-setup.sh` seeds from whatever the main checkout last
generated, which is routinely a whole tree of stale fixtures.

`--check-states` answers in ~2s, names the shared input that moved when
there is one, and gives you the command to regenerate just that one savestate
(`nice -n 10 ninja -f build/build.ninja <state>`) rather than the hours-long
full chain.  `suite.sh` and `worktree-setup.sh` both run it for you, and a
timeout that happens on a fixture it flagged says so in the failure itself.
Run it before you start re-running the same tests against unmodified `main`
to see whether they were red there too.

`make test` generates only the three savestates the suite asserts on.  The
story chain past the whelk (the Narshe escape, the Figaro chapter, Mt. Kolts
and Vargas, the three-scenario reunion and the Battle for Narshe, and on
through Kefka to Zozo) lives behind `make savestates`, which nothing in
`make test` depends on: each link is a multi-minute scripted playthrough
that consumes the previous link's savestate, and the suite's regeneration
cost has to stay what it was.

The graph of generated savestates is data: `tools/tests/savestate_graph.py`,
one entry per state.  `lib/savestate_ninja.py` emits it as
`build/build.ninja`, and `make savestates` / `make test` are thin wrappers
over `ninja -f build/build.ninja`.  A generated link is a function of the ROM
bytes, its generator `gen_*.lua`, and all three lib halves `lib/compose.py`
inlines into every composed script: `lib/ot6.lua` (battle core),
`lib/ot6_field.lua` (field/world navigation) and `lib/ot6_contract.lua`
(invariant contracts for saved checkpoints), plus, for a segment that starts
from a saved checkpoint, that checkpoint's manifest and SRAM payload.  Every
one of those is a declared ninja dependency, routed through a content latch
edge (`cmp || cp` with `restat = 1`), so staleness is decided by content
inside ninja's own scheduler: a rebuild or checkout that bumps timestamps
without moving bytes regenerates nothing, a changed input re-runs every
transitive dependent, and there is no stamp beside the graph to disagree
with it.  Editing one generator regenerates only the states it feeds (and
their descendants down the chain); editing any lib half regenerates the
whole chain, since every route runs through them.  That cost is acceptable
because the lib changes rarely while generators change constantly.
`lib/savestate_ninja_selftest.sh` checks those semantics against real ninja
on a mock tree in seconds, with no emulator.  `lib/savestate_stamp.sh`
covers provenance: each generation step stamps
`build/states/<state>.stamp` with three claims:

    sha256(GATE_CONTRACT ++ generator ++ ot6.lua ++ ot6_field.lua ++
           ot6_contract.lua ++ extras) <generator> [extras]
    artifact <sha256 of build/states/<state>.mss>
    ancestor <path> <sha256 of that file>     (prev= edges bind their
                                               predecessor's stamp; checkpoint=
                                               edges their manifest.json;
                                               power-on roots have no line)

`lib/compose.py` re-verifies all of them at consume time, printing an
`[ot6]` line if a fixture a test is about to boot has drifted from its
generator+lib, had its `.mss` replaced without being regenerated, or sits on
a chain whose ancestor stamp moved (the artifact and ancestor bindings make
the whole chain verifiable transitively from files on disk).  `GATE_CONTRACT`
(`ot6-provenance/v1`, one constant in `savestate_stamp.sh`) is a fixed sig
input: bumping it deliberately stales every stamp and forces everything to be
regenerated under new rules.  `compose.py --check-states` asks the same
question of the whole tree and is a hard `make test` check.

Some suite tests need a savestate only `make savestates` generates: each
declares `-- @suite savestate=<fixture>` and asserts on that state.
`battle_vargas` uses `vargas_entry.mss`, `battle_flyin` uses
`kolts_cave.mss` (the entry hud test, a fight whose monsters fly in,
present but not shown at battle start), `battle_kefka` uses
`kefka_entry.mss` (the Battle for Narshe, deeper still, since its boot
needs the reunion: all three scenarios completed in one playthrough via the
graph's scenario stack), and there are others.  `tools/tests/suite.sh --list`
prints the current set.  suite.sh adds each the moment its fixture
exists and reports it as `skip` when it does not, rather than dropping it
silently, so `make test` costs what it always did and `make savestates-test`
(generate the chain, then run the same suite) is the command that always
runs everything that can be generated.

The **scenario stack** turns those three opening chains (Locke, Terra,
Sabin) into one lineage.  The reunion needs all three completed in a single
playthrough, but each input-driven chain sets only its own flag, so a
stacked run replays a chain's route logic from a different boot.
`OT6_STACK=<prefix>` makes `compose.py` rewrite every `.mss` basename in the
script (never in the lib), so the same generator boots a prefixed
predecessor and emits prefixed
artifacts, leaving the original savestates untouched.  The graph seeds each
stacked hub from the previous chain's ending (`seed=` entries in
`savestate_graph.py`) and stacks the `t2_`/`s2_`/`t3_` layers up to
`reunion_ready`.  The full account is `savestate_graph.py`'s `SCENARIO
STACKING` section and `compose.py`'s `SCENARIO STACKING (OT6_STACK)`
docstring.

`run.sh` wraps:

```sh
Mesen --testrunner --timeout=600 --enableStdout build/ot6.sfc <composed.lua>
```

`--timeout=600` overrides the testrunner's default 100-second wall-clock
cap; expiry exits 255 with truncated stdout.  `--enableStdout` mirrors the
emulator message log, which is not where Lua errors land (see "Script errors
are invisible headless" below).  run.sh captures all output to
`build/states/last_run.log` (second arg overrides), decodes any `[b64:...]`
artifacts the script emitted (see below), prints the `[ot6]` log lines, and
exits with the script's `emu.stop()` code:

| exit | meaning                                    |
|------|--------------------------------------------|
| 0    | pass                                       |
| 1    | assertion failure / Lua error              |
| 2    | global frame budget exceeded (see `H.run`) |

Scripts built on the library always terminate on their own, so no external
watchdog is needed.  A bare hang would only happen if a script bypasses
`H.run()`'s frame budget.

### Parallel runs

Every `run.sh` invocation creates a unique directory under
`build/test-runs/`. `OT6_WORKER=<id>` is only a readable label on that
directory, never an isolation key: calls with the same id and id-less calls
are safe concurrently. Mesen's config home, saves, composed script,
working log, and decoded artifacts all live in that invocation directory.
Completed logs and artifacts are then atomically published to their usual
paths under `build/states/`; set `OT6_ARTIFACT_DIR` to choose another artifact
destination. Successful workspaces are removed, failed workspaces are retained
and reported, and `OT6_KEEP_RUNS=1` retains successful ones for investigation.

`suite.sh` likewise creates unique bookkeeping under `build/test-suites/`, so
two complete suites may overlap without sharing compositions, claims, or
results. It honors `OT6_JOBS=N` (1 = serial) and fans tests out across
scheduling labels; every suite test is a pure savestate load (the savestates
are generated through the ninja graph first), so order doesn't matter. Suite logs stay at
`build/states/suite_<t>.log` either way, and each test line reports its worker
label and wall time. `runner_isolation_selftest.sh`, run by `make test`,
deliberately overlaps same-label runner calls and complete-suite workspaces as
the positive control for these guarantees.

No worker owns a copy of the emulator.  Every worker on the machine execs
one shared, read-only bundle at `~/Library/Caches/ot6/Mesen-test.app`,
cloned from `tools/Mesen.app` once per machine, with its `settings.json`
stripped so it is not in portable mode, and each is given its own
`CFFIXED_USER_HOME`.  That sends its settings, its battery saves and its
`Debugger/*.cdl` into the current
`build/test-runs/<label>.<unique>/home/`, so nothing is ever written inside
the app and there is no per-worker emulator state left to race on.  The
shared copy is rebuilt automatically when `tools/Mesen.app` changes (a
size+mtime stamp beside it).  `make clean` does not remove it, and it
should not, for the reason in the Gatekeeper note below.

That arrangement depends on two properties, both easy to break again:

* A `settings.json` beside the binary puts Mesen in **portable mode**, and
  that file then is the config, with one shared `SaveDataFolder` for every
  worker to race on.  Portable mode wins over every other mechanism, which
  is why the shared copy must never be allowed to grow a `settings.json`.
  It is also why the copy exists at all rather than exec'ing
  `tools/Mesen.app` directly: the user's manual-play profile (`make run`)
  lives in that bundle as such a file.
* Mesen is ad-hoc signed but not notarized, so macOS runs a
  first-launch Gatekeeper assessment on every new bundle path: a
  user-visible "Verifying Mesen…" dialog and a multi-second scan of all
  413MB (4.7-6.1s on a fresh path, against 0.3-0.5s once the path is
  known).  Clearing quarantine does not help: `xattr -cr` before
  first launch still costs 5.5s, and the kernel puts
  `com.apple.provenance` straight back on exec, because the trigger is
  the new path rather than the flag.  Keeping the shared copy at one stable
  machine-wide location avoids the cost.

(The testrunner does not write settings back, since `DisableSaveSettings` is
set, and never creates `SaveStates/`.)

## Files

- `lib/ot6.lua` - harness library, battle core: steps/input/memory/
  savestates/battle signals/canaries plus the shared field-state reads
  (see header comment for full API).
- `lib/ot6_field.lua` - harness library, navigation half: passability
  model, BFS, `navTo`/`worldNavTo`/`advanceStory`/`route`.  Inlined by
  `lib/compose.py` right after `ot6.lua` into every composed script; tests
  still write only the one `dofile(".../lib/ot6.lua")` line and see one
  merged `H`.
- `lib/decode_b64.py` - decodes `[b64:tag]` stdout payloads into files.
- `gen_battle_state.lua` - title screen -> New Game -> intro -> Narshe ->
  walk into the first guard battle; emits `build/states/battle_entry.mss`
  (field, ~5 s before the trigger) and `build/states/first_battle.mss`
  (in battle) plus progress screenshots.
- `battle_smoke.lua` - loads `first_battle.mss` and asserts battle liveness,
  logging monster IDs and party HP.
- `smoke.lua` - original ROM-content smoke test (OCTO name bytes).
- `battle_entry.lua` - fast battle-entry regression test: loads
  `battle_entry.mss` and walks into the first battle (~30 s wall clock,
  PASS/FAIL on whether the battle engine comes up).  Use it as the
  tight iteration loop for battle/break-system changes.
- `battle_firebeam.lua` - full interaction test: entry point -> fresh battle ->
  A/A/A drives MagiTek Fire Beam onto a guard; asserts each press visibly
  changes the screen and the action resolves (guard HP drops).  Logs break
  RAM (guard shields $3E44/$3E46, HP $3C00/$3C02, revealed masks
  $3E95/$3E97) and screenshots before/during/after.  (The monster-window
  shield digit is retired; the under-enemy HUD is the shield display.)
- `probe23.lua` - positive control: input injection still works after
  loadSavestate (A opens the MagiTek submenu, B closes it; fails if
  a press has no visible effect).
- `probe16.lua` - diagnostic: savestate save/clobber/load round-trip
  (validates the exec-callback trampoline and the base64 codec).
- `probe19.lua` - diagnostic: entry point -> battle with screenshots + RAM
  dumps at +0/+60/+180/+420/+900/+1500/+2400 frames.
- `gen_whelk_poweron.lua` - the suite's whelk generator: cold power-on ->
  intro -> Narshe streets -> mines -> BFS to (42,6); emits
  `build/states/whelk_entry.mss` (field, one tile short of the
  trigger) plus a positive-control `whelk_battle` screenshot.  Needs no
  save file at all, so it works on a fresh clone; byte-identical every
  run.  The state is captured, then validated, then emitted: a sweep
  replays it at four spread frame phases and requires of each that the
  Whelk fight comes up, a battle command menu opens, and a command list
  draws.  A run that fails leaves no `whelk_entry.mss` at
  all rather than an unvalidated one.  The sweep exists because the
  fixture's frame phase seeds the battle RNG (`lda $021e / asl2 /
  sta $be`, battle_main.asm:6092-6094) and therefore picks whose menu
  opens first, and the generator cannot steer that for every consumer, because
  the seed is set at battle init and each consumer adds its own walk length
  first (measured on one identical fixture: probe_shadow_overlap 264
  frames, battle_whelkwipe 266, battle_dlgmenu 267, so three walks give three
  seeds, and on one ROM three different menu owners).  So the generator
  proves the fixture works across rolls instead of tuning a settle to
  chase one.
- `gen_whelk.lua` - the SRM-based route to the same spot: boot an
  injected play save and BFS the mines (see `docs/playing-headless.md`).
  Kept because probe_slots and the balance instruments still consume
  `make_srm_sidecar.sh` saves; requires a pre-Whelk save, which does not
  exist locally.
- `gen_post_opera_checkpoint.lua` - provenance generator for the tracked 32 KiB
  post-Opera SRAM checkpoint. It settles `blackjack.mss`, uses the real Save UI
  to write slot 3, and relies on `run.sh`'s explicit `OT6_CAPTURE_SRM` mode to
  capture Mesen's file after shutdown.

  **Save-drive rule: a gen that saves anywhere near live event state must
  drive the Save UI with pad input only, never by poking `ZMENUSTATE`.** The
  forced-state shortcut skips the menu entry's own writes, leaving menu
  tasks running on a corrupted exit: it produces a phantom `$021f` overlay
  and corrupts the live `$1188` event-timer block in WRAM with no error
  (SRAM is pushed first and stays correct).
  `probe_banquet_timer_save.lua` is the pad-input template.
- `gen_vector_entry.lua` - cold boots with the verified post-Opera
  checkpoint, drives vanilla Continue, checks story state plus the slot-3
  OT6 codex page, then walks the world map to the Vector event trigger at
  (121,187) and generates
  `vector_entry` on map 242.  Vector has no entrance record at all; it is
  `event_trigger.asm:36-37` -> `_ca5ecf` -> `load_map 242 {32,61}`, so the
  opening segment is an on-foot world walk through an area with random
  encounters fully enabled
  (worldGrind, not worldNavTo).  Its positive control reads the map name the
  engine would print (the live title index `$0520`, through `MapTitlePtrs`
  into `MapTitle`) and requires "VECTOR"; the same read is exercised at the
  Albrook map transition first and required to say "ALBROOK", so it cannot
  pass by returning nothing.  The rest of the Vector chain (`gen_vector_sneak`,
  `gen_mrf_entry`, `gen_mrf_chute`, `gen_mrf_263`, `gen_mrf_kefka`,
  `gen_ifrit_entry`, `gen_ifrit_magicite`, `gen_n024_entry`,
  `gen_esper_tubes`, `gen_esper_tubes_done`, `gen_minecart_entry`) chains
  off it; each generator's header documents the mechanism it had to measure.
  `gen_n128.lua` is written but does not produce a savestate; see its header
  and `probe_train_tail.lua`.
- `gen_edgar.lua` - the whole Figaro chapter, entrance to world map: walks
  `figaro_entry.mss` in, buys the BioBlaster + NoiseBlaster from the
  tool merchant (the only window, since the merchant refuses once Edgar or
  Sabin is in the party), takes Edgar's audience, crosses the
  castle to the matron and runs her flashback, which is what puts
  Edgar back on his throne ($0308), then returns for the second audience
  and Kefka's arrival, works the confrontation (both troopers, then
  Kefka), Locke's regroup, the burning night and the submerge, and rides
  the chocobos out.  Emits `figaro_intro.mss` (frame 5804),
  `figaro_matron.mss` (10433) and `figaro_cleared.mss` (32071 - world
  map, TERRA + LOCKE + EDGAR, tools carried, party on a chocobo).
  Its header documents four measured mechanisms the
  entrance/NPC tables do not provide: event switches $01F0..$01FF are
  per-map scratch (`LoadMap` zeroes $1EBE/$1EBF), NPC activation is
  decided by the party facing byte and a two-frame turn press does not
  set it, castle doors are walls until `CheckDoor` so every crossing is
  navTo-a-neighbour plus one hold, and the shop menu must be driven by
  state ($7E0026) rather than by timing.  It also documents the castle's
  disconnected walking regions, the diagonal staircases that join them
  (BFS plans those itself), why map 55's row y=43 must stay off
  every route (it is a world-exit trigger rather than a wall), and maps the
  beats it stops short of.
- `gen_kolts.lua` - tier 2's last route segment: figaro_cleared (world map,
  on a chocobo) to just before the Vargas fight on Mt. Kolts.  Generates
  `south_figaro.mss` (frame 6699), `kolts_entry.mss` (8133) and
  `vargas_entry.mss` (20240).  Its header documents three mechanisms
  no table in the ROM provides: the chocobo dismount (InitChoco never
  writes $E0/$E2, so worldNavTo cannot plan until a held B walks the
  LandAirship -> descent -> ExitVehicle -> ReloadMap -> InitWorld chain),
  that the Figaro desert cannot reach South Figaro on foot (1165 tiles
  bounded at y<=95 versus a separate 422-tile southern region; the link
  is the South Figaro cave, and its mouth is walled by two NPCs who only
  move when talked to), and that Mt. Kolts's map 100 is six disconnected
  shelves whose way in is a long entrance (map 96 (12,8) -> map 102);
  the short table's advertised (7,48)->98 is the way out, which is why
  Vargas's walk-on parks him on it.  Also: the crossing settle must not
  wait on `hasControl`, because the caves' async cutscenes flip the
  party's movement-type byte every few frames.
- `gen_vargas.lua` - the fight, and the chain's last tier-2 link:
  boots vargas_entry, clamps Vargas under his own script's second
  threshold so `battle_event $07/$08` put Sabin on the field, kills him
  with a real Pummel input, plays the reunion and generates `vargas_won.mss`
  (frame 11426, Sabin level 9 in the party for good).
- `battle_vargas.lua` - needs a generated savestate; the test for tier 2's
  boss: Vargas
  seeds 5/5 with class row $04 (OT6_BLUDG) and Ipoohs 2/2 slash-weak,
  his weak byte reads $28 = poison|holy (the poison bit is
  vanilla, the holy bit is Ot6ElemAddTbl's row, and this is the assertion
  that fails if that row is dropped), AuraBolt's holy chips a shield and
  reveals $20, Pummel's bludgeon chips another and reveals $04, and the
  same Pummel ends the fight through `if_attack PUMMEL -> battle_event
  $09 / kill_monsters ALL`.  Both Blitzes are driven as real pad edges
  into the code window rather than poked.
- `battle_flyin.lua` - needs the generated `kolts_cave.mss`.  Guards the entry
  hud case: a monster is flagged present (`$3AA8`) from battle init, but
  its sprite is not drawn until its fly-in animation runs, so the hud must
  not paint its shield/'?' cells before the "monsters shown" mask `$201E`
  covers it.  Paces map 96's Cirpius-x3 pool and asserts, every frame of
  the ~45-frame fly-in, that each present-but-unshown line is DISABLED and
  the bg3 field map holds zero OT6 glyphs; positive controls that the
  window was sampled and that the hud comes back once the birds land.
  Fails on `cur=$54AC`, which is glyphs drawn on the still-dark
  battlefield.
- `battle_hudanim16.lua` - needs the generated `kolts_cave.mss`
  (battle_flyin's fixture).  Guards the anim-mode veil: battle animation inits flip the
  battlefield's $2105 shadow (`$896F`) to 16x16 bg3 tiles while an effect
  uses bg3 as its canvas or color-math mask, and in that mode a map cell
  renders at doubled size/position pulling three neighbor tiles, so any
  live hud line inside the effect's scroll window draws doubled break-icon
  blocks flanked by neighbor-tile junk over and around the monsters.  Paces
  the natural
  pool, lets the entry veil finish, drives ~2 Terra casts, and asserts per
  frame: no live hud cell holds a painted glyph while `$896F` bit `$40` is
  up, with positive controls that >= 24 such
  frames were sampled, at least one live line read veiled ($01EE), the
  dialogue latch stayed 0 (the no-dialogue clause), and the hud repaints
  whole (glyphCanary) after.
- `probe_junk16.lua` - the reproduction instrument behind it: same fixture
  and drive plus per-frame $2105/$212C/scroll/anchor traces, a claimed-
  glyph-in-window detector with screenshot bursts, and a borrowed-font
  canary.  Its `j16_*_hudvis` shots show the failure: doubled shield/'?'
  glyphs and neighbor-tile bars over the battlefield during Cure.
- `probe_bg3anim.lua` - measures the display state: runs
  first_battle's Fire Beam (bg3-scripted, $2105=$59 for ~70 frames while
  bg3 stays on the main screen) with a full map-census log per frame.
- `probe_896f.lua` - write-watcher over the battlefield $2105 shadow
  ($7E896F): every writer PC and value through a Cirpius battle with a
  Terra cast.  Measured writer set: C1/B1AF=$59 (InitAnimType's bg1-gfx
  path, btlgfx_main.asm:26350), C2/F762=$51 (the priority-dropping circle
  family), C1/C1D8=$19 (weapon-swing bg1-only 16x16), restores at
  C1/B0AB and C1/C20A.  These are the flips battle_hudanim16's veil answers.
- `probe_vargas.lua` - the instrument behind both: dumps the seeded
  formation, gauge, element and class rows and Sabin's join level, and
  answers the two questions the sources do not.  Sabin gets no
  turns until the script's phase-two transition (measured: 9000 frames
  of entities 0/1/2 taking turns and entity 3 never).  The harness's
  force-kill idiom ends the fight cleanly in 117 frames on a boss whose
  death is scripted, because `if_self_dead / boss_death`
  sits ahead of the Pummel branch, but the scripted finish is the one
  the fixtures are generated through.
- `probe_dismount.lua` - the measurement instrument for getting off the
  chocobo: records the whole B -> $19=3 -> descent -> $11FA=0 ->
  InitWorld state machine frame by frame, asserts $E0/$E2 come back live
  from $1F60/$1F61, and plans (without walking) both tier-2 world segments.
- `probe_canstep.lua` - validates `H.canStep` (the movement-model port)
  against real movement, in two parts, one per engine branch.  Part 1,
  cardinal (`CheckPlayerMove`): four directions x two rounds at the mines
  boot area, plus a wall case; renders the model's view of the
  neighborhood as ASCII.  Part 2, diagonal (`player.asm:379`): boots
  `figaro_matron.mss` and sweeps the matron's own staircase - all four
  presses on each of its tiles, comparing the exact displacement the model
  predicts against the exact displacement the engine produces.  A tile
  whose prop byte has `$c0` set turns a left/right press into a diagonal
  move, which is what every Figaro staircase is made of.  The part-2
  assertions require the sweep to produce all three outcomes the
  branch can have (a diagonal, a diagonal-refused-to-cardinal fallback,
  and a refused press), so it cannot pass by exercising nothing.
- `battle_banner.lua` - timing test for the banner screen-tear: exec
  callbacks at the battle NMI's entry / flush start / flush end / post-
  INIDISP sample `ppu.scanline` on every frame through a Fire Beam cast
  (named banners: vanilla writes its name scratch at $7E57D5) and assert
  the whole NMI tail stays inside vblank (scanline 225..261), plus
  OT6_FONTDIRTY ($57B9) stays clear and the under-monster HUD cells are
  still painted in VRAM afterwards.  A flush that ends past 261 is
  the user-visible flash/tear.
- `probe_banner.lua` - the measurement instrument behind battle_banner:
  per-frame scanline table (NMI entry / flush start / flush end / post-
  INIDISP) plus $57D5, large-transfer flag/size, and a 44-frame
  screenshot burst across the banner window.
- `probe_57b9.lua` - write-watcher over $7E57B9-BF (OT6_FONTDIRTY's
  relocated home) with $7E57D5 as positive control; logs writer PCs.
- `battle_bushido.lua` - test for BP-Bushido: boost points pick Cyan's
  tech and vanilla's charge gauge is gone.  Cyan is not in the party at
  the opening guard fight, so he is installed into it the way
  the balance labs pin state: CHAR::CYAN into $3ED8, a Bushido-only
  command list at $202E (stride 12), the weapon SWDTECH flag in
  $3BA4/$3BA5 (without it UpdateCmd_02 greys the command out), and a
  pinned $2020 standing in for his level.  Asserts the clock is dead
  (150 settled in-window frames, one bar value, against vanilla stepping
  every 4 frames), the whole tier ladder including its learn-clamped rows,
  that Cleave (the `Oblivion` symbol) stays out of reach, the 3-BP spend
  cap, and that the chosen tech resolves: Quadra Slam's $58 reaches
  $3410, chips a slashing-weak guard, reveals the slash class, and
  consumes the boost with no regen.  (Names per CONTRIBUTING's FF3-US
  vocabulary rule; the test's own filename and the upstream
  `Bushido*`/`Oblivion` symbols stay as they are, because renaming symbols
  is churn against upstream and naming them here already covers it.)
- `probe_bushido.lua` - the measurement instrument behind it: logs the
  menu state, w7e7b82, pending boost and $3410 across the same install,
  and answers the questions the source alone does not: whether one A press
  reaches menu state $37, whether L/R still moves the boost inside that
  window, and what the bar does per frame.
- `battle_whelkwipe.lua` - test for the monster entry/exit wipe: the
  whelk retract cycle (FADE_DOWN/FADE_UP) sweeps the battle-field BG3
  region with a per-scanline scroll wave, so the field map must hold
  nothing but vanilla's tiles while the effect runs.
  Drives the fight passively (Heal Force) to both transitions, trips an
  exec callback on DoMonsterEntryExit (C2/E668), and asserts every
  animation frame at cell level: no OT6-claimed glyph char anywhere in
  the field map, every live hud line veiled to vanilla's $01ee fill
  (OT6_HUDVEIL $57BE is the wrapper's own end marker).  After each
  transition: hud gone with the head, hud repainted on return,
  glyphCanary.  No pixel compares, so it does not depend on the exact
  bytes of the savestate it loads.
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
holds `base_rom_for_comparison.sfc` (copy of the FF3us base image);
running any test against it instead of `build/ot6.sfc` is a quick A/B for
whether a failure is our code or the harness, and savestates cross-load
between the two images.

## Writing a test

**The input-driven rule (owner directive).**  A test or generator may inject
controller input and read emulated memory to assert things.  It may never
write emulated game state: no HP/MP pins, no forced kills, no boss clamps,
no cursor or menu-state pokes, no event-flag or RNG writes.  When we test
"can a person play this game," the script gets only the capabilities a
person has: pressing buttons and observing the result.  Determinism comes
from fixed, input-driven fixtures plus frame-exact input (the TAS way).
That property is transitive: a savestate or checkpoint generated by a poking
script is contaminated, and so is everything derived from it.

The rule is enforced mechanically.  `tools/check_state_writes.py` scans
every `.lua` here and fails `make test` on any write token not in
`tools/state_write_waivers.txt`, a burn-down list of pre-directive
exceptions that may only shrink; a stale waiver is itself a failure, so
prune it in the same change that earns it.  Do not add waivers to new code.

It is enforced twice.  For a file with no waivers, `lib/compose.py` arms a
runtime write gate in the composed script: the global `emu` becomes a proxy
whose write surface raises `[ot6] runtime write gate` at the call, closing
what a static scan cannot see (computed names, loadstring).  The lib keeps a
confined raw handle (`H.loadState` and the retry-blob path) for as long as
the lib's own waivers survive; deleting the last lib waiver flips every
composed script to strict automatically.  The handle's name is itself a
forbidden token, so reaching around the proxy fails the static check
instead.

The one sanctioned exception is **quarantined mechanism tests**: fault
injection whose inputs the game can only produce rarely or never on cue
(deliberate VRAM corruption for the font-restore path, the 1/65536
zero-checksum save, legacy-format codex migration).  These are unit tests
of mechanisms rather than claims about gameplay; they keep their waivers,
say so in their header comment, and may never produce fixtures.

House patterns for driving the game through real input: `gen_arvis.lua`
(real boss kill), `gen_moogle.lua` (multi-party set-piece, boosted fights,
retry ladder), `gen_scenario.lua`/`gen_rapids.lua` (menu-episode fighter,
bank-and-dump boost doctrine), `gen_sabin_gau.lua` (self-consuming capture
verification: reload your own capture and verify calm before publishing,
because a calm capture does not imply a calm reload).

A test is a list of steps handed to `H.run`; a `startFrame` callback
consumes them, one frame at a time (zero-frame steps like `H.call` chain
within a frame).  The step style below is the house pattern.  Coroutines
also work on this build; the step machine stays because the whole suite is
written in it.

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
`H.loadState("build/states/x.mss.lua")`, never by absolute path.  compose.py
resolves every reference against the running tree's own `build/states/` and
refuses a reference that resolves only outside the tree (including into a
nested worktree), so a worktree cannot boot a fixture generated from another
tree's ROM.
The gen_*.lua generators still carry the older absolute-path convention only
because their bytes are hashed into the savestate freshness stamps; behavior
is tree-local for them too (see compose.py's resolve_sidecar).

**Registering it in the suite.**  A test opts into `make test` with a
first-line marker in its own file: `-- @suite` (plain), `-- @suite slow`
(a long-runner; an LPT scheduling hint), or `-- @suite savestate=<fixture>`
(runs only once `make savestates` has generated `build/states/<fixture>.mss`).
Adding a test is thus a one-line edit to that test rather than to a shared
list; `tools/tests/suite.sh --list` shows what discovery resolved, and the
marker grammar is documented at the head of `tools/tests/suite.sh`.

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
- `H.sym("Name")` - the ca65 symbol's 24-bit SNES CPU address, derived from
  `ff6/rom/ff6-en.dbg` at compose time (so the argument must be a string
  literal; a variable resolves to nothing).  Mask `& 0x3FFFFF` for a
  `readRomByte/Word` file offset.  Use this instead of an address literal:
  literals go stale on every bank-`$F0`/`$C2`/`$C0` shift, and stale
  literals were the most recurring source of harness breakage.
  A name the linker emits more than once is a compose-time error rather
  than a guess: 3838 of this ROM's 98483 label names are non-unique, and
  `ExecCmd` is both field code and the battle command dispatcher.  Say which
  by naming the ca65 segment: `H.sym("ExecCmd@battle_code")`.  Segment names
  come from `ff6/cfg/ff6-en.cfg` and survive the bank shifts that move
  addresses, so a qualified reference is no more fragile than a bare one.
- `H.saveState(name)` / `H.loadState(sidecarPath)` - see savestate notes.
- `H.screenshot(tag)` - emits PNG via stdout; run.sh writes the file.
- `H.setPad(buttons)` - immediate raw input set (steps use this internally).
- FF6 battle signals: `H.monsterIds()`, `H.monstersPresent()`, `H.partyHp()`,
  `H.battleLoadStarted()` (HP table at $3BF4 populated),
  `H.battleActive()` (load started + monsters present + screen actually
  rendering, judged by screenshot PNG size), `H.screenLooksAlive()`,
  constants `H.MONSTER_IDS=$3F46`, `H.BATTLE_HP=$3BF4`.
  (Caveat: the six words at $3F46 are a liveness heuristic rather than clean
  IDs.  Monster #0 "Guard" is a valid 0x0000, empty slots read $FFFF, and
  healthy vanilla battles still show one stale word there, e.g. 874B, left
  over from earlier RAM traffic.  Treat `monstersPresent() > 0` as "battle
  has occupants", nothing finer.  To identify a specific fight, match the
  formation species words at $57C0 via `H.formationHas`, conditioned on
  `battleLoadStarted()`.)
- Field navigation (`H.fieldX/Y`, `H.hasControl`, `H.tileAligned`,
  `H.dialogWaiting`, `H.canStep`, `H.movePress`, `H.bfsPath`, `H.navTo`,
  `H.clearBattle`): see `docs/playing-headless.md` for the RAM tables and
  the design.  Moves are the four cardinals plus the four diagonals a
  left/right press produces on a `$c0` tile; `H.movePress(move)` gives the
  button that executes one.
- World-map navigation (`H.worldMode`, `H.worldId`, `H.worldX/Y`,
  `H.worldAligned`, `H.worldPassable/worldCanStep`, `H.worldBfs`,
  `H.worldHasControl`, `H.worldNavTo`, and `H.route`, the field/world
  handoff driver): see `docs/research/world-map-nav.md` for the RAM
  tables and every measured mechanism claim.
- `H.phaseWalk(tx, ty, spec)` -- crosses a timed-tilemap room (two
  complementary floors swapped on an event timer, e.g. Sealed Gate
  BASEMENT 2) by planning over the union graph of (x,y,phase) nodes and
  executing swap-window steps on a measured clock; `H.chaseTalk(objIdx,
  maxFrames, what)` -- talk to a wandering NPC, stopping the moment a
  choice list is up.  Both are documented at their definitions in
  `lib/ot6_field.lua`, including the measured rewrite-window mechanism
  `phaseWalk` plans against.

## Mesen 2.1.1 Lua API facts (all verified empirically on this binary)

- Runner: `Mesen --testrunner <rom> <script.lua>`; process exit code is the
  integer passed to `emu.stop(code)`.
- Lua 5.4.  `print()` -> stdout.  `emu.log()` -> the script log, which
  no headless process ever reads; it is not mirrored by
  `--enableStdout`.  `load()` (from a string) works.
  `io` / `os` are nil and `dofile()` / `loadfile()` raise, but that is a
  setting rather than a property of the sandbox:
  `Debug.ScriptWindow.AllowIoOsAccess` (default false;
  `ScriptingContext.cpp:66`, `Lua/lauxlib.c:776`).  Turn it on and all four
  work; Mesen's own error text names the setting.  `pin_test_saves.py`
  already writes that config section.  We leave it off and compose scripts
  flat (see compose.py) to keep runs hermetic.
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
  `emu.loadSavestate(blob)` takes one back.  Both may only be called
  "inside an exec memory operation callback for the main CPU"; calling
  them from an event callback raises that exact error.  The library wraps
  them in a one-shot trampoline (`H.requestSaveState()` /
  `H.requestLoadState(blob)`): register an exec memory callback over
  $000000-$FFFFFF, do the work on its first fire (the next executed
  instruction), remove the callback from within itself, harvest the result
  a frame later.  The step constructors `H.saveState(name)` /
  `H.loadState(sidecar)` package that dance.  (`saveSavestateAsync`-style
  slot functions from Mesen 1 do not exist in this build.)
- Screenshots: `emu.takeScreenshot()` works headless and returns a
  256x224 RGB PNG as a string; it returns an empty string during the first
  ~100 frames (before the first decoded frame).
- `emu.getState()` returns a huge table (cpu.*, ppu.*, spc.*,
  internalRegisters.*, frameCount...).  Handy: `cpu.k/cpu.pc` (crash triage),
  `ppu.screenBrightness`, `internalRegisters.enableNmi`.
  The keys are flat dotted strings: `s["ppu.scanline"]`, `s["cpu.pc"]`.
  `s.ppu` is nil, and indexing it as if it were nested throws; inside a
  callback the throw is not logged and the rest of that callback invocation
  is skipped.
  It works inside exec-memory and event callbacks too; `ppu.scanline`
  (0-261, NMI fires at 225) is how battle_banner samples vblank timing.
- Narrow exec memory callbacks on ROM code use CPU-bus addresses and do
  fire for bank C1/C2 (`emu.addMemoryCallback(fn, emu.callbackType.exec,
  0xC10BA7, 0xC10BA7)` fires once per battle NMI).  They fire for bank F0
  too: `battle_reveal`, `battle_reveal_poweron` and `probe_reveal_trace`
  all hook $F00000 and pass.  PRG-file-offset forms fire
  never (0x010BA7) or on the wrong thing; use the bus form.
- Memory callbacks survive `emu.loadSavestate()`; nothing in the load path
  clears them (`SaveStateManager.cpp` only raises `StateLoaded`).
  `battle_banner` relies on this: it registers four exec callbacks before
  its `H.loadState` and records through to a PASS.
- Reading $2137/$213D via `emu.read(..., emu.memType.snesMemory)` does not
  trigger the H/V counter latch side effect; both return 0.  Sample the
  scanline from Lua via `getState()["ppu.scanline"]`; from 65816 code the
  real register latch works fine (the flush's re-lay budget gate does it).
- `emu.getScriptDataFolder()` returns `true` (not a path) in this build -
  don't rely on it.

### Getting binary data out (no io library)

Scripts cannot write files.  The harness base64-encodes blobs to stdout as
`[b64:<tag>] <chunk>` lines (`H.emitBlob`); `run.sh` runs
`lib/decode_b64.py` afterwards to reassemble them:

- `*.mss` tags -> `build/states/<tag>` **plus** `<tag>.lua` sidecar
  (`return "<base64>"`) so a later test can `dofile` the state back in and
  `emu.loadSavestate` it; that is how `battle_smoke.lua` loads the battle.
- anything else -> `build/states/shots/<tag>` (screenshot PNGs).

## Working notes

### Screenshots headless

`emu.takeScreenshot()` produces valid PNGs under `--testrunner` with no
window/GUI, suitable for visual verification of UI work.
Empty-string result only occurs in the first ~2 s before the video decoder
has a frame.  `emu.getScreenBuffer()` also exists (table of RGB ints) if raw
pixels are ever needed.

### Determinism (by construction)

Test runs are bit-reproducible: identical scripts pass at identical frames
with byte-identical artifacts (savestates and screenshots), serial or
parallel.  Three harness pins make it so:

- `pin_test_saves.py` pins `Snes.RamPowerOnState = "AllZeros"`.  FF6 reads
  uninitialized RAM, so Mesen's default `Random` fed the RNG different
  garbage every boot: battle-trigger frames drifted (+-frames, extra
  encounters) and generated savestates embedded the garbage.
- `pin_test_saves.py` pins `Snes.DisableFrameSkipping = true`.  Frame-skip
  picks rendered frames by host timing, so screenshots (and the framebuffer
  inside savestates) varied run-to-run, worse under parallel load.
- `run.sh` wipes `<saves>/*.srm` before every launch.  The testrunner
  flushes battery on exit and reloads it next boot, so a stale srm is a
  hidden cross-run coupling channel; tests that need a save inject it
  explicitly (SRM sidecars).

Battery SRAM (the OT6 weakness codex included) rides along in Mesen
savestates (markers in banks $30 and $31 are both restored by
`emu.loadSavestate`), so post-load SRAM is a pure function of the fixture's
own generated bytes.  `H.loadState` therefore performs no codex
normalization of its own, because normalizing would be both a state write
and an overwrite of fixture content.  Runs that boot fresh instead of
loading get their codex pages formatted lazily by the ROM itself
(`Ot6CodexEnsure` and friends, `ff6/src/battle/ot6_codex.asm`).

Scripts still key off RAM signals rather than absolute frame numbers,
because every ROM or route edit shifts them.
- `emu.createSavestate()/loadSavestate()` round-trip works from Lua, but
  only inside an exec memory callback (see the trampoline above);
  `probe16.lua` is the regression test for the mechanism.

### Input injection

- `H.setPad()` records the held-button set; an `inputPolled` event callback
  pushes it into the emulator with `emu.setInput(input, 0)` on every poll.
- The game polls once per frame via NMI auto-joypad; 4+ frame holds are
  reliably seen, 8 used for title Start presses.
- Dialog/menu-text advancing is edge-triggered: a held A yields exactly one
  page; multi-page text needs press-release cycling (4 frames on / 4 off).
- `probe23.lua` is the positive control: after loading `first_battle.mss`,
  A must open the MagiTek submenu and B must close it (screenshot bytes
  compared).  `probe_input.lua` shows held input drives movement across a
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
  reason is ours rather than Mesen's: `run.sh` feeds that path to
  `pin_test_saves.py` as the base it pins on top of, and it opens it
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
  home from the password database rather than the environment; the binary
  carries the string `GetHomeDirectory:TryGetHomeDirectoryFromPasswd`.
  Measured: run the testrunner with `HOME` pointed at a scratch dir and it
  still writes its `.srm` and `Debugger/*.cdl` into the real profile;
  add `CFFIXED_USER_HOME` (Core Foundation's own home override) and
  everything lands in the scratch dir instead, including settings, saves,
  cdl, and the ~29MB of native libs Mesen seeds into a fresh home.
  Portable mode still beats both, so a bundle with a `settings.json` ignores
  `CFFIXED_USER_HOME` entirely.  This is what `run.sh` uses to keep
  parallel workers apart without copying the emulator.
- stdout also carries `[CPU] Uninitialized memory read: ...` debug spam;
  filter for `[ot6]` / `[probe]`.  It is read-before-write tracking (the
  debugger flags any address read before it has ever been written this
  power-on) and says nothing about the RAM fill: it appears under
  `AllZeros` just as it does under `Random` (89 vs 145 lines over 600
  frames, measured).  It only shows up headless because the testrunner
  force-enables the debugger via Mesen's `ConsoleMode` flag.
- **A 255 exit with truncated stdout means a wall-clock cap expired rather
  than a mystery crash.**  The testrunner defaults to 100 seconds (run.sh
  passes `--timeout=600`) and Mesen's per-Lua-slice watchdog defaults to 1
  second (`pin_test_saves.py` pins `Debug.ScriptWindow.ScriptTimeout = 30`).
  stdout is block-buffered, so output stops well before the actual death.
  Any error at script load has the same signature: no callbacks register,
  the emulator free-runs, the cap kills it.  A bare syntax error looks
  identical to a crash.
- **Script errors are invisible headless.**  `--enableStdout` mirrors the
  emulator message log (`MessageManager`); Lua errors and watchdog kills go
  to the script log, a separate 500-row buffer only the GUI script window
  ever reads.  There is no bridge.  `print()` is the only channel out of a
  script, so a test that goes quiet gives you no information; add prints.
- Coroutines, runtime `dofile` and `emu.getState()` in a poll loop are all
  fine: coroutines run clean 4/4 at 20k frames, `dofile` raises a tidy error
  naming the setting that enables it, and `battle_banner` calls
  `getState()` four times a frame in production and passes.
- `emu.stop()` from the initial script body works; from callbacks it works
  too (used everywhere here).
- No `timeout` command on macOS; not needed since `H.run` guarantees exit,
  but `( cmd & pid=$!; (sleep N; kill $pid) & wait $pid )` is the fallback
  pattern if a script without the library must be watchdogged.
