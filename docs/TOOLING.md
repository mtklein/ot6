# OT6 Tooling — installed and verified 2026-07-14

Everything below is working on this machine (macOS arm64). Research trail
with URLs: [research/toolchain.md](research/toolchain.md).

## The build

We build the whole game from source via the **everything8215/ff6
disassembly** (GPL-3.0), vendored directly at `ff6/` (upstream 1ea47b5;
pre-flatten commit history preserved in docs/history/). The base ROM lives
in `ff6/vanilla/` (git-ignored) and assets are ripped from it once
(`make rip`). Verified: the unmodified tree's `make ff6-en` reproduces
retail FF3us 1.0 **byte-for-byte** (CRC32 A27F1C7A), including retail's
famously wrong internal SNES checksum. OT6 code lives in
`ff6/src/battle/ot6.asm` (expanded bank $F0) plus minimal jsl shims in
vanilla banks.

Top-level `Makefile` targets:

| Target | Does |
|---|---|
| `make rom` | verify base-ROM SHA1 → build `ff6/rom/ff6-en.sfc` → copy to `build/ot6.sfc` |
| `make patch` | emit distributable `build/ot6.bps` (Flips; stores only what differs from the base ROM) |
| `make run` | open the built ROM in Mesen (GUI) |
| `make test` | headless Mesen testrunner, runs `tools/tests/smoke.lua`, exit code = pass/fail |

Hello-world proof: default name TERRA→OCTO in
`ff6/src/text/char_name_en.json` → rebuild → exactly 7 bytes differ from
vanilla (5 at the name table $C478C0 + auto-fixed checksum pair), BPS is
45 bytes, smoke test asserts the change from inside the emulator (negative
control verified to exit 1).

## Installed pieces

The Homebrew pieces are captured in the root `Brewfile` — `brew bundle` from
the repo root installs them in one go (the non-brew pieces below still need
the manual steps at each bullet).

- **cc65** (ca65/ld65) — via Homebrew. numpy is no longer needed
  (2026-07-18): `ff6/tools/fix_checksum.py` was rewritten onto stdlib
  `struct`, output verified byte-identical, so the build's only python
  requirement is any `python3` ≥3.9 — Command Line Tools 3.9.6 suffices.
  numpy imports survive only in the asset re-encoders (`brr.py`,
  `monster_stencil.py`, `shuffle_rng.py`), whose outputs are tracked.
- **Flips CLI** — binary at `tools/bin/flips` (git-ignored). Rebuild:
  clone github.com/Alcaro/Flips, `make CFLAGS=-O2`, copy `flips` in.
- **Mesen 2.1.1** — official macOS ARM64 release zip (77 MB) from
  github.com/SourMesen/Mesen2, unpacked to `tools/Mesen.app`. Debugger has
  breakpoints/memory watch/trace and **ca65 symbol integration** — the
  build already emits `ff6/rom/ff6-en.dbg` for source-level debugging.
- **sdl2** — via Homebrew; a hard Mesen runtime dependency.
  MesenCore.dylib's only non-system link is
  `/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib` (otool -L). Invisible
  until a machine lacked it: the .app bundles no SDL, and the core dylib
  only exists once the .NET host extracts it to
  `~/Library/Application Support/Mesen2/` — so the first launch after the
  2026-07-18 reformat died as DllNotFoundException → Abort trap 6.
  [research/toolchain.md](research/toolchain.md)'s Mesen entry said
  "needs `brew install sdl2`" all along; this list omitted it.
- **Calypsi 65816 C toolchain 5.17** — macOS pkg from
  github.com/hth313/Calypsi-tool-chains, expanded (not installed) to
  `tools/calypsi/expanded/...` (git-ignored; x86_64 binaries run under
  Rosetta). `tools/cc/build-c.sh` compiles `ff6/src/c/*.c`
  (`--target snes`, large models) and links with `ot6-rom.scm`, which
  pins section `farcode` at `$f0f000` — the `ot6_c` ld65 segment pins
  the same address, so both linkers agree by construction. The tiny
  `.raw` blobs are committed; hooks/NMI code stay ca65. ABI: 16-bit
  native modes, first arg in A, later args pushed as words (callee
  sees the first at `4,s`), result in A, `rtl` return. Leaf functions
  with no globals need no direct-page setup; anything using near data
  or `_Dp` needs a C context (direct page + data bank) marshalled by
  its trampoline first.
- Everything is one flat git repo; only the ROMs, `build/`,
  `tools/Mesen.app`, and `tools/bin` are ignored. Ripped assets are
  tracked. The release artifact is a BPS delta from `make patch`, which
  stores only what differs from the base ROM (measured on v0.1: 8,650
  literal bytes of ~20 KB).

## Gotchas learned the hard way

- **Mesen first-run wizard vs testrunner**: with no config file, Mesen
  ignores `--testrunner` and launches the GUI setup wizard (hangs any
  script). Its home folder on macOS is `~/Library/Application
  Support/Mesen2/`; an existing `settings.json` (even `{}`) skips the
  wizard. Already handled here.
- **Moving that home folder: `CFFIXED_USER_HOME`, never `$HOME`.** Mesen
  resolves it via .NET's `SpecialFolder.ApplicationData`, which on macOS
  goes through `NSSearchPathForDirectoriesInDomains` and reads the home
  from the password database — so `$HOME` is simply ignored (a testrunner
  run with `HOME` redirected still wrote its `.srm` into the real
  profile). Core Foundation's `CFFIXED_USER_HOME` does move it. A
  `settings.json` beside the binary (portable mode) overrides both.
  `tools/tests/run.sh` relies on all three facts; see its "shared
  emulator" header.
- Mesen is ad-hoc signed but **not notarized** (no Team ID), so Gatekeeper
  rejects it: the **first GUI launch** may need right-click → Open. Headless testrunner runs fine from the terminal.
  It also means every **new bundle path** costs a first-launch assessment —
  a "Verifying Mesen…" dialog and a ~5s scan of the whole 413MB bundle
  (measured against 0.3-0.5s for an already-known path). `xattr -cr` does
  not suppress it; the trigger is the path, not the quarantine flag. This
  is why the harness keeps ONE shared test bundle machine-wide instead of
  a copy per worker.
- macOS has no `timeout`; testrunner also has its own `timeout=N` arg if a
  test ever wedges.
- `make distclean` in `ff6/` deletes ripped assets including modified ones
  — recoverable via `git restore` now that they're tracked, but still
  don't run it casually.
- **Fresh clone**: all 665 `.lz` files are generated (compressed from
  tracked sources by `ff6/tools/ff6_lzss.py`) and git-ignored, so a fresh
  clone has none — and the vendored Makefile computes module deps with
  `$(wildcard)`, so files that don't exist yet are not prerequisites and
  nothing schedules the `%.lz: %` rule. The first build dies in ca65 on
  the missing includes. Regeneration is mechanical: enumerate the sources
  and make each `.lz` target by name — the pattern rule works when asked.
- A failed recipe used to leave a half-built, unchecksummed
  `rom/ff6-en.sfc` that the next `make` treated as up-to-date. Both
  Makefiles now set `.DELETE_ON_ERROR:` (added 2026-07-18), so a failed
  recipe's target is deleted instead.
- **ca65 width state is inherited across `.include`**: any asm file pulled
  into a module inherits the `.a8/.a16/.i8/.i16` assumptions active at the
  inclusion point. ALWAYS declare the expected widths at the top of a new
  file — we lost a debugging round to `cpy #imm` assembling a 1-byte
  operand while the CPU ran 16-bit indexes (instruction-stream desync,
  hung battle init).
- Mesen Lua: `emu.createSavestate`/`loadSavestate` must run inside an
  exec memory callback, not event callbacks (Mesen enforces this and says
  so). `dofile` and file writes are blocked by a **default-off setting**,
  `Debug.ScriptWindow.AllowIoOsAccess`, not by a fixed sandbox — flipping
  it enables both. We leave it off and compose scripts flat, tunnelling
  artifacts as base64 over stdout, because hermetic runs are worth more
  than the convenience — see tools/tests/run.sh.

## Reference docs for the asm work (see research/)

- [battle-code-map.md](research/battle-code-map.md) — verified C2 hook
  addresses for break/BP (damage calc, elemental handling, ATB tick,
  Stop/Freeze machinery), status-byte reality (Broken = pseudo-status).
- [ram-and-rom-space.md](research/ram-and-rom-space.md) — battle RAM map,
  free per-entity bytes, ROM expansion norms.
- [data-formats.md](research/data-formats.md) — monster/item/esper/spell
  record layouts with offsets.
- [prior-art.md](research/prior-art.md) — who has published reusable asm
  (BNW, RoSoDude's ATB/CTB) and what's never been done (break, BP, enemy
  gauges).
