#!/usr/bin/env python3
"""route_levels.py -- the line's levels leg by leg, bench included (#497).

    python3 tools/route_levels.py [--dir build/states] [--repo .]
                                  [--branches] [--csv] [--selftest]

audit_levels.py lists the members a party holds at every state; this
answers the leveling plan's questions about the line as a whole:

  legs    one row per leg on the main line (the chain of `prev` links from
          the graph's end state back to power-on; with --branches, the
          legs nothing on that chain boots too, marked `branch`), in play
          order: the battles its final attempt fought (random / event),
          deaths, wipes and the Fenix Downs that left the bag (every drop
          of a `fenix=` field, as audit_fenix counts them), the random XP
          paid to each member, and every recruited character's level at
          the leg's boot and at its end, the bench (recruited, in no party)
          marked with `_`;
  bench   for each character, the main-line stretches it sat recruited and
          in no party: from which leg to which, how many legs, its level;
  spread  at each main-line state: the seated members' and the whole
          roster's level range, so over- and under-levelling read at a
          glance.

The levels come from each state's .mss (roster.py's reader: all fourteen
records, the recruited mask $1EDE); the counts from the state's .log, cut
to the last attempt when the segment runner retried.  Read-only; exits 0
unless --selftest fails.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

GRAPH = "tools/tests/savestate_graph.py"

RETRY = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) FAILED")
PASS = re.compile(r"^\[ot6\] PASS \(frame \d+\)(?: attempts=(\d+)/(\d+))?")
OUTCOME = re.compile(r"^\[ot6\] .*\[outcome\] battle \$([0-9A-F]+) (\S+)")
REWARD = re.compile(r"\b(random|event) reward due \d+ a member (.*)")
PAID = re.compile(r"char (\d+) \+(\d+)")
DEATH = re.compile(r"^\[ot6\] .*\[death\] ")
WIPE = re.compile(r"^\[ot6\] .*\[wipe\] ")
FENIX = re.compile(r"\bfenix=(\d+)")


def graph_states(repo):
    spec = importlib.util.spec_from_file_location("savestate_graph", os.path.join(repo, GRAPH))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return list(mod.STATES)


def owner_of(states, name):
    """The state whose leg saves `name` (itself, or the leg it is an `also` of)."""
    for s in states:
        if s["state"] == name or name in (s.get("also") or []):
            return s["state"]
    return name


def main_line(states):
    """The owner states on the chain from the end state back to power-on."""
    owner = {}
    for s in states:
        owner[s["state"]] = s["state"]
        for a in s.get("also") or []:
            owner[a] = s["state"]
    by = {s["state"]: s for s in states}
    end = [s for s in states if s.get("end")] or states[-1:]
    line, cur = set(), end[0]["state"]
    while cur:
        line.add(cur)
        prev = by[cur]["prev"]
        cur = owner.get(prev) if prev else None
    return line


def scan_log(lines):
    """Counts over the last attempt of one leg's log lines."""
    start = 0
    for i, ln in enumerate(lines):
        if RETRY.match(ln):
            start = i + 1
    r = {"random": 0, "event": 0, "other": 0, "lost": 0, "deaths": 0, "wipes": 0,
         "fenix": 0, "xp": {}, "attempts": None}
    last_fenix = None
    for ln in lines[start:]:
        m = OUTCOME.match(ln)
        if m:
            w = REWARD.search(ln)
            kind = w.group(1) if w else "other"
            r[kind] += 1
            if m.group(2) != "WON":
                r["lost"] += 1
            if kind == "random":
                for c, n in PAID.findall(w.group(2)):
                    r["xp"][int(c)] = r["xp"].get(int(c), 0) + int(n)
        if DEATH.match(ln):
            r["deaths"] += 1
        if WIPE.match(ln):
            r["wipes"] += 1
        if ln.startswith("[ot6] "):
            for f in FENIX.findall(ln):
                f = int(f)
                if last_fenix is not None and f < last_fenix:
                    r["fenix"] += last_fenix - f
                last_fenix = f
    for ln in lines:
        m = PASS.match(ln)
        if m:
            r["attempts"] = f"{m.group(1) or 1}/{m.group(2) or 1}"
    return r


def read_log(path):
    try:
        with open(path, errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return None


def read_roster(path):
    """{name: (level, seated)} for every recruited character, or None."""
    if not os.path.exists(path):
        return None
    import roster  # noqa: E402  (loads the item names; only when used)
    rows, err = roster.roster(path)
    if err:
        return None
    return {m["name"]: (m["level"], m["party"] != 0) for m in rows}


def fmt_roster(r):
    if r is None:
        return "?"
    return " ".join(f"{n}{'' if s else '_'}{lv}" for n, (lv, s) in r.items())


def levels_change(before, after):
    if before is None or after is None:
        return ""
    out = []
    for n, (lv, s) in after.items():
        b = before.get(n)
        if b is None:
            out.append(f"{n} joins L{lv}")
        elif b[0] != lv:
            out.append(f"{n} {b[0]}->{lv}")
    return ", ".join(out)


def spread(r):
    if not r:
        return "?"
    seated = [lv for lv, s in r.values() if s]
    every = [lv for lv, s in r.values()]
    if not seated:
        return f"roster L{min(every)}-{max(every)}"
    return f"seated L{min(seated)}-{max(seated)}, roster L{min(every)}-{max(every)} ({len(every)})"


NAMES = None


def collect(repo, states_dir, branches):
    global NAMES
    import savestate_party as sp
    NAMES = sp.NAMES
    states = graph_states(repo)
    line = main_line(states)
    # A leg can save several states (`also`); its exit on the line is the
    # one the next main-line leg boots (south_figaro's grind ends in
    # kolts_entry, not in south_figaro, which it saves on the way).
    exit_of = {}
    for s in states:
        if s["state"] in line and s["prev"]:
            exit_of[owner_of(states, s["prev"])] = s["prev"]
    legs = []
    for s in states:
        on = s["state"] in line
        if not on and not branches:
            continue
        log = read_log(os.path.join(states_dir, s["state"] + ".log"))
        counts = scan_log(log) if log is not None else None
        before = read_roster(os.path.join(states_dir, s["prev"] + ".mss")) if s["prev"] else None
        exit_ = exit_of.get(s["state"], s["state"]) if on else s["state"]
        after = read_roster(os.path.join(states_dir, exit_ + ".mss"))
        legs.append({"state": s["state"], "main": on, "prev": s["prev"], "exit": exit_,
                     "checkpoint": s["checkpoint"], "counts": counts,
                     "before": before, "after": after})
    return legs


def bench_spans(legs):
    """Per character: [first leg, last leg, legs, level from, level to] benched."""
    spans, open_ = {}, {}
    main = [l for l in legs if l["main"] and l["after"] is not None]
    for l in main:
        cur = l["after"]
        for n, (lv, seated) in cur.items():
            if not seated:
                if n not in open_:
                    open_[n] = [l["state"], l["state"], 0, lv, lv]
                o = open_[n]
                o[1], o[2], o[4] = l["state"], o[2] + 1, lv
            elif n in open_:
                spans.setdefault(n, []).append(open_.pop(n))
        for n in list(open_):
            if n not in cur:
                spans.setdefault(n, []).append(open_.pop(n))
    for n, o in open_.items():
        spans.setdefault(n, []).append(o)
    return spans


def report(legs, out=print):
    out("legs in play order (main line; `branch` = nothing on the line boots it). "
        "_ marks the bench (recruited, in no party)")
    for l in legs:
        c = l["counts"]
        tag = "" if l["main"] else " branch"
        if c is None:
            out(f"\n{l['state']}{tag}: no log")
            continue
        xp = " ".join(f"{NAMES.get(k, '#%d' % k)}+{v}" for k, v in sorted(c["xp"].items()))
        out(f"\n{l['state']}{tag} (boots {l['checkpoint'] or l['prev']}; attempts={c['attempts']}): "
            f"battles {c['random']} random, {c['event']} event, {c['other']} other"
            f" ({c['lost']} not won); deaths {c['deaths']}; wipes {c['wipes']}; fenix left the bag {c['fenix']}")
        if xp:
            out(f"  random xp: {xp}")
        ch = levels_change(l["before"], l["after"])
        if ch:
            out(f"  levels: {ch}")
        ex = "" if l["exit"] == l["state"] else f" (at {l['exit']})"
        out(f"  after{ex}: {fmt_roster(l['after'])}   [{spread(l['after'])}]")
    out("\nthe bench on the main line (recruited, in no party), by character:")
    for n, ss in sorted(bench_spans(legs).items()):
        for a, b, k, l0, l1 in ss:
            out(f"  {n:7s} benched {k:3d} leg(s): {a} .. {b}, L{l0}" + (f" -> L{l1}" if l1 != l0 else ""))


def csv(legs, out=print):
    out("state,main,random,event,other,lost,deaths,wipes,fenix,char,level_before,level_after,seated_after,random_xp")
    for l in legs:
        c = l["counts"] or {}
        for n, (lv, s) in (l["after"] or {}).items():
            b = (l["before"] or {}).get(n, (None, None))[0]
            cid = [k for k, v in NAMES.items() if v == n]
            xp = c.get("xp", {}).get(cid[0], 0) if cid else 0
            out(f"{l['state']},{int(l['main'])},{c.get('random', '')},{c.get('event', '')},"
                f"{c.get('other', '')},{c.get('lost', '')},{c.get('deaths', '')},"
                f"{c.get('wipes', '')},{c.get('fenix', '')},{n},{'' if b is None else b},{lv},{int(s)},{xp}")


# ---------------------------------------------------------------- selftest --

def selftest(repo):
    bad = []
    log = [
        "[ot6] [retry] attempt 1/3 FAILED class=wipe frame=1 totalframes=1 shift=0 phase=1: x",
        "[ot6] [care] tonic=4 fenix=30",
        "[ot6] [navTo] [outcome] battle $18F WON after 2892 ticks: killed s0:$0A1; escaped none; "
        "0 of 4 seated fled (Run, Warp); random reward due 4500 a member (char 2 +4500 (due 4500), "
        "char 3 +4500 (due 4500)): paid as due",
        "[ot6note] 5 [navTo] [outcome] battle $18F WON after 1 ticks: random reward due 9 a member "
        "(char 2 +9 (due 9)): paid as due",
        "[ot6] [banquet window] [outcome] battle $1A2 WON after 1135 ticks: killed s2:$0C7; "
        "event reward due 63 a member (char 0 +63 (due 63)): paid as due",
        "[ot6] [x] [outcome] battle $1A3 PARTY left",
        "[ot6] [navTo] [death] f+490 entity 3 char 9 from 1698/1698 by slot 2",
        "[ot6] [care after battle] used $F0 on char 9: 0 -> 50 hp, 28 left fenix=28",
        "[ot6] [shop] FENIX DOWN to 35 fenix=35",
        "[ot6] [x] fenix=34",
        "[ot6] PASS (frame 9) attempts=2/3",
    ]
    pre = ["[ot6] [navTo] [outcome] battle $001 WON after 1 ticks: random reward due 5 a member "
           "(char 1 +5 (due 5)): paid as due", "[ot6] [navTo] [death] x"]
    r = scan_log(pre + log)
    want = {"random": 1, "event": 1, "other": 1, "lost": 1, "deaths": 1, "wipes": 0, "fenix": 3,
            "xp": {2: 4500, 3: 4500}, "attempts": "2/3"}
    for k, v in want.items():
        if r[k] != v:
            bad.append(f"scan_log {k}: got {r[k]!r}, want {v!r} (the first attempt's lines must not count)")
    # the line: power-on to the end state, every leg reached by prev links
    states = [
        {"state": "a", "prev": None, "also": ["a2"], "end": None},
        {"state": "b", "prev": "a2", "also": None, "end": None},
        {"state": "hunt", "prev": "a", "also": None, "end": None},
        {"state": "c", "prev": "b", "also": None, "end": True},
    ]
    if main_line(states) != {"a", "b", "c"}:
        bad.append(f"main_line: got {sorted(main_line(states))}, want a b c (hunt is a branch)")
    if owner_of(states, "a2") != "a":
        bad.append(f"owner_of(a2): got {owner_of(states, 'a2')}, want a")
    legs = [{"state": k, "main": True, "after": a} for k, a in [
        ("a", {"X": (5, True), "Y": (4, False)}),
        ("b", {"X": (6, True), "Y": (4, False)}),
        ("c", {"X": (7, True), "Y": (5, True), "Z": (9, False)})]]
    sp = bench_spans(legs)
    if sp.get("Y") != [["a", "b", 2, 4, 4]] or sp.get("Z") != [["c", "c", 1, 9, 9]] or "X" in sp:
        bad.append(f"bench_spans: got {sp}")
    # the real reader on a tracked checkpoint: the tower's boot holds twelve
    cp = os.path.join(repo, "tools/tests/checkpoints/wor-kt-factory-v1")
    if os.path.isdir(cp):
        r = read_roster(cp)
        if not r or len(r) < 12 or not all(1 <= lv <= 99 for lv, _ in r.values()):
            bad.append(f"read_roster(wor-kt-factory-v1): got {r}")
        elif sum(1 for _, s in r.values() if s) != 12:
            bad.append(f"wor-kt-factory-v1 should seat twelve in three parties: {r}")
    else:
        bad.append("tools/tests/checkpoints/wor-kt-factory-v1 not found")
    for b in bad:
        print("  SELFTEST FAIL", b)
    print(f"route_levels selftest: {len(want) + 5} checks, {len(bad)} failed")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--branches", action="store_true", help="list the branch legs too")
    ap.add_argument("--csv", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest(a.repo)
    legs = collect(a.repo, a.dir, a.branches)
    (csv if a.csv else report)(legs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
