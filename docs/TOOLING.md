# OT6 Tooling

Everything below is working on this machine (macOS arm64). Research notes
with URLs: [research/toolchain.md](research/toolchain.md).

## The build

We build the whole game from source via the **everything8215/ff6
disassembly** (GPL-3.0), vendored at `ff6/` (upstream 1ea47b5).
The base ROM lives
in `ff6/vanilla/` (git-ignored) and assets are ripped from it once
(`make rip`). Verified: the unmodified tree's `make ff6-en` reproduces
retail FF3us 1.0 byte-for-byte (CRC32 A27F1C7A), including retail's
incorrect internal SNES checksum. OT6 code lives in
the ordered `ff6/src/battle/ot6_*.asm` modules (emitted by `ot6.asm` into
expanded bank $F0) plus minimal jsl shims in
vanilla banks.

Top-level `Makefile` targets:

| Target | Does |
|---|---|
| `make rom` | verify base-ROM SHA1 → build `ff6/rom/ff6-en.sfc` → copy to `build/ot6.sfc` |
| `make test` | full headless correctness run: the compose, savestate-stamp, and concurrent-runner isolation selftests, then the marker-discovered suite (`tools/tests/suite.sh`) — which runs the MP-cost A/B's charge+refusal half on the shipped ROM — then the free-behavior half on the `nomp` baseline; stamps the passing ROM's sha1. Exit code = pass/fail |
| `make tested` | check: refuse unless `build/ot6.sfc` is the exact ROM `make test` last passed on (guards distributables) |
| `make nomp-rom` | build the `OT6_MP_COSTS=0` baseline `ff6/rom/ff6-en-nomp.sfc` (the pre-feature vanilla-OT6 build) and assert it differs from the shipped ON ROM — the A/B's OFF control (since v0.5 the shipped ROM charges MP; "every ability costs MP" is live by default) |
| `make patch` | (needs `tested`) emit the distributable BPS `build/dist/ot6-from-ff3us10.bps` (Flips; stores only what differs from the base ROM) |
| `make release` | build, run the full test suite, then emit `build/release/ot6-v$(VERSION).bps` plus release notes |
| `make run` | open the built ROM in Mesen (GUI) |
| `make savestates` | generate the deep story-chain savestate fixtures past the whelk (slow; nothing in `make test` depends on them) |
| `make savestates-test` | `make savestates`, then run the suite with those fixtures present (so the tests that need the generated savestates run) |

Hello-world check: default name TERRA→OCTO in
`ff6/src/text/char_name_en.json` → rebuild → exactly 7 bytes differ from
vanilla (5 at the name table $C478C0 + auto-fixed checksum pair), BPS is
45 bytes, smoke test asserts the change from inside the emulator (negative
control verified to exit 1).

## Installed pieces

The Homebrew pieces are captured in the root `Brewfile` — `brew bundle` from
the repo root installs them in one go (the non-brew pieces below still need
the manual steps at each bullet).

- **cc65** (ca65/ld65) — via Homebrew. The build's only python requirement
  is any `python3` ≥3.9; Command Line Tools 3.9.6 suffices. numpy is
  imported only by the asset re-encoders (`brr.py`, `monster_stencil.py`,
  `shuffle_rng.py`), whose outputs are tracked.
- **ninja** — via Homebrew. Runs the generated savestate graph
  (`build/build.ninja`, emitted by `tools/tests/lib/savestate_ninja.py` from
  `tools/tests/savestate_graph.py`); `make savestates` / `make test` are thin
  wrappers over it (issue #25).
- **Flips CLI** — binary at `tools/bin/flips` (git-ignored). Rebuild:
  clone github.com/Alcaro/Flips, `make CFLAGS=-O2`, copy `flips` in.
- **Mesen 2.1.1** — official macOS ARM64 release zip (77 MB) from
  github.com/SourMesen/Mesen2, unpacked to `tools/Mesen.app`. Debugger has
  breakpoints/memory watch/trace and **ca65 symbol integration** — the
  build already emits `ff6/rom/ff6-en.dbg` for source-level debugging.
- **sdl2** — via Homebrew; a hard Mesen runtime dependency.
  MesenCore.dylib's only non-system link is
  `/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib` (otool -L). It is easy
  to miss: the .app bundles no SDL, and the core dylib only exists once the
  .NET host extracts it to `~/Library/Application Support/Mesen2/`, so a
  machine without sdl2 dies on first launch as DllNotFoundException →
  Abort trap 6.
- **ca65/ld65 is the sole production compiler/linker path.** OT6 code
  stays in assembly alongside the vendored disassembly; there is no
  secondary compiler or committed compiler-generated blob to reproduce.
- Everything is one flat git repo; only the ROMs, `build/`,
  `tools/Mesen.app`, and `tools/bin` are ignored. Ripped assets are
  tracked. The release artifact is a BPS delta from `make patch`, which
  stores only what differs from the base ROM (measured on v0.1: 8,650
  literal bytes of ~20 KB).

## Gotchas

- **Mesen first-run wizard vs testrunner**: with no config file, Mesen
  ignores `--testrunner` and launches the GUI setup wizard (hangs any
  script). Its home folder on macOS is `~/Library/Application
  Support/Mesen2/`; an existing `settings.json` (even `{}`) skips the
  wizard. Already handled here.
- **Move that home folder with `CFFIXED_USER_HOME`, not `$HOME`.** Mesen
  resolves it via .NET's `SpecialFolder.ApplicationData`, which on macOS
  goes through `NSSearchPathForDirectoriesInDomains` and reads the home
  from the password database, so `$HOME` is ignored (a testrunner
  run with `HOME` redirected still wrote its `.srm` into the real
  profile). Core Foundation's `CFFIXED_USER_HOME` does move it. A
  `settings.json` beside the binary (portable mode) overrides both.
  `tools/tests/run.sh` relies on all three facts; see its "shared
  emulator" header.
- Mesen is ad-hoc signed but **not notarized** (no Team ID), so Gatekeeper
  rejects it: the **first GUI launch** may need right-click → Open. Headless testrunner runs fine from the terminal.
  It also means every **new bundle path** costs a first-launch assessment:
  a "Verifying Mesen…" dialog and a ~5s scan of the whole 413MB bundle
  (measured against 0.3-0.5s for an already-known path). `xattr -cr` does
  not suppress it; the trigger is the path, not the quarantine flag. This
  is why the harness keeps one shared test bundle machine-wide instead of
  a copy per worker.
- macOS has no `timeout`; testrunner also has its own `timeout=N` arg if a
  test ever wedges.
- `make distclean` in `ff6/` deletes ripped assets including modified ones.
  They are recoverable with `git restore` now that they are tracked, but
  do not run it casually.
- **ca65 width state is inherited across `.include`**: any asm file pulled
  into a module inherits the `.a8/.a16/.i8/.i16` assumptions active at the
  inclusion point. Always declare the expected widths at the top of a new
  file. A debugging round was lost to `cpy #imm` assembling a 1-byte
  operand while the CPU ran 16-bit indexes, which desynced the instruction
  stream and hung battle init.
- Mesen Lua: `emu.createSavestate`/`loadSavestate` must run inside an
  exec memory callback, not event callbacks (Mesen enforces this and says
  so). `dofile` and file writes are blocked by a **default-off setting**,
  `Debug.ScriptWindow.AllowIoOsAccess`, not by a fixed sandbox — flipping
  it enables both. We leave it off and compose scripts flat, tunnelling
  artifacts as base64 over stdout, because hermetic runs are worth more
  than the convenience; see tools/tests/run.sh.

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP (damage calc, elemental handling, ATB tick,
  Stop/Freeze machinery), status-byte reality (Broken = pseudo-status).
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
