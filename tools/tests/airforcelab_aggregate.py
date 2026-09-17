#!/usr/bin/env python3
"""Aggregate the Air Force lab's [result] lines (#201).

    python3 tools/tests/airforcelab_aggregate.py [dir]      (default build/attempts/airforce-lab)

Prints one row per policy (n, wins, losses by class, mean Air Force frames,
Fenix/Potion spent, deaths, deaths holding >= 3 BP, kill orders, Specks,
WaveCannons) and then every attempt's own line, raw fields kept.
"""
import glob
import os
import re
import sys
from collections import defaultdict

root = sys.argv[1] if len(sys.argv) > 1 else "build/attempts/airforce-lab"
rows = []
for path in sorted(glob.glob(os.path.join(root, "*.log"))):
    name = os.path.basename(path)[:-4]
    line = None
    with open(path, errors="replace") as f:
        for l in f:
            if l.startswith("[ot6] [result]"):
                line = l.strip()
    if line is None:
        rows.append({"name": name, "missing": True})
        continue
    d = {"name": name, "missing": False}
    head, _, montail = line.partition(" mon=")
    d["mon"] = montail.split(" mp=")[0] if montail else "none"
    for k, v in re.findall(r"(\w+)=(\S+)", head + (" mp=" + montail.split(" mp=")[1] if " mp=" in montail else "")):
        d[k] = v
    # the countdown, read off the body's own ExecCmd lines (the same read the
    # template makes; the first control runs predate the field): cmd $24 atk
    # $03 = the Speck launch, cmd $21 atk $38..$3C/$45 = Count 6..1
    launch, count = None, 0
    with open(path, errors="replace") as f:
        for l in f:
            m = re.match(r"\[ot6\] \[act\] t=(\d+) start e4 cmd=\$(\w\w) atk=\$(\w\w)", l)
            if not m:
                continue
            tt, cmd, atk = int(m.group(1)), m.group(2), m.group(3)
            if cmd == "24" and atk == "03" and launch is None:
                launch = tt
            if cmd == "21" and atk in ("38", "39", "3A", "3B", "3C", "45"):
                count += 1
    if d.get("speck", "none") == "none" and launch is not None:
        d["speck"] = str(launch)
    d["count"] = str(max(count, int(d.get("count", 0))))
    rows.append(d)

by = defaultdict(list)
for r in rows:
    if r.get("missing"):
        continue
    by[r["policy"]].append(r)

print("%-12s %2s %4s %-26s %6s %5s %6s %6s %6s %-22s %5s %5s" % (
    "policy", "n", "wins", "losses", "frames", "fenix", "potion", "deaths", "bp>=3", "kill orders", "speck", "wcann"))
# speck = fights where the body launched it; wcann = WaveCannons fired
for pol in sorted(by):
    rs = by[pol]
    wins = sum(1 for r in rs if r["outcome"] == "won")
    losses = defaultdict(int)
    for r in rs:
        if r["outcome"] != "won":
            losses[r["outcome"]] += 1
    frames = sum(int(r["t"]) for r in rs) / len(rs)
    fenix = sum(int(r["fenix"]) for r in rs)
    potion = sum(int(r["potion"]) for r in rs)
    deaths = sum(0 if r["deaths"] == "none" else len(r["deaths"].split(";")) for r in rs)
    banked = 0
    for r in rs:
        if r["deaths"] != "none":
            for d in r["deaths"].split(";"):
                if int(d.split("bp")[-1]) >= 3:
                    banked += 1
    orders = defaultdict(int)
    for r in rs:
        orders[",".join(k.split("@")[0] for k in r["kills"].split(","))] += 1
    specks = sum(1 for r in rs if r["speck"] != "none")
    wc = sum(int(r["wavecannon"]) for r in rs)
    print("%-12s %2d %4d %-26s %6.0f %5d %6d %6d %6d %-22s %5d %5d" % (
        pol, len(rs), wins, ",".join("%s:%d" % kv for kv in sorted(losses.items())) or "-",
        frames, fenix, potion, deaths, banked,
        " ".join("%s:%d" % kv for kv in sorted(orders.items())), specks, wc))

print()
for pol in sorted(by):
    print("== " + pol)
    for r in sorted(by[pol], key=lambda r: int(r["idle"])):
        print("  i%-3s seed=%s %-14s t=%-6s fenix=%s potion=%s deaths=%s kills=%s speck=%s count=%s wc=%s maxhit=%s mp=%s bp=%s" % (
            r["idle"], r["seed"], r["outcome"], r["t"], r["fenix"], r["potion"], r["deaths"], r["kills"],
            r["speck"], r["count"], r["wavecannon"], r["maxhit"], r["mp"], r["bp"]))
missing = [r["name"] for r in rows if r.get("missing")]
if missing:
    print("\nno [result] line:", " ".join(missing))
