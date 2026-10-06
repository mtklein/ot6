#!/bin/sh
# run_suite_test.sh <test> <ok-file> -- compose and run one suite test.
#
# The per-test edge body for the ninja graph.  Per-test environment
# (OT6_RAM_POWERON, OT6_SRAM_CHECKPOINT) arrives via the edge's `env =`
# splice, exported by the shell before this script runs.
#
# OT6_STACK=quick_ (`ninja quick`, savestate_ninja.py QUICK) composes the
# test against the quick_ copies of its fixtures, under its own composed
# file and log names.
#
# On failure the log's FAIL lines are printed so ninja's failure output
# names the assertion, not just the command; the full log path is stated
# for the rest.
set -u
t="${1:?test name}"
ok="${2:?ok path}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
n="${OT6_STACK:-}$t"

mkdir -p build/ninja/composed build/states
if ! python3 tools/tests/lib/compose.py "tools/tests/$t.lua" \
     "build/ninja/composed/$n.lua" > "build/ninja/composed/$n.compose.log" 2>&1
then
  echo "compose failed: $t"
  cat "build/ninja/composed/$n.compose.log"
  exit 1
fi

log="build/states/suite_$n.log"
if OT6_WORKER="$n" tools/tests/run.sh "build/ninja/composed/$n.lua" "$log" \
     >/dev/null 2>&1
then
  : > "$ok"
else
  rc=$?
  echo "FAIL: $t (rc=$rc) -- $log"
  grep -E 'FAIL|assertEq|Error' "$log" | tail -5
  exit "$rc"
fi
