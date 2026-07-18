# One-shot Homebrew setup for building and testing OT6: `brew bundle` here.
#
# The rest of the toolchain is not brew-installable — docs/TOOLING.md covers
# Mesen 2.1.1 (tools/Mesen.app), Flips (tools/bin/flips), and the optional
# Calypsi 65816 C toolchain — and you supply the base ROM (see README.md).

brew "cc65"   # ca65/ld65: assembles and links the whole game
brew "sdl2"   # MesenCore.dylib's one non-system link; Mesen aborts without it

# Optional. The build itself needs only stock python3 (>=3.9); numpy is used
# by the asset re-encoders (ff6/tools/brr.py, monster_stencil.py,
# shuffle_rng.py), whose outputs are already tracked.
# brew "numpy"
