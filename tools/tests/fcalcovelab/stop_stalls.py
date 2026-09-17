#!/usr/bin/env python3
"""stop_stalls.py -- what the party does while a member is under Stop (#221).

    python3 tools/tests/fcalcovelab/stop_stalls.py build/lab/fc-alcove/*/seed*.log

Brainpan's Special is Smirk (`monster_prop` +31 = $54: bit 6 set, so no
damage, status bit $14 = **Stop**).  The fight driver answers a denied
actor's open window by standing its stall counters down and pressing
nothing (`lib/ot6.lua`, the `#187` block: "The engine is about to take the
window away ... or never meant to open one, so nothing here is a stall").

This measures whether that holds for Stop.  For every `[status] ... is
under STOP` line it reports the battle tick it landed on, the tick of the
next `plan=` line any actor produced, and what the party's HP did in
between -- read straight out of the driver's own `battle f+N ... partyhp=`
lines.  A long gap with HP falling is the party standing still while the
monsters keep acting.

A `plan=` line carries no tick of its own, so it is dated by the driver's
last `battle f+N` line before it (they are 300 ticks apart): the gap is
accurate to that sampling, not to the frame.

Read-only; it parses retained logs and runs nothing.
"""
import re
import sys

STOP = re.compile(r"^\[ot6\] \[(\S+)\] \[status\] f\+(\d+) entity (\d) char (\d+) "
                  r"is under STOP")
CLEAR = re.compile(r"^\[ot6\] \[(\S+)\] \[status\] f\+(\d+) entity (\d)'s Stop is CLEARED")
PLAN = re.compile(r"^\[ot6\] \[(\S+)\] actor=(\d) char=(\d+) plan=(\S+)")
BATTLE = re.compile(r"^\[ot6\] \[(\S+)\] battle f\+(\d+) .*partyhp=(\S+) ")
DEATH = re.compile(r"^\[ot6\] \[(\S+)\] \[death\] f\+(\d+) entity (\d) char (\d+) from (\S+) ")
STAGE = re.compile(r"^\[ot6\] \[fcalcovelab\] \[stage\] f\d+ fight(\d+) form=(\S+) mask=")


def scan(path):
    rows, open_stops, form, fight = [], [], "?", 0
    last_hp, last_tick = None, 0
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        m = STAGE.match(line)
        if m:
            fight, form = int(m.group(1)), m.group(2)
            continue
        m = BATTLE.match(line)
        if m:
            last_tick, last_hp = int(m.group(2)), m.group(3)
            for s in open_stops:
                s["hp_end"], s["tick_end"] = last_hp, last_tick
            continue
        m = STOP.match(line)
        if m:
            s = dict(path=path, fight=fight, form=form, tick=int(m.group(2)),
                     entity=int(m.group(3)), char=int(m.group(4)),
                     hp0=last_hp, hp_end=last_hp, tick_end=int(m.group(2)),
                     plan_tick=None, deaths=[])
            open_stops.append(s)
            rows.append(s)
            continue
        m = PLAN.match(line)
        if m:
            for s in open_stops:
                if s["plan_tick"] is None:
                    s["plan_tick"] = last_tick
            open_stops = [s for s in open_stops if s["plan_tick"] is None]
            continue
        m = DEATH.match(line)
        if m:
            for s in open_stops:
                s["deaths"].append("char %s from %s at f+%s"
                                   % (m.group(4), m.group(5), m.group(2)))
            continue
        m = CLEAR.match(line)
        if m:
            for s in open_stops:
                if s["entity"] == int(m.group(3)):
                    s["cleared"] = int(m.group(2))
    return rows


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    total, stalls = 0, 0
    for path in argv:
        rows = scan(path)
        if not rows:
            continue
        print("== %s" % path)
        for s in rows:
            total += 1
            gap = (s["plan_tick"] - s["tick"]) if s["plan_tick"] is not None else None
            if gap is None or gap >= 600:
                stalls += 1
            print("  fight%d %-42s Stop on char %d at f+%-5d -> next plan %s "
                  "(gap %s ticks); partyhp %s -> %s%s"
                  % (s["fight"], s["form"], s["char"], s["tick"],
                     s["plan_tick"] if s["plan_tick"] is not None else "never",
                     gap if gap is not None else "-", s["hp0"], s["hp_end"],
                     ("; deaths inside: " + "; ".join(s["deaths"])) if s["deaths"] else ""))
    print("\n%d Stop landing(s); %d left the party without a plan for 600+ ticks"
          % (total, stalls))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
