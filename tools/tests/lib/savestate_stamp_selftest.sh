#!/bin/sh
# savestate_stamp_selftest.sh: check the provenance signature in isolation,
# no emulator, on a mock tree (OT6_ROOT).
#
# Checks that the provenance sig reacts to content on every axis a
# generated savestate was produced from (generator, all three composed-in
# lib halves, declared extras) and never to a bare mtime bump; that the
# compatibility bindings (gensig, romsig) react to the generator/extras and
# the ROM but NOT to the lib halves; and that `write` records all of it.
set -u
GATE="$(cd "$(dirname "$0")" && pwd)/savestate_stamp.sh"
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
mkdir -p "$TMP/tools/tests/checkpoints/fake"
printf 'checkpoint v1\n' > "$TMP/tools/tests/checkpoints/fake/payload.srm"
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
export OT6_ROOT="$TMP"

base=$(sh "$GATE" sig gen_fake)
gbase=$(sh "$GATE" gensig gen_fake)
rbase=$(sh "$GATE" romsig)

# 1. mtime-only touches change nothing: a checkout or worktree cp must not
#    look like an edit on any axis.
for f in tools/tests/gen_fake.lua tools/tests/lib/ot6.lua \
         tools/tests/lib/ot6_field.lua tools/tests/lib/ot6_contract.lua \
         build/ot6.sfc; do
  touch "$TMP/$f"
done
check "mtime-only touch (all axes)" SAME "$base" "$(sh "$GATE" sig gen_fake)"
check "mtime-only touch: gensig" SAME "$gbase" "$(sh "$GATE" gensig gen_fake)"
check "mtime-only touch: romsig" SAME "$rbase" "$(sh "$GATE" romsig)"

# 2. each content axis moves the provenance signature, and restoring it
#    restores the signature (pure function of bytes).  The compatibility
#    bindings are narrower: gensig follows the generator only, romsig the
#    ROM only -- a lib-half edit moves neither (docs/TESTING.md: a change
#    to logging, assertions or controller policy does not by itself stale
#    a legitimately reached snapshot).
for f in tools/tests/gen_fake.lua tools/tests/lib/ot6.lua \
         tools/tests/lib/ot6_field.lua tools/tests/lib/ot6_contract.lua; do
  orig=$(cat "$TMP/$f")
  printf '%s EDITED\n' "$orig" > "$TMP/$f"
  check "content edit trips sig: $f" DIFF "$base" "$(sh "$GATE" sig gen_fake)"
  case "$f" in
    */gen_fake.lua)
      check "gen edit trips gensig" DIFF "$gbase" "$(sh "$GATE" gensig gen_fake)" ;;
    *)
      check "lib edit leaves gensig alone: $f" SAME "$gbase" "$(sh "$GATE" gensig gen_fake)" ;;
  esac
  check "harness edit leaves romsig alone: $f" SAME "$rbase" "$(sh "$GATE" romsig)"
  printf '%s\n' "$orig" > "$TMP/$f"
done
check "restored bytes restore the sig" SAME "$base" "$(sh "$GATE" sig gen_fake)"
printf 'rom v2\n' > "$TMP/build/ot6.sfc"
check "ROM content edit trips romsig" DIFF "$rbase" "$(sh "$GATE" romsig)"
check "ROM content edit leaves sig alone" SAME "$base" "$(sh "$GATE" sig gen_fake)"
check "ROM content edit leaves gensig alone" SAME "$gbase" "$(sh "$GATE" gensig gen_fake)"
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
check "restored ROM bytes restore romsig" SAME "$rbase" "$(sh "$GATE" romsig)"
OT6_ROM="$TMP/build/other.sfc" sh "$GATE" romsig >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass romsig of a missing ROM -> hard error" ||
  { echo "  FAIL romsig of a missing ROM returned a digest"; ok=0; }

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
extra=tools/tests/checkpoints/fake/payload.srm
with=$(sh "$GATE" sig gen_fake "$extra")
check "extra input joins the sig" DIFF "$base" "$with"
touch "$TMP/$extra"
check "extra mtime-only touch" SAME "$with" "$(sh "$GATE" sig gen_fake "$extra")"
printf 'checkpoint v2\n' > "$TMP/$extra"
check "extra content changed" DIFF "$with" "$(sh "$GATE" sig gen_fake "$extra")"
# extras are the checkpoint a segment boots from, so they are compatibility
# inputs as well: gensig follows them the same way.
printf 'checkpoint v1\n' > "$TMP/$extra"
gwith=$(sh "$GATE" gensig gen_fake "$extra")
check "extra input joins gensig" DIFF "$gbase" "$gwith"
printf 'checkpoint v2\n' > "$TMP/$extra"
check "extra content change trips gensig" DIFF "$gwith" "$(sh "$GATE" gensig gen_fake "$extra")"

# 5. unsafe or missing extras are hard errors, not silent omissions.
sh "$GATE" sig gen_fake tools/tests/checkpoints/fake/missing.srm >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass missing extra -> hard error" ||
  { echo "  FAIL missing extra accepted"; ok=0; }
sh "$GATE" sig gen_fake /etc/passwd >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "  pass absolute extra -> hard error" ||
  { echo "  FAIL absolute extra accepted"; ok=0; }

# 6. the GATE_CONTRACT version is a real input: the digest is not the bare
#    hash of the concatenated files, so bumping the constant moves every
#    signature.
bare=$(cat "$TMP/tools/tests/gen_fake.lua" "$TMP/tools/tests/lib/ot6.lua" \
           "$TMP/tools/tests/lib/ot6_field.lua" \
           "$TMP/tools/tests/lib/ot6_contract.lua" | shasum -a 256 | cut -c1-64)
check "GATE_CONTRACT version participates in the sig" DIFF \
  "${base%% *}" "$bare"

# 7. write records the signature, the compatibility bindings and the
#    provenance bindings: line 1 is byte-identical to `sig` (the side
#    compose.py re-derives), line 2 binds the ROM, line 3 the generator's own
#    sig, lines 4-6 name each lib half's hash, line 7 binds the artifact,
#    line 8 binds the ancestor.
printf 'generated state bytes v1\n' > "$TMP/build/states/fake.mss"
sh "$GATE" write fake gen_fake - "$extra"
[ "$(head -n 1 "$TMP/build/states/fake.stamp")" = "$(sh "$GATE" sig gen_fake "$extra")" ] &&
  echo "  pass write records the sig" ||
  { echo "  FAIL write/sig disagree"; ok=0; }
[ "$(sed -n 2p "$TMP/build/states/fake.stamp")" = "rom $(sh "$GATE" romsig)" ] &&
  echo "  pass write records the ROM identity (romsig)" ||
  { echo "  FAIL rom line wrong or missing"; ok=0; }
[ "$(sed -n 3p "$TMP/build/states/fake.stamp")" = "generator $(sh "$GATE" gensig gen_fake "$extra")" ] &&
  echo "  pass write records the generator's own sig (gensig)" ||
  { echo "  FAIL generator line wrong or missing"; ok=0; }
want_lib="lib tools/tests/lib/ot6.lua $(shasum -a 256 "$TMP/tools/tests/lib/ot6.lua" | cut -c1-64)
lib tools/tests/lib/ot6_field.lua $(shasum -a 256 "$TMP/tools/tests/lib/ot6_field.lua" | cut -c1-64)
lib tools/tests/lib/ot6_contract.lua $(shasum -a 256 "$TMP/tools/tests/lib/ot6_contract.lua" | cut -c1-64)"
[ "$(sed -n 4,6p "$TMP/build/states/fake.stamp")" = "$want_lib" ] &&
  echo "  pass write records each lib half's hash (provenance)" ||
  { echo "  FAIL lib lines wrong or missing"; ok=0; }
want_art="artifact $(shasum -a 256 "$TMP/build/states/fake.mss" | cut -c1-64)"
[ "$(sed -n 7p "$TMP/build/states/fake.stamp")" = "$want_art" ] &&
  echo "  pass write binds the generated artifact's hash" ||
  { echo "  FAIL artifact binding wrong or missing"; ok=0; }
[ "$(wc -l < "$TMP/build/states/fake.stamp" | tr -d ' ')" = 7 ] &&
  echo "  pass a root state (ancestor -) carries no ancestor line" ||
  { echo "  FAIL unexpected ancestor line on a root state"; ok=0; }
# The ROM line is the ROM that RAN: OT6_ROM (run.sh's override) is honored.
printf 'other rom\n' > "$TMP/build/other.sfc"
OT6_ROM="$TMP/build/other.sfc" sh "$GATE" write fake gen_fake - "$extra"
[ "$(sed -n 2p "$TMP/build/states/fake.stamp")" = "rom $(shasum -a 256 "$TMP/build/other.sfc" | cut -c1-64)" ] &&
  echo "  pass write records OT6_ROM when run.sh was pointed elsewhere" ||
  { echo "  FAIL OT6_ROM not honored by write"; ok=0; }
sh "$GATE" write fake gen_fake - "$extra"
# A write with no ROM to identify is a hard error, and leaves the old stamp.
kept=$(cat "$TMP/build/states/fake.stamp")
OT6_ROM="$TMP/build/nope.sfc" sh "$GATE" write fake gen_fake - "$extra" >/dev/null 2>&1
[ "$?" -ne 0 ] && [ "$(cat "$TMP/build/states/fake.stamp")" = "$kept" ] &&
  echo "  pass write without a ROM -> hard error, old stamp kept" ||
  { echo "  FAIL write without a ROM produced a stamp"; ok=0; }

# 8. a chained state binds its predecessor's stamp file, giving transitivity
#    on disk: child stamp -> parent stamp -> parent artifact, down to the root.
printf 'child state bytes v1\n' > "$TMP/build/states/child.mss"
sh "$GATE" write child gen_fake build/states/fake.stamp
want_anc="ancestor build/states/fake.stamp $(shasum -a 256 "$TMP/build/states/fake.stamp" | cut -c1-64)"
[ "$(sed -n 8p "$TMP/build/states/child.stamp")" = "$want_anc" ] &&
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

[ "$ok" -eq 1 ] && { echo "savestate_stamp selftest: ok"; exit 0; }
echo "savestate_stamp selftest: FAILED"; exit 1
