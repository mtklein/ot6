#!/usr/bin/env python3
"""audit_fenix.py -- Fenix Downs as a proxy for under-leveling / a missing
fight strategy.

Owner heuristic: more than 1-2 Fenix Downs in a hard (boss/set-piece)
fight, or ANY in a random battle, means the party is under-leveled or that
fight needs a strategy lab.  This scans run logs, attributes every Fenix
use to the fight it happened in, classifies that fight as BOSS or RANDOM,
and flags the violations -- a countable lab/level-candidate list.

    tools/audit_fenix.py [logglob ...]

Default scan is every retained run workspace (build/test-runs/*/run.log)
plus published per-state logs (build/states/*.log).  For FULL route
coverage run a census with OT6_KEEP_RUNS=1 first so every segment's
workspace survives, then point this at build/test-runs.

A fight is BOSS when the driver context around the revive is a bespoke
set-piece driver or a spared/event formation; RANDOM when it is ordinary
traversal (navTo / worldNavTo / advanceStory / rideOut / field care).
"""
import glob
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FENIX = re.compile(
    r"(?:revive entity \d+ with Fenix Down|used \$F0 on char \d+|"
    r"with Fenix Down\b)")
# the driver tag a log line carries, e.g. "[FlameEater]", "[b70]",
# "[navTo]", "[care after battle (worldNavTo)]", "[ambush-plan-1]"
TAG = re.compile(r"\[([^\]]+)\]")
BATTLE = re.compile(r"battle (\d+)|formation|spared")

# bespoke set-piece / boss driver tags (extend as the route grows)
BOSS_HINT = re.compile(
    r"b70|FlameEater|ambush|Ultros|Kefka|Vargas|Whelk|Dadaluma|TunnelArmr|"
    r"Ifrit|Shiva|Number|Cranes|Atma|pursuit|boss|magitek", re.I)
RANDOM_HINT = re.compile(
    r"navTo|worldNavTo|advanceStory|rideOut|care after|care before|"
    r"the ride|climb|cross", re.I)


def worker_of(path):
    d = os.path.basename(os.path.dirname(path))
    if d == "states":                       # build/states/<name>.log
        return os.path.basename(path)[:-4]
    return d.split(".")[0]                   # build/test-runs/<name>.xxxx


def classify(context):
    """BOSS / RANDOM / '?' from the ~few log lines around a revive."""
    joined = " ".join(context)
    if BOSS_HINT.search(joined):
        return "BOSS"
    if RANDOM_HINT.search(joined):
        return "RANDOM"
    return "?"


def scan(path):
    """Yield (worker, fight_key, classification) per Fenix use."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return
    worker = worker_of(path)
    for i, line in enumerate(lines):
        if not FENIX.search(line):
            continue
        # context: a window of preceding lines names the fight/driver
        ctx = lines[max(0, i - 12):i + 1]
        # the fight key: the nearest tag that looks like a driver/fight
        key = None
        for c in reversed(ctx):
            m = TAG.search(c)
            if m and (BOSS_HINT.search(m.group(1))
                      or RANDOM_HINT.search(m.group(1))
                      or "battle" in c.lower()):
                key = m.group(1)
                break
        yield worker, (key or "?"), classify(ctx)


def main():
    globs = sys.argv[1:] or [
        os.path.join(ROOT, "build/test-runs/*/run.log"),
        os.path.join(ROOT, "build/states/*.log"),
    ]
    paths = []
    for g in globs:
        paths.extend(glob.glob(g))
    # aggregate per (segment, classification): the fuzzy fight-key is only
    # for context, so summing by the BOSS/RANDOM/? verdict gives one clean
    # row per kind per segment.  De-dup identical revive lines that both
    # regexes can match by counting distinct (line-index) uses per file --
    # scan() already yields one per matched line.
    tally = defaultdict(lambda: defaultdict(int))     # worker -> class -> n
    for p in sorted(paths):
        for worker, _key, cls in scan(p):
            tally[worker][cls] += 1

    flagged = []
    for worker in sorted(tally):
        for cls, n in tally[worker].items():
            boss = cls == "BOSS"
            violation = (boss and n > 2) or (cls == "RANDOM" and n >= 1)
            if violation or (cls == "?" and n > 2):
                flagged.append((worker, n, cls))

    if not flagged:
        print("Fenix audit: no threshold violations in the scanned logs "
              f"({len(paths)} logs).")
        return
    print(f"Fenix audit: {len(flagged)} flagged segment/kind(s) "
          f"(>2 Fenix in a boss, or any in a random) across {len(paths)} "
          "logs.\n")
    print(f"{'segment':28} {'fenix':>5}  {'kind':7} why")
    for worker, n, cls in sorted(flagged, key=lambda x: -x[1]):
        why = ("boss burned >2 -- underleveled or needs a strategy lab"
               if cls == "BOSS"
               else "Fenix in randoms -- underleveled or lab these encounters"
               if cls == "RANDOM"
               else "review: classify boss vs random")
        print(f"{worker:28} {n:>5}  {cls:7} {why}")


if __name__ == "__main__":
    main()
