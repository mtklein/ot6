#!/bin/sh
# Make a fresh git worktree of this repo buildable/testable. Run from the
# worktree root. The gitignored pieces a worktree lacks are seeded from the
# main tree: the base ROM (copied — make verify hashes it), Mesen.app and
# tools/bin (symlinked — run.sh clones its own portable Mesen copy per run,
# so a shared read-only source bundle is safe), and the generated .lz
# compression products (regenerated from tracked sources via the Makefile's
# own %.lz rule; enumerating from src keeps this correct even when the .lz
# set changes).
set -eu

MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
HERE=$(pwd)
[ "$MAIN" = "$HERE" ] && { echo "already in the main tree; nothing to do"; exit 0; }

ROM="Final Fantasy III (USA).sfc"
[ -f "$HERE/$ROM" ] || cp "$MAIN/$ROM" "$HERE/$ROM"
[ -e "$HERE/tools/Mesen.app" ] || ln -s "$MAIN/tools/Mesen.app" "$HERE/tools/Mesen.app"
[ -e "$HERE/tools/bin" ] || ln -s "$MAIN/tools/bin" "$HERE/tools/bin"

# .lz products of tracked sources, built via make's %.lz: % rule
# (python3 tools/ff6_lzss.py). Two reference classes (see the 2026-07-18
# fresh-clone bootstrap): eight directories consumed wholesale through
# .sprintf-built filenames — grep can't see those, so compress every file
# in them — plus literal .incbin/.include paths, which grep can.
# ~1 min on first run, no-op after. This section becomes obsolete once
# explicit .lz deps land in ff6/Makefile.
cd "$HERE/ff6"
LZDIRS="src/field/map_tile_prop src/field/map_tileset src/field/overlay_prop
        src/field/sub_tilemap src/gfx/battle_bg_tiles src/gfx/battle_bg_gfx
        src/gfx/map_gfx_bg3 src/gfx/map_anim_gfx_bg3"
{
  for d in $LZDIRS; do find "$d" -type f ! -name '*.lz' | sed 's/$/.lz/'; done
  git grep -h -o '[A-Za-z0-9_./-]*\.lz' -- src | sort -u \
    | while read -r f; do
        case "$f" in src/*) ;; *) f="src/$f" ;; esac
        [ -f "${f%.lz}" ] && echo "$f" || true
      done
} | sort -u | xargs make -s -j8

echo "worktree ready: ROM copied, Mesen/flips linked, .lz seeded"
