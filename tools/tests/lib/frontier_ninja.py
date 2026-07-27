#!/usr/bin/env python3
"""frontier_ninja.py -- emit the frontier graph (tools/tests/frontier_graph.py)
as build/build.ninja.

Replaces the Makefile's mint/mint_anchor/stackseed macros, the FRONTIER
lists, the ~104 hand-written rules, and the frontier_deps.sh grep-include
(issue #25).  Why ninja and not make, in one sentence each -- these are the
four failure modes the old shape kept producing, and the mechanism here that
kills each one:

 * "content stamp beside a touch": make decides staleness by mtime, so the
   content gate (frontier_stamp.sh needsmint) had to `touch` the target to
   stop make re-deciding -- two mechanisms that could disagree, and did
   (2026-07-27: a resumed run printed "rom content changed" then booted an
   old-ROM savestate against the new ROM).  Here the DECISION and the
   EXECUTION are one mechanism: every mint declares its real inputs, and the
   only "is the content the same?" question is answered by `restat` latch
   edges (below), inside ninja's own scheduler.
 * "make never reconsiders": a target with no newer prerequisite is skipped
   without its recipe running, so frontier_deps.sh existed only to graft
   generator/lib prerequisites back on.  Ninja edges list every input
   directly, emitted from the same data entry that defines the leg -- there
   is no second list to rot.
 * "silent .PHONY no-op": GNU make does not apply implicit pattern rules to
   .PHONY targets, so `smoke-%: rom` matched nothing and reported success in
   0.036s.  Ninja has no implicit rules: every target is an explicit edge,
   an unknown target is a hard error, and a dirty edge either runs its
   command or fails.
 * "the graph in three places": macros + rules + a generated include.  The
   graph is now ONE data list; this script is mechanical.

The content-staleness idiom (`restat`): git checkouts and rebuilds bump
mtimes without changing bytes, and a savestate mint costs minutes to hours,
so mtime alone must never schedule one.  Every SOURCE input to a mint -- the
ROM, the generator .lua, the three composed-in lib halves, anchor manifests
and payloads -- is therefore routed through a latch edge:

    build build/ninja/src/<path>: latch <path>      (cmp -s || cp; restat=1)

The latch re-runs on any mtime bump (cheap: one cmp), rewrites its output
ONLY when bytes differ, and `restat = 1` tells ninja to re-stat the output
and prune everything downstream when it did not move.  A touched-but-equal
file re-mints nothing; a changed ROM re-runs every transitive dependent,
because the mints' staleness IS their position in this graph.  Minted
states themselves are not latched: a re-minted .mss is genuinely new bytes
and everything booted from it must replay.

What deliberately does NOT participate in staleness (same as the stamp gate
this replaces): the harness itself (run.sh, compose.py, decode_b64.py,
pin_test_saves.py, sram_anchor.py) and ff6-en.dbg.  A harness edit has never
invalidated a minted state; widening that would re-mint the world on every
tooling tweak.

frontier_stamp.sh survives with a narrower job: each mint edge still
`write`s build/states/<state>.stamp after success, because lib/compose.py
re-derives that signature at embed time to catch a fixture that reached a
test WITHOUT passing any mint gate (a worktree-seeded state a local edit has
since drifted).  The stamp is provenance for that consume-time check -- it
no longer schedules anything.

Usage:
    python3 tools/tests/lib/frontier_ninja.py             # (re)write build/build.ninja
    python3 tools/tests/lib/frontier_ninja.py --list      # state names, play order
    python3 tools/tests/lib/frontier_ninja.py --selftest  # validation negatives

The write is compare-and-conditionally-write, so an unchanged graph leaves
build/build.ninja's mtime alone; build.ninja also regenerates itself via a
`generator = 1` edge when this script or the graph data changes, so bare
`ninja -f build/build.ninja` stays honest without the make wrapper.
Emitted paths are RELATIVE to the repo root: run ninja from the root (the
make wrappers do), or a mint's run.sh invocation will not resolve.
"""

import argparse
import re
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # tools/tests/lib
ROOT = HERE.parent.parent.parent                # lib -> tests -> tools -> root

SELF = "tools/tests/lib/frontier_ninja.py"
GRAPH = "tools/tests/frontier_graph.py"
OUT = "build/build.ninja"
ROM = "build/ot6.sfc"
LATCH_DIR = "build/ninja/src"
# The three lib halves compose.py inlines into EVERY composed generator, in
# inline order.  ot6_contract.lua is the invariant-contract half: an edit to
# a contract must re-run every leg that asserts it (issue #25), which the old
# stamp signature never covered.
LIB_HALVES = (
    "tools/tests/lib/ot6.lua",
    "tools/tests/lib/ot6_field.lua",
    "tools/tests/lib/ot6_contract.lua",
)

NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
STACK_RE = re.compile(r"^[A-Za-z0-9]+_$")
FIELDS = {"state", "gen", "prev", "anchor", "seed", "stack", "after"}


def anchor_inputs(root, key):
    """manifest first, then sorted payloads -- the exact order the Makefile's
    anchor_inputs always hashed, so no anchored mint signature changes."""
    adir = f"tools/tests/anchors/{key}"
    payloads = sorted(p.name for p in (root / adir).glob("*.sram"))
    return [f"{adir}/manifest.json"] + [f"{adir}/{p}" for p in payloads]


def validate(states, root):
    """Every error is fatal and named; a malformed entry must never emit as
    some other kind of edge (the quiet-no-op class this design exists to
    kill)."""
    errors = []
    seen = set()

    def err(entry, msg):
        errors.append(f"{entry.get('state', '<unnamed>')}: {msg}")

    for e in states:
        unknown = set(e) - FIELDS
        if unknown:
            err(e, f"unknown field(s) {sorted(unknown)}")
            continue
        s = e.get("state")
        if not (isinstance(s, str) and NAME_RE.match(s)):
            err(e, f"bad state name {s!r}")
            continue
        if s in seen:
            err(e, "duplicate state")
            continue
        gen, seed = e.get("gen"), e.get("seed")
        prev, anchor, after = e.get("prev"), e.get("anchor"), e.get("after")
        if bool(gen) == bool(seed):
            err(e, "exactly one of gen= or seed= is required")
        if seed:
            for k in ("prev", "anchor", "stack", "after"):
                if e.get(k):
                    err(e, f"seed= excludes {k}=")
            if seed not in seen:
                err(e, f"seed source {seed!r} is not an earlier state")
        if gen and not (root / "tools/tests" / f"{gen}.lua").is_file():
            err(e, f"no such generator tools/tests/{gen}.lua")
        if sum(map(bool, (prev, anchor, after))) > 1:
            err(e, "prev=, anchor= and after= are mutually exclusive")
        if prev and prev not in seen:
            err(e, f"prev {prev!r} is not an earlier state")
        if after and after not in seen:
            err(e, f"after {after!r} is not an earlier state")
        if anchor:
            # Dirs named negative-* are deliberately-wrong fixtures for
            # `make anchor-negatives`; no mint may ever name one.
            if anchor.startswith("negative"):
                err(e, f"anchor {anchor!r} is a negative fixture")
            elif not (root / "tools/tests/anchors" / anchor /
                      "manifest.json").is_file():
                err(e, f"anchor {anchor!r} has no manifest.json")
            elif not anchor_inputs(root, anchor)[1:]:
                err(e, f"anchor {anchor!r} has no *.sram payload")
        stack = e.get("stack")
        if stack and not STACK_RE.match(stack):
            err(e, f"stack prefix {stack!r} must end in '_'")
        if stack and not gen:
            err(e, "stack= requires gen=")
        seen.add(s)
    return errors


def latch(rel):
    return f"{LATCH_DIR}/{rel}"


def emit(states, root):
    """The build.ninja text.  Paths are relative to the repo root."""
    o = []
    w = o.append
    w(f"# AUTOGENERATED by {SELF} from {GRAPH} -- do not edit.")
    w("# `make frontier` / `make test` regenerate it; so does the generator")
    w("# edge below on a bare ninja run.  Invoke from the repo root:")
    w(f"#     ninja -f {OUT} <state|frontier>")
    w("ninja_required_version = 1.3")
    w("builddir = build/ninja")
    w("")
    w("rule regen")
    w(f"  command = python3 {SELF}")
    w("  description = regen $out")
    w("  generator = 1")
    w("  restat = 1")
    w("")
    w("# Content latch: re-runs on any mtime bump, rewrites only on a byte")
    w("# change; restat = 1 prunes everything downstream when it did not.")
    w("rule latch")
    w("  command = mkdir -p $$(dirname $out) && { cmp -s $in $out || cp $in $out; }")
    w("  description = latch $in")
    w("  restat = 1")
    w("")
    w("# One mint: run.sh composes the generator with the lib halves, boots")
    w("# Mesen, and publishes $state.mss + $state.mss.lua atomically into")
    w("# build/states -- OT6_EXPECT_ARTIFACT makes a run that passes without")
    w("# emitting BOTH a hard failure.  The stamp write is provenance for")
    w("# compose.py's consume-time drift check, not scheduling.")
    w("# NB: $env and $extras are optional per-edge splices; ninja strips a")
    w("# value's leading whitespace, so the separating spaces live HERE in")
    w("# the template (an empty splice leaves a harmless double space).")
    w("rule mint")
    w("  command = OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$state.mss "
      "$state.mss.lua' $env tools/tests/run.sh tools/tests/$gen.lua && "
      "sh tools/tests/lib/frontier_stamp.sh write $state $gen $extras")
    w("  description = mint $state <- $gen")
    w("")
    w("# A stacked chain's boot is a finished chain's ending: a pure copy of")
    w("# both halves.  No generator, no emulator, no stamp (compose.py's")
    w("# drift check correctly has nothing to say about a copy).")
    w("rule seed")
    w("  command = cp build/states/$src.mss build/states/$state.mss && "
      "cp build/states/$src.mss.lua build/states/$state.mss.lua")
    w("  description = stack seed $state <- $src")
    w("")
    w(f"build {OUT}: regen {SELF} {GRAPH}")
    w("")

    latched = [ROM] + list(LIB_HALVES)
    for e in states:
        if e.get("gen"):
            g = f"tools/tests/{e['gen']}.lua"
            if g not in latched:
                latched.append(g)
        if e.get("anchor"):
            for a in anchor_inputs(root, e["anchor"]):
                if a not in latched:
                    latched.append(a)
    for src in latched:
        w(f"build {latch(src)}: latch {src}")
    w("")

    for e in states:
        s = e["state"]
        outs = (f"build/states/{s}.mss.lua build/states/{s}.mss")
        if e.get("seed"):
            src = e["seed"]
            w(f"build {outs}: seed build/states/{src}.mss.lua "
              f"build/states/{src}.mss")
            w(f"  state = {s}")
            w(f"  src = {src}")
            continue
        gen = e["gen"]
        deps = [latch(ROM), latch(f"tools/tests/{gen}.lua")]
        deps += [latch(h) for h in LIB_HALVES]
        env = []
        extras = ""
        explicit = ""
        order = ""
        if e.get("prev"):
            p = e["prev"]
            explicit = f" build/states/{p}.mss.lua build/states/{p}.mss"
        if e.get("anchor"):
            key = e["anchor"]
            ins = anchor_inputs(root, key)
            deps += [latch(a) for a in ins]
            env.append(f"OT6_SRAM_ANCHOR=tools/tests/anchors/{key}")
            extras = " ".join(ins)
        if e.get("stack"):
            env.append(f"OT6_STACK={e['stack']}")
        if e.get("after"):
            order = f" || build/states/{e['after']}.mss.lua"
        w(f"build {outs} build/states/{s}.stamp: mint{explicit} | "
          f"{' '.join(deps)}{order}")
        w(f"  state = {s}")
        w(f"  gen = {gen}")
        if env:
            w(f"  env = {' '.join(env)}")
        if extras:
            w(f"  extras = {extras}")
    w("")
    for e in states:
        s = e["state"]
        w(f"build {s}: phony build/states/{s}.mss.lua")
    sidecars = " ".join(f"build/states/{e['state']}.mss.lua" for e in states)
    w(f"build frontier: phony {sidecars}")
    w("default frontier")
    w("")
    return "\n".join(o)


def load(root):
    ns = runpy.run_path(str(root / GRAPH))
    return ns["STATES"]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT,
                    help="tree to read the graph from and write into "
                         "(the selftest harness points this at a mock tree)")
    ap.add_argument("--list", action="store_true",
                    help="print state names in play order and exit")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    root = args.root.resolve()
    states = load(root)
    errors = validate(states, root)
    if errors:
        for e in errors:
            print(f"frontier_graph: {e}", file=sys.stderr)
        return 1
    if args.list:
        for e in states:
            print(e["state"])
        return 0
    text = emit(states, root)
    out = root / OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and out.read_text() == text:
        return 0
    out.write_text(text)
    print(f"wrote {out} ({len(states)} states)")
    return 0


def selftest():
    """Validation negatives: every malformed-entry class is a refusal, never
    a differently-shaped edge.  Pure python; the ninja-semantics proofs live
    in frontier_ninja_selftest.sh."""
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "tools/tests/anchors/good-v1").mkdir(parents=True)
        (root / "tools/tests/anchors/good-v1/manifest.json").write_text("{}")
        (root / "tools/tests/anchors/good-v1/a.sram").write_text("x")
        (root / "tools/tests/anchors/empty-v1").mkdir(parents=True)
        (root / "tools/tests/anchors/empty-v1/manifest.json").write_text("{}")
        (root / "tools/tests/gen_ok.lua").write_text("-- ok")

        def s(**kw):
            e = {"state": None, "gen": None, "prev": None, "anchor": None,
                 "seed": None, "stack": None, "after": None}
            e.update(kw)
            return e

        good = [s(state="a", gen="gen_ok"),
                s(state="b", gen="gen_ok", prev="a"),
                s(state="c", gen="gen_ok", anchor="good-v1"),
                s(state="d", seed="b"),
                s(state="e", gen="gen_ok", prev="d", stack="t9_")]
        check("well-formed graph validates", validate(good, root) == [])
        bad = [
            ("duplicate state", [s(state="a", gen="gen_ok")] * 2),
            ("gen and seed together",
             [s(state="a", gen="gen_ok", seed="a")]),
            ("neither gen nor seed", [s(state="a")]),
            ("unknown generator", [s(state="a", gen="gen_missing")]),
            ("prev not earlier",
             [s(state="a", gen="gen_ok", prev="zzz")]),
            ("prev+anchor together",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", anchor="good-v1")]),
            ("negative-* anchor refused",
             [s(state="a", gen="gen_ok", anchor="negative-x")]),
            ("anchor without manifest",
             [s(state="a", gen="gen_ok", anchor="nonexistent-v1")]),
            ("anchor without payload",
             [s(state="a", gen="gen_ok", anchor="empty-v1")]),
            ("stack without trailing underscore",
             [s(state="a", gen="gen_ok", stack="t9")]),
            ("seed of a later state", [s(state="a", seed="b"),
                                       s(state="b", gen="gen_ok")]),
            ("unknown field",
             [dict(s(state="a", gen="gen_ok"), anchorr="oops")]),
            ("bad state name", [s(state="a/b", gen="gen_ok")]),
        ]
        for label, graph in bad:
            check(label, validate(graph, root) != [])

        # the emitted text carries the load-bearing pieces
        text = emit(good, root)
        check("latch rule is restat", "rule latch" in text and
              text.split("rule latch")[1].split("rule ")[0].count(
                  "restat = 1") == 1)
        check("every mint depends on all three lib halves",
              all(f"{LATCH_DIR}/{h}" in line
                  for line in text.splitlines() if ": mint" in line
                  for h in LIB_HALVES))
        check("anchored mint hashes manifest before payload",
              "extras = tools/tests/anchors/good-v1/manifest.json "
              "tools/tests/anchors/good-v1/a.sram" in text)
        check("anchored mint exports OT6_SRAM_ANCHOR",
              "OT6_SRAM_ANCHOR=tools/tests/anchors/good-v1" in text)
        check("stacked mint exports OT6_STACK", "OT6_STACK=t9_" in text)
        check("seed consumes both halves of its source",
              "seed build/states/b.mss.lua build/states/b.mss" in text)
    print("frontier_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
