#!/usr/bin/env python3
"""audit_boost.py -- boost left on the table: at every party death, and in
every fizzle (#175, #230).

Owner heuristic (2026-09-07): "when we see a dead party with a bunch of
unused boost pips, it means we've not used the abilities of the characters
to their fullest extent."  And: "it's totally normal to sometimes be wiped
with a one shot attack early in a battle -- that means you're just under
level and need more HP.  But when a party is wiped with 3-4 pips each, it
means we weren't trying our best."

The fight driver (tools/tests/lib/ot6.lua) writes one line per party death
and one per wipe:

    [tag] [death] f+T entity E char C from H/M by slot S cmd $XX atk $YY (ONE ACTION from >= 80%) bp=B party_bp=a,b,c,d
    [tag] [wipe] f+T party_bp=a,b,c,d deaths=e1@f+T:H/M:bpB:one_action;... class=...

and the labs' own ledgers carry `[death] t=T entity E ... bp=B`.  This scans
run logs, lists every death with the pips it was holding, and classifies
every wipe the way the owner reads one:

    one-shot early        a member killed from >= ONE_SHOT_PCT of max HP by
                          one action inside the first EARLY_FRAMES of the
                          battle: a level / HP problem
    died with N BP banked some member fell holding >= BANKED_BP pips: a
                          driver problem first (ot6.lua's spend rule)

Both can hold for one wipe.  A wipe with neither is "worn down".

A FIZZLE is the same finding in its most literal form, and it is counted
here for that reason (#230).  The library writes one line per costed action
the pool could not pay for:

    [fizzle] fT slotS charC Tools($09) atk=$AA boost=3 cost=63 pool=25 -- ...

The turn is gone, the monsters took nothing, and the pips banked into the
boost were burned to buy it -- boost left on the table, spent on nothing.
A run with fizzles has a fighter that pressed R without checking the caster
could pay; the library's one place for that check is M.boostPlan.

    tools/audit_boost.py [--selftest] [logglob ...]

Default scan is audit_fenix's: build/test-runs/*/run.log and
build/states/*.log; audit_fenix.py also runs this report after its own.
The constants match the driver's (ONE_SHOT_PCT, EARLY_TICKS, BANKED_BP in
newFightDriver); a battle tick is one frame of F.frame, so EARLY_FRAMES is
in battle frames.
"""
import glob
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ONE_SHOT_PCT = 80
EARLY_FRAMES = 1800
BANKED_BP = 3

# the driver's line (frame-stamped [ot6note] mirrors are skipped by the scan)
DEATH = re.compile(
    r"\[(?P<tag>[^\]]+)\] \[death\] f\+(?P<tick>\d+) entity (?P<e>\d) char (?P<c>\d+) "
    r"from (?P<from>\d+)/(?P<max>\d+) by (?P<by>.*?)(?P<one> \(ONE ACTION from >= \d+%\))? "
    r"bp=(?P<bp>\d+) party_bp=(?P<pbp>[\d,]+)")
WIPE = re.compile(
    r"\[(?P<tag>[^\]]+)\] \[wipe\] f\+(?P<tick>\d+) party_bp=(?P<pbp>[\d,]+) "
    r"deaths=(?P<deaths>\S+) class=(?P<cls>.*)$")
# the labs' own ledgers: bp only (the driver's line, when the lab runs the
# driver, is in the same log and carries the rest)
LAB_DEATH = re.compile(r"\[death\] (?:t=|f)(?P<t>\d+) entity (?P<e>\d).*?\bbp=(?P<bp>\d+)")
# a battle opening, to group deaths into fights: the driver's f+1 line, or a
# lab's battle-up line when no driver ran
DRIVER_UP = re.compile(r"\] battle f\+1 ")
LAB_UP = re.compile(r"\[lab\] battle up|\[m269lab\] battle up|battle-up present mask")
# a wipe the driver did not write itself (the gen fighter, a lab's own
# verdict, the canary)
LAB_WIPE = re.compile(r"PARTY WIPED|\[m269lab\] WIPED|canary: BATTLE WIPE|outcome=lost_wiped|outcome=lost_gameover")
# the library's loud-fizzle line (#230), written by every run
FIZZLE = re.compile(
    r"\[fizzle\] f(?P<f>\d+) slot(?P<slot>\d) char(?P<c>\d+) "
    r"(?P<verb>\S+)\(\$(?P<cmd>[0-9A-F]{2})\) atk=\$(?P<atk>[0-9A-F]{2}) "
    r"boost=(?P<bp>\d+) cost=(?P<cost>\d+) pool=(?P<pool>\d+)")


def worker_of(path):
    d = os.path.basename(os.path.dirname(path))
    if d == "states":
        return os.path.basename(path)[:-4]
    if d in ("m269lab", "rizopaslab", "nerapalab", "zozolab", "thamlab"):
        return d + "/" + os.path.basename(path)[:-4]
    return d.split(".")[0]


def classify(deaths, one_pct=ONE_SHOT_PCT, early=EARLY_FRAMES, banked=BANKED_BP):
    """The owner's reading of one wipe from its death records
    (dicts with tick, from, max, bp, one_action)."""
    if not deaths:
        return "no deaths recorded"
    one_shot = any(d.get("one_action") and d["tick"] <= early and d["max"] > 0
                   and d["from"] * 100 // d["max"] >= one_pct for d in deaths)
    held = max((d["bp"] for d in deaths if d["bp"] >= banked), default=0)
    parts = []
    if one_shot:
        parts.append("one-shot early")
    if held:
        parts.append(f"died with {held} BP banked")
    return " + ".join(parts) if parts else "worn down (no one-shot, no pips banked)"


def scan(path):
    """Yield ('death', rec) and ('wipe', rec) events from one log, in order."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return
    worker = worker_of(path)
    fight = 0
    deaths = []            # this fight's death records
    seen_driver = set()    # entities the driver already wrote, so a lab line is not a second death
    # Fights are counted by the driver's own "battle f+1" line when the log
    # has one; a lab's battle-up line names the same fight (hundreds of
    # CPU-spam lines apart) and is only used when no driver ran (the
    # Rizopas control is gen_sabin_falls' own fighter).
    has_driver = any(DRIVER_UP.search(l) for l in lines if not l.startswith("[ot6note]"))
    up = DRIVER_UP if has_driver else LAB_UP
    for line in lines:
        if line.startswith("[ot6note]"):
            continue
        if up.search(line):
            fight += 1
            deaths, seen_driver = [], set()
            continue
        m = DEATH.search(line)
        if m:
            rec = dict(worker=worker, fight=fight, tag=m["tag"], tick=int(m["tick"]),
                       e=int(m["e"]), char=int(m["c"]), frm=int(m["from"]),
                       max=int(m["max"]), by=m["by"], one_action=bool(m["one"]),
                       bp=int(m["bp"]), party_bp=m["pbp"], source="driver")
            rec["from"] = rec["frm"]
            deaths.append(rec)
            seen_driver.add(rec["e"])
            yield "death", rec
            continue
        m = WIPE.search(line)
        if m:
            yield "wipe", dict(worker=worker, fight=fight, tag=m["tag"], tick=int(m["tick"]),
                               party_bp=m["pbp"], deaths=list(deaths), cls=m["cls"],
                               source="driver")
            deaths = []
            continue
        m = FIZZLE.search(line)
        if m:
            yield "fizzle", dict(worker=worker, fight=fight, f=int(m["f"]),
                                 slot=int(m["slot"]), char=int(m["c"]),
                                 verb=m["verb"], cmd=int(m["cmd"], 16),
                                 atk=int(m["atk"], 16), bp=int(m["bp"]),
                                 cost=int(m["cost"]), pool=int(m["pool"]))
            continue
        m = LAB_DEATH.search(line)
        if m and "[death] f+" not in line:
            if int(m["e"]) in seen_driver:
                continue        # the driver's own line already counted it
            rec = dict(worker=worker, fight=fight, tag="lab", tick=int(m["t"]),
                       e=int(m["e"]), char=-1, frm=-1, max=0, by="?",
                       one_action=False, bp=int(m["bp"]), party_bp="?", source="lab")
            rec["from"] = rec["frm"]
            deaths.append(rec)
            yield "death", rec
            continue
        if LAB_WIPE.search(line) and deaths:
            yield "wipe", dict(worker=worker, fight=fight, tag="lab", tick=-1,
                               party_bp="?", deaths=list(deaths), cls=classify(deaths),
                               source="lab")
            deaths = []


def fizzle_report(fizzles, nlogs):
    """The most literal boost left on the table (#230): a costed action the
    pool could not pay for, which burned the turn and the pips banked into
    it and bought nothing."""
    if not fizzles:
        print(f"Fizzle audit: no costed action was refused for MP in the "
              f"scanned logs ({nlogs} logs).")
        return
    bp = sum(z["bp"] for z in fizzles)
    print(f"Fizzle audit: {len(fizzles)} costed action(s) refused for MP, "
          f"{bp} boost point(s) burned on them, across {nlogs} logs.  A "
          f"fizzle is a fighter that pressed R without checking the caster "
          f"could pay (the check is M.boostPlan, lib/ot6.lua).")
    print()
    print(f"{'segment':34} {'f':>8} {'ent':>3} {'char':>4} {'verb':>8} "
          f"{'atk':>4} {'boost':>5} {'cost':>5} {'pool':>5}")
    for z in fizzles:
        print(f"{z['worker'][:34]:34} {z['f']:>8} {z['slot']:>3} {z['char']:>4} "
              f"{z['verb']:>8} {'$%02X' % z['atk']:>4} {z['bp']:>5} "
              f"{z['cost']:>5} {z['pool']:>5}")
    per = defaultdict(lambda: [0, 0])
    for z in fizzles:
        per[z["worker"]][0] += 1
        per[z["worker"]][1] += z["bp"]
    print()
    print(f"{'segment':34} {'fizzles':>7} {'bp':>4}  why")
    for k, (n, b) in sorted(per.items(), key=lambda kv: -kv[1][0]):
        print(f"{k[:34]:34} {n:>7} {b:>4}  turns and pips spent on actions "
              "the pool could not pay for")
    print()


def report(paths):
    deaths, wipes, fizzles = [], [], []
    for p in sorted(paths):
        for kind, rec in scan(p):
            {"death": deaths, "wipe": wipes, "fizzle": fizzles}[kind].append(rec)
    fizzle_report(fizzles, len(paths))
    if not deaths and not wipes:
        print(f"Boost audit: no party deaths in the scanned logs ({len(paths)} logs).")
        return
    banked = [d for d in deaths if d["bp"] >= BANKED_BP]
    print(f"Boost audit: {len(deaths)} party death(s), {len(banked)} holding "
          f">= {BANKED_BP} BP, {len(wipes)} wipe(s) across {len(paths)} logs.")
    print()
    print(f"{'segment':34} {'fight':>5} {'f+':>6} {'ent':>3} {'from':>9} {'bp':>2} {'party_bp':>8}  by")
    for d in deaths:
        frm = f"{d['from']}/{d['max']}" if d["max"] else "?"
        flag = " <- banked" if d["bp"] >= BANKED_BP else ""
        print(f"{d['worker'][:34]:34} {d['fight']:>5} {d['tick']:>6} {d['e']:>3} {frm:>9} "
              f"{d['bp']:>2} {d['party_bp']:>8}  {d['by']}{' ONE ACTION' if d['one_action'] else ''}{flag}")
    if wipes:
        print()
        print("wipes:")
        for w in wipes:
            ds = ";".join(f"e{d['e']}@f+{d['tick']}:{d['from']}/{d['max']}:bp{d['bp']}"
                          f"{':one_action' if d['one_action'] else ''}" for d in w["deaths"])
            print(f"  {w['worker']} fight {w['fight']} f+{w['tick']} party_bp={w['party_bp']} "
                  f"-> {w['cls']}  [{ds or 'no deaths recorded'}]")
    per = defaultdict(lambda: [0, 0])
    for d in deaths:
        per[d["worker"]][0] += 1
        if d["bp"] >= BANKED_BP:
            per[d["worker"]][1] += 1
    flagged = {k: v for k, v in per.items() if v[1]}
    if flagged:
        print()
        print(f"{'segment':34} {'deaths':>6} {'banked':>6}  why")
        for k, (n, b) in sorted(flagged.items(), key=lambda kv: -kv[1][1]):
            print(f"{k[:34]:34} {n:>6} {b:>6}  died holding >= {BANKED_BP} BP -- the driver "
                  "left boost on the table (ot6.lua spend rule)")


def selftest():
    import tempfile
    log = "\n".join([
        "[ot6] [navTo] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:555/sh2 monsters=3",
        "[ot6] [navTo] [death] f+512 entity 2 char 1 from 447/447 by slot 4 cmd $0C atk $95 (ONE ACTION from >= 80%) bp=1 party_bp=1,1,1,1",
        "[ot6] [navTo] [death] f+513 entity 3 char 6 from 443/443 by slot 4 cmd $0C atk $95 (ONE ACTION from >= 80%) bp=0 party_bp=1,1,1,0",
        "[ot6note] f513 [navTo] [death] f+513 entity 3 char 6 from 443/443 by slot 4 cmd $0C atk $95 (ONE ACTION from >= 80%) bp=0 party_bp=1,1,1,0",
        "[ot6] [navTo] [death] f+3000 entity 0 char 4 from 120/502 by slot 3 cmd $00 atk $EE bp=4 party_bp=4,3,0,0 -- died holding 4 BP",
        "[ot6] [navTo] [death] f+3100 entity 1 char 5 from 60/511 by slot 3 cmd $00 atk $EE bp=3 party_bp=0,3,0,0 -- died holding 3 BP",
        "[ot6] [navTo] [wipe] f+3101 party_bp=0,3,0,0 deaths=e2@f+512:447/447:bp1:one_action;e3@f+513:443/443:bp0:one_action;e0@f+3000:120/502:bp4;e1@f+3100:60/511:bp3 class=one-shot early + died with 4 BP banked",
        # the library's loud-fizzle line (#230), verbatim from a descent
        # control run: EDGAR's boosted crossbow against a 25 MP pool
        "[ot6] [fizzle] f36110 slot1 char4 Tools($09) atk=$AA boost=2 cost=25 pool=21 -- the pool could not pay it: CalcAttackEffect refused the action, the turn and 2 boost point(s) are gone and the pool is still 21.  Pressing R is a claim the caster can pay (M.boostPlan, #230).",
        "[ot6note] f36110 [fizzle] f36110 slot1 char4 Tools($09) atk=$AA boost=2 cost=25 pool=21 -- the pool could not pay it: CalcAttackEffect refused the action, the turn and 2 boost point(s) are gone and the pool is still 21.  Pressing R is a claim the caster can pay (M.boostPlan, #230).",
    ])
    # a lab whose fighter is not the driver (the Rizopas control): the lab's
    # own battle-up, death and wipe lines are all there is
    lab = "\n".join([
        "[ot6] [lab] battle up at f100: $BE=$64",
        "[ot6] [death] t=5583 entity 1 rizo=553/sh1 bp=0 party_bp=1,0",
        "[ot6] [death] t=6500 entity 0 rizo=553/sh1 bp=1 party_bp=1,0",
        "[ot6] [falls] LOST -- x: PARTY WIPED at f9000 (tier 1) [0/363 0/358]",
    ])
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "states", "x.log")
        os.makedirs(os.path.dirname(p))
        open(p, "w").write(log + "\n")
        q = os.path.join(d, "states", "y.log")
        open(q, "w").write(lab + "\n")
        ev = list(scan(p)) + list(scan(q))
    deaths = [r for k, r in ev if k == "death"]
    wipes = [r for k, r in ev if k == "wipe"]
    fizzles = [r for k, r in ev if k == "fizzle"]
    # the [ot6note] mirror is not a second fizzle
    assert len(fizzles) == 1, fizzles
    assert fizzles[0]["verb"] == "Tools" and fizzles[0]["cmd"] == 0x09
    assert fizzles[0]["atk"] == 0xAA and fizzles[0]["bp"] == 2
    assert fizzles[0]["cost"] == 25 and fizzles[0]["pool"] == 21
    assert len(deaths) == 6, deaths                    # the [ot6note] mirror is not a seventh
    assert [d["bp"] for d in deaths] == [1, 0, 4, 3, 0, 1], [d["bp"] for d in deaths]
    assert deaths[0]["one_action"] and deaths[0]["from"] == 447
    assert not deaths[2]["one_action"]
    assert len(wipes) == 2, wipes
    assert wipes[0]["cls"] == "one-shot early + died with 4 BP banked", wipes[0]["cls"]
    assert classify(wipes[0]["deaths"]) == wipes[0]["cls"]   # the python reading agrees with the lua one
    assert wipes[1]["source"] == "lab" and wipes[1]["cls"] == "worn down (no one-shot, no pips banked)", wipes[1]
    assert wipes[1]["fight"] == 1 and len(wipes[1]["deaths"]) == 2
    # the thresholds: a one-shot late in the fight is not "early"; 2 BP is not banked
    late = [dict(tick=5000, **{"from": 447}, max=447, bp=2, one_action=True)]
    assert classify(late) == "worn down (no one-shot, no pips banked)", classify(late)
    assert classify([]) == "no deaths recorded"
    print("audit_boost selftest ok")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--selftest":
        selftest()
        return
    globs = args or [
        os.path.join(ROOT, "build/test-runs/*/run.log"),
        os.path.join(ROOT, "build/states/*.log"),
    ]
    paths = []
    for g in globs:
        paths.extend(glob.glob(g))
    report(paths)


if __name__ == "__main__":
    main()
