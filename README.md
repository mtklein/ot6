# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM): FF6's
cast, story, and world played through Octopath Traveler's combat grammar —
sharp per-character job identities, shield/break tactics, and a boost-point
turn economy.

## Status

Design phase. See [docs/DESIGN.md](docs/DESIGN.md) for the mechanics design and
[docs/ROADMAP.md](docs/ROADMAP.md) for milestones. Toolchain notes land in
[docs/TOOLING.md](docs/TOOLING.md).

## Layout

```
ff6/        # full-game source (vendored everything8215/ff6 disassembly,
            #   GPL-3.0) + OT6 code in ff6/src/battle/ot6.asm (bank F0)
docs/       # design, roadmap, research notes, vendored-history patches
tools/      # Mesen 2, flips, Lua battle-test harness (tools/tests/)
build/      # built ROM + distributable .bps patch (git-ignored)
```

The base ROM (git-ignored, never committed) lives at the repo root and in
`ff6/vanilla/`. This repo tracks assets ripped from that dump for local
convenience, so it stays **private**; the public artifact is the `.bps`
patch from `make patch`.

## Legal

This repository contains only original code, patches, and documentation.
No ROM or copyrighted game data is committed or distributed. You must supply
your own legally obtained copy of the game; the build process applies our
patches to it locally.
