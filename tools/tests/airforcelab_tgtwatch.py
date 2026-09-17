#!/usr/bin/env python3
"""Tabulate the target cursor's observed moves from a *_trace lab log (#201).

    python3 tools/tests/airforcelab_tgtwatch.py build/attempts/airforce-lab/bay_trace_i6.log

Each [tgtwatch] line is a change of (monster mask $7B7E, party mask $7B7D,
target group $7ACE, pad $4218/9).  A press is a nonzero pad; the move it made
is the mask the window showed before the press -> the mask it showed while
that pad was still held.  Prints each (from, button, to) with its count, the
presses that moved nothing, and the masks the cursor ever showed.
"""
import re
import sys
from collections import Counter

BTN = {0x0100: "right", 0x0200: "left", 0x0400: "down", 0x0800: "up", 0x0080: "a", 0x8000: "b"}
rx = re.compile(r"\[tgtwatch\] t=(\d+) mons=(\w\w) chars=(\w\w) grp=(\w\w) pad=(\w{4}) actor=(\d)")
rows = []
for line in open(sys.argv[1], errors="replace"):
    m = rx.search(line)
    if m:
        rows.append((int(m.group(1)), m.group(2), m.group(3), int(m.group(5), 16)))

moves, dead, seen = Counter(), Counter(), Counter()
i = 0
while i < len(rows):
    t, mons, chars, pad = rows[i]
    seen["mons=%s chars=%s" % (mons, chars)] += 1
    if pad != 0 and i > 0 and rows[i - 1][3] == 0:
        before = "mons=%s chars=%s" % (rows[i - 1][1], rows[i - 1][2])
        after = before
        j = i
        while j < len(rows) and rows[j][3] == pad:
            after = "mons=%s chars=%s" % (rows[j][1], rows[j][2])
            j += 1
        name = BTN.get(pad, "%04X" % pad)
        if after == before:
            dead[(before, name)] += 1
        else:
            moves[(before, name, after)] += 1
    i += 1

print("moves (from --button--> to):")
for (a, b, c), n in sorted(moves.items()):
    print("  %3d  %s --%s--> %s" % (n, a, b, c))
print("presses that moved nothing:")
for (a, b), n in sorted(dead.items()):
    print("  %3d  %s --%s--> (no change)" % (n, a, b))
print("windows shown:")
for k, n in sorted(seen.items()):
    print("  %3d  %s" % (n, k))
