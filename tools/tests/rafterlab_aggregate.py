#!/usr/bin/env python3
"""rafterlab_aggregate.py -- fold build/rafterlab/*.log [result] lines into
per-configuration statistics for the rafter-crossing lab.

Groups by (strategy, runtry, radius, stuckcap, panic, fixture-implied tag
prefix of the log name before _h<hold>), one row per group:

  n, success rate, EXPECTED MARGIN (failures counted 0), mean margin given
  success, mean fights, mean battle frames, and the per-seed margins.

Usage: python3 tools/tests/rafterlab_aggregate.py [logdir]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

logdir = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rafterlab")
pat = re.compile(r"\[result\] (.*)")

rows = defaultdict(list)
for log in sorted(logdir.glob("*.log")):
    tag = re.sub(r"_h\d+$", "", log.stem)
    for line in log.read_text(errors="replace").splitlines():
        m = pat.search(line)
        if not m:
            continue
        kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
        rows[(tag, kv.get("strategy", "?"))].append(kv)

print(f"{'tag':34} {'n':>3} {'succ':>5} {'E[margin]':>9} "
      f"{'E[m|succ]':>9} {'fights':>6} {'bfr':>6}")
for (tag, strat), kvs in sorted(rows.items()):
    # last result per hold wins (reruns overwrite logs, but be safe)
    byhold = {}
    for kv in kvs:
        byhold[kv.get("hold", "?")] = kv
    ks = list(byhold.values())
    margins = [int(k["margin"]) for k in ks]
    arrived = [int(k["arrived"]) for k in ks]
    fights = [int(k.get("fights", 0)) for k in ks]
    bfr = [int(k.get("bframes", 0)) for k in ks]
    ok = [m for m, a in zip(margins, arrived) if a]
    print(f"{tag:34} {len(ks):>3} {sum(arrived)/len(ks):>5.0%} "
          f"{mean(margins):>9.0f} {mean(ok) if ok else 0:>9.0f} "
          f"{mean(fights):>6.2f} {mean(bfr):>6.0f}")
    seeds = " ".join(
        f"h{h}:{kv['margin']}{'' if int(kv['arrived']) else 'F'}"
        for h, kv in sorted(byhold.items(), key=lambda x: int(x[0])))
    print(f"    {seeds}")
