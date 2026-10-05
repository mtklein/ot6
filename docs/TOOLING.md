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
everything (qualification), and `ninja release` goes on to the release
preflights and the zip. Any narrower need is a
real output path (`ninja ff6/rom/ff6-en.sfc`,
`ninja build/results/suite/battle_break.ok`). The graph regenerates itself
when `configure.py`, the savestate graph, `VERSION`, or any globbed
directory changes.

To run a gate in the background, `sh tools/gate.sh -k 0 [target...]`
passes its arguments to ninja, exits with ninja's status and ends with
the FAILED edges (the log in `build/gate.log`). A wrapper like
`(ninja ...; echo $?)` exits with echo's 0, and a red gate has been read
green that way.

Don't edit `tools/tests/run.sh` or any other shell script while a `ninja`
or `run.sh` is executing it: bash reads scripts incrementally, and the
running instances resume at shifted offsets and fail.

### Cuts and the chain from power-on

A `.mss` belongs to one ROM, so after a ROM change every generated state
regenerates, each from the one before it. To keep that from being one long
serial run, the chain is cut where the play saves (at a
save point, or on the world map, where the game lets you save anywhere):
an entry in
`tools/tests/savestate_graph.py` with both `prev=` and `checkpoint=` is a
cut, and `prev=` names the state whose play ends where the save begins.
The leg before it ends by saving there through the real Save UI and
asserting the checkpoint's contract as its exit
(`H.saveAtCheckpoint`, `lib/ot6_contract.lua`); the leg after it
Continues the save and asserts the same contract as its entry
(`H.bootCheckpoint`). Qualification boots each cut leg from the tracked
checkpoint in `tools/tests/checkpoints/`, which still loads after a ROM
change, so the legs regenerate at once.

Two variants. In the Vector arc the save is made by a separate,
capture-only script booted from `prev`'s savestate rather than by
`prev`'s own run: `cutter=` names it (`gen_post_opera_checkpoint` from
blackjack, `gen_mrf_save_room_checkpoint`, `gen_n024_save_checkpoint`,
`gen_minecart_platform_checkpoint`, `gen_terra_returned_checkpoint` from
n128_won). Qualification never runs a cutter. And `saves=` marks a run
that ends by saving a tracked checkpoint no cut boots yet: the frontier
(`wor-falcon-v1`) and `crescent-landing-v1` (thamasa_night boots the
savestate).

`ninja chain` plays the whole chain from power-on instead: `chain_<state>`
copies of every state from the first cut on, each booted from the copy
before it and, at a cut, from the save the producing copy just made
(captured with `OT6_CAPTURE_SRM` and sealed into
`build/checkpoints/<key>/`); a cutter runs from the copy of its `prev`,
publishes no state, and records the ROM it played on in
`build/checkpoints/<key>.rom`. The line runs from power-on through the
Opera, the Vector arc, the Floating Continent and every World of Ruin leg
to wor_falcon. No boundary on it lacks a state to chain from: the World of
Balance -> World of Ruin crossing is a plain savestate link (wor_landing ->
wor_island, no save between), and wor-start-v1 is made by wor_start's own
run from wor_island's save. It is the one alias besides `release`,
because the chain's last state moves as cuts and legs are added.
`ninja release` depends on it. Run it too when a leg's exit contract
fails in qualification: the chain says whether the story still plays
through. It is long and serial (the World of Ruin legs alone carry
3600-7200 s caps); bare `ninja` never runs it.

Every tracked checkpoint something boots (a state, or a suite in
`configure.py`'s `TEST_ENV`) is captured on that line. The rest are named
in the graph's `NOT_GATED` with the reason (today none: the five that
stood there, booted by nothing, were retired with their cutters, #356).
Qualification's `checkpoint_coverage` check
(`savestate_ninja.py --coverage`) refuses any other tracked checkpoint, so
a new leg that boots a checkpoint with no `prev=` fails `ninja`.

A tracked checkpoint drifts from today's play as the route changes above
it. At each capture the chain prints the drift (`tools/tests/lib/checkpoint_drift.py`),
explained in play terms: every character's level, experience, HP/MP and
gear, gil and the bag, story switches, encounter counters, spells and
skills, the OT6 codex, and any other differing byte by address.
`ninja release` fails while any tracked checkpoint's battery differs from
its fresh capture byte for byte (play time and checksums aside; the chain
is deterministic), or while a capture is older than today's generator, lib
halves or ROM. Re-cut at every release, and during a cycle whenever the
report shows a material change:

    ninja chain
    python3 tools/tests/lib/checkpoint_drift.py --recut <key>...

`--recut` copies the chain's sealed capture over the tracked checkpoint
(any key the chain captures, World of Ruin legs and cutters included);
then commit and qualify again. The contracts stay light: a suite that
needs a level or an item asserts its own precondition.

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
- **openjdk@21** and **android-commandlinetools** — via Homebrew; only
  for the Android patcher APK (below), which only `ninja release` builds.

## Android patcher

`android/` is OT6 Patcher, a small Android app (plain Java, no libraries)
shipped as `ot6-vX.Y.apk` on each GitHub release so Obtainium can keep a
handheld current. It carries the release's .bps. Setup is one step: the
player grants the folder holding their ROM, and the app finds the ROM there
by size and CRC32 (`RomScan.java`; a 512-byte copier header is stripped),
applies the patch, checks the target CRC32 and writes `OT6.sfc` beside it.
Picking the ROM file is the fallback. After every update a
`MY_PACKAGE_REPLACED` receiver does it again, silently: the remembered ROM
if it still matches, else a fresh scan. Results go to the app's settings
and logcat (tag `OT6Patcher`), never a notification; the app asks for no
permissions. Installs set up by the first v0.23 build (a picked ROM plus an
output folder) keep working unchanged.

Built with the plain SDK tools by `tools/android/build_apk.sh` (aapt2,
javac, d8, zipalign, apksigner; no Gradle). The pieces, as installed on
this Mac (the release machine) on 2026-10-02:

```sh
brew bundle    # openjdk@21 (21.0.12.1), cask android-commandlinetools
JAVA_HOME=/opt/homebrew/opt/openjdk@21 sdkmanager \
  --sdk_root=/opt/homebrew/share/android-commandlinetools \
  "build-tools;35.0.1" "platforms;android-35"
```

Every release machine carries the same pieces, so any of them can cut a
release. On px13 (Linux, 2026-10-04): `apt-get install openjdk-21-jdk-headless`,
the command-line tools unpacked to `~/android-sdk/cmdline-tools/latest`, and
the same `sdkmanager --sdk_root=$HOME/android-sdk "build-tools;35.0.1"
"platforms;android-35"`; the keystore at `~/.config/ot6/android-release.jks`
and its password in `~/.config/ot6/android-release.pass` (mode 600), which
`build_apk.sh` reads where there is no Keychain.

`tools/android/env.sh` pins those versions (minSdk 26, targetSdk 35) and
finds them through `JAVA_HOME` and `ANDROID_HOME` when set; a missing
piece stops the build with the line above. The ninja edges:

- `build/checks/android_bps.ok` runs the app's BPS code
  (`android/src/.../Bps.java`) on the JVM: the patch must rebuild
  `build/ot6.sfc` from the base ROM byte for byte, and a corrupted patch,
  a wrong ROM and a short ROM must be refused (`android/test/BpsTest.java`).
  It also runs the folder scan: the ROM found by CRC32 among other files,
  a copier-headered copy matched, OT6.sfc never a candidate, wrong-size
  files never read, and nothing chosen when nothing matches.
  It needs a JDK only, and no qualification.
- `build/release/ot6-vX.Y.apk` carries `build/android/ot6.bps`, made by the
  release patch's own flips command from the same two ROMs, so it builds
  without qualification. versionName is VERSION exactly, with no "v":
  Obtainium reconciles a release tag `v0.24` with an installed `0.24` but
  not the other way round (its `reconcileVersionDifferences` takes the
  installed version as the template). versionCode is
  major×1000000 + minor×10000 + patch×100 + (N for `-rcN`, else 99), so
  0.24-rc1 → 240001 < 0.24 → 240099 < 0.24.1 → 240199; another VERSION
  shape fails only this edge, saying so.
- `build/checks/android_apk.ok` (`tools/android/verify_apk.sh`):
  `apksigner verify --print-certs` must show the certificate pinned in
  `android/release-cert.sha256`, `aapt2 dump badging` the package
  `io.github.mtklein.ot6patcher`, the label "OT6 Patcher", the versionCode,
  versionName, minSdk and targetSdk, no permissions and not debuggable (a
  test build fails), and the APK must carry the patch the host check tested.
- `build/checks/android_apk_release.ok`: that patch is byte for byte the
  qualified release .bps (so this one needs qualification).

`ninja release` builds all of them, so a release needs the JDK, the SDK and
the signing key; bare `ninja` builds none of them. Without qualification,
`ninja build/release/ot6-vX.Y.apk build/checks/android_apk.ok` builds and
checks the APK alone.

**The signing key.** Installed copies accept updates signed with one key
only, forever. It lives outside the repo at
`~/.config/ot6/android-release.jks` (PKCS12, alias `ot6`, certificate
SHA-256 `e27bba94…0a9d49`, the full digest in `android/release-cert.sha256`);
its password is the login Keychain item `ot6-android-release` (account
`ot6`), which the build reads with `security find-generic-password -w`.
Back both up. A missing keystore stops the build rather than making a new
key; `tools/android/new_keystore.sh` made the first one and refuses to
replace it.

**Test builds** install beside a player's copy when built with
`OT6_APK_PACKAGE=io.github.mtklein.ot6patcher.test`: their own settings,
their own update broadcasts, and the label "OT6 Patcher TEST". They are
debuggable, so `adb shell run-as io.github.mtklein.ot6patcher.test cat
shared_prefs/ot6.xml` shows the last result.

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
  harness compiles C (building OT6's Mesen does; see OT6's Mesen). `ninja release` also wants `tools/bin/flips`, built
  on px13 from the Flips source (the Flips bullet above), plus the
  Android pieces under "Android patcher" and `gh`. Every machine can cut a
  release; none is special.
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

The harness runs OT6's build of MesenCE 2.2.1: tag `ot6-2.2.1-4` of OT6's fork,
github.com/mtklein/mesen, which adds seven small commits to MesenCE's
`2.2.1` tag. `tools/mesen/EMULATOR` pins the commit and
`tools/mesen/build.sh` builds it (README.md there). The script-only change
stops Mesen's debugger keeping the per-access records only its windows
read (the code/data log, access counters, call stack, event log) when
`MESEN_SCRIPT_ONLY=1`; the screenshot change makes `emu.takeScreenshot`
return the frame just finished instead of sometimes the one before; the
third lets the .NET 10 SDK build it; the fifth to seventh (#394) draw only the
frames a script asks for (`emu.setRenderOnDemand`, `emu.requestRender`;
the harness asks for the few it reads; a frame not drawn still evaluates
the lines that set the PPU's palette-lookup address) and make the
debugger's hot paths test inline whether a script callback could run
before calling into it (README.md there, "Render on demand" and "Script
callbacks, paid per use"). On px13 and on the Air the first four played six
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
  generate, chain and suite edge depends on it (configure.py), so changing
  it regenerates every fixture and re-runs every test, and the chain's
  captures then make `checkpoint_drift.py` ask for every cut checkpoint to
  be re-cut. Change it in the same commit as a deployment, and deploy on
  every machine (px13, the Air, this Mac) before regenerating anywhere.
  Builds are deployed per pin (`~/mesen-pins/<commit>/`, README.md
  "Deploying"), so a new pin's deployment leaves trees on the old pin
  running. run.sh refuses to run on a machine whose deployed build is not the pinned
  one (it reads the `<repository> <tag> <commit>` record build.sh packs
  into the executable, `tools/mesen/buildinfo.py`; `OT6_MESEN_APP` is
  exempt), logs that commit on the `[emulator]` line (`commit=`), and each
  stamp records it as `pin <commit>`: `compose.py --check-states` reads a
  fixture made under another pin as stale.
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
- A machine runs the pinned build from `~/mesen-pins/<commit>/` once it is
  deployed there (README.md, "Deploying"), else the main tree's
  `tools/Mesen-linux/Mesen` (`tools/Mesen.app` on a Mac), which still hold
  ot6-2.2.1-1 (px13 executable `b5a407c3...8c54`; the Macs the same
  Air-built bundle, `e96f5fdf...7b37`). ot6-2.2.1-4 is deployed on all
  three, each its own build (README.md lists the shas). The 2.1.1 builds
  are kept in `~/mesen-patched/` as `2.1.1-<sha8>-Mesen[.app]`, with their
  `.buildinfo`.

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP, status-byte reality.
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
