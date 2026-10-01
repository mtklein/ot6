# One-shot Homebrew setup for building and testing OT6: `brew bundle` here.
#
# The rest of the toolchain is not brew-installable — docs/TOOLING.md covers
# OT6's Mesen (tools/Mesen.app, built by tools/mesen/build.sh) and Flips
# (tools/bin/flips) — and you supply the base ROM (see README.md).

brew "cc65"   # ca65/ld65: assembles and links the whole game
brew "sdl2"   # MesenCore.dylib's one non-system link; Mesen aborts without it
brew "ninja"  # runs the generated savestate graph (build/build.ninja; #25)
brew "lua"    # the standalone library self-tests qualification runs (instruments.ok)
brew "dotnet@8"  # .NET 8 SDK (keg-only): builds OT6's Mesen's UI (tools/mesen/build.sh)

# Optional. The build itself needs only stock python3 (>=3.9); numpy is used
# by the asset re-encoders (ff6/tools/brr.py, monster_stencil.py,
# shuffle_rng.py), whose outputs are already tracked.
# brew "numpy"
