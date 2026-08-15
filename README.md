# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM). It
keeps FF6's cast, story, and world, and replaces the combat system with
Octopath Traveler's: per-character job identities, shield/break tactics, and a
boost-point turn economy.

## Status

v0.11 is the current release
([tag](https://github.com/mtklein/ot6/releases/tag/v0.11)). The game is
playable from the start through the Raid on Vector: the Magitek Research
Facility, Number 024, the minecart and Number 128, the Cranes, the escape,
and Terra's return. v0.11 is a small themed release — magicite you can heal
with between fights — and does not extend that range; it is the next step in
a run of small, frequent releases.

Break and boost are the two central systems. Enemies carry shields and hidden
weaknesses, hitting a weakness chips a shield, and breaking drops defenses
hard. Boost banks turns and folds spell tiers (Fire → Fira → Firaga).
Magicite work as sub-jobs: equip an esper and its spells join your Magic list,
along with a stat bump, while you hold it — in battle and, as of v0.11, in the
field menu too, so you can heal and cure status between fights with the
magicite you carry. That adds to what the born mages can already do rather than
replacing it. Blitz is a menu, Steal guarantees the rare at three boost pips,
and level-ups fully restore HP and MP.

Route work is on the Sealed Gate: the Narshe mission handoff, the cave, the
Esper attack, the Imperial banquet, and the Thamasa handoff. A later release
(v0.12) is meant to make the game playable to the end of the World of Balance.

See [docs/ROADMAP.md](docs/ROADMAP.md) for milestones and how far the game is
playable, [docs/DESIGN.md](docs/DESIGN.md) for the mechanics design,
and [docs/HANDOFF.md](docs/HANDOFF.md) for facts that are expensive to
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
make savestates-test  # the same, plus the tests that need the deep story savestates
                    #   (slow: generates that chain of savestates first)
make run     # launch the built ROM in Mesen (GUI)
make patch   # emit a distributable .bps
```

`make test` runs the whole suite headlessly under Mesen's testrunner, with no
window and no input from you. It takes a few minutes. Tests self-register with
a `-- @suite` marker, so `tools/tests/suite.sh --list` shows what runs; see
[tools/tests/README.md](tools/tests/README.md) for how the harness works and
how to write a test.

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
[here](https://github.com/mtklein/ot6/issues), including known defects with
reproductions, which are a reasonable place to start.
