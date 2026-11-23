#!/usr/bin/env python3
"""line_stats.py A B -- two plays of the line, leg by leg and in total (#566).

A and B are directories of leg logs (build/states/<state>.log; suite_, quick_
and dotted names are skipped).  Per leg: party deaths (`[death]`), failed
attempts (`[retry] attempt N/M FAILED class=`), frames (the PASS frame plus
each failed attempt's), as build/attempts/wt/v050-line-deaths/legcmp.py
counted them; and from the battle lines:

  battles   `[keys]` lines (one a battle the driver fought)
  nokit     battles in which some gauged body with a class row stood whose
            classes the party's kit held none of (`nokit=` > 0); nohand the
            same for the weapons in hand alone
  breaks    a monster slot's shields reaching 0 from above, read off the
            `[board]` lines (one a party action: mons=s<slot>:hp/max/shields),
            so a break by a battle's last action is not seen -- the same in
            both plays

    python3 tools/proto_six/line_stats.py base/ six/ [--legs]
"""
import glob
import os
import re
import sys

DEATH = re.compile(r"^\[ot6\] .*\[death\] ")
FAIL = re.compile(r"^\[ot6\] \[retry\] attempt \d+/\d+ FAILED class=(\S+) frame=(\d+)")
OK = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
KEYS = re.compile(r"^\[ot6\] .*\[keys\] form=\$([0-9A-F]+) .*gauged=(\d+) nohand=(\d+) nokit=(\d+)")
BOARD = re.compile(r"^\[ot6\] .*\[board\] n=(\d+) .*mons=(\S*)")
OPEN = re.compile(r"^\[ot6\] .*\[open\] party HP as the battle opens")


def read(tree):
    out = {}
    for p in sorted(glob.glob(os.path.join(os.path.expanduser(tree), "*.log"))):
        name = os.path.basename(p)[:-4]
        if name.startswith(("suite_", "quick_", "last_run")) or "." in name:
            continue
        r = dict(deaths=0, fails=[], frames=0, passed=False, battles=0, gauged=0, nokit=0, nohand=0, breaks=0,
                 bodies=0, nokit_bodies=0, nohand_bodies=0)
        sh = {}
        for line in open(p, errors="replace"):
            if DEATH.match(line):
                r["deaths"] += 1
            m = FAIL.match(line)
            if m:
                r["fails"].append(m.group(1))
                r["frames"] += int(m.group(2))
            m = OK.match(line)
            if m:
                r["frames"] += int(m.group(1))
                r["passed"] = True
            if OPEN.search(line):
                sh = {}
            m = KEYS.search(line)
            if m:
                r["battles"] += 1
                g, nh, nk = int(m.group(2)), int(m.group(3)), int(m.group(4))
                r["gauged"] += 1 if g else 0
                r["bodies"] += g
                r["nokit"] += 1 if nk else 0
                r["nohand"] += 1 if nh else 0
                r["nokit_bodies"] += nk
                r["nohand_bodies"] += nh
            m = BOARD.search(line)
            if m:
                for part in m.group(2).split(","):
                    q = re.match(r"s(\d):(\d+)/(\d+)/(\d+)$", part)
                    if not q:
                        continue
                    s, cur = q.group(1), int(q.group(4))
                    if sh.get(s, 0) > 0 and cur == 0:
                        r["breaks"] += 1
                    sh[s] = cur
        out[name] = r
    return out


def pct(a, b):
    return "%.1f%%" % (100.0 * a / b) if b else "-"


def main():
    a, b = read(sys.argv[1]), read(sys.argv[2])
    both = sorted(k for k in a if k in b and a[k]["passed"] and b[k]["passed"])
    if "--legs" in sys.argv:
        for k in sorted(set(a) | set(b)):
            x, y = a.get(k), b.get(k)
            f = lambda r, key: "-" if r is None else str(r[key])
            print("%-30s deaths %3s -> %3s  retries %s -> %s  frames %7s -> %7s  battles %3s -> %3s  nokit %3s -> %3s  "
                  "breaks %3s -> %3s%s" % (
                      k, f(x, "deaths"), f(y, "deaths"),
                      "-" if x is None else "%d %s" % (len(x["fails"]), ",".join(x["fails"]) or "-"),
                      "-" if y is None else "%d %s" % (len(y["fails"]), ",".join(y["fails"]) or "-"),
                      f(x, "frames"), f(y, "frames"), f(x, "battles"), f(y, "battles"), f(x, "nokit"), f(y, "nokit"),
                      f(x, "breaks"), f(y, "breaks"),
                      "" if (x and y and x["passed"] and y["passed"]) else "   (A PASS: %s, B PASS: %s)" % (
                          x and x["passed"], y and y["passed"])))
    print("== legs: %d in A (%d passed), %d in B (%d passed), %d passed in both" % (
        len(a), sum(r["passed"] for r in a.values()), len(b), sum(r["passed"] for r in b.values()), len(both)))
    print("== not passed in A: %s" % sorted(k for k in a if not a[k]["passed"]))
    print("== not passed in B: %s" % sorted(k for k in b if not b[k]["passed"]))
    print("== only in A: %s; only in B: %s" % (sorted(k for k in a if k not in b), sorted(k for k in b if k not in a)))
    for label, t in (("A", a), ("B", b)):
        s = lambda key: sum(t[k][key] for k in both)
        print("== %s over the %d legs passed in both: deaths %d; retries %d; frames %d; battles %d (%d with a gauged, "
              "class-rowed body); no kit key for a body in %d (%s of those); no weapon-in-hand key in %d (%s); bodies "
              "%d, unkeyed by kit %d (%s), by hand %d (%s); breaks %d (%.2f a battle)" % (
                  label, len(both), s("deaths"), sum(len(t[k]["fails"]) for k in both), s("frames"), s("battles"),
                  s("gauged"), s("nokit"), pct(s("nokit"), s("gauged")), s("nohand"), pct(s("nohand"), s("gauged")),
                  s("bodies"), s("nokit_bodies"), pct(s("nokit_bodies"), s("bodies")), s("nohand_bodies"),
                  pct(s("nohand_bodies"), s("bodies")), s("breaks"), s("breaks") / max(1, s("battles"))))


if __name__ == "__main__":
    main()
