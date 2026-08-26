#!/bin/sh
# run_suite_test.sh <test> <ok-file> -- compose and run one suite test.
#
# The per-test edge body for the ninja graph: what one iteration of
# suite.sh's worker loop used to do, minus the scheduling (ninja's job
# server owns that now) and minus the tally (the release artifact depends
# on every test's .ok, so "how many ran, how many skipped" is structural:
# an absent result is an unbuilt target, not a number to cross-check).
#
# Per-test environment (the old ram_env_for table: OT6_RAM_POWERON,
# OT6_SRAM_CHECKPOINT) arrives via the edge's `env =` splice, exported by
# the shell before this script runs, so this file stays a mechanism with
# no test-specific knowledge.
#
# On failure the log's FAIL lines are printed so ninja's failure output
# names the assertion, not just the command; the full log path is stated
# for the rest.
set -u
t="${1:?test name}"
ok="${2:?ok path}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

mkdir -p build/ninja/composed build/states
if ! python3 tools/tests/lib/compose.py "tools/tests/$t.lua" \
     "build/ninja/composed/$t.lua" > "build/ninja/composed/$t.compose.log" 2>&1
then
  echo "compose failed: $t"
  cat "build/ninja/composed/$t.compose.log"
  exit 1
fi

log="build/states/suite_$t.log"
if OT6_WORKER="$t" tools/tests/run.sh "build/ninja/composed/$t.lua" "$log" \
     >/dev/null 2>&1
then
  : > "$ok"
else
  rc=$?
  echo "FAIL: $t (rc=$rc) -- $log"
  grep -E 'FAIL|assertEq|Error' "$log" | tail -5
  exit "$rc"
fi
