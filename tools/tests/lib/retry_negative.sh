#!/bin/sh
# retry_negative.sh: the segment runner's negative control (#178, #200).
#
# tools/tests/segment_retry.lua (suite) proves that a seed-dependent
# failure is replayed.  This is the other half: a CONTRACT failure (an
# assertEq) must fail on attempt 1 of 3 with NO replay, because a retry
# must never launder a bug.  A suite cannot expect a red run, so this
# drives tools/tests/probe_retry_negative.lua through the real path
# (tools/tests/run.sh) and asserts on the red verdict itself:
#
#   * run.sh exits non-zero;
#   * the log carries `[retry] attempt 1/3 FAILED class=assert`;
#   * no `attempt 2/3` line follows (nothing was replayed);
#   * the FAIL verdict says class=assert is NOT seed-dependent.
#
# Exit 0 only when the negative failed for the declared reason.  The run's
# output is build/states/retry_negative.log (run.sh's published log) and
# build/states/retry_negative.out (its stdout); grep those rather than
# the terminal scrollback.  Adding `assert` to the runner's RETRYABLE
# table, or breaking the classifier's assert branch, turns this red.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/build/states"
mkdir -p "$OUT"
LOG="$OUT/retry_negative.log"
STDOUT="$OUT/retry_negative.out"

fail() { echo "retry-negative: FAIL -- $1"; exit 1; }

# A deliberate failure still makes run.sh retain its workspace for
# inspection; this failure is the expected outcome, so reclaim the
# workspace once its log has been captured and checked.
reclaim_retained() {
  retained=$(sed -n 's/^failed run retained: //p' "$1")
  case "$retained" in
    "$ROOT"/build/test-runs/*) [ -d "$retained" ] && rm -rf "$retained" ;;
  esac
}

echo "retry-negative: an assertEq on attempt 1 of 3 must fail without a replay..."
if OT6_NO_PUBLISH=1 OT6_WORKER=retry_neg \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/probe_retry_negative.lua" "$LOG" \
   > "$STDOUT" 2>&1
then
  fail "the run came back GREEN: an assertEq failure passed (see $LOG)"
fi
grep -q '^\[ot6\] \[retry\] segment runner: probe_retry_negative, up to 3 attempt(s)' "$LOG" ||
  fail "the runner did not announce 3 attempts ($LOG)"
grep -q '^\[ot6\] \[retry\] attempt 1/3 FAILED class=assert ' "$LOG" ||
  fail "no '[retry] attempt 1/3 FAILED class=assert' line ($LOG)"
grep -q 'assertEq failed: on map 999 (an injected contract miss)' "$LOG" ||
  fail "the failure is not the injected contract miss ($LOG)"
if grep -q 'attempt 2/3' "$LOG"; then
  fail "the contract failure was REPLAYED: an 'attempt 2/3' line is in $LOG"
fi
grep -q '^\[ot6\] \[retry\] attempts=1/3 stopped; failed attempts: 1:assert' "$LOG" ||
  fail "the attempt tally is not 'attempts=1/3 stopped; failed attempts: 1:assert' ($LOG)"
grep -q 'class=assert is NOT seed-dependent, so this failed on attempt 1 of 3 without a retry' "$LOG" ||
  fail "the FAIL verdict does not say class=assert is not seed-dependent ($LOG)"
grep -q '^testrunner exit: 1 (verdict: 1)' "$STDOUT" ||
  fail "run.sh did not exit 1 ($STDOUT)"
reclaim_retained "$STDOUT"
echo "retry-negative: PASS -- attempt 1/3 failed class=assert, no attempt 2/3, verdict names the class"
