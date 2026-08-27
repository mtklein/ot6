#!/bin/sh
# thamlab_flame_batch.sh -- FlameEater-strategy agent's batch wrapper.
# Same shape as thamlab_batch.sh but substitutes into
# probe_thamlab_flame_aoe.lua (which adds the flame-aoe and libnuke
# strategies plus a HEALER knob: terra | all).
#
#   tools/tests/thamlab_flame_batch.sh <lab> <strategy> <seed> [seed ...]
#
# Env knobs: HEALPCT, BOOST, ITEMS, CURE, HEALER, JOBS (clamped to 3),
# TAG, FIXTURE.  Results and logs land in build/thamlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="${1:?usage: thamlab_flame_batch.sh <lab> <strategy> <seed> [seed ...]}"
STRATEGY="${2:?usage: thamlab_flame_batch.sh <lab> <strategy> <seed> [seed ...]}"
shift 2
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
FIXTURE="${FIXTURE:-thamlab_$LAB}"
HEALPCT="${HEALPCT:-60}"
BOOST="${BOOST:-1}"
ITEMS="${ITEMS:-1}"
CURE="${CURE:-1}"
HEALER="${HEALER:-terra}"
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-${LAB}_${STRATEGY}}"
OUT="$ROOT/build/thamlab"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@LAB@/$LAB/" -e "s/@STRATEGY@/$STRATEGY/" \
      -e "s/@SEED@/$seed/" -e "s/@FIXTURE@/$FIXTURE/" \
      -e "s/@HEALPCT@/$HEALPCT/" -e "s/@BOOST@/$BOOST/" \
      -e "s/@ITEMS@/$ITEMS/" -e "s/@CURE@/$CURE/" \
      -e "s/@HEALER@/$HEALER/" \
      "$ROOT/tools/tests/probe_thamlab_flame_aoe.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=900 OT6_WORKER="thamlab-$name" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/$name.log" > /dev/null 2>&1
  grep -h '^\[ot6\] \[result\]' "$OUT/$name.log" || echo "[result-missing] $name"
}

pids=""
n=0
for seed in "$@"; do
  run_one "$seed" &
  pids="$pids $!"
  n=$(( n + 1 ))
  if [ $(( n % JOBS )) -eq 0 ]; then wait; fi
done
wait
