#!/bin/sh
# probe_falls_wedge.sh [shards] [per_shard] -- run probe_falls_wedge.lua as
# N concurrent shards.  Each shard is a scratch copy of the probe with its
# SHARD line substituted (the sandbox cannot read the environment), so the
# attempts differ per shard and the logs land as
# build/states/probe_falls_wedge_s<N>.log.  Run from the tree root.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHARDS="${1:-6}"
PER="${2:-4}"
SCRATCH="${OT6_SCRATCH:-$ROOT/build/test-runs/falls_wedge}"
mkdir -p "$SCRATCH"
s=0
while [ "$s" -lt "$SHARDS" ]; do
  copy="$SCRATCH/probe_falls_wedge_s$s.lua"
  sed -e "s/^local SHARD = 0\$/local SHARD = $s/" \
      -e "s/^local PER_SHARD = 4\$/local PER_SHARD = $PER/" \
      "$ROOT/tools/tests/probe_falls_wedge.lua" > "$copy"
  OT6_WORKER="falls_s$s" OT6_TIMEOUT="${OT6_TIMEOUT:-3600}" \
    "$ROOT/tools/tests/run.sh" "$copy" "$ROOT/build/states/probe_falls_wedge_s$s.log" \
    > "$SCRATCH/s$s.out" 2>&1 &
  s=$((s + 1))
done
wait
s=0
while [ "$s" -lt "$SHARDS" ]; do
  printf 'shard %s: ' "$s"; tail -n 1 "$SCRATCH/s$s.out"
  s=$((s + 1))
done
