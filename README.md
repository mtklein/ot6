# OT6 — Octopath Traveler mechanics in Final Fantasy VI

A mechanics-overhaul ROM hack of Final Fantasy VI (SNES, US "FF3" ROM). It
keeps FF6's cast, story, and world, and replaces the combat system with
Octopath Traveler's: per-character job identities, shield/break tactics, and a
boost-point turn economy.

## Status

v0.16 is the current release
([tag](https://github.com/mtklein/ot6/releases/tag/v0.16)); it plays
identically to v0.15. The game is playable from the start through the end of
the World of Balance: the whole Thamasa arc, the world tour aboard the
repaired Blackjack, the IAF gauntlet, the Floating Continent and AtmaWeapon,
and the escape — stopping where the game sets you down in the World of Ruin.

Break and boost are the two central systems. Enemies carry shields and hidden
weaknesses, hitting a weakness chips a shield, and breaking drops defenses
hard. Boost banks turns and folds spell tiers (Fire → Fira → Firaga).
Magicite work as sub-jobs: equip an esper and its spells join your Magic list,
along with a stat bump, while you hold it — in battle and in the field menu.
Blitz is a menu, Steal guarantees the rare at three boost pips, and level-ups
fully restore HP and MP.

See [docs/DESIGN.md](docs/DESIGN.md) for the mechanics design and
[docs/TOOLING.md](docs/TOOLING.md) for tool installation.

## Building

You supply your own ROM; it is not included. The build verifies it by SHA-1
and refuses anything else: `Final Fantasy III (USA).sfc`, sha1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`, at the repo root.

```sh
brew bundle                 # cc65, sdl2, ninja, ffmpeg
python3 -m pip install numpy
python3 configure.py        # writes build.ninja
ninja                       # builds and tests everything; the default
                            # target is the qualified release zip
```

Mesen and Flips are not brew-installable; [docs/TOOLING.md](docs/TOOLING.md)
has those steps.

`ninja` runs the whole graph: both ROMs, every generated savestate (the
story-chain fixtures are multi-minute scripted playthroughs; a cold build
takes upward of an hour and a half), all 94 suite tests, the audits and
selftests, and the release packaging. Anything narrower is a real output
path:

```sh
ninja ff6/rom/ff6-en.sfc                    # just the ROM
ninja build/results/suite/battle_break.ok   # one suite test (and what it needs)
ninja build/states/vargas_entry.mss.lua     # one savestate (and its chain)
```

`tools/gui.sh` opens the built ROM in the Mesen GUI.
`OT6_RECORD=1 tools/tests/run.sh tools/tests/<test>.lua` records a run as a
watchable video with a pad-input panel; see
[tools/stream/README.md](tools/stream/README.md).

## Where the code is

OT6 code lives in feature modules emitted from
[ff6/src/battle/ot6.asm](ff6/src/battle/ot6.asm) into expanded bank `$F0`;
[ot6_memory.inc](ff6/src/battle/ot6_memory.inc) owns the shared WRAM/SRAM
map. `ff6/` is a vendored copy of the everything8215/ff6 disassembly
(GPL-3.0). The headless play harness is
[docs/playing-headless.md](docs/playing-headless.md);
[tools/tests/README.md](tools/tests/README.md) covers the test harness.

## A warning about Sketch

Relm's Sketch carries Final Fantasy VI 1.0's most famous bug, deliberately
left in place: when a Sketch misses, the game can rarely corrupt your
inventory or save. Save before experimenting with Sketch; the world map
saves anywhere.
