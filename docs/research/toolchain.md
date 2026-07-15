# Research: toolchain (macOS / Apple Silicon, verified 2026-07-14)

## ROM identification

- Our `Final Fantasy III (USA).sfc` = v1.0, CRC32 `A27F1C7A`, SHA1
  `4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` — the community-standard patch
  base (https://www.ff6hacking.com/wiki/doku.php?id=ff3%3Aversions).
- Our `FF6.smc` = v1.1 / Rev 1, CRC32 `C0FA0464`. v1.1's headline change is
  the Sketch-glitch fix. Community patches (BNW, Worlds Collide, …) demand
  1.0 specifically.
- The disassembly (below) can rip data from either revision and has
  byte-perfect build targets for both (`make ff6-en` → 1.0,
  `make ff6-en1` → 1.1).

## Source of truth: everything8215/ff6 disassembly

https://github.com/everything8215/ff6 (GPL-3.0)

- Builds three ROMs — FF6-JP 1.0, FF3-US 1.0, FF3-US 1.1; **the two US
  builds are byte-for-byte identical to retail** (CRC32s stated in README).
- Toolchain: GNU Make + **ca65/ld65** (cc65 suite — `brew install cc65`) +
  Python 3 asset encoders (text, MML music, BRR, compression).
- Workflow: clone → put unmodified headerless ROM in `vanilla/` →
  `make rip` (one-time asset extraction) → `make ff6-en`; output in `rom/`.
- 128 .asm files in modules (`battle`, `btlgfx`, `field`, `event`, `menu`,
  `world`, `sound`, `cutscene`, `text`, `gfx`) with explicit imports/exports
  — ideal substrate for a mechanics overhaul.
- `DEBUG` flag in `include/const.inc` skips the intro — useful for testing.
- IP hygiene: `make distclean` purges ripped copyrighted assets; README
  warns that IPS patches of a rebuilt ROM embed copyrighted data —
  distribute **BPS/xdelta** instead.
- Maintenance: sporadic but alive (commits through Sep 2025).

Ecosystem context: most published hacks are still patch-on-vanilla-ROM
(xkas/bass/asar on FF3us 1.0); randomizers (Worlds Collide, Beyond Chaos)
are Python programs that write the ROM directly. Full-source rebuild is the
better substrate for us; the cost is that community `.asm` patches assume
vanilla addresses and must be ported by hand.

Reference disassemblies (read-only aids):
- Imzogelmo/assassin17 commented bank C0–C3 text disassemblies, mirrored at
  https://github.com/clementgallet/ff6-tas/tree/master/DisassemblyDocs
- seibaby/ff3us — asar-syntax relocatable bank C2 (battle) disassembly:
  https://github.com/seibaby/ff3us

## Tools

| Tool | Role | Install |
|---|---|---|
| cc65 (ca65/ld65) | assembler/linker the disassembly uses | `brew install cc65` (arm64 bottle) |
| Flips v198 | create/apply BPS patches | build from source (repo archived 2025, stable): https://github.com/Alcaro/Flips |
| asar v1.91 | only for porting community patches for study | build from source, verified on arm64: https://github.com/RPGHacker/asar |
| FF6Tools | browser-based data editor (maps, monsters, AI, events) | https://everything8215.github.io/ff6tools/ — maintained (Jun 2026) |
| FF3usME | legacy Windows editor | skip (Wine/VM only); FF6Tools covers us |

## Emulators

- **Mesen 2** — the pick for both debugging and automation. Official macOS
  ARM64 builds (needs `brew install sdl2`); full SNES debugger with
  breakpoints/memory watch/trace **and ca65 debug-symbol integration**
  (perfect fit with the disassembly); Lua API + headless
  `--testrunner rom.sfc test.lua` mode that runs at max speed until
  `emu.stop(exitCode)` — CI-able regression tests.
  https://github.com/SourMesen/Mesen2, docs https://www.mesen.ca/docs/
- bsnes-plus: Windows/Linux era, macOS fork dead since 2018 — skip.
- ares v148: accuracy sanity-check target only (no real SNES debugger).
- snes9x / RetroArch: player-compat check targets; no usable Lua on macOS.

## Recommended stack (adopted)

1. Fork/clone the disassembly; our code lives as a branch on it.
2. `brew install cc65 sdl2`; Mesen 2 for debug + testrunner regression.
3. FF6Tools in browser for data prototyping; final values land in source.
4. Ship BPS patches made with Flips; never commit ripped assets
   (`make distclean` before commits in the inner repo).

## Unverified / watch-outs

- Mesen `--testrunner` on macOS specifically (verified in source/docs, not
  yet executed here — M0 exit criterion).
- No exhaustive public diff list of US 1.0 vs 1.1 exists; Sketch fix is the
  headline.
- BNW's own build uses xkas 0.06; treat its asm as reference, not drop-in.
