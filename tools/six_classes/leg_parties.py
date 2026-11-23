#!/usr/bin/env python3
"""leg_parties.py KEYS.json -- the legs of the line in graph order, each with
the battles its [keys] lines record and the members who fought them
(route_fights.py --keys output).  Run from the repo root (reads build.ninja
for the order)."""
import collections
import json
import re
import sys

N = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO",
     "UMARO", "BANON", "LEO"]


def order():
    names = []
    for line in open("build.ninja"):
        m = re.match(r"build build/states/(\w+)\.mss\.lua .*: generate", line)
        if m and not m.group(1).startswith("quick_"):
            names.append(m.group(1))
    return names


def main():
    f = json.load(open(sys.argv[1]))
    by = collections.OrderedDict()
    for x in f:
        e = by.setdefault(x["leg"], [set(), 0])
        e[0] |= {m["c"] for m in x["members"]}
        e[1] += 1
    for n in order():
        if n in by:
            print("%-26s %3d  %s" % (n, by[n][1], " ".join(N[c][:3] if c < 16 else str(c) for c in sorted(by[n][0]))))
        else:
            print("%-26s   -" % n)


if __name__ == "__main__":
    main()
