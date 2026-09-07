#!/usr/bin/env python3
"""nerapalab_aggregate.py -- fold build/nerapalab/*.log [result] lines into
one table for the Nerapa strategy lab: per policy, over the declared seed
spread, wins (a win with under 900 frames of escape clock is `won_late`:
Nerapa fell but the ledge cannot be reached in time, gen_fc_escape's
CLOCK_MARGIN), Fenix Downs per win, mean fight frames, mean clock left on
a win, and the raw per-seed line.

Usage: python3 tools/tests/nerapalab_aggregate.py [logdir] [--md]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

args = [a for a in sys.argv[1:] if not a.startswith("--")]
md = "--md" in sys.argv
logdir = Path(args[0] if args else "build/nerapalab")
pat = re.compile(r"\[result\] (.*)")

rows = defaultdict(dict)
for log in sorted(logdir.glob("*.log")):
    for line in log.read_text(errors="replace").splitlines():
        m = pat.search(line)
        if not m:
            continue
        kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
        rows[kv.get("policy", "?")][int(kv.get("idle", -1))] = kv   # last wins

if md:
    print("| policy | seeds | won | won_late | lost | Fenix/win | mean t (won) | clock left (won) |")
    print("|---|---|---|---|---|---|---|---|")
else:
    print(f"{'policy':12} {'n':>2} {'won':>3} {'late':>4} {'lost':>4} {'fx/win':>6} {'t(won)':>7} {'clock(won)':>10}")
for pol, byidle in sorted(rows.items()):
    ks = [byidle[i] for i in sorted(byidle)]
    won = [k for k in ks if k["outcome"] == "won"]
    late = [k for k in ks if k["outcome"] == "won_late"]
    lost = [k for k in ks if k["outcome"].startswith("lost")]
    fx = mean(int(k["fenix"]) for k in won) if won else float("nan")
    tw = mean(int(k["t"]) for k in won) if won else float("nan")
    cw = mean(int(k["clock_left"]) for k in won) if won else float("nan")
    if md:
        print(f"| {pol} | {len(ks)} | {len(won)} | {len(late)} | {len(lost)} | "
              f"{fx:.1f} | {tw:.0f} | {cw:.0f} |")
    else:
        print(f"{pol:12} {len(ks):>2} {len(won):>3} {len(late):>4} {len(lost):>4} "
              f"{fx:>6.1f} {tw:>7.0f} {cw:>10.0f}")
        for k in ks:
            print(f"    idle={k['idle']:>2} seed={k['seed']} {k['outcome']:<12} t={k['t']:>5} "
                  f"clock={k['clock_left']:>5} fenix={k['fenix']} potion={k['potion']} "
                  f"deaths={k['deaths']} raises={k['raises']}")
