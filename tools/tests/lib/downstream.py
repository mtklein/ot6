#!/usr/bin/env python3
"""downstream.py -- what a change to one leg of the savestate graph reaches.

    downstream.py LEG        LEG is a state name, an also= name, a generator
                             (gen_wor_tower) or a cutter= script
    downstream.py --selftest

A landing that changes play replays from the earliest section the change can
reach and then re-cuts the tracked checkpoints downstream of it
(docs/TOOLING.md "Landing a play-changing branch"; #480).  This states that
scope without a hand list.  It reads the graph (tools/tests/savestate_graph.py,
through savestate_ninja.py's own producers()) and the consumers configure.py
wires (its TEST_ENV, the `-- @suite` and `-- @manual` headers, the .mss names
a script boots), and prints:

  states      the graph states the change replays: LEG's own, then every one
              whose prev= chain reaches it (a cut's prev= is the run that
              saves its boot, so the chain runs through checkpoint= boots)
  keys        the tracked checkpoints (tools/tests/checkpoints/*) those runs
              cut: what `checkpoint_drift.py --recut` has to copy
  consumers   the suites and instruments that boot any of those states or
              capture keys, which the replay re-runs

then a ready-to-paste `--recut` line.  A branch leg that nothing boots
feeds no key, and says so.  A cutter's key is cut by a run booted from its
prev, so it follows that prev's state; changing the cutter itself reaches
its key and the legs that boot it.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(HERE))
import savestate_ninja as sn  # noqa: E402

STATE_REF = re.compile(r"([A-Za-z0-9_]+)\.mss")
BOOT_CHECKPOINT = re.compile(r'H\.bootCheckpoint\("([^"]+)"|^-- @checkpoint\s+(\S+)', re.M)


def downstream(states, leg):
    """(states in graph order, keys in graph order) a change to `leg`
    reaches; ValueError if `leg` is not on the graph."""
    owner = sn._owners(states)
    hit = {e["state"] for e in states
           if leg in (e["state"], e.get("gen")) or owner.get(leg) == e["state"]
           or "gen_" + leg == e.get("gen")}
    cutter = leg if any(e.get("cutter") == leg for e in states) else None
    if not hit and not cutter:
        raise ValueError(f"{leg!r} names no state, generator or cutter on the graph")
    # a changed cutter changes the save its entry boots
    hit |= {e["state"] for e in states if cutter and e.get("cutter") == cutter}
    grew = True
    while grew:
        grew = False
        for e in states:
            p = e.get("prev")
            if e["state"] not in hit and p and owner[p] in hit:
                hit.add(e["state"])
                grew = True
    keys = [key for key, run in sn.producers(states).items()
            if (run[1] in hit if run[0] == "run"
                else run[1] == cutter or owner[run[2]] in hit)]
    pos = {k: i for i, k in enumerate(
        k for e in states for k in (e.get("checkpoint"), e.get("saves")) if k)}
    return ([e["state"] for e in states if e["state"] in hit],
            sorted(keys, key=lambda k: pos.get(k, 1 << 20)))


def test_env(root=ROOT):
    """configure.py's TEST_ENV literal, read without running configure.py."""
    tree = ast.parse((root / "configure.py").read_text())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                getattr(t, "id", "") == "TEST_ENV" for t in node.targets):
            return ast.literal_eval(node.value)
    raise RuntimeError("configure.py has no TEST_ENV literal")


def consumers(states, hit, keys, root=ROOT):
    """[(script, kind, what it boots from the downstream set)] for the
    suites (`-- @suite`) and instruments (`-- @manual`) under tools/tests."""
    owner = sn._owners(states)
    reach = {n for n, o in owner.items() if o in hit}
    env = test_env(root)
    out = []
    for f in sorted((root / "tools" / "tests").glob("*.lua")):
        text = f.read_text(errors="replace")
        kind = ("suite" if re.search(r"^-- @suite", text, re.M) else
                "instrument" if re.search(r"^-- @manual", text, re.M) else None)
        if kind is None:
            continue
        booted = {s for s in STATE_REF.findall(text) if s in reach}
        m = re.search(r"savestate=([A-Za-z0-9_]+)", text)
        if m and m.group(1) in reach:
            booted.add(m.group(1))
        got = set(re.findall(r"OT6_SRAM_CHECKPOINT=build/checkpoints/(\S+)",
                             env.get(f.stem, "")))
        got |= {a or b for a, b in BOOT_CHECKPOINT.findall(text)}
        got &= set(keys)
        if booted or got:
            out.append((f.stem, kind, sorted(booted) + sorted(got)))
    return out


def report(leg, root=ROOT):
    states = sn.load(root)
    hit, keys = downstream(states, leg)
    users = consumers(states, set(hit), keys, root)
    lines = [f"downstream of {leg}:",
             f"  states ({len(hit)}): " + " ".join(hit)]
    if keys:
        lines.append(f"  tracked checkpoint keys ({len(keys)}): " + " ".join(keys))
    else:
        lines.append("  tracked checkpoint keys (0): none; this leg feeds no key")
    lines.append(f"  suites and instruments that boot them ({len(users)}):")
    for name, kind, what in users:
        lines.append(f"    {name} [{kind}] boots {', '.join(what)}")
    if keys:
        lines.append("recut after the replay:")
        lines.append("  python3 tools/tests/lib/checkpoint_drift.py --recut "
                     + " ".join(keys))
    return "\n".join(lines)


def selftest():
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond
    states = sn.load(ROOT)
    three = ["wor-colosseum-v1", "wor-dino-v1", "wor-desert-v1"]
    for leg in ("wor_colosseum", "gen_wor_colosseum", "wor_colosseum_in"):
        h, keys = downstream(states, leg)
        check(f"{leg}: exactly {', '.join(three)}", keys == three)
    check("...through the prev= chain: wor_dino and wor_desert replay",
          {"wor_colosseum", "wor_dino", "wor_desert"} <= set(h))
    _, keys = downstream(states, "wor_desert")
    check("the last leg feeds only its own saves= key", keys == ["wor-desert-v1"])
    h, keys = downstream(states, "wor_thamasa_plain")
    check("a branch leg that nothing boots feeds no tracked key", keys == [])
    _, keys = downstream(states, "wor_gogo")
    check("a leg upstream reaches the frontier too", set(three) <= set(keys))
    _, keys = downstream(states, "gen_post_opera_checkpoint")
    check("a cutter's own key is downstream of it", "post-opera-v1" in keys)
    h, keys = downstream(states, "wor_colosseum")
    users = {n for n, _, _ in consumers(states, set(h), keys)}
    h2, keys2 = downstream(states, "wor_desert")
    users2 = {n for n, _, _ in consumers(states, set(h2), keys2)}
    check("a later leg's consumers are a subset of an earlier leg's",
          users2 <= users)
    check("a suite that boots nothing downstream (battle_runicblade, "
          "wor-tomb-v1) is not a consumer", "battle_runicblade" not in users)
    _, tkeys = downstream(states, "wor_tomb")
    check("...and is one of wor_tomb's",
          "battle_runicblade" in {n for n, _, _ in consumers(
              states, set(downstream(states, "wor_tomb")[0]), tkeys)})
    try:
        downstream(states, "no_such_leg")
        raised = False
    except ValueError:
        raised = True
    check("an unknown leg is refused, not answered with an empty set", raised)
    # negative control: a deliberately wrong expectation must go red
    _, keys = downstream(states, "wor_colosseum")
    check("negative control: an expectation without wor-desert-v1 does not "
          "match", keys != three[:2])
    check("negative control: an expectation with a branch leg's key does not "
          "match", keys != three + ["wor-thamasa-v1"])
    print("downstream selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 1 or argv[0].startswith("--"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        print(report(argv[0]))
    except ValueError as exc:
        print(f"downstream: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
