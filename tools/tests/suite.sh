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
TESTS="smoke school battle_entry battle_break battle_reveal battle_reveal_poweron battle_class battle_bp battle_boost battle_bushido battle_steal probe_bushidobusy probe_ctrboost battle_runic battle_hits battle_fold battle_preview battle_codex battle_c battle_fontrestore battle_banner battle_dlgmenu battle_whelkwipe battle_dmgnum battle_lateboost battle_hudtrack battle_levelup battle_mpcost probe_shadow_overlap hud_stability visual_f1 visual_f2 battle_blitzlist"

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
# FRONTIER-GATED TESTS.  battle_vargas asserts on vargas_doorstep.mss, which
# only `make frontier` mints -- and reaching it means replaying the whole
# story chain, nine multi-minute scripted playthroughs.  Making `make test`
# depend on that would multiply the gate's cost by an order of magnitude,
# which is the exact cost the frontier exists to keep out of it.  So the test
# joins the suite the moment its fixture exists and is reported SKIPPED --
# never silently dropped -- when it does not.  `make frontier-test` is the
# one command that always runs it.
# battle_kefka gates on kefka_doorstep.mss, which is deeper still: it needs
# the REUNION (all three scenarios in one playthrough), so it stays skipped
# until Sabin's chain lands and the scenario stack mints reunion_ready (see
# the Makefile's stacking block).  Wired now so the day that state exists,
# the gate grows by itself.
# battle_flyin gates on kolts_cave.mss: it needs a fight whose monsters FLY IN
# (present-but-not-shown at entry), which the suite's non-frontier fights do
# not have -- kolts_cave's map-96 pool is 93.75% Cirpius x3.  It guards the
# entry hud gate ($201E) added for the v0.3-rc1 cave "white text overdraw".
# battle_hudclobber gates on moogle_doorstep.mss: it needs a fight with a
# mid-battle DIALOGUE while the under-enemy hud is live (the Narshe Magitek-
# flashback, Kefka's "Uwee, hee, hee!").  The dialogue re-uploads the small
# font and blanks OT6's glyph tiles; the gate proves the hud never renders from
# them (the "junk over/around enemies" sighting) and the flush stays in vblank.
# battle_hudanim16 gates on kolts_cave.mss too: it needs a formation whose hud
# rows sit inside the battlefield's 16x16 scroll window (Cirpius x3, rows 5/8)
# plus a caster whose animation flips bg3 to 16x16 tiles with the priority
# flag kept (Terra's Cure).  It guards the anim-mode veil: the hud must never
# render while $896F holds bg3-16x16 -- the owner's no-dialogue "break icons
# amongst junk over and around the enemies", the residual sighting after the
# fly-in and dialogue-clobber fixes.
# battle_hudtrail gates on rapids_start.mss: it needs an entrance that SLIDES
# shown monsters under live hud lines while holding bg3-16x16 (the Lete River
# forced battle 8, either die roll).  It guards the abandoned-cell fill: cells
# a hud line leaves behind must hold vanilla's $01EE, never a priority-set
# word -- the owner's "white flash at the START of the fight, as the enemies
# are appearing", the residual sighting after all three fixes above.
FRONTIER_TESTS="battle_vargas battle_kefka battle_flyin battle_hudclobber battle_hudanim16 battle_hudtrail"
frontier_fixture() {
  case "$1" in
    battle_vargas)     echo "$ROOT/build/states/vargas_doorstep.mss" ;;
    battle_kefka)      echo "$ROOT/build/states/kefka_doorstep.mss" ;;
    battle_flyin)      echo "$ROOT/build/states/kolts_cave.mss" ;;
    battle_hudclobber) echo "$ROOT/build/states/moogle_doorstep.mss" ;;
    battle_hudanim16)  echo "$ROOT/build/states/kolts_cave.mss" ;;
    battle_hudtrail)   echo "$ROOT/build/states/rapids_start.mss" ;;
    *) echo "" ;;
  esac
}
skipped=""
for t in $FRONTIER_TESTS; do
  if [ -f "$(frontier_fixture "$t")" ]; then
    TESTS="$TESTS $t"
  else
    skipped="$skipped $t"
  fi
done

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
  # which no amount of fan-out can split). This list is ONLY a hint -- every
  # test not named here still runs (appended in canonical order below), and if
  # these durations drift the worst case is a little idle tail, never a lost or
  # double-run test. Keep the biggest handful in front; exact order past that
  # barely moves the makespan.
  in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
  SCHED_LONG="battle_class battle_reveal_poweron battle_vargas battle_whelkwipe battle_hudclobber battle_hits battle_codex battle_dmgnum battle_break battle_runic probe_shadow_overlap battle_dlgmenu hud_stability"
  ORDER=""
  for t in $SCHED_LONG; do in_list "$t" "$TESTS" && ORDER="$ORDER $t"; done
  for t in $TESTS; do in_list "$t" "$ORDER" || ORDER="$ORDER $t"; done
  w=0
  while [ "$w" -lt "$JOBS" ]; do
    (
      for t in $ORDER; do
        # Atomic claim: whoever creates the marker first runs the test; the
        # rest skip on. mkdir is the portable filesystem compare-and-swap, so
        # no test runs twice and (because every worker walks the whole list)
        # none is ever left unclaimed. Result files keep the same
        # "rc w secs" shape the verdict loop and the golden's worker lookup
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

for t in $skipped; do
  result "$t" "skip (needs \`make frontier\`: $(frontier_fixture "$t") absent)"
done

printf "OT6 suite:%b\n" "$summary"
exit $fail
