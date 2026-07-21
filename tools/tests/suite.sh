#!/bin/sh
# suite.sh -- the OT6 correctness gate. Runs every test on every covered
# formation, honors an
# explicit expected-fail list. Nonzero exit on any unexpected result.
#
# OT6_JOBS=N fans the tests out across N isolated run.sh workers
# (OT6_WORKER; default 4 = the P-core knee, 1 = serial). Every suite test
# is a pure savestate load -- the mints (gen_battle_state, gen_battle2)
# run as Makefile prerequisites BEFORE the suite -- so tests are
# independent and fan out freely. Tests are composed once up front:
# composing reads lib/ot6.lua + lib/ot6_field.lua live, and a mid-suite
# edit must not split the suite across two libs.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$ROOT/tools/tests/run.sh"
SHOTS="$ROOT/build/states/shots"
JOBS="${OT6_JOBS:-4}"
# -------------------------------------------------------------- test discovery
# Suite membership is SELF-DECLARED, one marker per test file, so adding a test
# is a one-line edit to that test's OWN .lua -- never the shared list that every
# integration used to edit in lockstep (the merge magnet this replaced).  A test
# opts in with a directive comment on its first line:
#
#   -- @suite                          plain member
#   -- @suite slow                     member; a long-runner (LPT ordering hint)
#   -- @suite frontier=<fixture>       member IFF build/states/<fixture>.mss
#                                      exists -- else reported SKIPPED, never
#                                      silently dropped (see FRONTIER-GATED below)
#   -- @suite frontier=<fixture> slow  frontier member that is also a long-runner
#
# The four lists suite.sh used to hand-sync -- TESTS, FRONTIER_TESTS,
# frontier_fixture(), SCHED_LONG -- are ALL derived here in one pass from those
# markers.  The glob expands in sorted order, so discovery is deterministic; and
# because every suite test is a pure savestate load that run.sh isolates, the
# order tests run and print in carries no meaning (README: "order doesn't
# matter").  Membership and gating are what must be exact, and they are.
SUITE=""; FRONTIER_TESTS=""; FRONTIER_FIX=""; SLOW=""
for f in "$ROOT"/tools/tests/*.lua; do
  grep -q '^-- @suite' "$f" || continue
  t=$(basename "$f" .lua)
  attrs=$(sed -n 's/^-- @suite *//p' "$f" | head -n1)   # text after "@suite"
  fix=$(printf '%s' "$attrs" | sed -n 's/.*frontier=\([A-Za-z0-9_]*\).*/\1/p')
  if [ -n "$fix" ]; then
    FRONTIER_TESTS="$FRONTIER_TESTS $t"; FRONTIER_FIX="$FRONTIER_FIX $t=$fix"
  else
    SUITE="$SUITE $t"
  fi
  case " $attrs " in *" slow "*) SLOW="$SLOW $t" ;; esac
done
TESTS="$SUITE"

# Tests that must run under a dirty RAM fill (see battle_reveal_poweron): they
# boot from power-on, so the fill reaches battle init instead of being masked
# by a savestate load. AllOnes is dirty AND deterministic. run.sh rewrites the
# pin every run, so this env applies to exactly the one invocation.
ram_env_for() {
  case "$1" in
    battle_reveal_poweron) echo "OT6_RAM_POWERON=AllOnes" ;;
    *) echo "" ;;
  esac
}
# FRONTIER-GATED TESTS.  A frontier test asserts on a fixture that only
# `make frontier` mints -- reaching it replays the whole story chain, many
# multi-minute scripted playthroughs, the very cost the frontier exists to keep
# out of `make test`.  Such a test declares `-- @suite frontier=<fixture>` and
# joins the suite the instant build/states/<fixture>.mss exists; until then it is
# reported SKIPPED (below), never silently dropped.  `make frontier-test` mints
# the chain first, so it always runs whatever is mintable.  The per-test WHY --
# which fixture, and why that formation is the one that exercises the gate --
# lives in each test's own header now, right under its @suite marker.
frontier_fixture() {   # test name -> the abs .mss path from its @suite marker
  for pair in $FRONTIER_FIX; do
    case "$pair" in "$1="*) echo "$ROOT/build/states/${pair#*=}.mss"; return ;; esac
  done
}
skipped=""
for t in $FRONTIER_TESTS; do
  if [ -f "$(frontier_fixture "$t")" ]; then
    TESTS="$TESTS $t"
  else
    skipped="$skipped $t"
  fi
done

# `suite.sh --list` -- print what discovery resolved, run nothing, exit.  A fast
# check that a new @suite marker took: which tests would run, which are SKIPPED
# for an absent fixture, which count as long-runners.  `make test` calls suite.sh
# with no args, so this never touches the gate.
if [ "${1:-}" = "--list" ]; then
  set -- $TESTS;   echo "TESTS ($#): $*"
  set -- $skipped; echo "SKIPPED ($#): $*"
  set -- $SLOW;    echo "SLOW ($#): $*"
  exit 0
fi

XFAIL=""   # keep empty; XPASS fails the suite to force cleanup
fail=0; summary=""

result() { summary="$summary\n  $1: $2"; }

# verdict <test> <rc> <suffix> -- shared pass/FAIL/xfail/XPASS bookkeeping
verdict() {
  if [ "$2" -eq 0 ]; then
    case " $XFAIL " in
      *" $1 "*) result "$1" "XPASS (unexpected pass - remove from XFAIL)$3"; fail=1 ;;
      *) result "$1" "pass$3" ;;
    esac
  else
    case " $XFAIL " in
      *" $1 "*) result "$1" "xfail (known: formation VRAM clobber)$3" ;;
      *) result "$1" "FAIL (see build/states/suite_$1.log)$3"; fail=1 ;;
    esac
  fi
}

if [ "$JOBS" -gt 1 ]; then
  WROOT="$ROOT/build/test-workers"
  CDIR="$WROOT/suite-composed"; RDIR="$WROOT/suite-results"
  CLAIMS="$WROOT/suite-claims"
  rm -rf "$CDIR" "$RDIR" "$CLAIMS"; mkdir -p "$CDIR" "$RDIR" "$CLAIMS"
  for t in $TESTS; do
    python3 "$ROOT/tools/tests/lib/compose.py" \
      "$ROOT/tools/tests/$t.lua" "$CDIR/$t.lua" >/dev/null \
      || { echo "compose failed: $t"; exit 1; }
  done
  # Execution order for the pull queue below: front-load the known long
  # runners. Workers used to get a STATIC i%JOBS slice, and that was the whole
  # problem -- it pinned battle_class (~156s) AND battle_vargas (~64s) AND four
  # more onto one worker (~311s of work) while another drained in ~60s and then
  # sat idle. The fix is two things: (1) a dynamic claim queue -- each worker
  # grabs the NEXT unclaimed test as it frees up, so fast workers pull more --
  # and (2) longest-first order, so no worker ever starts a 156s test after the
  # rest have drained. That is textbook LPT scheduling: measured makespan
  # ~311s -> ~168s at JOBS=4, against a ~156s floor (the single longest test,
  # which no amount of fan-out can split). The long-runner set is ONLY a hint,
  # and it now comes from the `slow` attribute on tests' @suite markers ($SLOW,
  # discovered up top) instead of a hand-kept list here -- the list that used to
  # drift out of sync with TESTS. Every test still runs whether or not it is
  # marked slow (unmarked ones are appended below); a mis-marked duration just
  # costs a little idle tail, never a lost or double-run test. $SLOW is in sorted
  # order, which still front-loads the two longest (battle_class, battle_divines)
  # into the first wave -- all LPT needs; exact order past that barely moves the
  # makespan.
  in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
  ORDER=""
  for t in $SLOW; do in_list "$t" "$TESTS" && ORDER="$ORDER $t"; done
  for t in $TESTS; do in_list "$t" "$ORDER" || ORDER="$ORDER $t"; done
  w=0
  while [ "$w" -lt "$JOBS" ]; do
    (
      for t in $ORDER; do
        # Atomic claim: whoever creates the marker first runs the test; the
        # rest skip on. mkdir is the portable filesystem compare-and-swap, so
        # no test runs twice and (because every worker walks the whole list)
        # none is ever left unclaimed. Result files keep the same
        # "rc w secs" shape the verdict loop
        # already read, so nothing downstream changes.
        mkdir "$CLAIMS/$t" 2>/dev/null || continue
        t0=$(python3 -c 'import time; print(time.time())')
        env $(ram_env_for "$t") OT6_WORKER="$w" "$RUN" "$CDIR/$t.lua" "$ROOT/build/states/suite_$t.log" >/dev/null 2>&1
        rc=$?
        secs=$(python3 -c "import time; print(f'{time.time()-$t0:.1f}')")
        echo "$rc $w $secs" > "$RDIR/$t"
      done
    ) &
    w=$((w + 1))
  done
  wait
  for t in $TESTS; do
    if [ -f "$RDIR/$t" ]; then
      read -r rc w secs < "$RDIR/$t"
      verdict "$t" "$rc" " [w$w ${secs}s]"
    else
      result "$t" "FAIL (worker never reported)"; fail=1
    fi
  done
  # screenshots decode into the artifact dir of the worker that ran the test
  if [ -f "$RDIR/visual_f1" ]; then
    read -r rc w secs < "$RDIR/visual_f1"
    SHOTS="$WROOT/w$w/artifacts/shots"
  fi
else
  for t in $TESTS; do
    env $(ram_env_for "$t") "$RUN" "$ROOT/tools/tests/$t.lua" "$ROOT/build/states/suite_$t.log" >/dev/null 2>&1
    verdict "$t" "$?" ""
  done
fi

for t in $skipped; do
  result "$t" "skip (needs \`make frontier\`: $(frontier_fixture "$t") absent)"
done

printf "OT6 suite:%b\n" "$summary"
exit $fail
