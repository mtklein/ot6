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
FF6.smc     # base ROM — bring your own, git-ignored, never committed
docs/       # design, roadmap, research notes
src/        # assembly patches (from M0)
tools/      # build scripts, emulator test harness (from M0)
build/      # built ROM + distributable .bps patch (git-ignored)
```

## Legal

This repository contains only original code, patches, and documentation.
No ROM or copyrighted game data is committed or distributed. You must supply
your own legally obtained copy of the game; the build process applies our
patches to it locally.
