#!/bin/sh
# build-c.sh -- regenerate ff6/src/c/ot6c.raw from the C sources with the
# Calypsi 65816 toolchain (expanded locally under tools/calypsi, see
# docs/TOOLING.md). The 6-byte-per-leaf outputs are committed, so this
# only needs to run when a .c file changes.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAL="$ROOT/tools/calypsi/expanded/Payload/usr/local/lib/calypsi-65816-5.17/bin"
CD="$ROOT/ff6/src/c"

# cc65816 ignores -o for -S output and writes the .s into the CURRENT
# directory (measured on 5.17 during the 2026-07-20 restore: run from the
# repo root it left a stray ./ot6spike.s and never touched the tracked
# one). cd into the source dir so the tracked .s is the one regenerated,
# from wherever the script is invoked.
cd "$CD"
"$CAL/cc65816" --target snes --code-model large --data-model large \
    -O2 --speed -S "$CD/ot6spike.c" -o "$CD/ot6spike.s"
"$CAL/as65816" "$CD/ot6spike.s" -o "$CD/ot6spike.o"
"$CAL/ln65816" --no-auto-libraries --root-symbol ot6_c_mix \
    --output-format raw --list-file "$CD/ot6c.map" \
    -o "$CD/ot6c.bin" "$CD/ot6spike.o" "$CD/ot6-rom.scm"
# ln65816 emits the actual raw bytes as <output>.raw
ls -la "$CD/ot6c.raw"
echo "rebuilt; symbol map in ff6/src/c/ot6c.map"
