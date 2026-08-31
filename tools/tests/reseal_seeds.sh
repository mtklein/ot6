#!/bin/sh
# reseal_seeds.sh -- re-cut every SRM seed whose boot state has moved past
# its sealed provenance.  Idempotent: a seed whose provenance is newer than
# its boot state is skipped, so running this after every chain wave keeps
# the seed set coherent with the lineage at no extra cost.
#
#   tools/tests/reseal_seeds.sh            # sweep everything stale
#
# Each row: <cutter> <boot state> <checkpoint dir> <payload>.
set -u
cd "$(dirname "$0")/../.." || exit 2

fail=0
sweep() {
  cutter=$1 state=$2 dir=$3 payload=$4
  prov="tools/tests/checkpoints/$dir/$payload.provenance.json"
  mss="build/states/$state.mss"
  [ -f "$mss" ] || { echo "[$dir] SKIP: $state.mss not generated yet"; return; }
  if [ -f "$prov" ] && [ ! "$mss" -nt "$prov" ]; then
    echo "[$dir] fresh (provenance newer than $state.mss)"
    return
  fi
  echo "[$dir] re-cutting from $state.mss ..."
  if OT6_CAPTURE_SRM="tools/tests/checkpoints/$dir/$payload" \
       tools/tests/run.sh "tools/tests/$cutter.lua" \
       "build/states/last_$cutter.log" >/dev/null 2>&1 \
     && python3 tools/tests/lib/sram_checkpoint.py seal \
          "tools/tests/checkpoints/$dir" \
     && python3 tools/tests/lib/sram_checkpoint.py validate \
          "tools/tests/checkpoints/$dir"; then
    echo "[$dir] sealed"
  else
    echo "[$dir] FAILED (see build/states/last_$cutter.log)"
    fail=1
  fi
}

sweep gen_seed_worldnarshe  worldmap_narshe world-narshe-v1     world-narshe.sram
sweep gen_seed_worldsfigaro south_figaro    world-sfigaro-v1    world-sfigaro.sram
sweep gen_seed_summit       vargas_entry    kolts-summit-v1     kolts-summit.sram
sweep gen_seed_hub          scenario_hub    hub-v1              hub.sram
sweep gen_seed_basement     sfigaro_escape  sfigaro-basement-v1 sfigaro-basement.sram
sweep gen_seed_train        train_done      train-engineer-v1   train-engineer.sram
sweep gen_seed_terracave    terra_clifftop  terra-caves-v1      terra-caves.sram

exit $fail
