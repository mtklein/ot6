#!/bin/sh
# run.sh <script.lua> [logfile] -- run a Lua test under Mesen 2's headless testrunner.
#
#   tools/tests/run.sh tools/tests/battle_smoke.lua
#
# * Composes the script with the lib (ot6.lua + ot6_field.lua) into one flat
#   file in the invocation workspace first (see compose.py).  A script that
#   is already composed (first line carries compose.py's marker) runs as-is.
# * Runs build/ot6.sfc.
# * All emulator/script output goes to the logfile
#   (default: build/states/last_run.log).
# * [b64:<tag>] payloads emitted by the script (savestates, screenshots) are
#   decoded into build/states/ and build/states/shots/ afterwards.
# * Every invocation gets a fresh workspace under build/test-runs/.  OT6_WORKER
#   is only a diagnostic label.  Every worker execs one shared read-only
#   Mesen bundle and is kept apart by CFFIXED_USER_HOME (XDG_CONFIG_HOME on
#   Linux; see "shared emulator" below).
# * Exit code: 0 = pass, 1 = assertion/Lua error, 2 = frame budget exceeded.
#   The [ot6] PASS/FAIL verdict in the log takes precedence over the raw
#   process code.
# * The emulator is the build tools/mesen/EMULATOR pins, deployed on this
#   machine at ~/mesen-pins/<commit>/Mesen.app (macOS; ~/mesen-pins/<commit>/Mesen
#   on Linux), else tools/Mesen-linux (tools/Mesen.app on macOS), or the
#   directory/bundle in OT6_MESEN_APP, which then needs an OT6_MESEN_CACHE
#   other than the machine-wide one.  Its sha256 is recorded as an
#   `[emulator]` line at the end of the log, with the sha256 of the core
#   that run loaded (core=), and beside every published .mss as
#   <state>.mss.emulator (that same line), where savestate_stamp.sh reads
#   the first sha for the stamp.
# * MESEN_SCRIPT_ONLY=1 is exported unless the run measures coverage: the
#   patched build (tools/mesen/) then skips the debugger bookkeeping the
#   harness never reads; the official binary ignores the variable.
set -u
# Every emulator runs at low CPU priority (niceness 10 or more), however it
# was started: the machines are shared with their owner, and placement fills
# them on the understanding that whatever the owner runs comes first.
_ni=$(ps -o nice= -p $$ 2>/dev/null | tr -d ' ')   # BSD nice(1) can't print it
case "$_ni" in ''|*[!0-9-]*) _ni=10 ;; esac
if [ "$_ni" -lt 10 ]; then exec nice -n $((10 - _ni)) sh "$0" "$@"; fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROM="${OT6_ROM:-$ROOT/build/ot6.sfc}"
# The verdict patterns must match a whole verdict line rather than a prefix.
# lib/ot6.lua emits two terminal lines, `PASS (frame N)` and `FAIL: <why>`,
# through M.log, so they arrive as `[ot6] PASS (frame N)` / `[ot6] FAIL: ...`.
# The patterns anchor on the parenthesis and the colon that only the real
# verdicts carry, so a bare `PASSED phase N: ...` progress line never matches.
PASS_RE='^\[ot6\] PASS \(frame '
FAIL_RE='^\[ot6\] FAIL: '
verdict_spoken() { grep -qE "$PASS_RE|$FAIL_RE" "$1"; }

# --verdict-selftest: falsify the PASS/FAIL parsing without launching Mesen.
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

# The build lock: the shell's own exclusive create (noclobber `>` opens with
# O_CREAT|O_EXCL), so exactly one of any number of concurrent takers gets
# it, whatever mkdir(1) the machine has.  It used to be `mkdir "$LOCK"`, and
# px13's mkdir is uutils coreutils 0.10.0 (Ubuntu 26.04), which is not
# atomic: of 16 concurrent `mkdir L`, more than one reported success in 145
# of 300 rounds on ext4 and 114 of 300 on tmpfs (GNU mkdir, os.mkdir and
# this lock: 0 of 300; build/attempts/wt/v026-graph/371/mkdirrace.txt), so
# two workers built the shared copy at once, the second mv nesting its
# build inside the first's (#371).
take_lock() { ( set -C; : > "$1" ) 2>/dev/null; }
# --take-lock <path> [<go>]: the primitive alone, for
# shared_emulator_selftest.sh; with <go>, spin (no forks) until it exists,
# so concurrent takers all reach the lock in the same instant.
if [ "${1:-}" = "--take-lock" ]; then
  if [ -n "${3:-}" ]; then while [ ! -e "$3" ]; do :; done; fi
  take_lock "${2:?--take-lock <path> [<go>]}"; exit
fi

SCRIPT="${1:?usage: run.sh <script.lua> [logfile]}"

# A human-readable prefix for the workspace directory name.
label=$(printf '%s' "${OT6_WORKER:-$(basename "$SCRIPT" .lua)}" | tr -c 'A-Za-z0-9_.-' '_')
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
  COMPOSED="$SCRIPT"   # already composed; run as-is
else
  python3 "$ROOT/tools/tests/lib/compose.py" "$SCRIPT" "$COMPOSED" || exit 2
fi

# The live broadcast (lib/ot6.lua "live broadcast") is unconditional: every
# headless run streams its screen, its pad and its notes into the run log,
# and tools/stream/live.py shows every one of them.  There is no flag and no
# environment variable, on purpose.
#
# There used to be OT6_LIVE, and it is why the survey had holes: eighteen
# launchers passed OT6_LIVE=0 to skip the stream, one of them written the
# same day the first five were cleaned up, by copying a neighbour.  Chasing
# call sites cannot give a guarantee -- the next lab copies the last one --
# so the capability is gone rather than defaulted.  A run that is genuinely
# too hot for a screenshot every 128 frames should say so and get the
# interval changed in one place, for everybody.
# OT6_ART_DIR rides the same prelude: it is where this invocation's decoded
# artifacts land.  The segment runner (lib/ot6.lua) names the screenshot it
# took at a fast failure in the FAIL line, and a failed workspace is
# retained, so that path has to be the real one rather than "somewhere under
# build/test-runs".
PRELUDE="$WDIR/composed_live.lua"
{ printf 'OT6_ART_DIR = "%s"\n' "$ART"
  cat "$COMPOSED"; } > "$PRELUDE"
COMPOSED="$PRELUDE"

# Script-only Mesen (tools/mesen/README.md): the patched build stops keeping
# the code/data log and access counters the debugger windows read, and the
# harness reads neither -- except a coverage run, whose coverageFlush reads
# the code/data log (emu.getCdlData).  So every run but a coverage run asks
# for it; the official binary ignores the variable.  A coverage run is one
# composed with OT6_COVERAGE set, whether here or in an already composed
# script.  An explicit MESEN_SCRIPT_ONLY=0 opts a run out.
if [ -n "${OT6_COVERAGE:-}" ] || grep -q '^OT6_COVERAGE = true' "$COMPOSED"; then
  export MESEN_SCRIPT_ONLY=0
else
  export MESEN_SCRIPT_ONLY="${MESEN_SCRIPT_ONLY:-1}"
fi

# ------------------------------------------------------------ shared emulator
# Every worker on this machine execs one read-only Mesen bundle, and nothing
# ever writes inside it.  Workers are kept apart by giving each its own Mesen
# config home rather than its own copy of the app.
#
# Mesen picks that home one of two ways: portable mode, where a settings.json
# beside the binary wins unconditionally, or otherwise via CoreFoundation's
# home resolution, which $HOME does not redirect but CFFIXED_USER_HOME does
# (settings, saves, Debugger/*.cdl, and the rest).
#
# So strip settings.json from the shared copy, which makes it non-portable,
# and hand each worker its own CFFIXED_USER_HOME.
#
# The shared copy is not tools/Mesen.app itself: that bundle carries the
# manual-play profile's settings.json, which forces portable mode, so execing
# it directly would put every worker back on one shared config.
#
# One copy, machine-wide, under ~/Library/Caches, rather than one per worker
# or one per worktree: Mesen is ad-hoc signed but not notarized (see
# docs/TOOLING.md), so macOS runs a Gatekeeper assessment on every new bundle
# path.
#
# Linux (docs/TOOLING.md "Linux worker") runs the official single-file x64
# binary from tools/Mesen-linux/ the same way: one shared copy with no
# settings.json beside it, under ~/.cache/ot6, and a private home per worker.
# There .NET finds the home through XDG_CONFIG_HOME, which is the isolation
# boundary in place of CFFIXED_USER_HOME.  The native libraries live inside
# the binary, so the pre-seed loop below finds none and Mesen extracts them
# into each fresh home itself (~0.05s).
# OT6_MESEN_CACHE relocates the cache (shared_emulator_selftest.sh provisions
# into a scratch one); the default is the machine-wide path above.
# Deployed per pin (#394): each machine keeps every pinned build at
# ~/mesen-pins/<commit>/ (tools/mesen/README.md, Deploying), and a tree runs
# the one its tools/mesen/EMULATOR names, through a shared copy of its own
# (Mesen-test-<commit12>).  So trees on different pins run side by side, and
# a pin bump deploys without touching anyone else's tree.  A machine without
# the pin's directory falls back to the tree's tools/Mesen.app (Mesen-linux),
# and the check below holds that to the pin.
PIN_COMMIT=$(cut -d' ' -f3 "$ROOT/tools/mesen/EMULATOR" 2>/dev/null)
PIN_DIR="$HOME/mesen-pins/$PIN_COMMIT"
PIN_TAG=""
if [ "$(uname -s)" = Darwin ]; then
  DEF_APP="$ROOT/tools/Mesen.app"
  if [ -n "$PIN_COMMIT" ] && [ -x "$PIN_DIR/Mesen.app/Contents/MacOS/Mesen" ]; then
    DEF_APP="$PIN_DIR/Mesen.app"; PIN_TAG="-$(echo "$PIN_COMMIT" | cut -c1-12)"
  fi
  SRC_APP="${OT6_MESEN_APP:-$DEF_APP}"
  DEFAULT_CACHE="$HOME/Library/Caches/ot6"
  MESEN_CACHE="${OT6_MESEN_CACHE:-$DEFAULT_CACHE}"
  SHARED_APP="$MESEN_CACHE/Mesen-test$PIN_TAG"; APP_EXT=.app
  BIN_SUB=/Contents/MacOS          # the executable's directory in the bundle
  file_stamp() { stat -Lf '%z %m' "$1"; }
  clone_cp() { cp -c "$@" 2>/dev/null || cp "$@"; }   # APFS clonefile
  GATEKEEPER_NOTE="; expect a Gatekeeper scan"
else
  GATEKEEPER_NOTE=
  DEF_APP="$ROOT/tools/Mesen-linux"
  if [ -n "$PIN_COMMIT" ] && [ -x "$PIN_DIR/Mesen" ]; then
    DEF_APP="$PIN_DIR"; PIN_TAG="-$(echo "$PIN_COMMIT" | cut -c1-12)"
  fi
  SRC_APP="${OT6_MESEN_APP:-$DEF_APP}"
  DEFAULT_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ot6"
  MESEN_CACHE="${OT6_MESEN_CACHE:-$DEFAULT_CACHE}"
  SHARED_APP="$MESEN_CACHE/Mesen-test$PIN_TAG"; APP_EXT=
  BIN_SUB=
  file_stamp() { stat -Lc '%s %Y' "$1"; }
  clone_cp() { cp --reflink=auto "$@"; }
fi
# Rebuild the shared copy when the source bundle changes (a Mesen upgrade).
# -L: in a worktree tools/Mesen.app is a symlink into the main tree.
SRC_STAMP=$(file_stamp "$SRC_APP$BIN_SUB/Mesen" 2>/dev/null) || {
  echo "no Mesen at $SRC_APP (run tools/worktree-setup.sh?)"; exit 2; }
# Another emulator must not rebuild the machine-wide shared copy every other
# worker execs: OT6_MESEN_APP needs a cache of its own, and its shared copy
# is named after its binary's sha256, so two different apps can never take
# turns rebuilding one copy under each other.
if [ -n "${OT6_MESEN_APP:-}" ]; then
  real_dir() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "${1%/}"; }
  if [ -z "${OT6_MESEN_CACHE:-}" ] ||
     [ "$(real_dir "$OT6_MESEN_CACHE")" = "$(real_dir "$DEFAULT_CACHE")" ]; then
    echo "OT6_MESEN_APP needs an OT6_MESEN_CACHE of its own, not the machine-wide $DEFAULT_CACHE"; exit 2
  fi
  APP_SHA=$(shasum -a 256 "$SRC_APP$BIN_SUB/Mesen" | cut -c1-64)
  SHARED_APP="$SHARED_APP-$(echo "$APP_SHA" | cut -c1-16)"
fi
SHARED_APP="$SHARED_APP$APP_EXT"

shared_app_ready() {
  [ -x "$SHARED_APP$BIN_SUB/Mesen" ] &&
  [ ! -e "$SHARED_APP$BIN_SUB/settings.json" ] &&
  [ "$(cat "$SHARED_APP.stamp" 2>/dev/null)" = "$SRC_STAMP" ]
}
# What a not-ready look saw, for the build line (#371: a selftest wave once
# counted two builds of one cold cache, never reproduced; the next one says
# what the second builder found).
shared_app_why() {
  if [ ! -x "$SHARED_APP$BIN_SUB/Mesen" ]; then echo "no executable"
  elif [ -e "$SHARED_APP$BIN_SUB/settings.json" ]; then echo "a settings.json"
  else echo "stamp '$(cat "$SHARED_APP.stamp" 2>/dev/null)', want '$SRC_STAMP'"; fi
}

if ! shared_app_ready; then
  # Many workers can arrive here at once on a cold cache.  Whoever takes the
  # lock builds it; the rest wait for that one build instead of racing to
  # install over each other (mv of a directory onto an existing directory
  # nests it rather than replacing it, which would corrupt the bundle).
  mkdir -p "$MESEN_CACHE"
  LOCK="$MESEN_CACHE/.build.lock"
  held=""; waited=0
  until shared_app_ready; do
    if take_lock "$LOCK"; then held=1; break; fi
    sleep 1; waited=$((waited + 1))
    [ "$waited" -gt 180 ] && { echo "stale lock $LOCK; remove it and retry"; exit 2; }
  done
  if [ -n "$held" ]; then
    # Release the lock however we leave: a run that dies mid-build must not
    # stall every later worker behind a lock nobody holds.
    HELD_LOCK="$LOCK"
    # Look again under the lock.  The look that sent us here can predate the
    # previous holder's last step, and a rebuild on that stale look tears a
    # finished bundle down under every worker between its own look and its
    # exec (#242: three generate edges died that way on a cold cache).
    if ! shared_app_ready; then
      echo "creating shared test emulator (one-time${GATEKEEPER_NOTE}; pid $$ found $(shared_app_why))..."
      TMP="$MESEN_CACHE/.build.$$"
      rm -rf "$TMP" "$SHARED_APP" "$SHARED_APP.stamp"
      # cp -c = APFS clonefile: instant and ~zero physical disk.  -L because
      # in a worktree the source is a symlink and cp -R would copy the LINK.
      clone_cp -RL "$SRC_APP" "$TMP" || {
        rm -rf "$TMP"; echo "could not copy $SRC_APP"; exit 2; }
      # No settings.json (nor the .bak rotation Mesen leaves beside it) may
      # survive into the copy, or portable mode wins and every worker is back
      # on one shared config.
      rm -f "$TMP$BIN_SUB/settings.json" "$TMP$BIN_SUB"/settings.*.bak
      # Profile dirs the source bundle accumulated while it was portable
      # belong to the user's play profile, not to the tests; they must not
      # ride along.
      rm -rf "$TMP$BIN_SUB/Saves" "$TMP$BIN_SUB/SaveStates" \
             "$TMP$BIN_SUB/RecentGames" "$TMP$BIN_SUB/Debugger"
      mv "$TMP" "$SHARED_APP"
      printf '%s' "$SRC_STAMP" > "$SHARED_APP.stamp"
      # Verify before the lock is let go: a build the next look cannot see
      # as ready would be built again under every worker already handed it.
      shared_app_ready || {
        echo "shared test emulator built but not ready: $(shared_app_why)"; exit 2; }
    fi
    rm -rf "$LOCK"; HELD_LOCK=""
  fi
fi
shared_app_ready || { echo "shared test emulator missing at $SHARED_APP"; exit 2; }
# Test-only: shared_emulator_selftest.sh drives many workers through the
# gate above against a scratch cache and stops each one here, before the
# Gatekeeper scan a fresh bundle path would cost.
if [ -n "${OT6_PROVISION_PROBE_OUT:-}" ]; then
  printf '%s\n' "$SHARED_APP" > "$OT6_PROVISION_PROBE_OUT"
  exit 0
fi
# The emulator's identity for the log: a provenance record, not a binding.
# It is the executable's sha256, and that covers the emulation core too:
# the core is packed in the executable (Dependencies.zip), and the only copy
# Mesen loads is the one it unpacks into the worker's fresh home, because the
# seeding below never pre-seeds a core.  The [emulator] line also names the
# core that actually ran (core=, hashed in the home after the run).
# Hashed once per shared copy; the file names the copy (its source stamp),
# so a copy rebuilt by a run.sh that predates this is hashed again.
EMULATOR_SHA=""
[ -f "$SHARED_APP.sha256" ] && read -r EMULATOR_SHA EMULATOR_OF < "$SHARED_APP.sha256"
if [ -z "$EMULATOR_SHA" ] || [ "${EMULATOR_OF:-}" != "$SRC_STAMP" ]; then
  EMULATOR_SHA=$(shasum -a 256 "$SHARED_APP$BIN_SUB/Mesen" | cut -c1-64)
  printf '%s %s\n' "$EMULATOR_SHA" "$SRC_STAMP" > "$SHARED_APP.sha256.$$" &&
    mv -f "$SHARED_APP.sha256.$$" "$SHARED_APP.sha256"
fi
# Which build that is (#345): the `<repository> <tag> <commit>` record
# tools/mesen/build.sh packs into the executable (tools/mesen/buildinfo.py;
# `none` for a build without one), read once per shared copy like the sha.
# The deployed emulator must be the one tools/mesen/EMULATOR pins: every
# fixture and verdict is the emulator's as much as the ROM's, and a machine
# still running the old build after a pin change would regenerate under
# the new pin with the wrong emulator.  OT6_MESEN_APP is a deliberate
# other emulator (build.sh's smoke test runs a stock reference) and is not
# held to the pin.
EMULATOR_REC=""
[ -f "$SHARED_APP.buildinfo" ] && { read -r EMULATOR_REC_OF; read -r EMULATOR_REC; } < "$SHARED_APP.buildinfo"
if [ -z "$EMULATOR_REC" ] || [ "${EMULATOR_REC_OF:-}" != "$SRC_STAMP" ]; then
  EMULATOR_REC=$(python3 "$ROOT/tools/mesen/buildinfo.py" "$SHARED_APP$BIN_SUB/Mesen")
  printf '%s\n%s\n' "$SRC_STAMP" "$EMULATOR_REC" > "$SHARED_APP.buildinfo.$$" &&
    mv -f "$SHARED_APP.buildinfo.$$" "$SHARED_APP.buildinfo"
fi
EMULATOR_COMMIT=$(printf '%s' "$EMULATOR_REC" | cut -d' ' -f3)
PIN=$(cat "$ROOT/tools/mesen/EMULATOR" 2>/dev/null)
if [ -z "${OT6_MESEN_APP:-}" ] && [ "$EMULATOR_REC" != "$PIN" ]; then
  echo "[ot6] FAIL: the deployed emulator $SRC_APP is the build '$EMULATOR_REC', but tools/mesen/EMULATOR pins '$PIN': deploy the pinned build on this machine first, at $PIN_DIR/ (tools/mesen/README.md, Deploying); refused BEFORE boot"
  exit 2
fi

# Remove any stale per-worker bundle in build/.  Test -L as well as -e: it
# may be a symlink whose target is gone, and -e alone is false for that.
if [ -L "$STALE_APP" ] || [ -e "$STALE_APP" ]; then rm -rf "$STALE_APP"; fi

# The worker's private Mesen config home.  Mesen copies its native libs and
# the Satellaview firmware into a fresh home on first use (~29MB); pre-clone
# them (cp -c again, so eight worker homes cost eight sets of pointers rather
# than 232MB) and Mesen leaves them alone, because its copy is copy-if-missing
# and -p keeps the mtimes it stamps them with.  Re-seed from scratch when the
# emulator changes.
# Never MesenCore.dylib: a loose one in a bundle is only what Mesen unpacked
# there while the bundle was portable (the official tools/Mesen.app, played
# by hand), and Mesen keeps a home's copy whenever its size and mtime match
# the packed one's, so seeding it would run a core the executable's sha256
# does not cover.  Mesen unpacks its own (~9MB) instead, as it does on Linux.
if [ "$(uname -s)" = Darwin ]; then
  MESEN2="$MESEN_HOME/Library/Application Support/Mesen2"
  USER_SETTINGS="$HOME/Library/Application Support/Mesen2/settings.json"
  # exec: backgrounded, the watchdog below must see Mesen's own pid.
  run_mesen() { exec env CFFIXED_USER_HOME="$MESEN_HOME" "$@"; }
else
  MESEN2="$MESEN_HOME/.config/Mesen2"
  USER_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/Mesen2/settings.json"
  # DOTNET_SYSTEM_GLOBALIZATION_INVARIANT: without it .NET loads ICU, which
  # pulls the system libstdc++ in ahead of MesenCore.so; the official build
  # links its own libstdc++ statically, the two collide, and MesenCore dies
  # as it loads (std::bad_cast from a static std::regex; Ubuntu 26.04).
  run_mesen() { exec env XDG_CONFIG_HOME="$MESEN_HOME/.config" \
                  DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 "$@"; }
fi
if [ "$(cat "$MESEN_HOME/.stamp" 2>/dev/null)" != "$SRC_STAMP" ]; then
  rm -rf "$MESEN_HOME"; mkdir -p "$MESEN2"
  for f in MesenNesDB.txt libHarfBuzzSharp.dylib libSkiaSharp.dylib Satellaview; do
    [ -e "$SHARED_APP$BIN_SUB/$f" ] || continue   # let Mesen seed it itself
    clone_cp -Rp "$SHARED_APP$BIN_SUB/$f" "$MESEN2/$f"
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
  "$USER_SETTINGS" \
  "$MESEN2/settings.json" \
  "$TEST_SAVES" || { echo "pin_test_saves.py failed; refusing to run unpinned"; exit 2; }

# Fresh battery every run: the testrunner flushes SRAM to <saves>/*.srm on
# exit and reloads it on the next boot without reporting that it did, so a
# stale srm couples one run to the next and gets baked into generated
# savestates.  Tests that need a save inject it explicitly (SRM sidecars).
rm -f "$TEST_SAVES"/*.srm
# A script that declares a battery layout (the marker below) and embeds no
# savestate boots only by Continuing a battery, so without
# OT6_SRAM_CHECKPOINT it would Continue an empty one, start a New Game and
# fail much later on whatever it waited for (#248: probe_save_compat ran to
# its timeout that way).  Refuse it here, naming the fix.
if [ -z "${OT6_SRAM_CHECKPOINT:-}" ] &&
   grep -q '^-- OT6_CHECKPOINT_LAYOUT: ' "$COMPOSED" &&
   ! grep -q '^-- state [A-Za-z0-9_]*\.mss\.lua ' "$COMPOSED"; then
  echo "[ot6] FAIL: $(basename "$SCRIPT") boots by Continuing a battery (it declares OT6_CHECKPOINT_LAYOUT and loads no savestate), and no OT6_SRAM_CHECKPOINT was given: run it as OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/<key> (configure.py's TEST_ENV names a suite's; refused BEFORE boot)"
  exit 2
fi
if [ -n "${OT6_SRAM_CHECKPOINT:-}" ]; then
  # A generator step declares the persistent-SRAM layout it understands with
  # a marker comment in its script:
  #
  #     [dash][dash] OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
  #
  # (spelled as a real Lua comment at the start of a line; not written out
  # here so this file can never satisfy the grep).  sram_checkpoint.py
  # compares it against the checkpoint manifest's persistent_layout and
  # refuses a mismatch here, before the emulator boots.  A step with no
  # marker is refused too.
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
# run_mesen's home variable is the isolation boundary measured above.
CAP="${OT6_TIMEOUT:-600}"
# A timeout kill carries no result, so the harness retries it instead of
# reporting it.  The cap is wall clock and `nice` does not slow the wall, so
# concurrent jobs starve each other: a savestate generation that takes 400s
# alone can cross 600s when a dozen share ten cores.  Every invocation gets
# its own workspace and CFFIXED_USER_HOME, which is what makes a retry safe
# and deterministic: the same inputs run again with nothing shared disturbed.
#
# The retry fires only on the timeout-kill signature: no verdict in the log,
# and the run lived to the cap.  A real FAIL is never retried, since that
# would turn a flaky test into a green one with no notice.  A no-verdict run
# that died well short of the cap is not retried either: that is a Lua load
# error, which is deterministic and will fail identically.
# The machine-wide emulator limit (#407): before its emulator starts, this run
# takes one of the machine's slots (lib/emu_slot.py: a flock the kernel drops
# when the holder dies; N from the machine's own ~/.config/ot6/emulator-slots,
# else its CPU count) and keeps it for every attempt.  A batch larger than N
# queues here instead of swamping the machine, whatever the caller asked
# placement for.  The wait comes before t0, so it never eats the load grace
# or the wall-clock cap.
SLOT_READY="$WDIR/emu-slot"
python3 "$ROOT/tools/tests/lib/emu_slot.py" --hold $$ "$SLOT_READY" &
slot_pid=$!
until [ -s "$SLOT_READY" ]; do
  kill -0 "$slot_pid" 2>/dev/null || { echo "emu_slot.py exited without a slot"; exit 2; }
  sleep 1
done
read -r slot_k slot_n slot_wait < "$SLOT_READY"
[ "$slot_wait" -gt 0 ] && echo "[emu-slot] waited ${slot_wait}s for slot $slot_k of $slot_n" >&2

RETRIES="${OT6_TIMEOUT_RETRIES:-1}"
attempt=0
retried=0
while :; do
  attempt=$(( attempt + 1 ))
  t0=$(date +%s)
  # The emulator runs in the background under a load-error watchdog: a
  # script that dies at LOAD (a nil table key at file scope, an undefined
  # name -- gen_fc_escape's summon table keyed by an EDGAR it never
  # declared, 2026-09-01) leaves Mesen running the game unscripted at 100%
  # CPU until the wall-clock cap, with nothing in this log but the
  # emulator's own [CPU] chatter; the script log that would name the error
  # is not read headless.  Every live script prints an [ot6] line within
  # its first seconds (the tiles record at frame 21 at the latest), so a
  # log with no [ot6] line after OT6_LOAD_GRACE seconds is that death:
  # kill it and say so as a FAIL, which is deterministic and never retried.
  run_mesen "$SHARED_APP$BIN_SUB/Mesen" --testrunner --timeout="$CAP" --enableStdout \
    "$ROM" "$COMPOSED" > "$RUN_LOG" 2>&1 &
  mesen_pid=$!
  load_grace="${OT6_LOAD_GRACE:-120}"
  load_dead=0
  # Polled every half second: the loop's sleep is the wall time a run spends
  # after Mesen has exited (it was 5 s, 2.5 s a run on average, #394).
  while kill -0 "$mesen_pid" 2>/dev/null; do
    sleep 0.5
    if [ "$load_dead" -eq 0 ] && [ $(( $(date +%s) - t0 )) -ge "$load_grace" ] \
       && ! grep -q '^\[ot6' "$RUN_LOG" 2>/dev/null; then
      load_dead=1
      kill "$mesen_pid" 2>/dev/null
      sleep 2
      kill -9 "$mesen_pid" 2>/dev/null
    fi
  done
  wait "$mesen_pid"
  code=$?
  if [ "$load_dead" -eq 1 ]; then
    printf '[ot6] FAIL: the script printed nothing in %ss -- a Lua LOAD error (a nil table key or an undefined name at file scope); the emulator ran the game unscripted and was killed.  Load the composed script with `luac -p` for syntax, then read its file-scope code: this is deterministic and is not retried.\n' \
      "$load_grace" >> "$RUN_LOG"
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

# core=: the MesenCore this run loaded, as Mesen unpacked it into the home.
CORE_SHA=unknown
for f in "$MESEN2/MesenCore.dylib" "$MESEN2/MesenCore.so"; do
  [ -f "$f" ] && CORE_SHA=$(shasum -a 256 "$f" | cut -c1-64)
done
printf '[emulator] %s MESEN_SCRIPT_ONLY requested=%s core=%s commit=%s\n' "${EMULATOR_SHA:-unknown}" "$MESEN_SCRIPT_ONLY" "$CORE_SHA" "${EMULATOR_COMMIT:-none}" >> "$RUN_LOG"

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
  # No verdict in the log: the emulator was killed rather than finishing.
  # If it lived roughly to the cap, the cap is what killed it; "exit 255,
  # truncated stdout" reads like a crash but is a kill.
  #
  # Usually contention rather than the test: the cap is wall clock and
  # `nice` does not slow it, so concurrent jobs starve each other.  "Lived
  # to the cap" allows 5s of slack for rounding, rather than a fixed 30s
  # margin, which goes negative and always fires under a small OT6_TIMEOUT.
  #
  # Written into $RUN_LOG with the [ot6] prefix so it reaches both readers:
  # the `grep '^\[ot6\]'` at the end of this script for a direct invocation,
  # and the published log for anything reading it after the fact.
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
    # Provenance sidecar: records what cut this battery -- the capturing
    # generator's provenance signature (savestate_stamp.sh), plus the hash
    # of everything the run booted from (each embedded savestate's stamp,
    # and the prior checkpoint's manifest when the run Continued from one).
    # The sidecar lands beside the payload; `sram_checkpoint.py seal` folds
    # it into manifest.json.  A capture that cannot state its provenance is
    # refused.
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
# OT6_NO_PUBLISH=1 runs a generator for its verdict only, leaving build/states
# untouched.
#
# A generating edge publishes only its own artifacts.  OT6_EXPECT_ARTIFACT is
# set by savestate_ninja.py's `generate` rule, naming the one state the
# invoking ninja edge is for.  A script that generates several states emits
# every sibling state on every invocation, and each sibling is its own ninja
# edge running this same script, so publishing the whole workspace would let
# one edge rewrite another edge's declared outputs with fresh mtimes.  The
# sibling copies this run just emitted are discarded rather than moved: the
# published copy is always the one whose own edge scheduled it.  Screenshots
# publish either way, since they are forensic output with no edge of their own.
# Each published .mss gets <state>.mss.emulator beside it: this run's
# [emulator] log line, verbatim, which savestate_stamp.sh write records in
# the stamp, so the log and the stamp name the same binary by construction.
publish_emulator() {
  case "$1" in *.mss)
    grep '^\[emulator\]' "$RUN_LOG" | tail -n 1 > "$1.emulator.tmp.$$" &&
      mv -f "$1.emulator.tmp.$$" "$1.emulator" ;;
  esac
}
if [ "$verdict" -eq 0 ] && [ -z "${OT6_NO_PUBLISH:-}" ]; then
  if [ -n "${OT6_EXPECT_ARTIFACT:-}" ]; then
    for src in $OT6_EXPECT_ARTIFACT; do
      pub="$PUBLISH/$src"   # before publish_file, which reuses $src
      publish_file "$ART/$src" "$pub"
      publish_emulator "$pub"
    done
  else
    for src in "$ART"/*; do
      [ -f "$src" ] || continue
      pub="$PUBLISH/$(basename "$src")"
      publish_file "$src" "$pub"
      publish_emulator "$pub"
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
