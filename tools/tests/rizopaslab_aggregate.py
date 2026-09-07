#!/usr/bin/env python3
"""rizopaslab_aggregate.py -- fold build/rizopaslab/*.log [result] lines into
one table for the Rizopas strategy lab (#162): per policy, over the
declared seed spread, wins, Fenix Downs per win, Potions per win, deaths,
mean battle frames on a win (battle-up to teardown), mean boss-phase frames
(Rizopas surfacing to its death), and the raw per-seed line.

Usage: python3 tools/tests/rizopaslab_aggregate.py [logdir] [--md] [--raw]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

args = [a for a in sys.argv[1:] if not a.startswith("--")]
md = "--md" in sys.argv
raw = "--raw" in sys.argv
logdir = Path(args[0] if args else "build/rizopaslab")
pat = re.compile(r"\[result\] (.*)")

rows = defaultdict(dict)
for log in sorted(logdir.glob("*.log")):
    for line in log.read_text(errors="replace").splitlines():
        m = pat.search(line)
        if not m:
            continue
        kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
        kv["_log"] = log.name
        rows[kv.get("policy", "?")][int(kv.get("idle", -1))] = kv   # last wins


def fmean(xs):
    return f"{mean(xs):.0f}" if xs else "-"


if md:
    print("| policy | distinct seeds | won | lost | Fenix/win | Potion/win | deaths (all) | mean t (won) | mean boss phase (won) |")
    print("|---|---|---|---|---|---|---|---|---|")
else:
    print(f"{'policy':10} {'n':>2} {'won':>3} {'lost':>4} {'fx/win':>6} {'po/win':>6} {'deaths':>6} {'t(won)':>7} {'boss(won)':>9}")
for pol, byidle in sorted(rows.items()):
    # Two idles can draw the same seed: a repeated seed is a replicate of
    # the same fight, not a new sample.  Statistics are over DISTINCT
    # seeds; replicates are listed and marked.
    ks, seen, reps = [], set(), []
    for i in sorted(byidle):
        k = byidle[i]
        if k["seed"] in seen:
            reps.append(k)
        else:
            seen.add(k["seed"])
            ks.append(k)
    won = [k for k in ks if k["outcome"] == "won"]
    lost = [k for k in ks if k["outcome"] != "won"]
    fx = mean(int(k["fenix"]) for k in won) if won else float("nan")
    po = mean(int(k["potion"]) for k in won) if won else float("nan")
    deaths = sum(0 if k["deaths"] == "none" else len(k["deaths"].split(";")) for k in ks)
    tw = [int(k["t"]) for k in won]
    bw = [int(k["t_boss"]) for k in won if k["t_boss"] != "none"]
    if md:
        print(f"| {pol} | {len(ks)} | {len(won)} | {len(lost)} | {fx:.1f} | {po:.1f} | {deaths} | {fmean(tw)} | {fmean(bw)} |")
    else:
        print(f"{pol:10} {len(ks):>2} {len(won):>3} {len(lost):>4} {fx:>6.1f} {po:>6.1f} {deaths:>6} {fmean(tw):>7} {fmean(bw):>9}")
        if raw:
            for k in ks + reps:
                rep = " (replicate seed)" if k in reps else ""
                print(f"    idle={k['idle']:>2} seed={k['seed']} be_up={k['be_up']} {k['outcome']:<13} t={k['t']:>5} "
                      f"boss={k['t_boss']:>5} fenix={k['fenix']} potion={k['potion']} tonic={k['tonic']} "
                      f"deaths={k['deaths']} raises={k['raises']} bp@surface={k['bp_at_surface']} "
                      f"shore={k['shore']} party={k.get('party', '?')}{rep}")
