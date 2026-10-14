#!/bin/sh
# gate.sh [ninja args...] -- run ninja and exit with ninja's own status,
# then repeat its FAILED lines at the end where a reader looks (#248).
#
#   sh tools/gate.sh -k 0            # the qualification gate
#   sh tools/gate.sh -k 0 release    # the release gate
#
# Why: a backgrounded `(ninja ...; echo NINJA_EXIT=$?)` exits with echo's 0,
# so a task notification read green on a red gate twice in the v0.21 gate.
# Here the last command is `exit` with ninja's status, so whatever runs this
# sees ninja's verdict, and the summary line says it in words too.
# OT6_GATE_LOG names the log the output is also written to (default:
# build/gate.log, overwritten each run).  The log opens with the commit and
# the tree's state and closes with the summary and ninja's exit status, so
# a log read on its own says what ran and how it ended (#424: qualification
# logs stopped one edge short, with no status, and "green" rested on the
# absence of FAILED lines).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${OT6_GATE_LOG:-$ROOT/build/gate.log}"
mkdir -p "$(dirname "$LOG")"
STATUS="$LOG.status.$$"
SHA=$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY=$(cd "$ROOT" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "gate: start $(date -u +%Y-%m-%dT%H:%M:%SZ) sha=$SHA dirty=$DIRTY host=$(uname -n) ninja $*" | tee "$LOG"
# The pipe through tee would hand back tee's status; ninja's is kept aside.
{ ninja "$@" 2>&1; echo $? > "$STATUS"; } | tee -a "$LOG"
rc=$(cat "$STATUS" 2>/dev/null || echo 2)
rm -f "$STATUS"
failed=$(grep -c '^FAILED: ' "$LOG")
{
  echo "--------------------------------------------------------------------"
  if [ "$rc" -eq 0 ]; then
    echo "gate: GREEN -- ninja $* exited 0 (log $LOG)"
  else
    echo "gate: RED -- ninja $* exited $rc, $failed FAILED edge(s) (log $LOG):"
    grep '^FAILED: ' "$LOG"
  fi
  echo "gate: end $(date -u +%Y-%m-%dT%H:%M:%SZ) rc=$rc sha=$SHA"
} | tee -a "$LOG"
exit "$rc"
