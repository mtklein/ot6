#!/bin/sh
# Positive concurrency control for issue #14.  It overlaps two
# run.sh calls carrying the same worker label, then two suite.sh calls, and
# checks that each pair owns distinct live directories.  Probe modes stop
# before Mesen/test discovery, so this is fast and deterministic.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ot6-runner-selftest.XXXXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

check_pair() {
  kind=$1
  a=$2
  b=$3
  gate=$4
  tries=0
  while { [ ! -s "$a" ] || [ ! -s "$b" ]; }; do
    sleep 1
    tries=$((tries + 1))
    [ "$tries" -lt 15 ] || { echo "$kind isolation selftest: probes timed out"; return 1; }
  done
  pa=$(cat "$a"); pb=$(cat "$b")
  [ "$pa" != "$pb" ] || { echo "$kind isolation selftest: shared $pa"; return 1; }
  [ -d "$pa" ] && [ -d "$pb" ] || {
    echo "$kind isolation selftest: workspace vanished before release"; return 1; }
  : > "$gate"
}

gate="$TMP/run.go"
OT6_WORKER=same OT6_ISOLATION_PROBE_OUT="$TMP/run.a" OT6_ISOLATION_PROBE_GO="$gate" \
  "$ROOT/tools/tests/run.sh" ignored.lua &
p1=$!
OT6_WORKER=same OT6_ISOLATION_PROBE_OUT="$TMP/run.b" OT6_ISOLATION_PROBE_GO="$gate" \
  "$ROOT/tools/tests/run.sh" ignored.lua &
p2=$!
check_pair runner "$TMP/run.a" "$TMP/run.b" "$gate" || exit 1
wait "$p1"; wait "$p2"

gate="$TMP/suite.go"
"$ROOT/tools/tests/suite.sh" --isolation-probe "$TMP/suite.a" "$gate" &
p1=$!
"$ROOT/tools/tests/suite.sh" --isolation-probe "$TMP/suite.b" "$gate" &
p2=$!
check_pair suite "$TMP/suite.a" "$TMP/suite.b" "$gate" || exit 1
wait "$p1"; wait "$p2"

echo "runner isolation selftest: ok"
