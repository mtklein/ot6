#!/usr/bin/env python3
"""m269lab_aggregate.py -- tabulate lab_map269_random.lua result lines.

    python3 tools/tests/m269lab_aggregate.py [build/m269lab/*.log ...]

Default: every build/m269lab/<tag>_s<seed>.log.  Prints the raw per-run
[result] / [walkresult] lines (the evidence) grouped by tag, then one
summary row per fight-mode tag: attempts, formations drawn, distinct battle
seeds, deaths, Fenix Downs (before the walk, in battle, at the care stop),
wipes, mean frames, L4 Flare casts, the worst single hit and the largest
raw damage word.  Walk-mode tags get their own table.  Nothing here selects
a run; every retained log counts.
"""
import glob
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESULT = re.compile(r"\[ot6\] \[(result|walkresult)\] (.*)$")


def parse(line):
    out = {}
    for m in re.finditer(r"(\w+)=(\S+)", line):
        out[m.group(1)] = m.group(2)
    return out


def num(s, default=0):
    m = re.match(r"-?\d+", str(s))
    return int(m.group(0)) if m else default


def main(paths):
    if not paths:
        paths = sorted(glob.glob(os.path.join(ROOT, "build", "m269lab", "*_s*.log")))
    rows = defaultdict(list)
    for p in paths:
        txt = open(p, encoding="utf-8", errors="replace").read()
        hits = [RESULT.search(l) for l in txt.splitlines()]
        hits = [h for h in hits if h]
        name = os.path.basename(p)
        tag = name.rsplit("_s", 1)[0]
        if not hits:
            rows[tag].append({"kind": "none", "seed": name.rsplit("_s", 1)[-1][:-4],
                              "raw": "", "note": "NO RESULT (crash/timeout)"})
            continue
        r = parse(hits[-1].group(2))
        r["kind"] = hits[-1].group(1)
        r["raw"] = hits[-1].group(2)
        rows[tag].append(r)

    for tag in sorted(rows):
        print("== %s (%d runs)" % (tag, len(rows[tag])))
        for r in sorted(rows[tag], key=lambda r: num(r.get("seed", ""), 999)):
            print("  " + (r["raw"] or r["note"]))
    print()
    fight = {t: [r for r in rs if r["kind"] == "result"] for t, rs in rows.items()}
    fight = {t: rs for t, rs in fight.items() if rs}
    if fight:
        print("%-11s %3s %-14s %5s %6s %6s %6s %6s %5s %6s %6s %6s %6s" % (
            "policy", "n", "formations", "seeds", "deaths", "fenixP", "fenixB", "fenixC",
            "wipes", "frames", "flares", "maxhit", "maxraw"))
        for tag in sorted(fight):
            rs = fight[tag]
            forms = defaultdict(int)
            for r in rs:
                forms[r["form"]] += 1
            fstr = ",".join("%s:%d" % (k, v) for k, v in sorted(forms.items()))
            seeds = len(set(r["bseed"] for r in rs))
            deaths = sum(num(r["deaths"]) for r in rs)
            fp = sum(num(r["fenix_pre"]) for r in rs)
            fb = sum(num(r["fenix_battle"]) for r in rs)
            fc = sum(num(r["fenix_care"]) for r in rs)
            wipes = sum(1 for r in rs if r["wiped"] == "true")
            frames = [num(r["frames"]) for r in rs if str(r["frames"]).isdigit()]
            mf = sum(frames) / len(frames) if frames else 0
            flares = sum(num(r["flares"]) for r in rs)
            mh = max((num(r["maxhit"]) for r in rs), default=0)
            mr = max((num(r["maxraw"]) for r in rs), default=0)
            print("%-11s %3d %-14s %5d %6d %6d %6d %6d %5d %6.0f %6d %6d %6d" % (
                tag, len(rs), fstr, seeds, deaths, fp, fb, fc, wipes, mf, flares, mh, mr))
    walk = {t: [r for r in rs if r["kind"] == "walkresult"] for t, rs in rows.items()}
    walk = {t: rs for t, rs in walk.items() if rs}
    if walk:
        print()
        print("%-16s %4s %-8s %7s %-40s %6s %6s %6s %6s %6s %6s" % (
            "walk tag", "seed", "reached", "battles", "formations", "deaths", "fenixP",
            "fenixT", "flares", "maxraw", "frames"))
        for tag in sorted(walk):
            for r in sorted(walk[tag], key=lambda r: num(r.get("seed", ""), 999)):
                print("%-16s %4s %-8s %7s %-40s %6s %6s %6s %6s %6s %6s" % (
                    tag, r["seed"], r["reached"], r["battles"], r["forms"][:40], r["deaths"],
                    r["fenix_pre"], r["fenix_total"], r["flares"], r["maxraw"], r["frames"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
