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
everything, ending at the qualified release zip. Any narrower need is a
real output path (`ninja ff6/rom/ff6-en.sfc`,
`ninja build/results/suite/battle_break.ok`). The graph regenerates itself
when `configure.py`, the savestate graph, `VERSION`, or any globbed
directory changes.

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

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP, status-byte reality.
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
