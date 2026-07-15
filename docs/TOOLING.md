# OT6 Tooling — installed and verified 2026-07-14

Everything below is working on this machine (macOS arm64). Research trail
with URLs: [research/toolchain.md](research/toolchain.md).

## The build

We build the whole game from source via the **everything8215/ff6
disassembly** (GPL-3.0), cloned at `ff6/` (its own git repo; our changes go
on its `ot6` branch). The base ROM lives in `ff6/vanilla/` and assets are
ripped from it once (`make rip`). Verified: `make ff6-en` reproduces retail
FF3us 1.0 **byte-for-byte** (CRC32 A27F1C7A), including retail's famously
wrong internal SNES checksum.

Top-level `Makefile` targets:

| Target | Does |
|---|---|
| `make rom` | verify base-ROM SHA1 → build `ff6/rom/ff6-en.sfc` → copy to `build/ot6.sfc` |
| `make patch` | emit distributable `build/ot6.bps` (Flips; BPS never contains game data) |
| `make run` | open the built ROM in Mesen (GUI) |
| `make test` | headless Mesen testrunner, runs `tools/tests/smoke.lua`, exit code = pass/fail |

Hello-world proof: default name TERRA→OCTO in
`ff6/src/text/char_name_en.json` → rebuild → exactly 7 bytes differ from
vanilla (5 at the name table $C478C0 + auto-fixed checksum pair), BPS is
45 bytes, smoke test asserts the change from inside the emulator (negative
control verified to exit 1).

## Installed pieces

- **cc65** (ca65/ld65) + **numpy** — via Homebrew (build + asset encoders).
- **Flips CLI** — built from source (github.com/Alcaro/Flips), binary at
  `tools/bin/flips`.
- **Mesen 2.1.1** — official macOS ARM64 release zip (77 MB) from
  github.com/SourMesen/Mesen2, unpacked to `tools/Mesen.app`. Debugger has
  breakpoints/memory watch/trace and **ca65 symbol integration** — the
  build already emits `ff6/rom/ff6-en.dbg` for source-level debugging.
- ff6 disassembly clone at `ff6/`, Flips clone at `Flips/` — both
  git-ignored by the outer repo, as are `tools/Mesen.app` and `tools/bin`.

## Gotchas learned the hard way

- **Mesen first-run wizard vs testrunner**: with no config file, Mesen
  ignores `--testrunner` and launches the GUI setup wizard (hangs any
  script). Its home folder on macOS is `~/Library/Application
  Support/Mesen2/`; an existing `settings.json` (even `{}`) skips the
  wizard. Already handled here.
- Mesen is unsigned: the **first GUI launch** may need right-click → Open
  to satisfy Gatekeeper. Headless testrunner runs fine from the terminal.
- macOS has no `timeout`; testrunner also has its own `timeout=N` arg if a
  test ever wedges.
- `make distclean` in `ff6/` deletes ripped (copyrighted) assets INCLUDING
  any we've modified — our hello-world lives in a ripped JSON, so don't run
  distclean casually; real OT6 data changes should eventually be applied by
  script/patch at build time so they survive a re-rip.
- The rip/build regenerates some tracked `.inc` files in `ff6/` — expected
  noise on the `ot6` branch; commit deliberately.

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
