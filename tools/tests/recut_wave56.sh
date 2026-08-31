#!/bin/sh
# recut_wave56.sh -- re-hang boundaries G through P on the fighting lineage.
#
# Same pattern as recut_wave4.sh, but this stretch's gens each cold-boot
# the PREVIOUS boundary's checkpoint and cut the NEXT one in a single
# hand-run (the invocations are documented per-step in savestate_graph.py):
#
#   G narshe-mission   <- terra-returned    (gen_narshe_mission)
#   H gate-cave-save   <- narshe-mission    (gen_gate_cave_save)
#   I vector-crash     <- gate-cave-save    (gen_vector_crash)
#   J banquet-done     <- vector-crash      (gen_banquet_done)
#   K crescent-landing <- banquet-done      (gen_voyage)
#   L thamasa-night    <- crescent-landing  (gen_thamasa_arrive)
#   M fire-out         <- thamasa-night     (gen_thamasa_fire)
#   N esper-mtn-save   <- fire-out          (gen_esper_mtn)
#   O ultros-won       <- esper-mtn-save    (gen_ultros)
#   P thamasa-done     <- ultros-won        (gen_massacre)
#
# Any failure stops the cascade with its log named; fix, commit, re-run --
# completed cuts are cheap to redo and the gens are deterministic.
set -u
cd "$(dirname "$0")/../.." || exit 2

CK=tools/tests/checkpoints
step() {
  gen=$1 prev=$2 dir=$3 payload=$4
  echo "=== $dir <- $prev (via $gen) ==="
  OT6_SRAM_CHECKPOINT="$CK/$prev" \
  OT6_CAPTURE_SRM="$CK/$dir/$payload" \
    tools/tests/run.sh "tools/tests/$gen.lua" "build/states/last_$gen.log" \
    || { echo "STEP FAILED: $gen (build/states/last_$gen.log)"; exit 1; }
  python3 tools/tests/lib/sram_checkpoint.py seal "$CK/$dir" || exit 1
  python3 tools/tests/lib/sram_checkpoint.py validate "$CK/$dir" || exit 1
}

step gen_narshe_mission terra-returned-v1   narshe-mission-v1   narshe-mission.sram
step gen_gate_cave_save narshe-mission-v1   gate-cave-save-v1   gate-cave-save.sram
step gen_vector_crash   gate-cave-save-v1   vector-crash-v1     vector-crash.sram
step gen_banquet_done   vector-crash-v1     banquet-done-v1     banquet-done.sram
step gen_voyage         banquet-done-v1     crescent-landing-v1 crescent-landing.sram
step gen_thamasa_arrive crescent-landing-v1 thamasa-night-v1    thamasa-night.sram
step gen_thamasa_fire   thamasa-night-v1    fire-out-v1         fire-out.sram
step gen_esper_mtn      fire-out-v1         esper-mtn-save-v1   esper-mtn-save.sram
step gen_ultros         esper-mtn-save-v1   ultros-won-v1       ultros-won.sram
step gen_massacre       ultros-won-v1       thamasa-done-v1     thamasa-done.sram

echo "=== waves 5+6 re-hung on the fighting lineage: the chain reaches the FC stop line ==="
