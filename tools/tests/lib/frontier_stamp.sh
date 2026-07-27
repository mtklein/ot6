#!/bin/sh
# frontier_stamp.sh -- the ONE definition of a minted fixture's provenance
# signature.
#
# HISTORY: this script used to also DECIDE mint-or-skip (`needsmint`), and the
# Makefile's mint macro would `touch` the target afterwards to stop make
# re-deciding by mtime -- a content gate beside an mtime scheduler, two
# mechanisms that could disagree (and on 2026-07-27 did: a resumed run
# printed "rom content changed", then booted an old-ROM savestate against the
# new ROM).  Scheduling now belongs entirely to the generated ninja graph
# (tools/tests/lib/frontier_ninja.py): every input is a declared dependency
# and content-staleness is ninja's own restat mechanism, so `needsmint` is
# gone with the macros that called it.
#
# What remains is the signature itself, because it is compared on two sides
# and both must agree byte-for-byte:
#   * the mint edge `write`s build/states/<state>.stamp after a successful
#     mint (see the mint rule in build/build.ninja);
#   * lib/compose.py re-derives it at embed time (via `sig`, shelled to this
#     script so there is exactly one implementation) and refuses -- loudly,
#     through the [ot6] channel -- a fixture that reached a test WITHOUT
#     passing any mint gate: a worktree-setup seed that a local generator or
#     lib edit has since drifted.  That consume-time guard is why the stamp
#     still exists at all.
#
#   frontier_stamp.sh write <state> <generator> [extra ...]
#   frontier_stamp.sh sig   <generator> [extra ...]
#
# The signature hashes the generator and ALL THREE lib halves compose.py
# inlines into every composed script -- lib/ot6.lua, lib/ot6_field.lua and
# lib/ot6_contract.lua, in inline order -- plus any declared extra inputs
# (battery anchors hash manifest then payloads).  The contract half joined
# the digest with the ninja graph (issue #25): an invariant-contract edit
# re-mints every leg, and the consume-time check has to agree that a
# pre-edit fixture is stale.  Content-keyed throughout: a mere mtime bump
# (a `git checkout`, a worktree cp) changes no signature.
set -u

# OT6_ROOT lets selftests and compose.py point the sig at another tree; the
# default is the real tree this script lives in (lib/ -> tests/ -> tools/ ->
# root).
ROOT="${OT6_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
STATES="$ROOT/build/states"

# sha256(<generator source> ++ <battle core> ++ <nav half> ++ <contract
# half>) plus the generator's name and the extras' paths.  Order is FIXED --
# the same order compose.py inlines them -- so the digest is reproducible
# from either side.
sig() {
  gen="$1"
  shift
  files="$ROOT/tools/tests/$gen.lua
$ROOT/tools/tests/lib/ot6.lua
$ROOT/tools/tests/lib/ot6_field.lua
$ROOT/tools/tests/lib/ot6_contract.lua"
  # Every fixed input must exist BEFORE hashing: the digest pipeline's `cat`
  # cannot fail it (a pipeline swallows the status), so a typo'd generator
  # would otherwise hash the remaining files and call that a signature.
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] ||
      { echo "frontier_stamp: missing input '$f'" >&2; exit 2; }
  done || exit 2
  extras=""
  for extra in "$@"; do
    case "$extra" in /*|*..*) echo "frontier_stamp: unsafe extra '$extra'" >&2; exit 2 ;; esac
    [ -f "$ROOT/$extra" ] ||
      { echo "frontier_stamp: missing extra '$ROOT/$extra'" >&2; exit 2; }
    files="$files
$ROOT/$extra"
    extras="$extras $extra"
  done
  digest=$(
    printf '%s\n' "$files" | while IFS= read -r file; do cat "$file"; done |
      shasum -a 256 | cut -c1-64
  )
  printf '%s %s%s' "$digest" "$gen" "$extras"
}

cmd="${1:?usage: frontier_stamp.sh write|sig ...}"
case "$cmd" in
  sig)
    gen="${2:?sig needs a generator}"; shift 2
    sig "$gen" "$@"
    ;;
  write)
    state="${2:?write needs a state}"; gen="${3:?write needs a generator}"
    shift 3
    sig "$gen" "$@" > "$STATES/$state.stamp"
    ;;
  *)
    echo "frontier_stamp.sh: unknown command '$cmd'" >&2
    exit 2
    ;;
esac
