#!/bin/sh
# Positive control for suite.sh's bookkeeping: the tally line, and the
# discovered-vs-reported cross-check that guards it.
#
# WHY A SELFTEST AND NOT "just read the suite output": the tally is the thing
# people will quote instead of counting, so it has to be right when nobody is
# checking -- and the interesting cases (a FAIL, an xfail, a worker that never
# reports) are exactly the ones a green suite run never exercises.  Proving
# them against the real suite would mean deliberately breaking a test and
# burning an emulator run per case.
#
# So this builds a MINIATURE tree -- $TMP/tools/tests/{suite.sh,run.sh,*.lua}
# -- and lets suite.sh discover and "run" it.  suite.sh derives ROOT from its
# own path (`dirname $0/../..`), so a copy placed there is rooted in the fake
# tree and never touches the real one.  The stub run.sh exits with whatever
# code the test's filename asks for, so every verdict branch is reachable in
# milliseconds with no Mesen anywhere in the picture.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ot6-tally-selftest.XXXXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/tools/tests" "$TMP/build/states"
cp "$ROOT/tools/tests/suite.sh" "$TMP/tools/tests/suite.sh"
chmod +x "$TMP/tools/tests/suite.sh"
# The OT6_JOBS>1 path composes each test up front, and suite.sh now opens with
# a fixture-freshness check, so the fake tree needs a lib/.  COPIED, not
# symlinked: compose.py finds its tree root with Path(__file__).resolve(),
# which follows a symlink straight back to the real checkout -- a symlinked
# lib would have this selftest reporting on the REAL tree's fixtures.
cp -R "$ROOT/tools/tests/lib" "$TMP/tools/tests/lib"

# Stub runner: `pass_*` exits 0, `fail_*` exits 1.  It also writes the log
# file suite.sh names, because the parallel path copies it unconditionally.
cat > "$TMP/tools/tests/run.sh" <<'STUB'
#!/bin/sh
: > "$2"
case "$(basename "$1")" in fail_*) exit 1 ;; *) exit 0 ;; esac
STUB
chmod +x "$TMP/tools/tests/run.sh"

mk() {  # mk <name> [savestate-fixture]
  if [ -n "${2:-}" ]; then
    echo "-- @suite savestate=$2" > "$TMP/tools/tests/$1.lua"
  else
    echo "-- @suite" > "$TMP/tools/tests/$1.lua"
  fi
}

ok=0
check() {  # check <label> <got> <want>
  if [ "$2" = "$3" ]; then
    echo "  pass $1"
  else
    echo "  FAIL $1"; echo "       got  $2"; echo "       want $3"; ok=1
  fi
}
tally() { sed -n 's/^OT6 suite: [A-Z][A-Z]* -- //p' "$1"; }

# ---- 1. all green, plus a test whose generated fixture is absent --------
mk pass_a; mk pass_b; mk pass_c
mk pass_gated deep_fixture           # no build/states/deep_fixture.mss -> skip
for j in 1 3; do
  OT6_JOBS=$j "$TMP/tools/tests/suite.sh" > "$TMP/out.$j" 2>&1
  rc=$?
  check "OT6_JOBS=$j green exits 0" "$rc" "0"
  check "OT6_JOBS=$j green tally" "$(tally "$TMP/out.$j")" \
    "3 ran: 3 pass, 0 fail; 1 skipped (need \`make savestates\`)"
done
# The verdict is on the line, not just in the exit status: an agent reading a
# scrolled terminal sees which one it was without scrolling back.
check "green run says GREEN" \
  "$(grep -c '^OT6 suite: GREEN' "$TMP/out.3")" "1"

# ---- 1b. fixture freshness is stated up front, not left in a per-test log --
# An unstamped tree says so and stays quiet; a tree holding a fixture whose
# recorded signature does not match its sources says THAT, before any test
# runs.  The stale case is built by hand: a stamp naming a real generator,
# carrying a signature that is simply not the one those bytes hash to.
check "an unstamped tree says so and does not cry stale" \
  "$(grep -c 'no generated fixtures in this tree' "$TMP/out.3")" "1"
echo '-- a generator' > "$TMP/tools/tests/gen_fake.lua"
echo "0000000000000000000000000000000000000000000000000000000000000000 gen_fake" \
  > "$TMP/build/states/fake_leg.stamp"
OT6_JOBS=3 "$TMP/tools/tests/suite.sh" > "$TMP/out.stale" 2>&1
check "a stale fixture is named before the first test runs" \
  "$(grep -c 'fixture fake_leg is STALE' "$TMP/out.stale")" "1"
check "...above the per-test list, where it will actually be read" \
  "$(awk '/fixture fake_leg is STALE/{s=NR} /^OT6 suite:/{if(!p){p=NR}}
          END{print !s ? "no stale line at all" : \
                     !p ? "no suite output at all" : \
                     (s<p) ? "before" : "after"}' "$TMP/out.stale")" "before"
check "...and does NOT by itself fail the suite" \
  "$(tally "$TMP/out.stale")" \
  "3 ran: 3 pass, 0 fail; 1 skipped (need \`make savestates\`)"
rm "$TMP/build/states/fake_leg.stamp" "$TMP/tools/tests/gen_fake.lua"

# ---- 1c. a compose failure must print WHY.  suite.sh used to send compose's
#          stdout to /dev/null and report a bare "compose failed: <test>",
#          which is the whole diagnosis thrown away one line before it is
#          printed.  An absolute sidecar literal is a compose error with a
#          long, specific message; assert the message survives.
printf -- '-- @suite\nlocal S = "/elsewhere/build/states/x.mss.lua"\n' \
  > "$TMP/tools/tests/pass_badref.lua"
OT6_JOBS=3 "$TMP/tools/tests/suite.sh" > "$TMP/out.compose" 2>&1
rc=$?
check "a compose failure exits nonzero" "$rc" "1"
check "...names the test" "$(grep -c 'compose failed: pass_badref' "$TMP/out.compose")" "1"
check "...and keeps compose's own explanation" \
  "$(grep -c 'absolute sidecar reference' "$TMP/out.compose")" "1"
rm "$TMP/tools/tests/pass_badref.lua"

# ---- 2. a skipped test joins the count once its fixture exists ----------
: > "$TMP/build/states/deep_fixture.mss"
OT6_JOBS=3 "$TMP/tools/tests/suite.sh" > "$TMP/out.gated" 2>&1
check "a generated fixture moves its test from skipped into the total" \
  "$(tally "$TMP/out.gated")" "4 ran: 4 pass, 0 fail"
rm "$TMP/build/states/deep_fixture.mss"

# ---- 3. one failure ------------------------------------------------------
mk fail_x
OT6_JOBS=3 "$TMP/tools/tests/suite.sh" > "$TMP/out.red" 2>&1
rc=$?
check "a failure exits nonzero" "$rc" "1"
check "a failure is counted and the verdict flips to RED" \
  "$(tally "$TMP/out.red")" \
  "4 ran: 3 pass, 1 fail; 1 skipped (need \`make savestates\`)"
check "red run says RED" "$(grep -c '^OT6 suite: RED' "$TMP/out.red")" "1"

# ---- 4. the tally agrees with the per-test list it summarises -------------
# The number is only worth quoting if it counts the same events the list
# shows.  Recount them out of the list and compare.
listed_pass=$(grep -c ': pass' "$TMP/out.red")
listed_fail=$(grep -c ': FAIL' "$TMP/out.red")
check "tally's pass count matches the per-test lines" "$listed_pass" "3"
check "tally's fail count matches the per-test lines" "$listed_fail" "1"

# ---- 5. A worker that dies mid-test still costs its claimed test a result
#         file.  suite.sh calls that "worker never reported"; it must land in
#         the tally as a failure, not vanish from the denominator.  The stub
#         kills its PARENT -- the worker subshell -- after the claim is taken
#         and before the result is written, which is the real shape of this.
cat > "$TMP/tools/tests/run.sh" <<'STUB'
#!/bin/sh
: > "$2"
case "$(basename "$1")" in
  vanish_*) kill -9 "$PPID"; sleep 5 ;;
  fail_*)   exit 1 ;;
  *)        exit 0 ;;
esac
STUB
chmod +x "$TMP/tools/tests/run.sh"
rm "$TMP/tools/tests/fail_x.lua"
mk vanish_z
OT6_JOBS=4 "$TMP/tools/tests/suite.sh" > "$TMP/out.vanish" 2>&1
rc=$?
check "a worker that never reports exits nonzero" "$rc" "1"
check "...and is counted, so the total still covers every discovered test" \
  "$(tally "$TMP/out.vanish")" \
  "4 ran: 3 pass, 1 fail; 1 skipped (need \`make savestates\`)"
check "...via the 'worker never reported' line, not a plain FAIL" \
  "$(grep -c 'worker never reported' "$TMP/out.vanish")" "1"

# ---- 6. NON-VACUITY for the cross-check itself.  Every case above keeps
#         ran == discovered, so nothing has yet watched the BUG branch fire.
#         Force the mismatch: take the SAME vanishing worker, but neuter the
#         "worker never reported" accounting so the test really does fall out
#         of the total.  If the cross-check is doing nothing, this run reports
#         "3 ran" and exits 0 -- a green suite that quietly skipped a test,
#         which is the failure mode the line exists to make impossible.
sed 's/n_fail=$((n_fail + 1)); fail=1$/:/' \
  "$ROOT/tools/tests/suite.sh" > "$TMP/tools/tests/suite.sh"
chmod +x "$TMP/tools/tests/suite.sh"
OT6_JOBS=4 "$TMP/tools/tests/suite.sh" > "$TMP/out.bug" 2>&1
rc=$?
check "an unaccounted-for test is reported as a BUG, not swallowed" \
  "$(grep -c 'BUG: 4 tests were discovered but 3 reported' "$TMP/out.bug")" "1"
check "...and fails the suite" "$rc" "1"

if [ "$ok" -eq 0 ]; then
  echo "suite tally selftest: ok"
else
  echo "suite tally selftest: FAILED"
fi
exit $ok
