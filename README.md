# OT6

OT6 is a Final Fantasy VI ROM hack. It adds Octopath Traveler combat
mechanics while keeping the FF6 story, world, and characters.

## Status

v0.30 is the current release: [download it](https://github.com/mtklein/ot6/releases/tag/v0.30).
`main` is v0.31 development.

The game is playable through the World of Balance and through Thamasa in the
World of Ruin, where Strago joins.

Main changes:

- Enemies have shields and weaknesses. Weak hits remove shields. Broken
  enemies lose turns and take more damage.
- Characters gain and spend Boost Points. Boost can add hits, raise spell
  tiers, improve odds, or extend effects.
- Equipped Magicite grant spells and stats. They do not teach spells
  permanently.
- Characters have distinct skill sets.

See [the design](docs/DESIGN.md) for details.

## Android

Each release includes `ot6-vX.Y.apk`. The app creates `OT6.sfc` from your
own ROM.

1. Add `https://github.com/mtklein/ot6` to
   [Obtainium](https://obtainium.imranr.dev/). Set the APK filter to
   `ot6-.*\.apk`.
2. Install and open OT6 Patcher. Select the folder containing your Final
   Fantasy III (USA) v1.0 ROM. If needed, select the ROM file directly.
3. Later app updates replace `OT6.sfc` with the new version.

`OT6.sfc` keeps its name across updates, so your emulator keeps its save.

For RetroArch, scan the folder containing `OT6.sfc`.

## Building

Put `Final Fantasy III (USA).sfc` (SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`) in the repository root, then run
`python3 configure.py` and `ninja`. See [the tooling guide](docs/TOOLING.md).

## License

OT6 code is MIT licensed. See [LICENSE](LICENSE). The FF6 disassembly, built
ROM, and release patch are GPL v3.
