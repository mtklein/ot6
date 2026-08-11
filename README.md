# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM): FF6's
cast, story, and world played through Octopath Traveler's combat grammar —
sharp per-character job identities, shield/break tactics, and a boost-point
turn economy.

## Status

**v0.9 is the current release**
([tag](https://github.com/mtklein/ot6/releases/tag/v0.9)). The game is
playable from the start through the Raid on Vector — the Magitek Research
Facility, Number 024, the minecart and Number 128, the Cranes, the escape,
and Terra's return.

Break and boost are the spine: enemies carry shields and hidden weaknesses,
hitting a weakness chips a shield, and breaking drops defenses hard; boost
banks turns and folds spell tiers (Fire → Fira → Firaga). Magicite are
sub-jobs — equip an esper and its spells join your Magic list, with a stat
bump, while you hold it, augmenting the born mages rather than replacing
them. Blitz is a menu, Steal guarantees the rare at three boost pips, and
level-ups fully restore HP and MP.

Route work follows the Sealed Gate: the Narshe mission handoff, the cave,
the Esper attack, the Imperial banquet, and the Thamasa handoff. Getting the
game playable to the end of the World of Balance is v0.10's job.

See [docs/ROADMAP.md](docs/ROADMAP.md) for milestones and how far the game is
playable, [docs/DESIGN.md](docs/DESIGN.md) for the mechanics design,
and [docs/HANDOFF.md](docs/HANDOFF.md) for the traps that cost real time to
rediscover.

## Quick start

You supply your own ROM; it is not included. The build verifies it by SHA-1
and refuses anything else:

```
Final Fantasy III (USA).sfc    sha1 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
```

Drop that file at the repo root, then:

```sh
make rom     # build build/ot6.sfc
make test    # full headless correctness run (the whole suite + the mp-cost A/B)
make frontier-test  # the same, plus the tests that need the deep story savestates
                    #   (slow: generates that chain of savestates first)
make run     # launch the built ROM in Mesen (GUI)
make patch   # emit a distributable .bps
```

`make test` runs the whole suite headlessly under Mesen's testrunner — no
window, no clicking. It takes a few minutes. Tests self-register with a
`-- @suite` marker, so `tools/tests/suite.sh --list` shows exactly what runs;
see [tools/tests/README.md](tools/tests/README.md) for how the harness works
and how to write a test.

## Layout

```
ff6/        # full-game source (vendored everything8215/ff6 disassembly,
            #   GPL-3.0) + OT6 modules under ff6/src/battle/ot6_* (bank F0)
docs/       # design, roadmap, research notes
tools/      # Mesen 2, flips, Lua battle-test harness (tools/tests/)
build/      # built ROM + distributable .bps patch (git-ignored)
```

Nearly all OT6 code lives in feature-oriented modules emitted in order from
`ff6/src/battle/ot6.asm` into expanded bank `$F0`; `ot6_memory.inc` is the
central WRAM/SRAM ownership map. Vanilla banks carry only minimal `jsl` hook
shims. [docs/TOOLING.md](docs/TOOLING.md) covers the
toolchain and [docs/research/](docs/research/) holds the reverse-engineering
notes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues are tracked
[here](https://github.com/mtklein/ot6/issues) — including known defects with
reproductions, which are a reasonable place to start.
