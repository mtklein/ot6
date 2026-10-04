#!/usr/bin/env python3
"""audit_zombie_touches.py -- a run log's [death] lines, Zombie touches apart.

A Zombie touch reads as a death.  ZOMBIE lands and the engine's
AfterAction1 (battle_main.asm @069b) zeroes the member's HP, so the fight
driver logs `[status] f+N entity E ... is under ZOMBIE` and
`[death] f+N entity E ...` for the same entity within a frame or two:
the gate cave's on one frame, tomb_zombie's `under ZOMBIE` at f+395 and
its death at f+396 (the review of care-items cae71db9 found the two
counted two ways), so a touch is a death within TOUCH_FRAMES of a ZOMBIE
status line on the same entity.  The member still takes its turns as the
engine's.  The care-policy reviews
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
TOUCH_FRAMES = 2


def is_touch(zomb, frame, entity):
    """Whether a [death] at f+frame on entity is a Zombie touch: a ZOMBIE
    status line on the same entity within TOUCH_FRAMES of it."""
    return any(e == entity and abs(f - frame) <= TOUCH_FRAMES for f, e in zomb)


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
            zomb.add((int(m.group(1)), m.group(2)))
    deaths = touches = 0
    for l in ours:
        m = DEATH.search(l)
        if m:
            deaths += 1
            if is_touch(zomb, int(m.group(1)), m.group(2)):
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
        # tomb_zombie: the status a frame before the death is the same touch
        "[ot6] [navTo] [status] f+395 entity 3 char 9 is under ZOMBIE (STATUS1 $02)",
        "[ot6] [navTo] [death] f+396 entity 3 char 9 from 1698/1698 by slot 1 cmd $00 atk $EF",
        # ...but a ZOMBIE line far from a death is not
        "[ot6] [navTo] [status] f+100 entity 0 char 6 is under ZOMBIE (STATUS1 $02)",
        "[ot6] [navTo] [death] f+500 entity 0 char 6 from 40/1798 by slot 1",
    ]
    d, t = split(lines)
    assert (d, t) == (5, 2), (d, t)
    print("audit_zombie_touches selftest: ok (5 deaths, 2 touches -- one a frame after its status line; "
          "the [ot6note] copies not counted)")


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
