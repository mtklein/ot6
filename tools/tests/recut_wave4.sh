#!/bin/sh
# recut_wave4.sh -- re-hang the Vector-era chain off the fighting lineage.
#
# The chain from vector_entry onward cold-boots the lettered SRAM
# checkpoints (A: post-opera, B: mrf-save-room, C: n024-entry-save,
# D: minecart-platform, E: vector-escape, F: terra-returned), and those
# payloads still hold the FLED lineage's party.  The graph's own rule --
# "editing either [manifest or payload] regenerates every state hung off
# the checkpoint" -- makes the re-cut cascade mechanical:
#
#   cut A from my blackjack -> ninja to ifrit_entry -> cut B ->
#   ninja to n024_entry -> cut C -> ninja to minecart_entry -> cut D ->
#   ninja to n128_won -> cut E and F.
#
# Each cut drives the game's own Save UI (the hand-run gen_*_checkpoint
# generators the graph documents), captures via OT6_CAPTURE_SRM, seals,
# and validates.  Any failure stops the cascade with its log named.
set -u
cd "$(dirname "$0")/../.." || exit 2

CK=tools/tests/checkpoints
cut() {
  gen=$1 dir=$2 payload=$3
  echo "=== cut $dir (via $gen) ==="
  OT6_CAPTURE_SRM="$CK/$dir/$payload" \
    tools/tests/run.sh "tools/tests/$gen.lua" "build/states/last_$gen.log" \
    || { echo "CUT FAILED: $gen (build/states/last_$gen.log)"; exit 1; }
  python3 tools/tests/lib/sram_checkpoint.py seal "$CK/$dir" || exit 1
  python3 tools/tests/lib/sram_checkpoint.py validate "$CK/$dir" || exit 1
}
build() {
  echo "=== ninja $1 ==="
  ninja "build/states/$1.mss.lua" || { echo "NINJA FAILED at $1"; exit 1; }
}

cut   gen_post_opera_checkpoint        post-opera-v1        post-opera.sram
build ifrit_entry
cut   gen_mrf_save_room_checkpoint     mrf-save-room-v1     mrf-save-room.sram
build n024_entry
cut   gen_n024_save_checkpoint         n024-entry-save-v1   n024-entry-save.sram
build minecart_entry
cut   gen_minecart_platform_checkpoint minecart-platform-v1 minecart-platform.sram
build n128_won
cut   gen_vector_escape_checkpoint     vector-escape-v1     vector-escape.sram
cut   gen_terra_returned_checkpoint    terra-returned-v1    terra-returned.sram

echo "=== wave 4 re-hung on the fighting lineage ==="
