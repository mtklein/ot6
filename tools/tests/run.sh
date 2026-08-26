#!/bin/sh
# run.sh <script.lua> [logfile] -- run a Lua test under Mesen 2's headless testrunner.
#
#   tools/tests/run.sh tools/tests/battle_smoke.lua
#
# * Composes the script with the lib (ot6.lua + ot6_field.lua) into one
#   flat file in the invocation workspace first. Runtime dofile()/loadfile() raise under
#   Mesen's default AllowIoOsAccess=false setting (a raise at script load
#   registers no callbacks, so the run then dies on the wall-clock cap, which
#   is the kill usually reported as the "255 crash").  Inlining keeps runs
#   hermetic; see compose.py.  A script that is
#   already composed (first line carries compose.py's marker) runs as-is.
#   suite.sh pre-composes every test once so a mid-suite lib edit can't split
#   a suite across two libs.
# * Runs build/ot6.sfc (rebuild with `make rom` if you changed sources).
# * All emulator/script output goes to the logfile
#   (default: build/states/last_run.log).
# * [b64:<tag>] payloads emitted by the script (savestates, screenshots) are
#   decoded into build/states/ and build/states/shots/ afterwards.
# * Every invocation gets a fresh workspace under build/test-runs/.  OT6_WORKER
#   is only a diagnostic label; two runs with the same label remain isolated.
#   No worker owns a copy of the
#   emulator: they all exec ONE shared read-only bundle and are kept apart by
#   CFFIXED_USER_HOME instead (see "shared emulator" below).
# * Exit code: 0 = pass, 1 = assertion/Lua error, 2 = frame budget exceeded.
#   The [ot6] PASS/FAIL verdict in the log takes precedence over the raw
#   process code (a 255 with unflushed stdout means the wall-clock cap killed
#   the run).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROM="${OT6_ROM:-$ROOT/build/ot6.sfc}"
# The verdict patterns must match a whole verdict line rather than a prefix.
# lib/ot6.lua emits two terminal lines, `PASS (frame N)` and `FAIL: <why>`,
# through M.log, so they arrive as `[ot6] PASS (frame N)` / `[ot6] FAIL: ...`.
# This used to be matched with `^\[ot6\] PASS`, a prefix, and that produced a
# false green: battle_thief logs `PASSED phase 1: ...` per phase, so a run
# killed by the wall-clock cap after phase 1 matched the pass pattern and was
# scored green, measured 2026-08-10 (testrunner exit 255, verdict 0, on a
# deliberately short OT6_TIMEOUT).  Issue #75 exists to stop a truncated run
# reporting success, so the patterns below anchor on the parenthesis and the
# colon that only the real verdicts carry.
PASS_RE='^\[ot6\] PASS \(frame '
FAIL_RE='^\[ot6\] FAIL: '
verdict_spoken() { grep -qE "$PASS_RE|$FAIL_RE" "$1"; }

# --verdict-selftest: falsify the PASS/FAIL parsing without launching Mesen.
# This exists because the parsing did not have a selftest, and the gap shipped
# a false green: `^\[ot6\] PASS` is a prefix, battle_thief logs `PASSED phase
# 1: ...` per phase, and a run killed by the wall-clock cap after phase 1 was
# therefore scored PASS (measured 2026-08-10: testrunner exit 255, verdict 0).
# Every other mechanical check in this repo carries a selftest (the
# state-write checker, compose, the ninja graph, runner isolation), and this
# one decides pass-vs-fail for every test in the project.  Wired into
# `make test` beside the others.
if [ "${1:-}" = "--verdict-selftest" ]; then
  fails=0
  vcheck() {  # <label> <log body> <want: pass|fail|none>
    _t=$(mktemp); printf '%s\n' "$2" > "$_t"
    if grep -qE "$PASS_RE" "$_t"; then _got=pass
    elif grep -qE "$FAIL_RE" "$_t"; then _got=fail
    else _got=none; fi
    rm -f "$_t"
    if [ "$_got" = "$3" ]; then printf '  pass  %s\n' "$1"
    else printf '  FAIL  %s (scored %s, want %s)\n' "$1" "$_got" "$3"; fails=$(( fails + 1 )); fi
  }
  vcheck "a real PASS verdict scores pass"        '[ot6] PASS (frame 309)'            pass
  vcheck "a real FAIL verdict scores fail"        '[ot6] FAIL: assertEq failed: x'     fail
  vcheck "the budget FAIL scores fail"            '[ot6] FAIL: frame budget exceeded (900 frames)' fail
  # The regression, in its original shape: a truncated run that announced phases.
  vcheck "PASSED-phase lines alone score NONE"    '[ot6] PASSED phase 1: the submenu
[ot6] PASSED phase 2: the ledger' none
  vcheck "a phase line plus a real verdict passes" '[ot6] PASSED phase 1: the submenu
[ot6] PASS (frame 13056)'                         pass
  vcheck "FAILED-phase lines alone score NONE"    '[ot6] FAILED phase 3: the cap'      none
  vcheck "an empty log scores none (a timeout kill)" ''                                none
  vcheck "prose naming PASS does not score"       '[ot6] this run will PASS if the gauge breaks' none
  vcheck "an unprefixed PASS does not score"      'PASS (frame 1)'                     none
  if [ "$fails" -ne 0 ]; then
    echo "run.sh --verdict-selftest: $fails FAILURE(S)"; exit 1
  fi
  echo "run.sh --verdict-selftest: OK"; exit 0
fi

SCRIPT="${1:?usage: run.sh <script.lua> [logfile]}"

# A worker id used to select a persistent directory, which made it an
# isolation key.  It is now only a human-readable prefix.
label=$(printf '%s' "${OT6_WORKER:-run}" | tr -c 'A-Za-z0-9_.-' '_')
RUN_ROOT="$ROOT/build/test-runs"
mkdir -p "$RUN_ROOT"
WDIR=$(mktemp -d "$RUN_ROOT/${label}.XXXXXXXX") || exit 2
MESEN_HOME="$WDIR/home"
TEST_SAVES="$WDIR/saves"
COMPOSED="$WDIR/composed.lua"
RUN_LOG="$WDIR/run.log"
LOG="${2:-$ROOT/build/states/last_run.log}"
ART="$WDIR/artifacts"
PUBLISH="${OT6_ARTIFACT_DIR:-$ROOT/build/states}"
STALE_APP="$ROOT/build/mesen-test.app"
mkdir -p "$TEST_SAVES" "$ART/shots" "$PUBLISH/shots" "$(dirname "$LOG")"

cleanup_run() {
  [ -z "${HELD_LOCK:-}" ] || rm -rf "$HELD_LOCK"
  [ "${OT6_KEEP_RUNS:-0}" = 1 ] || rm -rf "$WDIR"
}
trap cleanup_run EXIT INT TERM

# Test-only rendezvous used by runner_isolation_selftest.sh.  Both concurrent
# probes expose their live workspace before either may leave, proving the
# property without launching a 413MB emulator.
if [ -n "${OT6_ISOLATION_PROBE_OUT:-}" ]; then
  printf '%s\n' "$WDIR" > "$OT6_ISOLATION_PROBE_OUT"
  while [ ! -f "${OT6_ISOLATION_PROBE_GO:?probe requires OT6_ISOLATION_PROBE_GO}" ]; do sleep 1; done
  [ -d "$WDIR" ] || exit 1
  exit 0
fi

if head -n 1 "$SCRIPT" | grep -q '^-- AUTOGENERATED by lib/compose.py'; then
  COMPOSED="$SCRIPT"   # pre-composed by suite.sh; run as-is
else
  python3 "$ROOT/tools/tests/lib/compose.py" "$SCRIPT" "$COMPOSED" || exit 2
fi

# OT6_RECORD=1: run the same composed script under tools/stream/mesen_record
# instead of the testrunner, taping the whole run (video + emulated audio) to
# an AVI, then render build/stream/<script>.mp4 with the input panel at run
# end.  See tools/stream/README.md.  Everything in this block is record-only;
# with OT6_RECORD unset no line of it runs and the testrunner path below is
# untouched.
if [ -n "${OT6_RECORD:-}" ]; then
  # The lib's recording taps (lib/ot6.lua "recording sidecars") key off the
  # OT6_RECORD global, defined by prepending one line to a record-only copy.
  # The sandboxed script cannot read the environment, so the flag has to
  # travel in the script text; the original composed file is left alone.
  RECORD_LUA="$WDIR/composed_record.lua"
  { printf 'OT6_RECORD = true\n'; cat "$COMPOSED"; } > "$RECORD_LUA"
  # Compiled per invocation: the source is small (a ~2s build), and a stale
  # cached binary against a swapped Mesen core is exactly the layout-drift
  # case the tool's version guard exists to refuse loudly, not to dodge.
  RECORD_BIN="$WDIR/mesen_record"
  c++ -O2 -std=c++17 -o "$RECORD_BIN" "$ROOT/tools/stream/mesen_record.cpp" || {
    echo "mesen_record failed to compile; refusing to record"; exit 2; }
  RECORD_AVI="$WDIR/record.avi"
fi

# ------------------------------------------------------------ shared emulator
# Every worker on this machine execs one read-only Mesen bundle, and nothing
# ever writes inside it.  Workers are kept apart by giving each its own Mesen
# config home rather than its own copy of the app.
#
# Mesen picks that home one of two ways, both measured here:
#   * Portable: a settings.json sitting beside the binary wins over
#     everything else, unconditionally.  That is how this script used to
#     isolate workers, and it is why each needed a private 413MB bundle: the
#     config lived inside the app, so sharing an app meant sharing (and
#     racing on) one settings.json.  See 2bf5045 for what that cost.
#   * Otherwise: ~/Library/Application Support/Mesen2, resolved through
#     CoreFoundation.  $HOME does not move it; with HOME set to a scratch dir
#     a run still wrote its .srm and Debugger/*.cdl into the real profile,
#     because .NET reaches SpecialFolder.ApplicationData via
#     NSSearchPathForDirectoriesInDomains, which takes the home from the
#     password database (the binary carries the symbol
#     GetHomeDirectory:TryGetHomeDirectoryFromPasswd).  CFFIXED_USER_HOME,
#     Core Foundation's own home override, does move it: settings, saves,
#     Debugger/*.cdl, and the rest.
#
# So strip settings.json from the shared copy, which makes it non-portable,
# and hand each worker its own CFFIXED_USER_HOME.  That isolates workers more
# strongly than the copy scheme it replaces, because there is no per-worker
# app and so no per-worker state inside the app to race on.
#
# Why a copy of tools/Mesen.app rather than tools/Mesen.app itself: the user's
# manual-play profile (`make run`) lives in that bundle as the settings.json
# that forces portable mode, so execing it would put every worker back on one
# shared config.  The harness must not depend on the mutable state of the play
# bundle, so it keeps its own stripped copy.
#
# One copy, machine-wide, under ~/Library/Caches, rather than one per worker
# or one per worktree.  Mesen is ad-hoc signed but not notarized (see
# docs/TOOLING.md), so macOS runs a first-launch Gatekeeper assessment on
# every new bundle path: a user-visible "Verifying Mesen..." dialog and a
# multi-second scan of all 413MB (measured: 4.7s and 6.1s on two fresh paths
# against 0.3-0.5s once the path is known).  The old scheme created four of
# those per tree and four more every time an agent made a worktree.  Clearing
# quarantine does not help: `xattr -cr` before first launch still cost 5.5s,
# and the kernel puts com.apple.provenance straight back on exec.  The trigger
# is the new bundle path rather than the flag.
SRC_APP="$ROOT/tools/Mesen.app"
MESEN_CACHE="$HOME/Library/Caches/ot6"
SHARED_APP="$MESEN_CACHE/Mesen-test.app"
# Rebuild the shared copy when the source bundle changes (a Mesen upgrade).
# -L: in a worktree tools/Mesen.app is a symlink into the main tree.
SRC_STAMP=$(stat -Lf '%z %m' "$SRC_APP/Contents/MacOS/Mesen" 2>/dev/null) || {
  echo "no Mesen at $SRC_APP (run tools/worktree-setup.sh?)"; exit 2; }

shared_app_ready() {
  [ -x "$SHARED_APP/Contents/MacOS/Mesen" ] &&
  [ ! -e "$SHARED_APP/Contents/MacOS/settings.json" ] &&
  [ "$(cat "$SHARED_APP.stamp" 2>/dev/null)" = "$SRC_STAMP" ]
}

if ! shared_app_ready; then
  # suite.sh starts every worker within milliseconds of the others, so on a
  # cold cache all of them arrive here at once.  Whoever wins the mkdir builds
  # it; the rest wait for that one build instead of racing to install over
  # each other (mv of a directory onto an existing directory nests it rather
  # than replacing it, which would corrupt the bundle).
  mkdir -p "$MESEN_CACHE"
  LOCK="$MESEN_CACHE/.build.lock"
  if mkdir "$LOCK" 2>/dev/null; then held=1; else
    held=""; waited=0
    while [ -d "$LOCK" ] && ! shared_app_ready; do
      sleep 1; waited=$((waited + 1))
      [ "$waited" -gt 180 ] && { echo "stale lock $LOCK; remove it and retry"; exit 2; }
    done
    shared_app_ready || { mkdir "$LOCK" 2>/dev/null && held=1; }
  fi
  if [ -n "$held" ]; then
    # Release the lock however we leave: a run that dies mid-build must not
    # wedge every later worker behind a lock nobody holds.
    HELD_LOCK="$LOCK"
    echo "creating shared test emulator (one-time; expect a Gatekeeper scan)..."
    TMP="$MESEN_CACHE/.build.$$"
    rm -rf "$TMP" "$SHARED_APP" "$SHARED_APP.stamp"
    # cp -c = APFS clonefile: instant and ~zero physical disk.  -L because in
    # a worktree the source is a symlink and cp -R would copy the LINK.
    cp -c -RL "$SRC_APP" "$TMP" 2>/dev/null || cp -RL "$SRC_APP" "$TMP" || {
      rm -rf "$TMP"; echo "could not copy $SRC_APP"; exit 2; }
    # No settings.json (nor the .bak rotation Mesen leaves beside it) may
    # survive into the copy, or portable mode wins and every worker is back
    # on one shared config.
    rm -f "$TMP/Contents/MacOS/settings.json" "$TMP"/Contents/MacOS/settings.*.bak
    # Profile dirs the source bundle accumulated while it was portable belong
    # to the user's play profile, not to the tests; they must not ride along.
    rm -rf "$TMP/Contents/MacOS/Saves" "$TMP/Contents/MacOS/SaveStates" \
           "$TMP/Contents/MacOS/RecentGames" "$TMP/Contents/MacOS/Debugger"
    mv "$TMP" "$SHARED_APP"
    printf '%s' "$SRC_STAMP" > "$SHARED_APP.stamp"
    rm -rf "$LOCK"; HELD_LOCK=""
  fi
fi
shared_app_ready || { echo "shared test emulator missing at $SHARED_APP"; exit 2; }

# A tree from before this scheme still has a 413MB per-worker bundle in
# build/.  Nothing reads it any more, so remove it here, both to reclaim the
# space and so that a tree cannot go on running the old private-copy path
# without anyone noticing.  Test -L as well as -e: the bug in 2bf5045 left
# some of these as symlinks, and -e alone is false for a symlink whose target
# has since gone.
if [ -L "$STALE_APP" ] || [ -e "$STALE_APP" ]; then rm -rf "$STALE_APP"; fi

# The worker's private Mesen config home.  Mesen copies its native libs and
# the Satellaview firmware into a fresh home on first use (~29MB); pre-clone
# them (cp -c again, so eight worker homes cost eight sets of pointers rather
# than 232MB) and Mesen leaves them alone, because its copy is copy-if-missing
# and -p keeps the mtimes it stamps them with.  Re-seed from scratch when the
# emulator changes, so a home cannot serve a stale MesenCore.dylib to a newer
# binary.
MESEN2="$MESEN_HOME/Library/Application Support/Mesen2"
if [ "$(cat "$MESEN_HOME/.stamp" 2>/dev/null)" != "$SRC_STAMP" ]; then
  rm -rf "$MESEN_HOME"; mkdir -p "$MESEN2"
  for f in MesenCore.dylib MesenNesDB.txt libHarfBuzzSharp.dylib libSkiaSharp.dylib Satellaview; do
    [ -e "$SHARED_APP/Contents/MacOS/$f" ] || continue   # let Mesen seed it itself
    cp -c -Rp "$SHARED_APP/Contents/MacOS/$f" "$MESEN2/$f" 2>/dev/null ||
      cp -Rp "$SHARED_APP/Contents/MacOS/$f" "$MESEN2/$f"
  done
  printf '%s' "$SRC_STAMP" > "$MESEN_HOME/.stamp"
fi

# (Re)write this worker's settings every run so the pins can't drift.  Its
# exit code is checked: a failed pin leaves whatever settings.json the home
# already had, which is the unpinned state the determinism guarantees exclude.
# Refusing the run is better than reporting a green that never had the pins.
# With no settings.json at all Mesen ignores --testrunner and opens the GUI
# setup wizard, so this is also what keeps a fresh home headless.
python3 "$ROOT/tools/tests/lib/pin_test_saves.py" \
  "$HOME/Library/Application Support/Mesen2/settings.json" \
  "$MESEN2/settings.json" \
  "$TEST_SAVES" || { echo "pin_test_saves.py failed; refusing to run unpinned"; exit 2; }

# Fresh battery every run: the testrunner flushes SRAM to <saves>/*.srm on
# exit and reloads it on the next boot without reporting that it did, so a
# stale srm couples one run to the next and gets baked into generated
# savestates.  Tests that need a save inject it explicitly (SRM sidecars).
rm -f "$TEST_SAVES"/*.srm
if [ -n "${OT6_SRAM_CHECKPOINT:-}" ]; then
  # The persistent_layout check (issue #25).  A generator step declares the
  # persistent-SRAM layout it understands with a marker comment in its script,
  #
  #     [dash][dash] OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
  #
  # (spelled as a real Lua comment at the start of a line; not written out
  # here so this file can never satisfy the grep).  The declaration rides
  # the script itself rather than an env var, so every consumer (savestate
  # generation, smoke, a bare manual run.sh) gets the same refusal with no
  # caller wiring, and it survives composition, since comments do.
  # sram_checkpoint.py compares it against the checkpoint manifest's
  # persistent_layout and refuses a mismatch here, before the emulator boots,
  # naming both strings: a checkpoint left stale by schema drift should give a
  # named refusal rather than an in-emulator timeout.  A step with no marker
  # declares support for nothing and is refused too, so the check fails closed
  # instead of guarding only the steps that opted in.
  CHECKPOINT_LAYOUT=$(sed -n 's/^-- OT6_CHECKPOINT_LAYOUT: *\([^ ]*\).*$/\1/p' "$COMPOSED" | head -n 1)
  python3 "$ROOT/tools/tests/lib/sram_checkpoint.py" materialize \
    "$OT6_SRAM_CHECKPOINT" "$TEST_SAVES/$(basename "$ROM" .sfc).srm" \
    "$CHECKPOINT_LAYOUT" ||
    { echo "invalid SRAM checkpoint: $OT6_SRAM_CHECKPOINT (refused BEFORE boot)"; exit 2; }
fi
# --timeout: Mesen's testrunner has a default 100-second wall-clock cap
# (exit -1/255 and truncated stdout on expiry) that killed long runs.  Keep a
# cap as the only defense against a hung emulator, but a roomy one.
# OT6_TIMEOUT raises it for a run already known to be competing for cores;
# the cap is wall clock, so `nice` does not protect it (see the timeout
# diagnosis below).
# --enableStdout mirrors the emulator message log to stdout.  It does not
# carry Lua errors or watchdog kills; those go to the script log, which
# nothing reads headless.  print() is the only channel out of a script, so a
# script that stops printing reports nothing.  Kept for the ROM-info banner.
# CFFIXED_USER_HOME is the isolation boundary measured above.
CAP="${OT6_TIMEOUT:-600}"
# A timeout kill carries no result, so the harness retries it instead of
# reporting it.  The cap is wall clock and `nice` does not slow the wall, so
# concurrent jobs starve each other: a savestate generation that takes 400s
# alone can cross 600s when a dozen share ten cores.  That used to surface as
# a red edge with a paragraph of explanation, and every reader had to re-learn
# that "exit 255, truncated stdout" is a kill rather than a crash.
# Isolation was already solved: every invocation gets its own workspace and
# CFFIXED_USER_HOME (dd2266a, 10ce17c), which is what makes a retry safe and
# deterministic, since it is the same inputs run again with nothing shared to
# have been disturbed.
#
# The retry fires only on the timeout-kill signature, and that distinction
# matters: no verdict in the log, and the run lived to the cap.  A real FAIL
# is never retried, because retrying failures until they pass is the #74
# mistake in harness form and would turn a flaky test into a green one with no
# notice.  A no-verdict run that died well short of the cap is not retried
# either: that is a Lua load error, which is deterministic and will fail
# identically.
RETRIES="${OT6_TIMEOUT_RETRIES:-1}"
attempt=0
retried=0
while :; do
  attempt=$(( attempt + 1 ))
  t0=$(date +%s)
  if [ -n "${OT6_RECORD:-}" ]; then
    # The record host applies the pin_test_saves.py pins itself through the
    # core's config API (settings.json is a C#-side concept it never reads)
    # and takes the saves dir explicitly, so isolation matches the
    # testrunner path.  A retry overwrites the AVI from frame 0.
    "$RECORD_BIN" "$SHARED_APP/Contents/MacOS/MesenCore.dylib" \
      "$MESEN2" "$TEST_SAVES" "$ROM" "$RECORD_LUA" "$RECORD_AVI" "$CAP" \
      > "$RUN_LOG" 2>&1
    code=$?
  else
    env CFFIXED_USER_HOME="$MESEN_HOME" \
      "$SHARED_APP/Contents/MacOS/Mesen" --testrunner --timeout="$CAP" --enableStdout \
      "$ROM" "$COMPOSED" > "$RUN_LOG" 2>&1
    code=$?
  fi
  elapsed=$(( $(date +%s) - t0 ))
  verdict_spoken "$RUN_LOG" && break
  [ $(( elapsed + 5 )) -ge "$CAP" ] || break
  [ "$attempt" -le "$RETRIES" ] || break
  retried=$(( retried + 1 ))
  printf '[ot6] KILLED BY THE TIMEOUT after %ss against a %ss wall-clock cap -- retrying (attempt %s of %s).  Runs are isolated, so this is safe and is not a re-roll of a failure: no verdict was ever reached.\n' \
    "$elapsed" "$CAP" "$(( attempt + 1 ))" "$(( RETRIES + 1 ))" >&2
  sleep 5
done

python3 "$ROOT/tools/tests/lib/decode_b64.py" "$RUN_LOG" "$ART"

if [ "$retried" -gt 0 ] && verdict_spoken "$RUN_LOG"; then
  # Report every retry: a machine killing runs on the timeout is worth seeing
  # even when the retry rescued the result.
  printf '[ot6] this run was KILLED %s time(s) by the %ss wall-clock cap and retried; the verdict below is from attempt %s.\n' \
    "$retried" "$CAP" "$attempt" >> "$RUN_LOG"
fi
if grep -qE "$PASS_RE" "$RUN_LOG"; then
  verdict=0
elif grep -qE "$FAIL_RE" "$RUN_LOG"; then
  verdict=1
else
  verdict=$code
  # No verdict in the log.  The script never reached PASS or FAIL, so the
  # emulator was killed rather than finishing, and if it lived roughly to the
  # cap, the cap is what killed it.  Say so, because the raw signature is
  # "exit 255, truncated stdout", which reads like a crash: the brief has to
  # keep re-teaching agents that it is a kill, and it is the documented top
  # cause of a savestate generation failing for reasons other than the
  # generation.
  #
  # This is usually contention rather than the test.  The cap is wall clock,
  # and `nice` does not slow the wall.  Niced work yields to the owner's
  # game, but every agent's jobs are equally niced, so they starve each
  # other: a generation that takes 400s alone can cross 600s when a dozen of
  # them share ten cores.  Observed 2026-07-29: nine states generated fine,
  # four killed by the timeout, all four green when re-run alone.
  # "Lived to the cap" allows 5s of slack for rounding, rather than a fixed
  # 30s margin, which goes negative and always fires under a small
  # OT6_TIMEOUT.
  #
  # It goes into $RUN_LOG with the [ot6] prefix rather than straight to
  # stdout, because stdout is not where it would be read: suite.sh runs every
  # test as `"$RUN" ... >/dev/null 2>&1` and keeps only the log.  Written
  # here it reaches both readers: the `grep '^\[ot6\]'` at the end of this
  # script prints it for a direct invocation, and it is inside
  # build/states/suite_<test>.log for a suite one.  decode_b64 has already
  # read the log, so appending now is safe.
  timeout_note() { printf '[ot6] %s\n' "$@" >> "$RUN_LOG"; }
  if [ $(( elapsed + 5 )) -ge "$CAP" ]; then
    timeout_note "KILLED BY THE TIMEOUT: no verdict, and the run lasted ${elapsed}s against a ${CAP}s wall-clock cap (--timeout).  Mesen killed it; it did not crash." \
         "  This is the FINAL attempt: the harness already retried it ${retried} time(s)" \
         "  automatically (OT6_TIMEOUT_RETRIES=${RETRIES}), so the cap is not merely being" \
         "  grazed -- this run cannot finish inside it on this machine right now." \
         "  Load right now: $(uptime | sed 's/.*load average/load average/')" \
         "  The cap is wall clock, so nice(1) does not protect it -- concurrent" \
         "  jobs are all equally niced and starve each other." \
         "  Next: raise the cap for this run (OT6_TIMEOUT=1200), allow more" \
         "  retries (OT6_TIMEOUT_RETRIES=3), or lower parallelism (NINJAFLAGS=-j2)."
  elif [ "$verdict" -ne 0 ]; then
    timeout_note "no verdict after ${elapsed}s (cap ${CAP}s): the script died before reaching PASS or FAIL." \
         "  Well short of the cap, so this is NOT a timeout kill -- read this log for a Lua load error."
  fi
fi
if [ "$verdict" -eq 0 ] && [ -n "${OT6_EXPECT_ARTIFACT:-}" ]; then
  for expected in $OT6_EXPECT_ARTIFACT; do
    case "$expected" in */*|*..*) echo "invalid expected artifact: $expected"; verdict=2 ;; esac
    [ -f "$ART/$expected" ] || {
      echo "passing run did not emit expected artifact: $expected"; verdict=2; }
  done
fi

# Publish complete files only.  The invocation workspace remains the source of
# truth until decoding is finished; rename within each destination directory
# prevents readers from observing a partially copied log or artifact.
publish_file() {
  src=$1 dest=$2
  tmp="$dest.tmp.$$"
  cp "$src" "$tmp" && mv -f "$tmp" "$dest"
}
# Checkpoint creation is intentionally a separate, explicit operation.  Mesen
# flushes battery SRAM only while shutting down, so the complete 32 KiB file
# becomes available here, after the Lua script has exercised the real Save UI.
if [ "$verdict" -eq 0 ] && [ -n "${OT6_CAPTURE_SRM:-}" ]; then
  captured="$TEST_SAVES/$(basename "$ROM" .sfc).srm"
  if [ -f "$captured" ] && [ "$(wc -c < "$captured" | tr -d ' ')" -eq 32768 ]; then
    mkdir -p "$(dirname "$OT6_CAPTURE_SRM")"
    publish_file "$captured" "$OT6_CAPTURE_SRM"
    # Provenance sidecar (issue #75 step 5): record mechanically what cut
    # this battery.  That is the capturing generator's provenance signature
    # (from the one authority, savestate_stamp.sh), plus the hash of
    # everything the run booted from: the stamp of each savestate compose
    # embedded (read off the composed file's own `-- state` provenance lines)
    # and, when the run Continued from a prior checkpoint, that checkpoint's
    # manifest.  The sidecar lands beside the payload; `sram_checkpoint.py
    # seal` folds it into manifest.json.  A capture that cannot state its
    # provenance is refused, because a checkpoint is a root of the generated
    # chain and this program exists to stop generating roots whose provenance
    # cannot be proven.
    gen=$(basename "$SCRIPT" .lua)
    checkpoint_extras=""
    adir=""
    if [ -n "${OT6_SRAM_CHECKPOINT:-}" ]; then
      adir="$OT6_SRAM_CHECKPOINT"
      case "$adir" in "$ROOT"/*) adir="${adir#"$ROOT"/}" ;; esac
      checkpoint_extras="$adir/manifest.json"
      for p in "$ROOT/$adir"/*.sram; do
        [ -f "$p" ] && checkpoint_extras="$checkpoint_extras $adir/$(basename "$p")"
      done
    fi
    # shellcheck disable=SC2086 -- extras/ancestors are space-separated lists
    if generator_sig=$(sh "$ROOT/tools/tests/lib/savestate_stamp.sh" sig "$gen" $checkpoint_extras); then
      ancestors=$(
        sed -n 's/^-- state \([A-Za-z0-9_]*\)\.mss\.lua .*/\1/p' "$COMPOSED" |
          while IFS= read -r s; do
            [ -f "$ROOT/build/states/$s.stamp" ] && echo "build/states/$s.stamp"
          done
      )
      [ -z "$adir" ] || ancestors="$adir/manifest.json
$ancestors"
      # shellcheck disable=SC2086
      python3 "$ROOT/tools/tests/lib/sram_checkpoint.py" capture "$ROOT" \
        "$OT6_CAPTURE_SRM.provenance.json" "$OT6_CAPTURE_SRM" \
        "$generator_sig" $ancestors ||
        { echo "capture provenance sidecar failed for $OT6_CAPTURE_SRM"; verdict=2; }
    else
      echo "capture refused: cannot derive a provenance signature for $SCRIPT" \
           "(a capture must run a tools/tests generator; issue #75)"
      verdict=2
    fi
  else
    echo "Mesen did not flush a complete 32768-byte SRAM image: $captured"
    verdict=2
  fi
fi
publish_file "$RUN_LOG" "$LOG"
# Render the watchable video from the tape + the log's [ot6pad]/[ot6note]
# stream.  A FAILed run is composed too: watching what the run did is most
# of the point when it did the wrong thing.  Compose failure never flips a
# test verdict; the recording is an observer.
if [ -n "${OT6_RECORD:-}" ] && [ -s "$RECORD_AVI" ]; then
  mkdir -p "$ROOT/build/stream"
  python3 "$ROOT/tools/stream/compose.py" "$RUN_LOG" "$RECORD_AVI" \
    "$ROOT/build/stream/$(basename "$SCRIPT" .lua).mp4" \
    || echo "[ot6] compose.py failed; the raw tape is $RECORD_AVI (set OT6_KEEP_RUNS=1 to keep it)"
fi
# OT6_NO_PUBLISH=1 runs a generator for its verdict only, leaving build/states
# untouched.  `make smoke` uses it to falsify a lib change in minutes without
# half-updating the chain: a state generated mid-smoke would be fresher than
# its neighbours and make the tree harder to reason about, for no benefit,
# since the stamp check would regenerate it anyway.
#
# A generating edge publishes only its own artifacts (issue #30).
# OT6_EXPECT_ARTIFACT is set by savestate_ninja.py's `generate` rule, naming
# the one state the invoking ninja edge is for.  A script that generates
# several states emits every sibling state on every invocation (gen_edgar
# plays the whole Figaro chapter and emits all three figaro states no matter
# which edge invoked it), and each sibling is its own ninja edge running this
# same script, so publishing the whole workspace let one edge rewrite another
# edge's declared outputs with fresh mtimes.  For gen_edgar's figaro_cleared
# edge that meant republishing figaro_matron.mss, its own input, after its own
# outputs (the "$ART"/* glob publishes cleared before matron), so ninja saw
# input-newer-than-output forever and consecutive `make savestates` runs
# regenerated every such multi-state family and its downstream trunk with zero
# content changes.
# The sibling copies this run just emitted are discarded rather than moved:
# every sibling has its own edge, so the published copy is always the one whose
# edge ninja scheduled and whose stamp savestate_stamp.sh wrote.  Screenshots
# still publish either way, because they are forensic output rather than
# scheduled ninja outputs, and no edge declares them.
# savestate_ninja_selftest.sh's stub run.sh mirrors this block; keep in lockstep.
if [ "$verdict" -eq 0 ] && [ -z "${OT6_NO_PUBLISH:-}" ]; then
  if [ -n "${OT6_EXPECT_ARTIFACT:-}" ]; then
    for src in $OT6_EXPECT_ARTIFACT; do
      publish_file "$ART/$src" "$PUBLISH/$src"
    done
  else
    for src in "$ART"/*; do
      [ -f "$src" ] || continue
      publish_file "$src" "$PUBLISH/$(basename "$src")"
    done
  fi
  for src in "$ART/shots"/*; do
    [ -f "$src" ] || continue
    publish_file "$src" "$PUBLISH/shots/$(basename "$src")"
  done
fi

grep '^\[ot6\]' "$RUN_LOG"

echo "testrunner exit: $code (verdict: $verdict)"
[ "$verdict" -eq 0 ] || {
  # Failed workspaces are forensic evidence and are bounded to this
  # invocation.  Retain them without weakening successful-run cleanup.
  OT6_KEEP_RUNS=1
  echo "failed run retained: $WDIR"
}
exit "$verdict"
