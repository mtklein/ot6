# OT6

OT6 is a Final Fantasy VI ROM hack. It adds Octopath Traveler combat
mechanics while keeping the FF6 story, world, and characters.

## Status

v0.26 is the current release: [download it](https://github.com/mtklein/ot6/releases/tag/v0.26).
`main` is v0.27 development.

The game is playable through the World of Balance and through Darill's Tomb
in the World of Ruin.

Main changes:

- Enemies have shields and weaknesses. Weak hits remove shields. Broken
  enemies lose turns and take more damage.
- Characters gain and spend Boost Points. Boost can add hits, raise spell
  tiers, improve odds, or extend effects.
- Equipped Magicite grant spells and stats. They do not teach spells
  permanently.
- Characters have distinct skill sets.

See [the design](docs/DESIGN.md) for mechanics and
[the tooling guide](docs/TOOLING.md) for setup.

## Android

Each release includes `ot6-vX.Y.apk`. The app creates `OT6.sfc` from your
own ROM.

1. Add `https://github.com/mtklein/ot6` to
   [Obtainium](https://obtainium.imranr.dev/). Set the APK filter to
   `ot6-.*\.apk`.
2. Install and open OT6 Patcher. Select the folder containing your Final
   Fantasy III (USA) v1.0 ROM. If needed, select the ROM file directly.
3. Later app updates replace `OT6.sfc` with the new version.

The original ROM is not changed. `OT6.sfc` keeps the same name so the
emulator can keep using its save file.

For RetroArch, scan the folder containing `OT6.sfc`. Remove
`Final Fantasy III (USA).bps` from the original ROM's folder if you no longer
use soft patching. Do not place another patch beside `OT6.sfc`.

## Building

Place `Final Fantasy III (USA).sfc` in the repository root. It must have
SHA-1 `4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`. The ROM is not included.

```sh
brew bundle
python3 -m pip install numpy
python3 configure.py
ninja
ninja release
```

Mesen and Flips require separate installation. See
[the tooling guide](docs/TOOLING.md).

`ninja` builds both ROMs and runs the full test graph. `ninja release` also
runs release checks and creates the release archive. Specific outputs can be
built directly:

```sh
ninja ff6/rom/ff6-en.sfc
ninja build/results/suite/battle_break.ok
ninja build/states/vargas_entry.mss.lua
```

`tools/gui.sh` opens the built ROM in Mesen. To record a test run:

```sh
OT6_RECORD=1 tools/tests/run.sh tools/tests/<test>.lua
```

See [the recording guide](tools/stream/README.md) for details.

## Code

OT6 assembly starts in [ff6/src/battle/ot6.asm](ff6/src/battle/ot6.asm).
[ff6/src/battle/ot6_memory.inc](ff6/src/battle/ot6_memory.inc) defines shared
WRAM and SRAM. `ff6/` is a vendored copy of the everything8215 FF6
disassembly.

See [the headless play guide](docs/playing-headless.md) and
[the test harness guide](tools/tests/README.md).

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt
inventory or save data. Save before using Sketch.

## Contributing

See [AGENTS.md](AGENTS.md).

## License

OT6 code is MIT licensed. See [LICENSE](LICENSE). The FF6 disassembly, built
ROM, and release patch are GPL v3.
