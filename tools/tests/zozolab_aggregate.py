#!/usr/bin/env python3
"""zozolab_aggregate.py -- tabulate lab_zozo_street.lua [result] lines.

    python3 tools/tests/zozolab_aggregate.py [build/zozolab/*.log ...]

Default: every build/zozolab/<policy>_s<seed>.log.  Prints the raw per-run
lines (the evidence) grouped by policy, then one summary row per policy:
attempts, formations drawn, distinct battle seeds, deaths, Fenix Downs
(in battle, at the care stop), wipes, mean frames, and the worst single
hit.  Nothing here selects a run; every retained log counts.
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
        paths = sorted(glob.glob(os.path.join(ROOT, "build", "zozolab", "*_s*.log")))
    rows = defaultdict(list)
    for p in paths:
        txt = open(p, encoding="utf-8", errors="replace").read()
        hits = [RESULT.search(l) for l in txt.splitlines()]
        hits = [h.group(1) for h in hits if h]
        name = os.path.basename(p)
        if not hits:
            pol = name.split("_s")[0]
            rows[pol].append({"policy": pol, "seed": name, "note": "NO RESULT (crash/timeout)", "raw": ""})
            continue
        r = parse(hits[-1])
        r["raw"] = hits[-1]
        rows[name.split("_s")[0]].append(r)      # group by the batch TAG

    for pol in sorted(rows):
        print("== %s (%d runs)" % (pol, len(rows[pol])))
        for r in sorted(rows[pol], key=lambda r: int(r["seed"]) if str(r.get("seed", "")).isdigit() else 999):
            print("  " + (r["raw"] or r["note"]))
    print()
    print("%-10s %4s %-28s %5s %6s %6s %6s %5s %7s %7s" % (
        "policy", "n", "formations", "seeds", "deaths", "fenixB", "fenixC", "wipes", "frames", "maxhit"))
    for pol in sorted(rows):
        rs = [r for r in rows[pol] if "form" in r]
        forms = defaultdict(int)
        for r in rs:
            forms[r["form"]] += 1
        fstr = ",".join("%s:%d" % (k, v) for k, v in sorted(forms.items()))
        seeds = len(set(r["bseed"] for r in rs))
        deaths = sum(int(r["deaths"]) for r in rs)
        fb = sum(int(r["fenix_battle"]) for r in rs)
        fc = sum(int(r["fenix_care"]) for r in rs)
        wipes = sum(1 for r in rs if r["wiped"] == "true")
        frames = [int(r["frames"]) for r in rs if r["frames"].isdigit()]
        mf = sum(frames) / len(frames) if frames else 0
        mh = max((int(re.match(r"(\d+)", r["maxhit"]).group(1)) for r in rs), default=0)
        print("%-10s %4d %-28s %5d %6d %6d %6d %5d %7.0f %7d" % (
            pol, len(rs), fstr, seeds, deaths, fb, fc, wipes, mf, mh))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
