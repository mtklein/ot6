# OT6

OT6 is a Final Fantasy VI ROM hack. It adds Octopath Traveler combat
mechanics while keeping the FF6 story, world, and characters.

## Changes

- Enemies have shields and weaknesses. Weak hits remove shields. Broken
  enemies lose turns and take more damage.
- Characters gain and spend Boost Points. Boost can add hits, raise spell
  tiers, improve odds, or extend effects.
- Equipped Magicite grant spells and stats. They do not teach spells
  permanently.
- Characters have distinct skill sets.

See [the design](docs/DESIGN.md) for details.

## Building

Put `Final Fantasy III (USA).sfc` (SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`) in the repository root, then run
`python3 configure.py` and `ninja`. See [the tooling guide](docs/TOOLING.md).

## License

OT6 code is MIT licensed. See [LICENSE](LICENSE). The FF6 disassembly, built
ROM, and release patch are GPL v3.
