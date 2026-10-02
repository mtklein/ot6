#!/usr/bin/env python3
"""audit_zombie_touches.py -- a run log's [death] lines, Zombie touches apart.

A Zombie touch reads as a death.  ZOMBIE lands and the engine's
AfterAction1 (battle_main.asm @069b) zeroes the member's HP, so the fight
driver logs `[status] f+N entity E ... is under ZOMBIE` and
`[death] f+N entity E ...` on the same frame for the same entity.  The
member still takes its turns as the engine's.  The care-policy reviews
(f8f9ad66, bcf5240f) asked that these touches not be counted as deaths.
This splits every log's [death] lines into touches and the rest.

Only the `[ot6] ` lines are read.  A run log also carries each line again
as `[ot6note] <frame> ...`, and counting both doubles every number.

    tools/audit_zombie_touches.py ARM=DIR_OR_LOG [ARM=DIR_OR_LOG ...]
    tools/audit_zombie_touches.py --selftest

A DIR is read for *.log and *.log.gz (a name in both forms is read once,
the plain file).  Prints, per arm: [death] lines, Zombie touches, the rest.
"""
import gzip
import re
import sys
from pathlib import Path

STATUS = re.compile(r"\[status\] f\+(\d+) entity (\d) .* is under ZOMBIE")
DEATH = re.compile(r"\[death\] f\+(\d+) entity (\d) ")


def text(p):
    p = Path(p)
    if p.suffix == ".gz":
        with gzip.open(p, "rt", errors="replace") as f:
            return f.read()
    return p.read_text(errors="replace")


def logs(target):
    t = Path(target)
    if t.is_file():
        return [t]
    found = {}
    for p in sorted(t.glob("*.log.gz")):
        found[p.name[:-len(".log.gz")]] = p
    for p in sorted(t.glob("*.log")):
        found[p.name[:-len(".log")]] = p
    return [found[k] for k in sorted(found)]


def split(lines):
    """[death] lines and, of them, Zombie touches, over `[ot6] ` lines."""
    ours = [l[6:] for l in lines if l.startswith("[ot6] ")]
    zomb = set()
    for l in ours:
        m = STATUS.search(l)
        if m:
            zomb.add((m.group(1), m.group(2)))
    deaths = touches = 0
    for l in ours:
        m = DEATH.search(l)
        if m:
            deaths += 1
            if (m.group(1), m.group(2)) in zomb:
                touches += 1
    return deaths, touches


def selftest():
    lines = [
        "[ot6note] 646 [navTo] [status] f+646 entity 1 char 5 is under ZOMBIE (STATUS1 $02)",
        "[ot6] [navTo] [status] f+646 entity 1 char 5 is under ZOMBIE (STATUS1 $02)",
        "[ot6note] 646 [navTo] [death] f+646 entity 1 char 5 from 1710/1710 by slot 1",
        "[ot6] [navTo] [death] f+646 entity 1 char 5 from 1710/1710 by slot 1",
        "[ot6] [navTo] [death] f+900 entity 2 char 4 from 75/619 by slot 2",
        "[ot6] [navTo] [death] f+646 entity 3 char 9 from 40/1597 by slot 0",
    ]
    d, t = split(lines)
    assert (d, t) == (3, 1), (d, t)
    print("audit_zombie_touches selftest: ok (3 deaths, 1 touch; the [ot6note] copies not counted)")


def main(argv):
    if argv[1:] == ["--selftest"]:
        selftest()
        return 0
    if len(argv) < 2:
        print(__doc__)
        return 2
    for arg in argv[1:]:
        arm, _, target = arg.partition("=")
        deaths = touches = 0
        for p in logs(target):
            d, t = split(text(p).splitlines())
            deaths, touches = deaths + d, touches + t
        print(f"{arm} ({target}): [death] lines {deaths}, Zombie touches {touches}, the rest {deaths - touches}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
