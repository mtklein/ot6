#!/usr/bin/env python3
"""audit_fenix.py -- Fenix Downs as a proxy for under-leveling / a missing
fight strategy (#154).

Owner heuristic: more than 1-2 Fenix Downs in a hard (boss/set-piece)
fight, or ANY in a random battle, means the party is under-leveled or that
fight needs a strategy lab.  This scans run logs, counts every Fenix Down
that RESOLVED, attributes it to the fight it answered, classifies that
fight as BOSS or RANDOM, and flags the violations -- a countable
lab/level-candidate list.

    tools/audit_fenix.py [--since <when>] [--newer <file>] [-v] [logglob ...]
    tools/audit_fenix.py --selftest

WHAT COUNTS (a Fenix Down that resolved, nothing else):

  * a field-care revival: the care stop's own
      `[care after battle (worldNavTo)] used $F0 on char 5: 0 -> 50 hp, ...`
    line, written by lib/ot6_field.lua only once the item landed;
  * an in-battle revival, from the recovery action trace when the run
    carried one (`[ot6action] {... "event":"resolve", "kind":"item",
    "requested":240 ...}`, item $F0), and otherwise from the fight
    driver's own landing line
      `[worldNavTo] actor 1's Fenix Down landed: entity 0 is at 55/447 ...`
    which it writes when the raised member's HP moves off 0.  A traced log
    is read from its trace only, so the two never double-count.

Shop lines ("row 5 is Fenix Down = 240"), bag counts ("fenix=15"), the
driver's plan line ("revive entity 1 with Fenix Down: raise to ...") and a
Fenix that never landed are not uses.  The frame-stamped `[ot6note]`
mirror of the `[ot6]` stream is skipped.

WHICH FIGHT: an in-battle use belongs to the driver tag on its line; a
care-stop revival belongs to the nearest preceding `[<tag>] battle f+1`
line in the same attempt -- the fight that killed the member -- not to
the care tag (a post-boss field care used to read as "Fenix in randoms").

WHICH LOGS: every log is its own segment (build/states/cuts/x.log is
`cuts/x`, never folded into its directory), and a retried run is split at
its `[retry] attempt n/N FAILED` lines so each attempt's Fenix is counted
on its own, with the verdict's attempts=n/N beside it.  The default scan
is the CURRENT state logs only: build/states/<state>.log for every state
in tools/tests/savestate_graph.py.  Name globs to scan anything else
(build/test-runs/*/run.log, build/states/cuts/*.log, a sweep directory);
--since 2h / --since 2026-09-16 / --newer <file> keep only logs written
since then.

A fight is BOSS when its driver tag is a bespoke set-piece driver or a
spared/event formation; RANDOM when it is ordinary traversal (navTo /
worldNavTo / advanceStory / rideOut / a world walk); `?` otherwise.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FENIX_ID = 0xF0

# the three resolved-revive signals
CARE_USED = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] used \$F0 on char (?P<char>\d+): "
                       r"(?P<from>\d+) -> (?P<to>\d+) hp")
LANDED = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] actor (?P<actor>\d+)'s Fenix Down landed: "
                    r"entity (?P<e>\d+) is at (?P<hp>\d+)/(?P<max>\d+)")
TRACE = "[ot6action] "
# the fight a care stop follows: the driver's own f+1 line
BATTLE_UP = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] battle f\+1 ")
# the attempt boundaries and the verdict (tools/audit_retries.py's shapes)
ATTEMPT_FAILED = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) FAILED class=(\S+)")
RUNNER = re.compile(r"^\[ot6\] \[retry\] segment runner: \S+, up to (\d+) attempt")
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)(?: attempts=(\d+)/(\d+))?")
FAIL = re.compile(r"^\[ot6\] FAIL: ")

# bespoke set-piece / boss driver tags (extend as the route grows)
BOSS_HINT = re.compile(
    r"\bb\d+\b|FlameEater|ambush|Ultros|Kefka|Vargas|Whelk|Dadaluma|TunnelArmr|"
    r"Ifrit|Shiva|Number|Cranes|Atma|pursuit|boss|magitek|"
    r"\bIAF\b|Nerapa|Rizopas|Leader|Guardian", re.I)
# ordinary traversal drivers.  NOT "care after"/"care before": a care stop
# is attributed to the fight before it (#154, third defect).
RANDOM_HINT = re.compile(
    r"navTo|worldNavTo|advanceStory|rideOut|the ride|climb|cross|ledge|"
    r"world walk|world grind|followPath|Follow\b|phaseWalk|trash|"
    r"ride battle|rafters|draw \d+-win", re.I)


def classify(tag):
    """BOSS / RANDOM / '?' from the driver tag a use is attributed to."""
    if tag is None:
        return "?"
    if BOSS_HINT.search(tag):
        return "BOSS"
    if RANDOM_HINT.search(tag):
        return "RANDOM"
    return "?"


def segment_of(path):
    """The log's own name: build/states/x.log -> x, build/states/cuts/x.log
    -> cuts/x, build/test-runs/<ws>/run.log -> test-runs/<ws>/run.  Relative
    to the nearest `states` or `build` directory above it, so another
    tree's logs read the same way."""
    path = os.path.abspath(path)
    name = path[:-4] if path.endswith(".log") else path
    d = os.path.dirname(path)
    while d and d != os.path.dirname(d):
        if os.path.basename(d) in ("states", "build"):
            return os.path.relpath(name, d)
        d = os.path.dirname(d)
    return name


def scan(path):
    """One log -> (uses, attempts) where uses is a list of dicts
    (attempt, line, fight, cls, kind, text) and attempts is the verdict's
    n/N (or the count seen when the log has no verdict)."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return [], "?"
    traced = any(l.startswith(TRACE) for l in lines)
    uses = []
    attempt, max_attempts = 1, None
    last_battle = None          # the most recent [tag] battle f+1 in this attempt
    verdict = None
    for i, line in enumerate(lines, 1):
        if line.startswith("[ot6note]"):
            continue
        m = RUNNER.match(line)
        if m:
            max_attempts = int(m.group(1))
            continue
        m = ATTEMPT_FAILED.match(line)
        if m:
            attempt = int(m.group(1)) + 1
            max_attempts = int(m.group(2))
            last_battle = None
            continue
        m = PASS.match(line)
        if m:
            verdict = (f"{m.group(2)}/{m.group(3)}" if m.group(2)
                       else f"1/{max_attempts or 1}")
            continue
        if FAIL.match(line):
            # the attempt counter already stepped past the last FAILED line
            verdict = f"{min(attempt, max_attempts or attempt)}/{max_attempts or attempt}"
            continue
        m = BATTLE_UP.match(line)
        if m:
            last_battle = m.group("tag")
            continue
        m = CARE_USED.match(line)
        if m:
            tag = m.group("tag")
            # a care stop's revival is the preceding fight's Fenix; any
            # other tag using $F0 outside a battle is its own driver
            fight = last_battle if tag.startswith("care ") else tag
            uses.append(dict(attempt=attempt, line=i, fight=fight,
                             cls=classify(fight), kind="care", text=line))
            continue
        if line.startswith(TRACE):
            try:
                e = json.loads(line[len(TRACE):])
            except ValueError:
                continue
            if (e.get("event") == "resolve" and e.get("kind") == "item"
                    and e.get("requested") == FENIX_ID):
                fight = e.get("tag") or last_battle
                uses.append(dict(attempt=attempt, line=i, fight=fight,
                                 cls=classify(fight), kind="battle", text=line))
            continue
        m = LANDED.match(line)
        if m and not traced:
            fight = m.group("tag")
            uses.append(dict(attempt=attempt, line=i, fight=fight,
                             cls=classify(fight), kind="battle", text=line))
    if verdict is None:
        verdict = f"{attempt}/{max_attempts or '?'} (no verdict)"
    return uses, verdict


def parse_since(s):
    """'2h', '30m', '3d' (ago), or an ISO date/time -> a POSIX timestamp."""
    m = re.fullmatch(r"(\d+)([mhd])", s)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        secs = n * {"m": 60, "h": 3600, "d": 86400}[unit]
        return dt.datetime.now().timestamp() - secs
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M", "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%d %H:%M"):
        try:
            return dt.datetime.strptime(s, fmt).timestamp()
        except ValueError:
            pass
    raise SystemExit(f"--since: cannot read '{s}' (want 2h / 3d / 2026-09-16 / 2026-09-16T13:00)")


def current_state_logs():
    """build/states/<state>.log for every state the graph generates."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "tests"))
    from savestate_graph import STATES
    names = []
    for e in STATES:
        names.append(e["state"])
        names.extend(e.get("also") or [])
    paths = [os.path.join(ROOT, "build", "states", n + ".log") for n in names]
    return [p for p in paths if os.path.exists(p)]


def select_logs(globs, since=None, newer=None):
    if globs:
        paths = []
        for g in globs:
            paths.extend(glob.glob(g))
    else:
        paths = current_state_logs()
    cutoff = since
    if newer:
        t = os.path.getmtime(newer)
        cutoff = max(cutoff, t) if cutoff else t
    if cutoff:
        paths = [p for p in paths if os.path.getmtime(p) > cutoff]
    return sorted(set(paths))


def report(paths, verbose=False):
    rows = {}                     # (segment, attempt) -> {cls: n}
    verdicts = {}                 # segment -> attempts n/N
    detail = []
    for p in paths:
        seg = segment_of(p)
        uses, verdict = scan(p)
        verdicts[seg] = verdict
        for u in uses:
            rows.setdefault((seg, u["attempt"]), defaultdict(int))[u["cls"]] += 1
            detail.append((seg, u))

    flagged = []
    for (seg, attempt), tally in sorted(rows.items()):
        for cls, n in tally.items():
            boss = cls == "BOSS"
            violation = (boss and n > 2) or (cls == "RANDOM" and n >= 1)
            if violation or (cls == "?" and n > 2):
                flagged.append((seg, attempt, n, cls))

    total = sum(n for t in rows.values() for n in t.values())
    if not flagged:
        print(f"Fenix audit: no threshold violations in the scanned logs "
              f"({len(paths)} logs, {total} Fenix Down(s) resolved).")
    else:
        print(f"Fenix audit: {len(flagged)} flagged segment/kind(s) "
              f"(>2 Fenix in a boss, or any in a random) across {len(paths)} "
              f"logs, {total} Fenix Down(s) resolved.\n")
        print(f"{'segment':28} {'attempt':>7} {'fenix':>5}  {'kind':7} why")
        for seg, attempt, n, cls in sorted(flagged, key=lambda x: (-x[2], x[0], x[1])):
            why = ("boss burned >2 -- underleveled or needs a strategy lab"
                   if cls == "BOSS"
                   else "Fenix in randoms -- underleveled or lab these encounters"
                   if cls == "RANDOM"
                   else "review: classify boss vs random")
            att = f"{attempt}/{verdicts[seg].split('/')[1].split()[0]}" \
                if "/" in verdicts[seg] else str(attempt)
            print(f"{seg[:28]:28} {att:>7} {n:>5}  {cls:7} {why}")
    used = sorted({seg for seg, _ in rows})
    if used:
        print()
        print("per log (attempts=n/N is the verdict's; a use is listed under the "
              "attempt it happened in):")
        for seg in used:
            parts = []
            for (s, attempt), tally in sorted(rows.items()):
                if s != seg:
                    continue
                kinds = ", ".join(f"{cls} {n}" for cls, n in sorted(tally.items()))
                parts.append(f"attempt {attempt}: {kinds}")
            print(f"  {seg}: attempts={verdicts[seg]}; " + "; ".join(parts))
    if verbose and detail:
        print()
        print("every resolved Fenix Down (segment attempt line fight kind: the log line):")
        for seg, u in detail:
            print(f"  {seg} a{u['attempt']} L{u['line']} [{u['fight'] or '?'}] "
                  f"{u['cls']} {u['kind']}: {u['text'][:160]}")
    # The sibling audit (#175): boost left on the table at every death and
    # the classification of every wipe, over the same logs.  Wherever the
    # Fenix audit runs, this runs beside it.
    import audit_boost
    print()
    audit_boost.report(paths)


def selftest():
    import tempfile
    untraced = "\n".join([
        "[ot6] [retry] segment runner: gen_x, up to 3 attempt(s), seed shift 0, watchdogs ON (no-effect 300 frames, no-progress 1800)",
        # the lines the first version counted as uses: none of these is one
        "[ot6] ok: shop 12 row 5 is Fenix Down = 240",
        "[ot6] [shop] FENIX DOWN to 15: already there (0 wanted); skipping",
        "[ot6] [transit a1 care 2] done: c2 331/358 hp 96/96 mp | tonic=67 potion=21 fenix=15 antidote=4 soft=2 remedy=1",
        "[ot6] ok: the party leaves Mobliz with Fenix Downs -- a death is answerable now = true",
        # a boss fight, then a care stop that raises the member it killed:
        # the boss's Fenix, not a random's
        "[ot6] [b70] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:555/sh2 monsters=1",
        "[ot6] [b70] [death] f+512 entity 2 char 1 from 447/447 by slot 4 cmd $0C atk $95 (ONE ACTION from >= 80%) bp=1 party_bp=1,1,1,1",
        "[ot6] [care after battle (b70)] used $F0 on char 1: 0 -> 55 hp, status1 80 -> 00, 14 left",
        "[ot6note] 9000 [care after battle (b70)] used $F0 on char 1: 0 -> 55 hp, status1 80 -> 00, 14 left",
        # a random, an in-battle plan that landed (one use), and a care stop
        "[ot6] [worldNavTo] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:288/sh2 monsters=1",
        "[ot6] [worldNavTo] actor=1 revive entity 0 with Fenix Down: raise to 55 HP (1/8 of 447), the living enemy's smallest hit 175",
        "[ot6] [worldNavTo] actor 1's Fenix Down landed: entity 0 is at 55/447 at tick 5017 -- a top-up is owed (the care budget opens for it)",
        "[ot6] [care after battle (worldNavTo)] used $F0 on char 4: 0 -> 44 hp, status1 80 -> 00, 13 left",
        # a Fenix confirmed but never landed is not a use
        "[ot6] [worldNavTo] actor 2's Fenix Down on entity 3 never landed (840 ticks) -- forgetting it",
        # a care stop with no fight before it in this attempt is unattributed
        "[ot6] [retry] attempt 1/3 FAILED class=wipe frame=9000 totalframes=9000 shift=0 phase=1: GAME OVER fired",
        "[ot6] [care before the climb] used $F0 on char 5: 0 -> 63 hp, status1 80 -> 00, 11 left",
        "[ot6] [IAF] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:555/sh2 monsters=3",
        "[ot6] [care between IAF waves] used $F0 on char 6: 0 -> 55 hp, status1 80 -> 00, 10 left",
        "[ot6] PASS (frame 20000) attempts=2/3",
    ])
    traced = "\n".join([
        "[ot6] [retry] segment runner: gen_y, up to 3 attempt(s), seed shift 0, watchdogs ON (no-effect 300 frames, no-progress 1800)",
        "[ot6] [b70] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:555/sh2 monsters=1",
        '[ot6action] {"actor":1,"event":"plan","frame":100,"id":1,"kind":"item","reason":"revive","requested":240,"tag":"b70","target":2,"v":1}',
        '[ot6action] {"actor":1,"all":false,"attack":240,"boost":0,"bp_net":0,"command":1,"elapsed_frames":603,"event":"resolve","execution_frames":242,"frame":4980,"hp_net":"0,0,55,0","id":1,"kind":"item","mp_net":0,"requested":240,"tag":"b70","target":2,"targets":4,"v":1}',
        # the driver's landing line for the SAME Fenix: the trace already counted it
        "[ot6] [b70] actor 1's Fenix Down landed: entity 2 is at 55/447 at tick 600 -- a top-up is owed (the care budget opens for it)",
        # a Potion resolving is not a Fenix
        '[ot6action] {"actor":1,"all":false,"attack":233,"boost":0,"bp_net":0,"command":1,"elapsed_frames":742,"event":"resolve","execution_frames":239,"frame":6180,"hp_net":"0,0,0,100","id":3,"kind":"item","mp_net":0,"requested":233,"tag":"b70","target":3,"targets":8,"v":1}',
        # a plan for a Fenix that was dropped is not a use
        '[ot6action] {"actor":2,"event":"plan","frame":7000,"id":4,"kind":"item","reason":"revive","requested":240,"tag":"b70","target":0,"v":1}',
        '[ot6action] {"actor":2,"elapsed_frames":40,"event":"drop","frame":7040,"id":4,"reason":"new_plan","v":1}',
        "[ot6] PASS (frame 9000) attempts=1/3",
    ])
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "states", "cuts"))
        p = os.path.join(d, "states", "x.log")
        open(p, "w").write(untraced + "\n")
        q = os.path.join(d, "states", "cuts", "y.log")
        open(q, "w").write(traced + "\n")
        uses, verdict = scan(p)
        tuses, tverdict = scan(q)
        # --since / --newer selection
        os.utime(p, (1_000_000, 1_000_000))
        newer = select_logs([os.path.join(d, "states", "*.log"),
                             os.path.join(d, "states", "cuts", "*.log")], newer=p)
    # the untraced log: 4 uses -- b70 care (BOSS), the landed random raise
    # (RANDOM), its care stop (RANDOM), the IAF between-waves care (BOSS);
    # the unattributed care before any fight is '?'
    got = [(u["attempt"], u["fight"], u["cls"], u["kind"]) for u in uses]
    want = [(1, "b70", "BOSS", "care"),
            (1, "worldNavTo", "RANDOM", "battle"),
            (1, "worldNavTo", "RANDOM", "care"),
            (2, None, "?", "care"),
            (2, "IAF", "BOSS", "care")]
    assert got == want, got
    assert verdict == "2/3", verdict
    # the [ot6note] mirror was not a sixth; the shop/bag lines were none
    assert len(uses) == 5, len(uses)
    # the traced log: exactly one Fenix, from the trace; the landing line
    # and the dropped plan add nothing; the Potion is not one
    tgot = [(u["attempt"], u["fight"], u["cls"], u["kind"]) for u in tuses]
    assert tgot == [(1, "b70", "BOSS", "battle")], tgot
    assert tverdict == "1/3", tverdict
    # keys: a cuts/ log is its own segment
    assert segment_of(os.path.join(ROOT, "build/states/cuts/y.log")) == "cuts/y"
    assert segment_of(os.path.join(ROOT, "build/states/zozo_arrival.log")) == "zozo_arrival"
    assert segment_of(os.path.join(ROOT, "build/test-runs/fc_landing.abc/run.log")) \
        == "test-runs/fc_landing.abc/run"
    # --newer kept only the log written after p
    assert [os.path.basename(n) for n in newer] == ["y.log"], newer
    # a care tag alone is no longer a random
    assert classify("care after battle (worldNavTo)") == "RANDOM"   # by its fight, when that is all we have
    assert classify("care before the climb") == "RANDOM"           # 'climb' is traversal
    assert classify("b72") == "BOSS" and classify("Kefka vs Leo") == "BOSS"
    assert classify("world walk -> Jidoor approach (27,129)") == "RANDOM"
    assert classify("healerdown") == "?"
    # --since shapes
    now = dt.datetime.now().timestamp()
    assert now - 7200 - 5 < parse_since("2h") < now - 7200 + 5
    assert parse_since("2026-09-16") == dt.datetime(2026, 9, 16).timestamp()
    print("audit_fenix selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("globs", nargs="*", help="log globs (default: the current "
                    "state logs, build/states/<state>.log per graph state)")
    ap.add_argument("--since", help="keep logs written since: 2h, 3d, 2026-09-16, "
                    "2026-09-16T13:00")
    ap.add_argument("--newer", help="keep logs written after this file (find -newer)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="list every resolved Fenix Down with its log line")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    since = parse_since(args.since) if args.since else None
    paths = select_logs(args.globs, since=since, newer=args.newer)
    report(paths, verbose=args.verbose)


if __name__ == "__main__":
    main()
