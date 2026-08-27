#!/bin/sh
# thamlab_batch.sh -- run a batch of Thamasa fire lab experiments.
#
#   tools/tests/thamlab_batch.sh <lab> <strategy> <seed> [seed ...]
#
#   lab       flame | ambush
#   strategy  control | taps (see probe_thamlab_template.lua)
#   seed      frames to stand still before engaging (shifts $021e; only
#             seed mod 60 matters -- $021e has period 60)
#
# Substitutes each seed into probe_thamlab_template.lua, runs the variants
# under run.sh with bounded parallelism, and prints the [result] line per
# run.  Knobs ride in as environment variables (defaults match the
# template): HEALPCT, BOOST, ITEMS, CURE, JOBS, TAG, FIXTURE.
#
# Machine etiquette: JOBS defaults to 3 and is clamped to 3 (the campaign's
# ceiling on concurrent emulator runs per agent).
#
# Results and per-run logs land in build/thamlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="${1:?usage: thamlab_batch.sh <lab> <strategy> <seed> [seed ...]}"
STRATEGY="${2:?usage: thamlab_batch.sh <lab> <strategy> <seed> [seed ...]}"
shift 2
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
FIXTURE="${FIXTURE:-thamlab_$LAB}"
HEALPCT="${HEALPCT:-60}"
BOOST="${BOOST:-1}"
ITEMS="${ITEMS:-1}"
CURE="${CURE:-1}"
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
      "$ROOT/tools/tests/probe_thamlab_template.lua" > "$lua"
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
