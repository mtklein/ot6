#!/usr/bin/env python3
"""Tally lab_tower_split.lua runs (#496): each party's battles on Kefka's Tower's first map.

    python3 tools/tower_tally.py [--by-arm] RUNDIR_OR_LOG...

A run is a run.log, run.log.gz or lab.txt (the `[ot6]` lines), or a directory holding one.  Per run: the
verdict, each battle's formation and how it ended (won, lost; a battle key with no `[outcome]` before the
next is a run, and the last battle of a FAIL is the wipe), the deaths by character (`[death] ... char N`),
the distinct battle keys (be<seed>-g<formation>), and the measured party's levels and the bag at the start
and the end.  --by-arm groups the runs by the name's prefix before the first `_` (the arm) and prints each
arm's totals: battles, wins, wipes, deaths per character, Fenix Downs and Potions spent, distinct keys.
Read-only.
"""
import gzip
import os
import re
import sys
from collections import Counter, defaultdict

NAMES = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER", "MOG",
         "GAU", "GOGO", "UMARO"]
KEY = re.compile(r"\[key\] battle key (be[0-9A-F]{2}-g([0-9A-F]{4}))")
OUT = re.compile(r"\[lab\] party \d battle (\d+) formation (\d+) (\w+) after")
DEATH = re.compile(r"\[death\] f\+\d+ entity \d+ char (\d+)")
START = re.compile(r"\[lab\] f\d+ party (\d) starts: (.*?); party 1 .*?; (potion=.*)$")
DONE = re.compile(r"\[lab\] f\d+ party \d done: (\d+) battles; .*?; (potion=.*)$")
ENDLV = re.compile(r"\[lab\] party \d battle \d+ formation \d+ \w+ after -?\d+ ticks; (.*)$")
BAG = re.compile(r"(\w+)=(\d+)")


def lines(path):
    if os.path.isdir(path):
        for n in ("run.log.gz", "run.log", "lab.txt"):
            if os.path.exists(os.path.join(path, n)):
                path = os.path.join(path, n)
                break
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", errors="replace") as f:
        for ln in f:
            if ln.startswith("[ot6] "):
                yield ln.rstrip("\n")


def one(path):
    r = {"verdict": "?", "battles": [], "deaths": Counter(), "keys": set(), "start": "", "end": "",
         "bag0": {}, "bag1": {}}
    measuring, cur = False, None
    for ln in lines(path):
        m = START.search(ln)
        if m:
            measuring, r["start"], r["bag0"] = True, m.group(2), dict((k, int(v)) for k, v in BAG.findall(m.group(3)))
            continue
        if not measuring:
            continue
        m = KEY.search(ln)
        if m:
            cur = {"key": m.group(1), "form": int(m.group(2), 16), "end": None, "deaths": 0}
            r["battles"].append(cur)
            r["keys"].add(m.group(1))
            continue
        m = DEATH.search(ln)
        if m and cur:
            r["deaths"][NAMES[int(m.group(1))] if int(m.group(1)) < 14 else m.group(1)] += 1
            cur["deaths"] += 1
            continue
        m = OUT.search(ln)
        if m and cur:
            cur["end"] = m.group(3)
            e = ENDLV.search(ln)
            if e:
                r["end"] = e.group(1)
            continue
        m = DONE.search(ln)
        if m:
            r["bag1"] = dict((k, int(v)) for k, v in BAG.findall(m.group(2)))
        if ln.startswith("[ot6] PASS"):
            r["verdict"] = "PASS"
        elif ln.startswith("[ot6] FAIL"):
            r["verdict"] = "FAIL " + ln[11:130]
    for b in r["battles"]:
        if b["end"] is None:
            b["end"] = "lost" if r["verdict"].startswith("FAIL") and b is r["battles"][-1] else "run"
    return r


def name_of(path):
    p = path.rstrip("/")
    return os.path.basename(p if os.path.isdir(p) else os.path.dirname(p))


def main(argv):
    by_arm = "--by-arm" in argv
    paths = [a for a in argv if a != "--by-arm"]
    arms = defaultdict(list)
    for p in paths:
        r = one(p)
        n = name_of(p)
        arms[n.split("_")[0] if by_arm else n].append((n, r))
        ends = Counter("%d %s" % (b["form"], b["end"]) for b in r["battles"])
        spent = {k: r["bag0"].get(k, 0) - r["bag1"].get(k, r["bag0"].get(k, 0)) for k in ("potion", "fenix")}
        print("== %s  %s" % (n, r["verdict"]))
        print("   start: %s" % r["start"])
        print("   end:   %s" % r["end"])
        print("   battles %d: %s; deaths %s; keys %d; spent potion %d fenix %d" % (
            len(r["battles"]), ", ".join("%s x%d" % kv for kv in sorted(ends.items())),
            dict(r["deaths"]) or "none", len(r["keys"]), spent["potion"], spent["fenix"]))
    if not by_arm:
        return
    print("== by arm")
    for a in sorted(arms):
        runs = arms[a]
        res, deaths, keys, fen, pot = Counter(), Counter(), set(), 0, 0
        wipes = 0
        for _, r in runs:
            for b in r["battles"]:
                res[b["end"]] += 1
            deaths.update(r["deaths"])
            keys |= r["keys"]
            wipes += 1 if r["verdict"].startswith("FAIL") else 0
            fen += r["bag0"].get("fenix", 0) - r["bag1"].get("fenix", r["bag0"].get("fenix", 0))
            pot += r["bag0"].get("potion", 0) - r["bag1"].get("potion", r["bag0"].get("potion", 0))
        print("   %s: %d runs, %d FAIL; battles %s; distinct keys %d; deaths %s; spent potion %d fenix %d "
              "(PASS runs)" % (a, len(runs), wipes, dict(res), len(keys), dict(deaths) or "none", pot, fen))
        print("      party: %s" % runs[0][1]["start"])
        forms, fkeys = defaultdict(Counter), defaultdict(set)
        for _, r in runs:
            for b in r["battles"]:
                forms[b["form"]][b["end"]] += 1
                forms[b["form"]]["deaths"] += b["deaths"]
                fkeys[b["form"]].add(b["key"])
        for f in sorted(forms):
            c = forms[f]
            print("      form %d: %s; deaths %d; distinct keys %d" % (f, ", ".join(
                "%s %d" % (k, v) for k, v in sorted(c.items()) if k != "deaths"), c["deaths"], len(fkeys[f])))


if __name__ == "__main__":
    main(sys.argv[1:])
