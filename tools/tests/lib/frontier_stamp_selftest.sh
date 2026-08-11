#!/bin/sh
# frontier_stamp_selftest.sh -- prove the provenance signature in isolation,
# no emulator, on a mock tree (OT6_ROOT).
#
# The signature is compared on two sides -- the ninja `mint` edge `write`s it,
# lib/compose.py re-derives it at embed time to catch a drifted
# worktree-seeded fixture -- so what matters is that it reacts to CONTENT on
# every axis a generated savestate depends on (generator, all three composed-in
# lib halves, declared extras) and NEVER to a bare mtime bump.  The old
# `needsmint` generate-or-skip DECISION this file also used to pin now belongs
# to ninja; its axes are proven end-to-end against real ninja
# in frontier_ninja_selftest.sh, which is this file's other half.
set -u
GATE="$(cd "$(dirname "$0")" && pwd)/frontier_stamp.sh"
ok=1
check() { # <label> <expected: SAME|DIFF> <sig-a> <sig-b>
  got=DIFF; [ "$3" = "$4" ] && got=SAME
  if [ "$got" = "$2" ]; then echo "  pass $1 -> $got"
  else echo "  FAIL $1: got $got want $2"; ok=0; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tools/tests/lib" "$TMP/build/states"
printf 'gen body v1\n'      > "$TMP/tools/tests/gen_fake.lua"
printf 'lib body v1\n'      > "$TMP/tools/tests/lib/ot6.lua"
printf 'field body v1\n'    > "$TMP/tools/tests/lib/ot6_field.lua"
printf 'contract body v1\n' > "$TMP/tools/tests/lib/ot6_contract.lua"
mkdir -p "$TMP/tools/tests/anchors/fake"
printf 'anchor v1\n' > "$TMP/tools/tests/anchors/fake/payload.srm"
export OT6_ROOT="$TMP"

base=$(sh "$GATE" sig gen_fake)

# 1. mtime-only touches change NOTHING: a checkout or worktree cp must not
#    look like an edit on any axis.
for f in tools/tests/gen_fake.lua tools/tests/lib/ot6.lua \
         tools/tests/lib/ot6_field.lua tools/tests/lib/ot6_contract.lua; do
  touch "$TMP/$f"
done
check "mtime-only touch (all axes)" SAME "$base" "$(sh "$GATE" sig gen_fake)"

# 2. each content axis moves the signature, and restoring it restores the
#    signature (pure function of bytes).
for f in tools/tests/gen_fake.lua tools/tests/lib/ot6.lua \
         tools/tests/lib/ot6_field.lua tools/tests/lib/ot6_contract.lua; do
  orig=$(cat "$TMP/$f")
  printf '%s EDITED\n' "$orig" > "$TMP/$f"
  check "content edit trips: $f" DIFF "$base" "$(sh "$GATE" sig gen_fake)"
  printf '%s\n' "$orig" > "$TMP/$f"
done
check "restored bytes restore the sig" SAME "$base" "$(sh "$GATE" sig gen_fake)"

# 3. per-generator granularity: two generators over the same libs have
#    different signatures, and editing one moves only its own.
printf 'other gen g\n' > "$TMP/tools/tests/gen_other.lua"
other=$(sh "$GATE" sig gen_other)
check "distinct generators differ" DIFF "$base" "$other"
printf 'gen body v2\n' > "$TMP/tools/tests/gen_fake.lua"
check "per-gen: edited gen trips"    DIFF "$base"  "$(sh "$GATE" sig gen_fake)"
check "per-gen: sibling unaffected"  SAME "$other" "$(sh "$GATE" sig gen_other)"
printf 'gen body v1\n' > "$TMP/tools/tests/gen_fake.lua"

# 4. declared extras extend the same signature (SRAM checkpoints: manifest +
#    payload); content-not-mtime rule holds for them too.
extra=tools/tests/anchors/fake/payload.srm
with=$(sh "$GATE" sig gen_fake "$extra")
check "extra input joins the sig" DIFF "$base" "$with"
touch "$TMP/$extra"
check "extra mtime-only touch" SAME "$with" "$(sh "$GATE" sig gen_fake "$extra")"
printf 'anchor v2\n' > "$TMP/$extra"
check "extra content changed" DIFF "$with" "$(sh "$GATE" sig gen_fake "$extra")"

# 5. unsafe or missing extras are hard errors, not silent omissions.
sh "$GATE" sig gen_fake tools/tests/anchors/fake/missing.srm >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass missing extra -> hard error" ||
  { echo "  FAIL missing extra accepted"; ok=0; }
sh "$GATE" sig gen_fake /etc/passwd >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass absolute extra -> hard error" ||
  { echo "  FAIL absolute extra accepted"; ok=0; }

# 6. the GATE_CONTRACT version is a real input: the digest is NOT the bare
#    hash of the concatenated files, so bumping the constant moves every
#    signature (issue #75 step 5 -- the deliberate invalidate-the-world knob).
bare=$(cat "$TMP/tools/tests/gen_fake.lua" "$TMP/tools/tests/lib/ot6.lua" \
           "$TMP/tools/tests/lib/ot6_field.lua" \
           "$TMP/tools/tests/lib/ot6_contract.lua" | shasum -a 256 | cut -c1-64)
check "GATE_CONTRACT version participates in the sig" DIFF \
  "${base%% *}" "$bare"

# 7. write records the signature AND the provenance bindings (issue #75
#    step 5): line 1 is byte-identical to `sig` (the side compose.py
#    re-derives), line 2 binds the artifact, line 3 binds the ancestor.
printf 'minted state bytes v1\n' > "$TMP/build/states/fake.mss"
sh "$GATE" write fake gen_fake - "$extra"
[ "$(head -n 1 "$TMP/build/states/fake.stamp")" = "$(sh "$GATE" sig gen_fake "$extra")" ] &&
  echo "  pass write records the sig" ||
  { echo "  FAIL write/sig disagree"; ok=0; }
want_art="artifact $(shasum -a 256 "$TMP/build/states/fake.mss" | cut -c1-64)"
[ "$(sed -n 2p "$TMP/build/states/fake.stamp")" = "$want_art" ] &&
  echo "  pass write binds the generated artifact's hash" ||
  { echo "  FAIL artifact binding wrong or missing"; ok=0; }
[ "$(wc -l < "$TMP/build/states/fake.stamp" | tr -d ' ')" = 2 ] &&
  echo "  pass a root state (ancestor -) carries no ancestor line" ||
  { echo "  FAIL unexpected ancestor line on a root state"; ok=0; }

# 8. a chained state binds its predecessor's STAMP FILE -- transitivity on
#    disk: child stamp -> parent stamp -> parent artifact, down to the root.
printf 'child state bytes v1\n' > "$TMP/build/states/child.mss"
sh "$GATE" write child gen_fake build/states/fake.stamp
want_anc="ancestor build/states/fake.stamp $(shasum -a 256 "$TMP/build/states/fake.stamp" | cut -c1-64)"
[ "$(sed -n 3p "$TMP/build/states/child.stamp")" = "$want_anc" ] &&
  echo "  pass chained write binds the ancestor stamp's hash" ||
  { echo "  FAIL ancestor binding wrong or missing"; ok=0; }

# 9. refusals: a write may never produce a stamp it cannot back.
sh "$GATE" write ghost gen_fake - >/dev/null 2>&1
[ "$?" -ne 0 ] && [ ! -f "$TMP/build/states/ghost.stamp" ] &&
  echo "  pass write without a generated .mss -> hard error, no stamp" ||
  { echo "  FAIL write accepted a missing artifact"; ok=0; }
sh "$GATE" write child gen_fake build/states/nope.stamp >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass missing ancestor -> hard error" ||
  { echo "  FAIL missing ancestor accepted"; ok=0; }
sh "$GATE" write child gen_fake /etc/passwd >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass absolute ancestor -> hard error" ||
  { echo "  FAIL absolute ancestor accepted"; ok=0; }
sh "$GATE" write child gen_fake >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass ancestor-less write form -> hard error" ||
  { echo "  FAIL old 3-arg write form accepted"; ok=0; }

[ "$ok" -eq 1 ] && { echo "frontier_stamp selftest: ok"; exit 0; }
echo "frontier_stamp selftest: FAILED"; exit 1
