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

### Cuts and the chain from power-on

A `.mss` belongs to one ROM, so after a ROM change every generated state
regenerates, each from the one before it. To keep that from being one long
serial run, the World of Balance chain is cut where the play saves (at a
save point, or on the world map, where the game lets you save anywhere):
an entry in
`tools/tests/savestate_graph.py` with both `prev=` and `checkpoint=` is a
cut. The leg before it ends by saving there through the real Save UI and
asserting the checkpoint's contract as its exit
(`H.saveAtCheckpoint`, `lib/ot6_contract.lua`); the leg after it
Continues the save and asserts the same contract as its entry
(`H.bootCheckpoint`). Qualification boots each cut leg from the tracked
checkpoint in `tools/tests/checkpoints/`, which still loads after a ROM
change, so the legs regenerate at once.

`ninja chain` plays the whole chain from power-on instead: `chain_<state>`
copies of every state from the first cut on, each booted from the copy
before it and, at a cut, from the save the producing copy just made
(captured with `OT6_CAPTURE_SRM` and sealed into
`build/checkpoints/<key>/`). It is the one alias besides `release`,
because the chain's last state moves as cuts and legs are added.
`ninja release` depends on it. Run it too when a leg's exit contract
fails in qualification: the chain says whether the story still plays
through.

A tracked checkpoint drifts from today's play as the route changes above
it. At each cut the chain prints the drift, decoded from both saves:
`tools/tests/lib/checkpoint_drift.py` compares the party (levels,
experience, max HP/MP, gear), gil, the bag and the story switches.
`ninja release` fails while any tracked checkpoint differs from its fresh
capture in those fields. Re-cut at every release, and during a cycle
whenever the report shows a material change:

    ninja chain
    python3 tools/tests/lib/checkpoint_drift.py --recut <key>...

`--recut` copies the chain's sealed capture over the tracked checkpoint;
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
- **Mesen 2.1.1** — official macOS ARM64 release zip from
  github.com/SourMesen/Mesen2, unpacked to `tools/Mesen.app`. Debugger has
  breakpoints/memory watch/trace and ca65 symbol integration; the build
  emits `ff6/rom/ff6-en.dbg` for source-level debugging.
- **sdl2** — via Homebrew; a hard Mesen runtime dependency.
  MesenCore.dylib's only non-system link is
  `/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib`, the .app bundles no
  SDL, and the core dylib only exists once the .NET host extracts it to
  `~/Library/Application Support/Mesen2/` — a machine without sdl2 dies on
  first launch as DllNotFoundException → Abort trap 6.

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
  harness compiles C. `ninja release` also wants `tools/bin/flips`, which
  would need a compiler to build (see the Flips bullet above), so release
  packaging stays on a Mac.
- **Mesen 2.1.1**: the official `Mesen_2.1.1_Linux_x64.zip` from
  github.com/SourMesen/Mesen2's 2.1.1 release (sha256 `7a994757...1ce9`),
  one self-contained binary, unzipped to `tools/Mesen-linux/Mesen`. It needs
  `libsdl2-2.0-0` and nothing else extra.
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

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP, status-byte reality.
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
