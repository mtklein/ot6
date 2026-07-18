#!/bin/sh
# suite.sh -- the OT6 correctness gate. Runs every test on every covered
# formation, compares visual checkpoints against goldens, honors an
# explicit expected-fail list. Nonzero exit on any unexpected result.
#
# OT6_JOBS=N fans the tests out across N isolated run.sh workers
# (OT6_WORKER; default 4 = the P-core knee, 1 = serial). Every suite test
# is a pure savestate load -- the mints (gen_battle_state, gen_battle2)
# run as Makefile prerequisites BEFORE the suite -- so tests are
# independent and fan out freely. Tests are composed once up front:
# composing reads lib/ot6.lua live, and a mid-suite edit must not split
# the suite across two libs.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$ROOT/tools/tests/run.sh"
GOLD="$ROOT/tools/tests/goldens"
SHOTS="$ROOT/build/states/shots"
JOBS="${OT6_JOBS:-4}"
TESTS="smoke battle_entry battle_break battle_reveal battle_reveal_poweron battle_class battle_bp battle_boost battle_hits battle_fold battle_preview battle_codex battle_c battle_fontrestore battle_banner battle_dlgmenu battle_whelkwipe probe_shadow_overlap hud_stability visual_f1 visual_f2"

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
  rm -rf "$CDIR" "$RDIR"; mkdir -p "$CDIR" "$RDIR"
  for t in $TESTS; do
    python3 "$ROOT/tools/tests/lib/compose.py" \
      "$ROOT/tools/tests/$t.lua" "$CDIR/$t.lua" >/dev/null \
      || { echo "compose failed: $t"; exit 1; }
  done
  w=0
  while [ "$w" -lt "$JOBS" ]; do
    (
      i=0
      for t in $TESTS; do
        if [ $((i % JOBS)) -eq "$w" ]; then
          t0=$(python3 -c 'import time; print(time.time())')
          env $(ram_env_for "$t") OT6_WORKER="$w" "$RUN" "$CDIR/$t.lua" "$ROOT/build/states/suite_$t.log" >/dev/null 2>&1
          rc=$?
          secs=$(python3 -c "import time; print(f'{time.time()-$t0:.1f}')")
          echo "$rc $w $secs" > "$RDIR/$t"
        fi
        i=$((i + 1))
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

for g in visual_f1_idle; do
  if [ -f "$SHOTS/$g.png" ]; then
    out=$("$ROOT/tools/tests/compare_golden.py" "$SHOTS/$g.png" "$GOLD/$g.png" 1500)
    rc=$?
    if [ $rc -eq 0 ]; then result "golden $g" "pass"
    else result "golden $g" "FAIL ($out)"; fail=1; fi
  else
    result "golden $g" "FAIL (screenshot never emitted)"; fail=1
  fi
done

printf "OT6 suite:%b\n" "$summary"
exit $fail
