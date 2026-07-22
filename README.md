# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM): FF6's
cast, story, and world played through Octopath Traveler's combat grammar —
sharp per-character job identities, shield/break tactics, and a boost-point
turn economy.

## Status

**v0.4.1 released** ([tag](https://github.com/mtklein/ot6/releases/tag/v0.4.1)) —
playable from the start through Zozo: the escape from Narshe, the crane
maze, Dadaluma beaten, and Ramuh's offer on the roof. Magicite are sub-jobs
now — equip an esper and its spells join your Magic list, with a stat bump,
while you hold it, augmenting the born mages rather than replacing them.
Blitz becomes a menu, Steal guarantees the rare at three boost pips, and
level-ups fully restore HP and MP. Break and boost remain the spine: enemies
carry shields and hidden weaknesses, hitting a weakness chips a shield, and
breaking drops defenses hard; boost banks turns and folds spell tiers
(Fire → Fira → Firaga).

Work in progress toward the next rung, the rest of the World of Balance
(Opera → Vector → the Floating Continent). See [docs/ROADMAP.md](docs/ROADMAP.md) for milestones and the
"playable frontier" metric, and [docs/DESIGN.md](docs/DESIGN.md) for the
mechanics design.

## Quick start

You supply your own ROM; it is not included. The build verifies it by SHA-1
and refuses anything else:

```
Final Fantasy III (USA).sfc    sha1 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
```

Drop that file at the repo root, then:

```sh
make rom     # build build/ot6.sfc
make test    # full headless correctness gate (35 tests + pixel goldens + the mp-cost A/B)
make frontier-test  # the same gate plus its frontier-gated tests (slow: mints the story chain)
make run     # launch the built ROM in Mesen (GUI)
make patch   # emit a distributable .bps
```

`make test` runs the whole suite headlessly under Mesen's testrunner — no
window, no clicking. It takes a few minutes. See
[tools/tests/README.md](tools/tests/README.md) for how the harness works and
how to write a test.

## Layout

```
ff6/        # full-game source (vendored everything8215/ff6 disassembly,
            #   GPL-3.0) + OT6 code in ff6/src/battle/ot6.asm (bank F0)
docs/       # design, roadmap, research notes, vendored-history patches
tools/      # Mesen 2, flips, Lua battle-test harness (tools/tests/)
build/      # built ROM + distributable .bps patch (git-ignored)
```

Nearly all OT6 code lives in expanded bank `$F0`; vanilla banks carry only
minimal `jsl` hook shims. [docs/TOOLING.md](docs/TOOLING.md) covers the
toolchain and [docs/research/](docs/research/) holds the reverse-engineering
notes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues are tracked
[here](https://github.com/mtklein/ot6/issues) — including known defects with
reproductions, which are a reasonable place to start.
