# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM): FF6's
cast, story, and world played through Octopath Traveler's combat grammar —
sharp per-character job identities, shield/break tactics, and a boost-point
turn economy.

## Status

**v0.9 released** ([tag](https://github.com/mtklein/ot6/releases/tag/v0.9)) —
Locke, and the break economy: Locke gets a kit at last (a thief submenu
holding Steal, Filch and Bestow, with Steal's price finally on screen),
boosting a spell into a higher tier now charges what that tier actually
costs, boosting Runic buys turns of a standing rune stance that Celes can
fight through, the broken-shield glyph reads as broken, a monster that tags
out mid-break recovers on schedule, ability pages show their element, and
poison damage over time is confirmed to chip shields. Same playable
frontier as v0.6.

**v0.8** ([tag](https://github.com/mtklein/ot6/releases/tag/v0.8)) —
the economy bites: every ability price recalibrated against what vanilla's
own spells cost, each kit's ultimate anchored at 99 MP, breaking an enemy
now flashes it white and lands a sound, Gau can fight, and magicite grant
real stat packages in the same format FF6 uses for armour. Same playable
frontier as v0.6.

**v0.7** ([tag](https://github.com/mtklein/ot6/releases/tag/v0.7)) —
the playtest release: MP is visible everywhere it is spent, boost pips and
weakness reveals now land on the frame of the action they belong to, Cyan's
Bushido costs at least one Boost Point, Setzer's Slot answers to boost, True
Knight banks a pip when it covers, and Gau becomes a hunter with a chosen
loadout of eight rages instead of a wall of two hundred. Six more magicite
are real sub-jobs. Same playable frontier as v0.6.

**v0.6** ([tag](https://github.com/mtklein/ot6/releases/tag/v0.6)) —
playable from the start through the Raid on Vector: the Magitek Research
Facility, Ifrit and Shiva as complete magicite sub-jobs, Number 024, the
minecart and Number 128, the Cranes, the escape, and Terra's return. Battle
MP is universal now — every character brings their save's pool into every
fight — the esper detail page shows each stone's while-worn bonus, and the
Vector band carries hand-authored break coverage. The first release
validated by a full human playtest.

Break and boost are the spine: enemies carry shields and hidden weaknesses,
hitting a weakness chips a shield, and breaking drops defenses hard; boost
banks turns and folds spell tiers (Fire → Fira → Firaga). Magicite are
sub-jobs — equip an esper and its spells join your Magic list, with a stat
bump, while you hold it, augmenting the born mages rather than replacing
them. Blitz is a menu, Steal guarantees the rare at three boost pips, and
level-ups fully restore HP and MP.

Route work now follows the Sealed Gate: the Narshe mission handoff, the
cave, the Esper attack, the Imperial banquet, and the Thamasa handoff. The
playable frontier itself has not moved since v0.6 — v0.7, v0.8 and v0.9 were
all deliberately about how the game feels where you already are. Pushing it
to the end of the World of Balance is v0.10's job.

Picking this up cold? [docs/HANDOFF.md](docs/HANDOFF.md) is the state of play —
what is in flight, what is next, and the handful of traps that cost real time to
rediscover.

See [docs/ROADMAP.md](docs/ROADMAP.md) for milestones and the "playable
frontier" metric, and [docs/DESIGN.md](docs/DESIGN.md) for the mechanics
design. The playtest findings ledgers are
[docs/playtest-v0.7.md](docs/playtest-v0.7.md) (newest),
[docs/playtest-v0.6-rc1.md](docs/playtest-v0.6-rc1.md) and
[docs/playtest-v0.5.md](docs/playtest-v0.5.md).

## Quick start

You supply your own ROM; it is not included. The build verifies it by SHA-1
and refuses anything else:

```
Final Fantasy III (USA).sfc    sha1 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
```

Drop that file at the repo root, then:

```sh
make rom     # build build/ot6.sfc
make test    # full headless correctness gate (the whole suite + the mp-cost A/B)
make frontier-test  # the same gate plus its frontier-gated tests (slow: mints the story chain)
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
docs/       # design, roadmap, research notes, vendored-history patches
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
