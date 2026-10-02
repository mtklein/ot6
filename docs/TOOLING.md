# OT6 Tooling

Everything below is working on this machine (macOS arm64).

## The build

The whole game builds from source via the **everything8215/ff6
disassembly** (GPL-3.0), vendored at `ff6/` (upstream 1ea47b5). The
unmodified tree reproduces retail FF3us 1.0 byte-for-byte (CRC32 A27F1C7A),
including retail's incorrect internal SNES checksum. OT6 code lives in the
ordered `ff6/src/battle/ot6_*.asm` modules (emitted by `ot6.asm` into
expanded bank $F0) plus minimal jsl shims in vanilla banks.

`python3 configure.py` writes `build.ninja`; `ninja` builds and tests
everything (qualification, the checkpoint drift gate included), and
`ninja build/release/ot6-vX.Y.zip` goes on to the release preflights and
the zip. There are no aliases: any narrower need is a real output path
(`ninja ff6/rom/ff6-en.sfc`, `ninja build/results/suite/battle_break.ok`).
The graph regenerates itself when `configure.py`, the savestate graph,
`VERSION`, or any globbed directory changes.

### Cuts and the one graph

A `.mss` belongs to one ROM, so after a ROM change every generated state
regenerates, each from the one before it: the graph is one line, played
once from power-on. It is cut where the play saves (at a save point, or on
the world map, where the game lets you save anywhere): an entry in
`tools/tests/savestate_graph.py` with both `prev=` and `checkpoint=` is a
cut, and `prev=` names the state whose play ends where the save begins.
The leg before it ends by saving there through the real Save UI and
asserting the checkpoint's contract as its exit (`H.saveAtCheckpoint`,
`lib/ot6_contract.lua`); its run captures the battery into
`build/checkpoints/<key>/`, a seal edge checks it holds the declared save,
and the leg after it Continues that capture and asserts the same contract
as its entry (`H.bootCheckpoint`). A cut is where the play goes through the
real Continue screen; it does not make the legs independent.

Two variants. In the Vector arc the save is made by a separate,
capture-only script booted from `prev`'s savestate rather than by
`prev`'s own run: `cutter=` names it (`gen_post_opera_checkpoint` from
blackjack, `gen_mrf_save_room_checkpoint`, `gen_n024_save_checkpoint`,
`gen_minecart_platform_checkpoint`, `gen_terra_returned_checkpoint` from
n128_won). And `saves=` marks a run that ends by saving a tracked
checkpoint no cut boots yet: the frontier (`wor-falcon-v1`) and
`crescent-landing-v1` (thamasa_night boots the savestate). The graph's
`CAPTURES` lift the five checkpoints nothing in the graph boots
(`world-sfigaro-v1`, `sfigaro-basement-v1`, `train-engineer-v1`,
`terra-caves-v1`, `vector-escape-v1`) with their capture-only cutters. The
line runs from power-on through the Opera, the Vector arc, the Floating
Continent and every World of Ruin leg to wor_falcon; the World of Balance
-> World of Ruin crossing is a plain savestate link (wor_landing ->
wor_island).

Every tracked checkpoint in `tools/tests/checkpoints/` is made by one run on
the graph (configure refuses a graph that leaves one out), and suites in
`configure.py`'s `TEST_ENV` and by-hand runs boot the tracked copies. The
drift gate, `build/checks/checkpoint_drift.ok` in the default, holds each
tracked copy to the graph's capture byte for byte (play time and checksums
aside; the graph is deterministic), and explains a drift in play terms
(`tools/tests/lib/checkpoint_drift.py`): every character's level,
experience, HP/MP and gear, gil and the bag, story switches, encounter
counters, spells and skills, the OT6 codex, and any other differing byte by
address. A drifted checkpoint is re-cut from the graph's capture and
committed:

    python3 tools/tests/lib/checkpoint_drift.py --recut <key>...

`--recut` refuses a capture whose stamp is not current
(`lib/stamps.py`). Re-cutting re-runs the suites that boot that checkpoint
and nothing in the graph, which boots its own captures. The contracts stay
light: a suite that needs a level or an item asserts its own precondition.

## Installed pieces

Homebrew pieces are in the root `Brewfile`; `brew bundle` installs them.
The non-brew pieces need the manual steps at each bullet.

- **cc65** (ca65/ld65) — via Homebrew; the sole production compiler/linker
  path. Any `python3` ≥3.9 works; the asset encoders additionally need
  `python3 -m pip install numpy`.
- **ninja** — via Homebrew.
- **ffmpeg** — via Homebrew; used only by the playthrough recorder
  (`tools/stream/`).
- **Flips CLI** — binary at `tools/bin/flips` (git-ignored). Rebuild:
  clone github.com/Alcaro/Flips, `make CFLAGS=-O2`, copy `flips` in.
- **Mesen** — `tools/Mesen.app` is OT6's build of MesenCE 2.2.1 (OT6's
  Mesen, below) on both Macs; a stock 2.2.1 build is kept at
  `~/mesen-reference/Mesen.app` for build.sh's smoke test, and the 2.1.1
  builds run until 2026-10-01 at `~/mesen-patched/2.1.1-*` (the official
  2.1.1 release at `~/mesen-official/Mesen.app`).
  Debugger has breakpoints/memory watch/trace and ca65 symbol integration;
  the build emits `ff6/rom/ff6-en.dbg` for source-level debugging.
- **sdl2** — via Homebrew; a hard Mesen runtime dependency.
  MesenCore.dylib's only non-system link is
  `/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib` (OT6's build's:
  `/opt/homebrew/opt/sdl2-compat/lib/...`, the same keg today), the .app
  bundles no SDL, and the core dylib only exists once the .NET host extracts
  it to `~/Library/Application Support/Mesen2/` — a machine without sdl2
  dies on first launch as DllNotFoundException → Abort trap 6.
- **dotnet@8** — via Homebrew (keg-only); only for building OT6's Mesen
  (`tools/mesen/build.sh` finds it), not for running it.

Only the ROMs, `build/`, `build.ninja`, `tools/Mesen.app`, and `tools/bin`
are git-ignored. Ripped assets are tracked.

## Mesen facts the harness depends on

- With no config file, Mesen ignores `--testrunner` and launches the GUI
  setup wizard. Its home folder is `~/Library/Application Support/Mesen2/`;
  an existing `settings.json` (even `{}`) skips the wizard.
- A `{}` profile connects no controller, and `emu.setInput(pad, 0)` is
  inert without a SnesController on port 0. `pin_test_saves.py` forces
  `Snes.Port1.Type = SnesController`; if you drive Mesen yourself outside
  the harness, connect a controller first.
- Move the home folder with `CFFIXED_USER_HOME`, not `$HOME`: Mesen
  resolves it via .NET's `SpecialFolder.ApplicationData` →
  `NSSearchPathForDirectoriesInDomains`, which reads the home from the
  password database and ignores `$HOME`. A `settings.json` beside the
  binary (portable mode) overrides both.
- Mesen is ad-hoc signed but not notarized, so the first GUI launch may
  need right-click → Open, and every new bundle path costs a ~5s
  Gatekeeper scan of the 413MB bundle (`xattr -cr` does not suppress it;
  the trigger is the path). The harness keeps one shared test bundle
  machine-wide for this reason.
- Mesen Lua: `emu.createSavestate`/`loadSavestate` must run inside an exec
  memory callback, not event callbacks. `dofile` and file writes are
  gated by the default-off `Debug.ScriptWindow.AllowIoOsAccess`; the
  harness leaves it off, composes scripts flat, and tunnels artifacts as
  base64 over stdout.
- ca65 width state is inherited across `.include`: declare `.a8/.a16/
  .i8/.i16` at the top of every new asm file.

## Linux worker

`px13` (`ssh px13.local`: Ubuntu 26.04, Ryzen AI 9 HX 370 12c/24t, 29 GB)
runs the same scripts. At the same commit as a Mac it built the same ROM
byte for byte, and its generators and suites played the same games: the same
verdicts, frames and screenshots, log lines differing only in byte counts
and state hashes, and savestates whose emulated machine is byte-identical
(build/attempts/wt/linux-px13/). Its `.mss` files are not byte-identical to
the Macs': the machine stream compresses differently, most likely because
miniz (level 1) takes an x86-only deflate path; that hasn't been confirmed
by compressing the same stream both ways. So a state's artifact hash, the stamps that record it,
and the `sha=` in a log line naming a loaded state differ between the two
machines. Each machine generates its own chain. A copied state still plays
the same (battle_banner on a Mac from px13's battle_entry: same verdict and
screenshots, build/attempts/review-linux-px13/xload-summary.txt), and a
coherent copied set (each `.mss` with its stamp) verifies fresh; mixing a
copied parent into a local chain marks its descendants stale and ninja
regenerates them. To compare a state across
the two, inflate its zlib streams (the screen, then the machine) and compare
those.

- **Packages** (apt): `git cc65 ninja-build python3 python3-numpy
  libsdl2-2.0-0 unzip`. No compiler is needed: nothing in the build or the
  harness compiles C (building OT6's Mesen does; see OT6's Mesen). The release zip (`ninja build/release/ot6-vX.Y.zip`) also wants `tools/bin/flips`, which
  would need a compiler to build (see the Flips bullet above), so release
  packaging stays on a Mac.
- **Mesen**: OT6's build (OT6's Mesen, below), one self-contained binary
  at `tools/Mesen-linux/Mesen`, built on px13 by `tools/mesen/build.sh`.
  It needs `libsdl2-2.0-0` and nothing else extra to run. The official
  2.1.1 release binary (`Mesen_2.1.1_Linux_x64.zip`, binary sha256
  `ae43f143...3b41`) is kept at `~/mesen-official/Mesen`. Every run log names the binary that ran (`[emulator] <sha256> ...
  core=<sha256>`, the second the MesenCore it unpacked and loaded), and so
  does every generated fixture's stamp (`emulator <sha256>`, a record, not
  a binding).
- **Settings**: `mkdir -p ~/.config/Mesen2 && echo '{}' >
  ~/.config/Mesen2/settings.json`. That is the source profile
  `pin_test_saves.py` copies, as the Mac's `~/Library/Application
  Support/Mesen2/settings.json` is (which is also `{}`); run.sh refuses to run
  without it.
- **Seeding**: clone to `~/ot6`, scp `Final Fantasy III (USA).sfc` into it
  from a Mac, `python3 configure.py`, `ninja build/ot6.sfc`. Savestates come
  from running `ninja` there. A worktree seeds from `~/ot6` with
  `tools/worktree-setup.sh`, as on the Macs.

What differs from macOS:

- Mesen's home is `$XDG_CONFIG_HOME/Mesen2` (else `~/.config/Mesen2`), so
  each worker gets its own `XDG_CONFIG_HOME` where a Mac gets its own
  `CFFIXED_USER_HOME`. The shared copy is `~/.cache/ot6/Mesen-test/`. The
  native libraries are packed inside the binary, and Mesen unpacks them into
  each fresh home itself (about 0.05 s).
- The official build dies as it loads `MesenCore.so` (`std::bad_cast`
  thrown from a static `std::regex` in `Base6502Assembler.cpp`) once .NET's
  ICU has pulled in the system libstdc++: MesenCore links its own GCC 12
  libstdc++ statically and the two collide. `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`
  keeps ICU out and Mesen runs.
- No `caffeinate`: `systemd-inhibit --what=idle --who=ot6 --why=<job>
  <command>` is what an ssh session is allowed without a password (sleep and
  lid-switch locks need interactive polkit auth). A closed lid still
  suspends the machine. live.py's `--peer px13.local` uses the same wrapper.

## OT6's Mesen

The harness runs OT6's build of MesenCE 2.2.1: tag `ot6-2.2.1-1` of OT6's fork,
github.com/mtklein/mesen, which adds four small commits to MesenCE's
`2.2.1` tag. `tools/mesen/EMULATOR` pins the commit and
`tools/mesen/build.sh` builds it (README.md there). The script-only change
stops Mesen's debugger keeping the per-access records only its windows
read (the code/data log, access counters, call stack, event log) when
`MESEN_SCRIPT_ONLY=1`; the screenshot change makes `emu.takeScreenshot`
return the frame just finished instead of sometimes the one before; the
third lets the .NET 10 SDK build it. On px13 and on the Air it played six
legs (the full gen_zozo2_arrival, battle_rage, a cold boot, an SRAM
Continue, an in-game save, wipe_reclass) exactly as a stock 2.2.1 build
did: every log line but `[CPU]`/`[emulator]`, every screenshot, every
`.mss` and the captured `.sram` byte for byte
(build/attempts/wt/mesen-fork/px13/eq/, air/eq/). Until 2026-10-01 the same
two code changes ran on Mesen 2.1.1, about 1.4x as fast as the official
binary (build/attempts/wt/mesen-lean/, build/attempts/wt/mesen-mac/); that
build is the fork's tag `ot6-2.1.1-1`. Stock 2.2.1 plays OT6 a few frames
differently from 2.1.1, because of MesenCE's DMA clock-counting fix
1da6c1ad (build/attempts/mesence-eval/).

- `tools/mesen/EMULATOR` is a regeneration input like the ROM: every
  generate, capture and suite edge depends on it (configure.py), so
  changing it regenerates every fixture and re-runs every test, and the
  drift gate then asks for every checkpoint whose capture moved to be
  re-cut. Change it in the same commit as a deployment, and deploy on
  every machine (px13, the Air, this Mac) before regenerating anywhere: a
  machine still running the old build would regenerate on the old
  emulator, and nothing checks which build a run used beyond the stamp's
  `emulator` record.
- run.sh exports `MESEN_SCRIPT_ONLY=1` for every run except a coverage run
  (OT6_COVERAGE), which needs the code/data log; a stock build ignores
  the variable.
- `OT6_MESEN_APP=<dir or .app> OT6_MESEN_CACHE=<own cache>` runs another
  emulator for one invocation without touching the shared copy.
- Every OT6 build keeps frame pointers (`-fno-omit-frame-pointer
  -mno-omit-leaf-frame-pointer`, owner 2026-10-01), so a profile can be
  taken any time.
- Building needs a compiler and the .NET SDK (Linux: apt `clang lld zip
  libsdl2-dev zlib1g-dev dotnet-sdk-10.0 dotnet-sdk-aot-10.0`; macOS: the
  Xcode command line tools and the Brewfile's `dotnet@8`); the build ends
  with a smoke test against a stock 2.2.1 build each machine keeps in
  `~/mesen-reference/` (`build.sh --stock`).
- A machine uses it once the emulator in its main tree is replaced by the
  build (README.md, "Deploying"): `tools/Mesen-linux/Mesen` on px13
  (executable `b5a407c3...8c54`, core `045e8526...a568`), `tools/Mesen.app`
  on the Macs, both running the same Air-built bundle (executable
  `e96f5fdf...7b37`, core `f5821dc3...3b57`). The builds they replaced are
  kept in `~/mesen-patched/` as `2.1.1-<sha8>-Mesen[.app]`, with their
  `.buildinfo`.

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP, status-byte reality.
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
