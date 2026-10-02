#!/bin/sh
# reseal_seeds.sh -- re-cut every SRM seed whose boot state has moved past
# its sealed provenance.  Idempotent: a seed is fresh when its sealed
# manifest's ancestor record names its boot state's stamp with the sha256
# that stamp has now, and is skipped, so running this after every chain
# wave keeps the seed set coherent with the run at no extra cost.  The
# verdict is by content, not mtimes: a checkout that rewrites the
# provenance files does not make a stale seed look fresh (v0.24,
# build/attempts/wt/v024-recut/reseal/).
#
#   tools/tests/reseal_seeds.sh            # sweep everything stale
#
# Each row: <cutter> <boot state> <checkpoint dir> <payload>.  The
# checkpoints a cut boots (savestate_graph.py, prev= with checkpoint=) are
# not here: `ninja chain` captures each of those into
# build/checkpoints/<key>/ (docs/TOOLING.md).
set -u
cd "$(dirname "$0")/../.." || exit 2

fail=0
sweep() {
  cutter=$1 state=$2 dir=$3 payload=$4
  stamp="build/states/$state.stamp"
  [ -f "build/states/$state.mss" ] && [ -f "$stamp" ] ||
    { echo "[$dir] SKIP: $state.mss not generated yet"; return; }
  # the sha256 the sealed manifest records for the boot state's stamp, or
  # nothing when it records none (an unsealed or legacy seed: re-cut it)
  recorded=$(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
p = m.get("provenance")
for a in (p.get("ancestors", []) if isinstance(p, dict) else []):
    if a.get("path") == sys.argv[2]:
        print(a.get("sha256", ""))
' "tools/tests/checkpoints/$dir/manifest.json" "$stamp" 2>/dev/null)
  now=$(shasum -a 256 "$stamp" 2>/dev/null || sha256sum "$stamp")
  now=${now%% *}
  if [ -n "$recorded" ] && [ "$recorded" = "$now" ]; then
    echo "[$dir] fresh (sealed from $stamp ${now%"${now#????????????}"})"
    return
  fi
  echo "[$dir] stale: sealed from $stamp ${recorded:-(no record)}, which is now $now"
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

sweep gen_seed_worldsfigaro south_figaro    world-sfigaro-v1    world-sfigaro.sram
sweep gen_seed_basement     sfigaro_escape  sfigaro-basement-v1 sfigaro-basement.sram
sweep gen_seed_train        train_done      train-engineer-v1   train-engineer.sram
sweep gen_seed_terracave    terra_clifftop  terra-caves-v1      terra-caves.sram

exit $fail
