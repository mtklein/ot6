#!/bin/sh
# rafterlab_bake_seeds.sh -- bake the arrangement-seed catwalk fixtures
# rafterlab_catwalk_s0..s7 from probe_rafterlab_catwalk_seed.lua, 4 at a
# time.  Delays are k*25 frames spent just inside map 235: 150 frames was
# measured to fully decorrelate the arrangement, while delays >=450 shifted
# rat 0 into the approach path and the resulting battle both taxed ~2600
# frames and resynchronized the arrangements -- so the ladder stays small.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/rafterlab"
mkdir -p "$OUT"
bake() {
  k=$1; delay=$2
  lua="$OUT/bake_s$k.lua"
  sed -e "s/@DELAY@/$delay/" -e "s/@SEED@/s$k/g" \
    "$ROOT/tools/tests/probe_rafterlab_catwalk_seed.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=900 OT6_WORKER="rafterlab-bake-s$k" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/bake_s$k.log" > /dev/null 2>&1
  grep -h "CATWALK-s\|banked" "$OUT/bake_s$k.log" | grep '^\[ot6\]' | tail -2
}
for k in 0 1 2 3; do bake "$k" $(( k * 25 )) & done
wait
for k in 4 5 6 7; do bake "$k" $(( k * 25 )) & done
wait
ls -la "$ROOT"/build/states/rafterlab_catwalk_s*.mss 2>/dev/null
