#!/bin/sh
# suite.sh -- the OT6 correctness gate. Runs every test on every covered
# formation, compares visual checkpoints against goldens, honors an
# explicit expected-fail list. Nonzero exit on any unexpected result.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$ROOT/tools/tests/run.sh"
GOLD="$ROOT/tools/tests/goldens"
SHOTS="$ROOT/build/states/shots"
XFAIL=""   # keep empty; XPASS fails the suite to force cleanup
fail=0; summary=""

result() { summary="$summary\n  $1: $2"; }

for t in smoke battle_entry battle_break battle_bp battle_boost battle_hits battle_fold battle_preview battle_codex hud_stability visual_f1 visual_f2; do
  "$RUN" "$ROOT/tools/tests/$t.lua" "$ROOT/build/states/suite_$t.log" >/dev/null 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    case " $XFAIL " in
      *" $t "*) result "$t" "XPASS (unexpected pass - remove from XFAIL)"; fail=1 ;;
      *) result "$t" "pass" ;;
    esac
  else
    case " $XFAIL " in
      *" $t "*) result "$t" "xfail (known: formation VRAM clobber)" ;;
      *) result "$t" "FAIL (see build/states/suite_$t.log)"; fail=1 ;;
    esac
  fi
done

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
