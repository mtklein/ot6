#!/bin/sh
# suite.sh -- the OT6 correctness check. Runs every test on every covered
# formation, honors an
# explicit expected-fail list. Nonzero exit on any unexpected result.
#
# OT6_JOBS=N fans the tests out across N isolated run.sh workers
# (OT6_WORKER; 1 = serial). Every suite test is a pure savestate load, since
# the savestate generators (gen_battle_state, gen_battle2) run as Makefile
# prerequisites before the suite, so tests are independent and fan out
# freely. Tests are composed once up front:
# composing reads lib/ot6.lua + lib/ot6_field.lua live, and a
# mid-suite edit must not split the suite across two libs.
#
# The default is the machine's P-core count (perflevel0) rather than a fixed
# number. Measured on an M4 Max (10 P-cores, 42-test suite): the LPT makespan
# is CPU-bound until ~6 workers (113s at 4 -> 83s at 6) and flat past that,
# where the limit is the single longest test, which no fan-out can split
# (battle_rage, 112s on the v0.15 gate's 94-test run). So the P-core count
# auto-sizes to the CPU-bound region and self-caps at the floor;
# over-provisioning workers is harmless (idle pull-queue slots), and the old
# hardcoded 4 left P-cores idle on anything bigger than a 4-core part. To
# push under the floor, shorten the longest test itself; adding workers will
# not do it.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$ROOT/tools/tests/run.sh"
SHOTS="$ROOT/build/states/shots"
JOBS="${OT6_JOBS:-$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo 4)}"

# Suite bookkeeping is per invocation too.  This matters when two independent
# `make test` processes overlap: worker numbers are local scheduling labels,
# not globally unique directory names.
SROOT_BASE="$ROOT/build/test-suites"
mkdir -p "$SROOT_BASE"
SROOT=$(mktemp -d "$SROOT_BASE/suite.XXXXXXXX") || exit 2
cleanup_suite() {
  [ "${OT6_KEEP_RUNS:-0}" = 1 ] || rm -rf "$SROOT"
}
trap cleanup_suite EXIT INT TERM

# Code-coverage mode (#130): with OT6_COVERAGE set in the environment, every
# run.sh dumps a CDL touched-byte bitmap (lib/ot6.lua coverageFlush).  Give
# each test its own artifact dir so the per-test coverage.cdl files do not
# clobber one another under the shared build/states publish dir, then union
# them with lib/coverage_report.py after the run.  Inert when unset, so the
# correctness path is unchanged.  OT6_COVERAGE itself already inherits into
# each run.sh through env(1); only the per-test artifact dir needs setting.
COVDIR=""
if [ -n "${OT6_COVERAGE:-}" ]; then COVDIR="$SROOT/coverage"; mkdir -p "$COVDIR"; fi
cov_env_for() { [ -n "$COVDIR" ] && printf 'OT6_ARTIFACT_DIR=%s' "$COVDIR/$1"; }

# Test-only rendezvous used by runner_isolation_selftest.sh.
if [ "${1:-}" = "--isolation-probe" ]; then
  printf '%s\n' "$SROOT" > "${2:?probe output path required}"
  while [ ! -f "${3:?probe gate path required}" ]; do sleep 1; done
  [ -d "$SROOT" ] || exit 1
  exit 0
fi
# -------------------------------------------------------------- test discovery
# Suite membership is self-declared, one marker per test file, so adding a test
# is a one-line edit to that test's own .lua rather than an edit to the shared
# list that every integration used to change in lockstep, which drew merge
# conflicts.  A test opts in with a directive comment on its first line:
#
#   -- @suite                          plain member
#   -- @suite slow                     member; a long-runner (LPT ordering hint)
#   -- @suite savestate=<fixture>      member if and only if
#                                      build/states/<fixture>.mss exists;
#                                      otherwise reported SKIPPED rather than
#                                      dropped without notice (see the
#                                      savestate= section below)
#   -- @suite savestate=<fixture> slow savestate= member, also a long-runner
#
# The four lists suite.sh used to hand-sync (TESTS, SAVESTATE_TESTS,
# savestate_fixture(), SCHED_LONG) are all derived here in one pass from those
# markers.  The glob expands in sorted order, so discovery is deterministic,
# and because every suite test is a pure savestate load that run.sh isolates,
# the order tests run and print in carries no meaning (README: "order doesn't
# matter").  Membership and the fixture condition are what must be exact.
SUITE=""; SAVESTATE_TESTS=""; SAVESTATE_FIX=""; SLOW=""
for f in "$ROOT"/tools/tests/*.lua; do
  grep -q '^-- @suite' "$f" || continue
  t=$(basename "$f" .lua)
  attrs=$(sed -n 's/^-- @suite *//p' "$f" | head -n1)   # text after "@suite"
  fix=$(printf '%s' "$attrs" | sed -n 's/.*savestate=\([A-Za-z0-9_]*\).*/\1/p')
  if [ -n "$fix" ]; then
    SAVESTATE_TESTS="$SAVESTATE_TESTS $t"; SAVESTATE_FIX="$SAVESTATE_FIX $t=$fix"
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
    # battle_reveal_poweron additionally cold-boots a tracked battery (issue
    # #75): its slot-3 page is the real persistent knowledge New Game must
    # preserve, and its valid stale transient page is the knowledge New Game
    # must wipe.  Which battery is not free: it has to carry both, and that
    # is a property of the battery rather than of the test.  post-opera-v1
    # was the original pick and carries neither -- measured 2026-08-13, its
    # slot-3 and transient pages hold the 'O8' magic and zero knowledge
    # bytes, where every other tracked battery holds 2 to 13.
    # terra-returned-v1 is slot 3, layout ot6-codex-o8-v1, slot-3 page 11
    # bytes, transient page 2.
    battle_reveal_poweron) echo "OT6_RAM_POWERON=AllOnes OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1" ;;
    # battle_slotsboot cold-Continues the tracked terra-returned battery --
    # the same checkpoint hand-off the Makefile's SMOKE_CHECKPOINT_* map gives
    # the smoke generators that use one (run.sh materializes it before boot).
    battle_slotsboot) echo "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1" ;;
    # battle_slots' input-driven half (issue #75) cold-Continues the same
    # checkpoint for its tier-1/tier-2 spins before its labeled quarantine lab.
    battle_slots) echo "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1" ;;
    *) echo "" ;;
  esac
}
# Tests that need the generated savestates.  Such a test asserts on a fixture
# that only `make savestates` generates; reaching it replays the whole story
# chain, many multi-minute scripted playthroughs, which is the cost
# `make savestates` exists to keep out of `make test`.  Such a test declares
# `-- @suite savestate=<fixture>` and
# joins the suite once build/states/<fixture>.mss exists; until then it is
# reported SKIPPED (below) rather than dropped without notice.
# `make savestates-test` generates the chain first, so it always runs whatever
# can be generated.  The reason for each such test, which fixture it uses and
# why that formation is the one that exercises the check, lives in that test's
# own header, under its @suite marker.
savestate_fixture() {   # test name -> the abs .mss path from its @suite marker
  for pair in $SAVESTATE_FIX; do
    case "$pair" in "$1="*) echo "$ROOT/build/states/${pair#*=}.mss"; return ;; esac
  done
}
skipped=""
for t in $SAVESTATE_TESTS; do
  if [ -f "$(savestate_fixture "$t")" ]; then
    TESTS="$TESTS $t"
  else
    skipped="$skipped $t"
  fi
done

# `suite.sh --list`: print what discovery resolved, run nothing, exit.  A fast
# check that a new @suite marker took: which tests would run, which are SKIPPED
# for an absent fixture, which count as long-runners.  `make test` calls suite.sh
# with no args, so this never touches the correctness check.
if [ "${1:-}" = "--list" ]; then
  set -- $TESTS;   echo "TESTS ($#): $*"
  set -- $skipped; echo "SKIPPED ($#): $*"
  set -- $SLOW;    echo "SLOW ($#): $*"
  exit 0
fi

XFAIL=""   # keep empty; XPASS fails the suite to force cleanup
fail=0; summary=""
# Tally, printed as one line under the per-test list.  Establishing "82 pass,
# 0 fail" used to mean grepping the output for '": pass ["' and counting, and
# an agent doing that from a scrolled terminal counts what is in the window
# rather than what the run did.  Same reasoning as the $(STAMP) machinery in
# the Makefile ("nothing here is allowed to depend on remembering to look"),
# one level down: the exit status is still what decides, but the number is now
# stated rather than reconstructed.  Counted in verdict()/result() so that a
# category added later cannot stay out of the total without notice; the
# breakdown is summed at print time and cross-checked against it.
n_pass=0; n_fail=0; n_xfail=0; n_xpass=0; n_skip=0

result() { summary="$summary\n  $1: $2"; }

# verdict <test> <rc> <suffix> -- shared pass/FAIL/xfail/XPASS bookkeeping
verdict() {
  if [ "$2" -eq 0 ]; then
    case " $XFAIL " in
      *" $1 "*) result "$1" "XPASS (unexpected pass - remove from XFAIL)$3"
                n_xpass=$((n_xpass + 1)); fail=1 ;;
      *) result "$1" "pass$3"; n_pass=$((n_pass + 1)) ;;
    esac
  else
    case " $XFAIL " in
      *" $1 "*) result "$1" "xfail (known: formation VRAM clobber)$3"
                n_xfail=$((n_xfail + 1)) ;;
      *) result "$1" "FAIL (see build/states/suite_$1.log)$3"
         n_fail=$((n_fail + 1)); fail=1 ;;
    esac
  fi
}

# Fixture freshness, stated before the run rather than discovered after it.
# A stale generated fixture makes a test red for a reason other than the
# reader's change, and the only notice of it used to be a print() inside
# build/states/suite_<t>.log, which nobody opens for a test they did not
# expect to fail.  ~2s for ~105 fixtures, against a multi-minute suite.
if [ -d "$ROOT/build/states" ]; then
  python3 "$ROOT/tools/tests/lib/compose.py" --check-states || {
    echo "^^ read that before you debug a red test below."
    echo
  }
fi

if [ "$JOBS" -gt 1 ]; then
  CDIR="$SROOT/composed"; RDIR="$SROOT/results"
  CLAIMS="$SROOT/claims"; LDIR="$SROOT/logs"
  mkdir -p "$CDIR" "$RDIR" "$CLAIMS" "$LDIR"
  for t in $TESTS; do
    # Keep the whole compose log.  `>/dev/null` used to discard it, including,
    # on failure, the only line saying why, leaving "compose failed: <test>"
    # and nothing else.  That is the shape of the mistake the brief warns
    # about ("do not let a pipe eat your failure"), and it got worse
    # when an ambiguous symbol became a fatal compose error: the message
    # naming both candidate addresses would have gone straight to /dev/null.
    if ! python3 "$ROOT/tools/tests/lib/compose.py" \
         "$ROOT/tools/tests/$t.lua" "$CDIR/$t.lua" > "$SROOT/compose.$t" 2>&1
    then
      echo "compose failed: $t"
      cat "$SROOT/compose.$t"
      exit 1
    fi
    # Warnings other than the fixture staleness already reported above, such
    # as an unresolvable symbol.  Deduped across tests: ~100 tests share
    # ~30 fixtures, so an undeduped list is the same line a hundred times.
    grep '^WARNING' "$SROOT/compose.$t" | grep -v 'is STALE' | grep -v 'is UNBOUND' >> "$SROOT/warn" || :
  done
  if [ -s "$SROOT/warn" ]; then
    echo "compose warnings:"
    sort -u "$SROOT/warn" | sed 's/^/  /'
    echo
  fi
  # Execution order for the pull queue below: front-load the known long
  # runners. Workers used to get a static i%JOBS slice, which was the problem:
  # it pinned battle_class (~156s), battle_vargas (~64s) and four
  # more onto one worker (~311s of work) while another drained in ~60s and then
  # sat idle. The fix is two things: (1) a dynamic claim queue, in which each
  # worker grabs the next unclaimed test as it frees up, so fast workers pull
  # more, and (2) longest-first order, so no worker starts a 156s test after the
  # rest have drained. That is LPT scheduling: measured makespan
  # ~311s -> ~168s at JOBS=4, against a ~156s floor (the single longest test,
  # which no amount of fan-out can split). The long-runner set is only a hint,
  # and it now comes from the `slow` attribute on tests' @suite markers ($SLOW,
  # discovered up top) instead of a hand-kept list here, which used to
  # drift out of sync with TESTS. Every test still runs whether or not it is
  # marked slow (unmarked ones are appended below); a mis-marked duration
  # costs a little idle tail and never loses or double-runs a test. $SLOW is in
  # sorted order, which still front-loads the longest runners into the first
  # wave, which is all LPT needs; exact order past that barely moves the
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
        env $(ram_env_for "$t") $(cov_env_for "$t") OT6_WORKER="$w" "$RUN" "$CDIR/$t.lua" "$LDIR/$t.log" >/dev/null 2>&1
        rc=$?
        # Preserve the familiar diagnostic path, but publish it atomically.
        tmp="$ROOT/build/states/suite_$t.log.tmp.$$"
        cp "$LDIR/$t.log" "$tmp" && mv -f "$tmp" "$ROOT/build/states/suite_$t.log"
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
      result "$t" "FAIL (worker never reported)"
      n_fail=$((n_fail + 1)); fail=1
    fi
  done
else
  for t in $TESTS; do
    env $(ram_env_for "$t") $(cov_env_for "$t") "$RUN" "$ROOT/tools/tests/$t.lua" "$ROOT/build/states/suite_$t.log" >/dev/null 2>&1
    verdict "$t" "$?" ""
  done
fi

for t in $skipped; do
  result "$t" "skip (needs \`make savestates\`: $(savestate_fixture "$t") absent)"
  n_skip=$((n_skip + 1))
done

printf "OT6 suite:%b\n" "$summary"

# The tally.  `ran` is summed from the categories rather than counted
# separately, and then checked against the discovered TESTS list: if the two
# disagree, a test was discovered and never accounted for, which is worse
# than printing no summary line at all.  Say so and fail rather than print a
# number that is short without saying so.
set -- $TESTS; discovered=$#
ran=$((n_pass + n_fail + n_xfail + n_xpass))
line="$ran ran: $n_pass pass, $n_fail fail"
[ "$n_xfail" -gt 0 ] && line="$line, $n_xfail xfail"
[ "$n_xpass" -gt 0 ] && line="$line, $n_xpass XPASS"
[ "$n_skip"  -gt 0 ] && line="$line; $n_skip skipped (need \`make savestates\`)"
if [ "$ran" -ne "$discovered" ]; then
  line="$line -- BUG: $discovered tests were discovered but $ran reported"
  fail=1
fi
if [ "$fail" -eq 0 ]; then
  echo "OT6 suite: GREEN -- $line"
else
  echo "OT6 suite: RED -- $line"
fi

# The machine-readable tally, for callers that must CHECK a suite result
# instead of rerunning the suite (the Makefile's release gate).  The ROM sha
# binds the verdicts to the exact ROM they are about -- the same binding the
# `tested` stamp uses -- so a tally from before a rebuild cannot vouch for
# the ROM on disk now.  Written unconditionally, red or green: a red tally
# that says red is evidence; a missing file is not.  (Under
# suite_tally_selftest.sh $ROOT is the selftest's fake tree, so this lands in
# its scratch build/, never the real one.)
mkdir -p "$ROOT/build"
{
  printf 'rom=%s\n' "$(shasum -a 1 "$ROOT/build/ot6.sfc" 2>/dev/null | cut -d' ' -f1)"
  printf 'discovered=%s ran=%s pass=%s fail=%s xfail=%s xpass=%s skip=%s\n' \
    "$discovered" "$ran" "$n_pass" "$n_fail" "$n_xfail" "$n_xpass" "$n_skip"
  printf 'green=%s\n' "$([ "$fail" -eq 0 ] && echo 1 || echo 0)"
} > "$ROOT/build/.suite-tally"

# Coverage report (#130).  Union the per-test bitmaps and print the OT6 blind
# spots, before the EXIT trap removes $SROOT.  A report also lands under
# build/states so it survives the run for inspection.  This never changes the
# suite's pass/fail; a failed union is reported but does not flip $fail.
if [ -n "$COVDIR" ]; then
  echo
  python3 "$ROOT/tools/tests/lib/coverage_report.py" \
    "$ROOT/ff6/rom/ff6-en.map" "$COVDIR" \
    | tee "$ROOT/build/states/coverage-report.txt" || true
fi

exit $fail
