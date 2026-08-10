#!/bin/sh
# run.sh <script.lua> [logfile] -- run a Lua test under Mesen 2's headless testrunner.
#
#   tools/tests/run.sh tools/tests/battle_smoke.lua
#
# * Composes the script with the lib (ot6.lua + ot6_field.lua) into one
#   flat file in the invocation workspace first. Runtime dofile()/loadfile() raise under
#   Mesen's default AllowIoOsAccess=false setting (a raise at script load
#   registers no callbacks, so the run then dies on the wall-clock cap --
#   that is the "255 crash", not a crash).  Inlining keeps runs hermetic;
#   see compose.py.  A script that is
#   ALREADY composed (first line carries compose.py's marker) runs as-is --
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
#   The [ot6] PASS/FAIL verdict in the log wins over the raw process code
#   (a 255 with unflushed stdout is a wall-clock cap, not a crash).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROM="${OT6_ROM:-$ROOT/build/ot6.sfc}"
# THE VERDICT PATTERNS ARE EXACT, AND THAT IS LOAD-BEARING.  lib/ot6.lua
# emits exactly two terminal lines -- `PASS (frame N)` and `FAIL: <why>` --
# through M.log, so they arrive as `[ot6] PASS (frame N)` / `[ot6] FAIL: ...`.
# This used to be matched with `^\[ot6\] PASS`, a PREFIX, and that is a
# false-green generator: battle_thief logs `PASSED phase 1: ...` per phase,
# so a run KILLED BY THE WALL-CLOCK CAP after phase 1 matched the pass
# pattern and was scored green -- measured 2026-08-10 (testrunner exit 255,
# verdict 0, on a deliberately short OT6_TIMEOUT).  A truncated run reporting
# success is the exact failure #75 exists to abolish, so the patterns below
# anchor on the parenthesis and the colon that only the real verdicts carry.
PASS_RE='^\[ot6\] PASS \(frame '
FAIL_RE='^\[ot6\] FAIL: '
verdict_spoken() { grep -qE "$PASS_RE|$FAIL_RE" "$1"; }

# --verdict-selftest: falsify the PASS/FAIL parsing WITHOUT launching Mesen.
# This exists because the parsing did not have one, and the gap shipped a
# false green: `^\[ot6\] PASS` is a PREFIX, battle_thief logs `PASSED phase
# 1: ...` per phase, and a run killed by the wall-clock cap after phase 1 was
# therefore scored PASS (measured 2026-08-10: testrunner exit 255, verdict 0).
# Every other mechanical anchor in this repo carries a selftest -- the
# state-write checker, compose, the ninja graph, runner isolation -- and the
# one component that decides pass-vs-fail for every test in the project did
# not.  Wired into `make test` beside the others.
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
  # THE REGRESSION, verbatim in shape: a truncated run that announced phases.
  vcheck "PASSED-phase lines alone score NONE"    '[ot6] PASSED phase 1: the submenu
[ot6] PASSED phase 2: the ledger' none
  vcheck "a phase line plus a real verdict passes" '[ot6] PASSED phase 1: the submenu
[ot6] PASS (frame 13056)'                         pass
  vcheck "FAILED-phase lines alone score NONE"    '[ot6] FAILED phase 3: the cap'      none
  vcheck "an empty log scores none (a reap)"      ''                                   none
  vcheck "prose naming PASS does not score"       '[ot6] this run will PASS if the gauge breaks' none
  vcheck "an unprefixed PASS does not score"      'PASS (frame 1)'                     none
  if [ "$fails" -ne 0 ]; then
    echo "run.sh --verdict-selftest: $fails FAILURE(S)"; exit 1
  fi
  echo "run.sh --verdict-selftest: OK"; exit 0
fi

SCRIPT="${1:?usage: run.sh <script.lua> [logfile]}"

# A worker id used to select a persistent directory and was therefore an
# isolation key.  It is now deliberately only a human-readable prefix.
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

# ------------------------------------------------------------ shared emulator
# Every worker on this machine execs ONE read-only Mesen bundle, and nothing
# ever writes inside it.  Workers are kept apart by giving each its own Mesen
# CONFIG HOME rather than its own copy of the app.
#
# Mesen picks that home exactly one of two ways, both measured here:
#   * PORTABLE -- a settings.json sitting beside the binary wins over
#     everything else, unconditionally.  That is how this script used to
#     isolate workers, and it is why each needed a private 413MB bundle: the
#     config lived INSIDE the app, so sharing an app meant sharing (and
#     racing on) one settings.json.  See 2bf5045 for what that cost.
#   * otherwise -- ~/Library/Application Support/Mesen2, resolved through
#     CoreFoundation.  $HOME does NOT move it: with HOME set to a scratch dir
#     a run still wrote its .srm and Debugger/*.cdl into the real profile,
#     because .NET reaches SpecialFolder.ApplicationData via
#     NSSearchPathForDirectoriesInDomains, which takes the home from the
#     password database (the binary carries the giveaway symbol
#     GetHomeDirectory:TryGetHomeDirectoryFromPasswd).  CFFIXED_USER_HOME,
#     Core Foundation's own home override, DOES move it -- settings, saves,
#     Debugger/*.cdl, the lot.
#
# So: strip settings.json from the shared copy, which makes it non-portable,
# and hand each worker its own CFFIXED_USER_HOME.  The isolation is strictly
# stronger than the copy scheme it replaces -- there is no per-worker state
# inside the app to race on, because there is no per-worker app.
#
# Why a COPY of tools/Mesen.app and not tools/Mesen.app itself: the user's
# manual-play profile (`make run`) lives in that bundle as precisely the
# settings.json that forces portable mode, so execing it would put every
# worker back on one shared config.  The harness must not depend on the
# mutable state of the play bundle, so it keeps its own stripped copy.
#
# ONE copy, machine-wide, under ~/Library/Caches -- not one per worker, and
# not one per worktree.  Mesen is ad-hoc signed but NOT notarized (see
# docs/TOOLING.md), so macOS runs a first-launch Gatekeeper assessment on
# every NEW bundle path: a user-visible "Verifying Mesen..." dialog and a
# multi-second scan of all 413MB (measured: 4.7s and 6.1s on two fresh paths
# against 0.3-0.5s once the path is known).  The old scheme minted four of
# those per tree and four more every time an agent made a worktree.  Clearing
# quarantine does not help -- `xattr -cr` before first launch still cost 5.5s,
# and the kernel puts com.apple.provenance straight back on exec -- because
# the trigger is the new bundle path, not the flag.
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
    # The whole point: no settings.json (nor the .bak rotation Mesen leaves
    # beside it) may survive into the copy, or portable mode wins and every
    # worker is back on one shared config.
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

# A tree from before this scheme still has a 413MB per-worker bundle sitting
# in build/.  Nothing reads it any more, so reclaim it on the way past rather
# than leave it to rot -- and, more to the point, so a tree can never quietly
# keep running the old private-copy path.  Test -L as well as -e: the bug in
# 2bf5045 left some of these as symlinks, and -e alone is false for a symlink
# whose target has since gone.
if [ -L "$STALE_APP" ] || [ -e "$STALE_APP" ]; then rm -rf "$STALE_APP"; fi

# The worker's private Mesen config home.  Mesen copies its native libs and
# the Satellaview firmware into a fresh home on first use (~29MB); pre-clone
# them (cp -c again, so eight worker homes cost eight sets of pointers rather
# than 232MB) and Mesen leaves them alone -- its copy is
# copy-if-missing, and -p keeps the mtimes it stamps them with.  Re-seed from
# scratch when the emulator changes, so a home can never serve a stale
# MesenCore.dylib to a newer binary.
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
# already had, which is exactly the unpinned state the determinism guarantees
# exclude.  Refusing the run beats reporting a green that never had the pins.
# With no settings.json at all Mesen ignores --testrunner and opens the GUI
# setup wizard, so this is also what keeps a fresh home headless.
python3 "$ROOT/tools/tests/lib/pin_test_saves.py" \
  "$HOME/Library/Application Support/Mesen2/settings.json" \
  "$MESEN2/settings.json" \
  "$TEST_SAVES" || { echo "pin_test_saves.py failed; refusing to run unpinned"; exit 2; }

# Fresh battery every run: the testrunner flushes SRAM to <saves>/*.srm on
# exit and silently reloads it next boot -- a stale srm is a hidden
# cross-run coupling channel (and fossilizes into minted savestates).
# Tests that need a save inject it explicitly (SRM sidecars).
rm -f "$TEST_SAVES"/*.srm
if [ -n "${OT6_SRAM_ANCHOR:-}" ]; then
  # THE persistent_layout GATE (issue #25).  A leg declares the persistent-
  # SRAM layout it understands with a marker comment in its script,
  #
  #     [dash][dash] OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
  #
  # (spelled as a real Lua comment at the start of a line; not written out
  # here so THIS file can never satisfy the grep).  The declaration rides
  # the script itself rather than an env var, so every consumer -- mint,
  # smoke, a bare manual run.sh -- gets the same refusal with no caller
  # wiring, and it survives composition (comments do).  sram_anchor.py
  # compares it against the anchor manifest's persistent_layout and refuses
  # a mismatch NAMING BOTH STRINGS, here, before the emulator boots: a
  # schema-drift stale anchor must be a named refusal, never an in-emulator
  # timeout.  A leg with no marker declares support for nothing and is
  # refused too -- fail closed, or the gate only guards legs that opted in.
  ANCHOR_LAYOUT=$(sed -n 's/^-- OT6_ANCHOR_LAYOUT: *\([^ ]*\).*$/\1/p' "$COMPOSED" | head -n 1)
  python3 "$ROOT/tools/tests/lib/sram_anchor.py" materialize \
    "$OT6_SRAM_ANCHOR" "$TEST_SAVES/$(basename "$ROM" .sfc).srm" \
    "$ANCHOR_LAYOUT" ||
    { echo "invalid SRAM anchor: $OT6_SRAM_ANCHOR (refused BEFORE boot)"; exit 2; }
fi
# --timeout: Mesen's testrunner has a hard DEFAULT 100-second wall-clock
# cap (exit -1/255 + truncated stdout on expiry) that reaped long runs; keep
# a cap as the only defense against a genuinely hung emulator, just a roomy one.
# OT6_TIMEOUT raises it for a run you already know is competing for cores --
# the cap is WALL clock, so `nice` does not protect it (see the reap
# diagnosis below).
# --enableStdout mirrors the EMULATOR message log to stdout.  It does NOT
# carry Lua errors or watchdog kills -- those go to the script log, which
# nothing reads headless.  A script that goes quiet has told you nothing;
# print() is the only channel out.  Kept for the ROM-info banner.
# CFFIXED_USER_HOME is the isolation boundary measured above.
CAP="${OT6_TIMEOUT:-600}"
# A REAP IS NOT A RESULT, SO THE HARNESS RESOLVES IT INSTEAD OF REPORTING IT.
# The cap is WALL clock and `nice` does not slow the wall, so concurrent jobs
# starve each other: a mint that takes 400s alone can cross 600s when a dozen
# share ten cores.  That used to surface as a red edge with a paragraph of
# explanation, and every reader had to re-learn that "exit 255, truncated
# stdout" is not a crash.  Isolation was already solved -- every invocation
# gets its own workspace and CFFIXED_USER_HOME (dd2266a, 10ce17c) -- which is
# exactly what makes a retry SAFE and deterministic: the same inputs, run
# again, with nothing shared to have been disturbed.  So retry it.
#
# RETRIED ONLY ON THE REAP SIGNATURE, and this distinction is load-bearing:
# no verdict in the log AND the run lived to the cap.  A real FAIL is NEVER
# retried -- retrying failures until they pass is the #74 mistake in harness
# clothing, and it would silently launder a flaky test into a green one.  A
# no-verdict run that died WELL SHORT of the cap is not retried either: that
# is a Lua load error, which is deterministic and will fail identically.
RETRIES="${OT6_REAP_RETRIES:-1}"
attempt=0
retried=0
while :; do
  attempt=$(( attempt + 1 ))
  t0=$(date +%s)
  env CFFIXED_USER_HOME="$MESEN_HOME" \
    "$SHARED_APP/Contents/MacOS/Mesen" --testrunner --timeout="$CAP" --enableStdout \
    "$ROM" "$COMPOSED" > "$RUN_LOG" 2>&1
  code=$?
  elapsed=$(( $(date +%s) - t0 ))
  verdict_spoken "$RUN_LOG" && break
  [ $(( elapsed + 5 )) -ge "$CAP" ] || break
  [ "$attempt" -le "$RETRIES" ] || break
  retried=$(( retried + 1 ))
  printf '[ot6] REAPED after %ss against a %ss wall-clock cap -- retrying (attempt %s of %s).  Runs are isolated, so this is safe and is not a re-roll of a failure: no verdict was ever reached.\n' \
    "$elapsed" "$CAP" "$(( attempt + 1 ))" "$(( RETRIES + 1 ))" >&2
  sleep 5
done

python3 "$ROOT/tools/tests/lib/decode_b64.py" "$RUN_LOG" "$ART"

if [ "$retried" -gt 0 ] && verdict_spoken "$RUN_LOG"; then
  # Never let a retry be silent: a machine reaping runs is a fact worth
  # seeing even when the retry rescued the result.
  printf '[ot6] this run was REAPED %s time(s) by the %ss wall-clock cap and retried; the verdict below is from attempt %s.\n' \
    "$retried" "$CAP" "$attempt" >> "$RUN_LOG"
fi
if grep -qE "$PASS_RE" "$RUN_LOG"; then
  verdict=0
elif grep -qE "$FAIL_RE" "$RUN_LOG"; then
  verdict=1
else
  verdict=$code
  # NO VERDICT IN THE LOG.  The script never reached PASS or FAIL, so the
  # emulator was killed rather than finishing -- and if it lived roughly to
  # the cap, the killer was the cap.  Say so, because the raw signature is
  # "exit 255, truncated stdout" and that reads exactly like a crash: the
  # brief has to keep re-teaching agents that it is not one, and it is the
  # documented top cause of a mint failing for reasons that are not the mint.
  #
  # WHY THIS IS USUALLY CONTENTION AND NOT THE TEST: the cap is WALL clock,
  # and `nice` does not slow the wall.  Niced work yields to the owner's
  # game, but every agent's jobs are equally niced, so they starve EACH
  # OTHER -- a mint that takes 400s alone can cross 600s when a dozen of
  # them share ten cores.  Observed 2026-07-29: nine states minted fine,
  # four reaped, all four green when re-run alone.
  # "Lived to the cap" with 5s of slack for rounding -- not a fixed 30s
  # margin, which goes negative and always fires under a small OT6_TIMEOUT.
  #
  # It goes into $RUN_LOG with the [ot6] prefix rather than straight to
  # stdout, because stdout is not where it would be read: suite.sh runs every
  # test as `"$RUN" ... >/dev/null 2>&1` and keeps only the log.  Written
  # here it reaches BOTH readers -- the `grep '^\[ot6\]'` at the end of this
  # script prints it for a direct invocation, and it is inside
  # build/states/suite_<test>.log for a suite one.  decode_b64 has already
  # read the log, so appending now is safe.
  reap() { printf '[ot6] %s\n' "$@" >> "$RUN_LOG"; }
  if [ $(( elapsed + 5 )) -ge "$CAP" ]; then
    reap "REAPED: no verdict, and the run lasted ${elapsed}s against a ${CAP}s wall-clock cap (--timeout).  Mesen killed it; it did not crash." \
         "  This is the FINAL attempt: the harness already retried it ${retried} time(s)" \
         "  automatically (OT6_REAP_RETRIES=${RETRIES}), so the cap is not merely being" \
         "  grazed -- this run cannot finish inside it on this machine right now." \
         "  Load right now: $(uptime | sed 's/.*load average/load average/')" \
         "  The cap is wall clock, so nice(1) does not protect it -- concurrent" \
         "  jobs are all equally niced and starve each other." \
         "  Next: raise the cap for this run (OT6_TIMEOUT=1200), allow more" \
         "  retries (OT6_REAP_RETRIES=3), or lower parallelism (NINJAFLAGS=-j2)."
  elif [ "$verdict" -ne 0 ]; then
    reap "no verdict after ${elapsed}s (cap ${CAP}s): the script died before reaching PASS or FAIL." \
         "  Well short of the cap, so this is NOT the reap -- read this log for a Lua load error."
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
# Anchor creation is intentionally a separate, explicit operation.  Mesen
# flushes battery SRAM only while shutting down, so the complete 32 KiB file
# becomes available here, after the Lua script has exercised the real Save UI.
if [ "$verdict" -eq 0 ] && [ -n "${OT6_CAPTURE_SRM:-}" ]; then
  captured="$TEST_SAVES/$(basename "$ROM" .sfc).srm"
  if [ -f "$captured" ] && [ "$(wc -c < "$captured" | tr -d ' ')" -eq 32768 ]; then
    mkdir -p "$(dirname "$OT6_CAPTURE_SRM")"
    publish_file "$captured" "$OT6_CAPTURE_SRM"
    # Provenance sidecar (issue #75 step 5): record MECHANICALLY what cut
    # this battery -- the capturing generator's mint sig (from the one
    # authority, frontier_stamp.sh), plus the hash of everything the run
    # booted FROM: the stamp of each savestate compose embedded (read off
    # the composed file's own `-- state` provenance lines) and, when the
    # run Continued from a prior anchor, that anchor's manifest.  The
    # sidecar lands beside the payload; `sram_anchor.py seal` folds it
    # into manifest.json.  A capture that cannot state its provenance is
    # refused outright -- an anchor is a frontier root, and an unprovable
    # root is the exact thing this program exists to stop minting.
    gen=$(basename "$SCRIPT" .lua)
    anchor_extras=""
    adir=""
    if [ -n "${OT6_SRAM_ANCHOR:-}" ]; then
      adir="$OT6_SRAM_ANCHOR"
      case "$adir" in "$ROOT"/*) adir="${adir#"$ROOT"/}" ;; esac
      anchor_extras="$adir/manifest.json"
      for p in "$ROOT/$adir"/*.sram; do
        [ -f "$p" ] && anchor_extras="$anchor_extras $adir/$(basename "$p")"
      done
    fi
    # shellcheck disable=SC2086 -- extras/ancestors are space-separated lists
    if mint_sig=$(sh "$ROOT/tools/tests/lib/frontier_stamp.sh" sig "$gen" $anchor_extras); then
      ancestors=$(
        sed -n 's/^-- state \([A-Za-z0-9_]*\)\.mss\.lua .*/\1/p' "$COMPOSED" |
          while IFS= read -r s; do
            [ -f "$ROOT/build/states/$s.stamp" ] && echo "build/states/$s.stamp"
          done
      )
      [ -z "$adir" ] || ancestors="$adir/manifest.json
$ancestors"
      # shellcheck disable=SC2086
      python3 "$ROOT/tools/tests/lib/sram_anchor.py" capture "$ROOT" \
        "$OT6_CAPTURE_SRM.provenance.json" "$OT6_CAPTURE_SRM" \
        "$mint_sig" $ancestors ||
        { echo "capture provenance sidecar failed for $OT6_CAPTURE_SRM"; verdict=2; }
    else
      echo "capture refused: cannot derive a mint sig for $SCRIPT" \
           "(a capture must run a tools/tests generator; issue #75)"
      verdict=2
    fi
  else
    echo "Mesen did not flush a complete 32768-byte SRAM image: $captured"
    verdict=2
  fi
fi
publish_file "$RUN_LOG" "$LOG"
# OT6_NO_PUBLISH=1 runs a generator for its VERDICT ONLY, leaving build/states
# untouched.  `make smoke` uses it to falsify a lib change in minutes without
# half-updating the chain: a state minted mid-smoke would be fresher than its
# neighbours and make the tree harder to reason about, for no benefit -- the
# stamp gate would re-mint it anyway.
#
# A MINT EDGE PUBLISHES ONLY ITS OWN ARTIFACTS (issue #30).  OT6_EXPECT_ARTIFACT
# is set exactly by frontier_ninja.py's mint rule, naming the ONE state the
# invoking ninja edge is for.  A multi-mint script emits EVERY sibling state
# on every invocation (gen_edgar plays the whole Figaro chapter and emits all
# three figaro states no matter which edge invoked it), and each sibling is
# its own ninja edge running this same script -- so publishing the whole
# workspace let one edge rewrite ANOTHER edge's declared outputs with fresh
# mtimes.  For gen_edgar's figaro_cleared edge that meant republishing
# figaro_matron.mss -- its own INPUT -- after its own outputs (the "$ART"/*
# glob publishes cleared before matron), so ninja saw input-newer-than-output
# forever and consecutive `make frontier` runs re-minted every multi-mint
# family and its downstream trunk with zero content changes.  The sibling
# copies this run just emitted are deliberately DISCARDED, not moved: every
# sibling has its own edge, so the published copy is always the one whose
# edge ninja scheduled and whose stamp frontier_stamp.sh wrote.  Screenshots
# still publish either way -- they are forensic output, not scheduled ninja
# outputs, and no edge declares them.
# frontier_ninja_selftest.sh's stub run.sh MIRRORS this block; keep in lockstep.
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
  # Failed workspaces are valuable forensic evidence and bounded to this exact
  # invocation.  Retain them without weakening successful-run cleanup.
  OT6_KEEP_RUNS=1
  echo "failed run retained: $WDIR"
}
exit "$verdict"
