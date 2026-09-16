#!/usr/bin/env python3
"""sfigarolab_aggregate.py -- tabulate lab_sfigaro_gate.lua [result] lines.

    python3 tools/tests/sfigarolab_aggregate.py [build/attempts/locke-solo-lab/*_s*.log ...]

Default: every build/attempts/locke-solo-lab/<policy>_s<seed>.log.  Prints
the raw per-run lines (the evidence) grouped by policy, then one summary
row per policy: attempts, distinct battle seeds, wins, wipes, other
endings, Potions / Tonics / Fenix Downs spent, mean frames, the worst
single hit (clamped to HP) and the worst raw roll the engine wrote, and
how many TekLasers landed.  Nothing here selects a run; every retained log
counts.
"""
import glob
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESULT = re.compile(r"\[ot6\] \[result\] (.*)$")


def parse(line):
    out = {}
    for m in re.finditer(r"(\w+)=(\S+)", line):
        out[m.group(1)] = m.group(2)
    return out


def main(paths):
    if not paths:
        paths = sorted(glob.glob(os.path.join(ROOT, "build", "attempts", "locke-solo-lab", "*_s*.log")))
    rows = defaultdict(list)
    for p in paths:
        txt = open(p, encoding="utf-8", errors="replace").read()
        hits = [RESULT.search(l) for l in txt.splitlines()]
        hits = [h.group(1) for h in hits if h]
        name = os.path.basename(p)
        pol = name.split("_s")[0]
        if not hits:
            rows[pol].append({"policy": pol, "seed": name, "note": "NO RESULT (crash/timeout)", "raw": ""})
            continue
        r = parse(hits[-1])
        r["raw"] = hits[-1]
        rows[pol].append(r)

    for pol in sorted(rows):
        print("== %s (%d runs)" % (pol, len(rows[pol])))
        for r in sorted(rows[pol], key=lambda r: int(r["seed"]) if str(r.get("seed", "")).isdigit() else 999):
            print("  " + (r["raw"] or r["note"]))
    print()
    print("%-10s %3s %5s %4s %5s %5s %7s %6s %5s %7s %6s %6s %6s" % (
        "policy", "n", "seeds", "won", "wiped", "other", "potions", "tonics", "fenix",
        "frames", "maxhit", "maxraw", "lasers"))
    for pol in sorted(rows):
        rs = [r for r in rows[pol] if "outcome" in r]
        seeds = len(set(r["bseed"] for r in rs))
        won = sum(1 for r in rs if r["outcome"] == "won")
        wiped = sum(1 for r in rs if r["outcome"] == "wiped")
        other = len(rs) - won - wiped
        potions = sum(int(r["potions"]) for r in rs)
        tonics = sum(int(r["tonics"]) for r in rs)
        fenix = sum(int(r["fenix"]) for r in rs)
        frames = [int(r["frames"]) for r in rs if r["frames"].isdigit()]
        mf = sum(frames) / len(frames) if frames else 0
        mh = max((int(re.match(r"(\d+)", r["maxhit"]).group(1)) for r in rs), default=0)
        mr = max((int(r["maxraw"]) for r in rs), default=0)
        lasers = sum(int(r["lasers"]) for r in rs)
        print("%-10s %3d %5d %4d %5d %5d %7d %6d %5d %7.0f %6d %6d %6d" % (
            pol, len(rs), seeds, won, wiped, other, potions, tonics, fenix, mf, mh, mr, lasers))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
