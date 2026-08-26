#!/bin/sh
# link_rom.sh <cfg> <out.sfc> <obj...> -- the double-link ROM recipe.
#
# ld65 config maps the cutscene wram segment to temp_lz/cutscene.bin (the
# path is hardcoded in cfg/ff6-*.cfg's bank_7e FILE=), so: link once to
# materialize that segment, lzss-compress it, wrap the .lz in a one-line
# .incbin module, assemble it, link again with that object appended, then
# fix the SNES checksum.  Verbatim from the old ff6/Makefile ROM recipes.
#
# temp_lz is shared scratch BECAUSE the cfg hardcodes it, so two ROM links
# must never run concurrently; the ninja graph serializes them with an
# order-only edge (make never hit this because it built targets serially).
#
# Runs with cwd=ff6 (all cfg/source paths are ff6-relative).
set -eu
cfg="${1:?cfg}"
out="${2:?out.sfc}"
shift 2

cd "$(dirname "$0")/../../ff6"
mkdir -p temp_lz rom

ld65 -o "" -C "$cfg" "$@"
python3 tools/encode_cutscene.py temp_lz/cutscene.bin temp_lz/cutscene.lz
printf '.segment "cutscene_lz"\n.incbin "cutscene.lz"' > temp_lz/cutscene_lz.asm
ca65 --bin-include-dir temp_lz temp_lz/cutscene_lz.asm -o temp_lz/cutscene.lz.o
ld65 --dbgfile "${out%.sfc}.dbg" -m "${out%.sfc}.map" -o "$out" -C "$cfg" \
  "$@" temp_lz/cutscene.lz.o
rm -rf temp_lz
python3 tools/fix_checksum.py "$out"
