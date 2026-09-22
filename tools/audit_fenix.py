#!/usr/bin/env python3
"""audit_fenix.py -- Fenix Downs as a proxy for under-leveling / a missing
fight strategy (#154, #220).

Owner heuristic: more than 1-2 Fenix Downs in a hard (boss/set-piece)
fight, or ANY in a random battle, means the party is under-leveled or that
fight needs a strategy lab.  This scans run logs, counts every Fenix Down
the bags paid for and every one that raised somebody, attributes each to
the fight it answered, classifies that fight as BOSS or RANDOM, and flags
the violations -- a countable lab/level-candidate list.

    tools/audit_fenix.py [--since <when>] [--newer <file>] [-v] [logglob ...]
    tools/audit_fenix.py --selftest

WHAT COUNTS.  Two counts, side by side, because they disagree exactly when
it matters (#220: the v0.18 qualification reported 5 across 53 logs while
the bags fell by 14):

  * LANDED -- a revive that resolved: a care stop's own
      `[care after battle (worldNavTo)] used $F0 on char 5: 0 -> 50 hp, ...`
    line, written by lib/ot6_field.lua only once the item landed; an
    in-battle revive from the recovery action trace when the run carried
    one (`[ot6action] {... "event":"resolve", "kind":"item",
    "requested":240 ...}`, item $F0), and otherwise the fight driver's own
      `[worldNavTo] actor 1's Fenix Down landed: entity 0 is at 55/447 ...`
    which it writes when the raised member's HP moves off 0.  A traced log
    is read from its trace only, so the two never double-count.

  * LEFT THE BAG -- the running count the logs already print, read at
    every `fenix=<n>` field (care and shop lines, a driver's own bag line)
    and at the `<n> left` tail of a care use; every drop within an attempt
    is Fenix the bag paid for, whether or not anybody rose.  A retry
    reloads its checkpoint and restores the bag, so each attempt starts
    its own baseline and a refill never reads as a negative spend.

  * NEVER LANDED -- a Fenix the driver confirmed and gave up on
    (`actor 1's Fenix Down on entity 2 never landed (841 ticks)`): the bag
    paid, nobody rose.  Thrown at a Zombied member (#190), or into a fight
    already lost.  Each is listed by name; the bag delta counts it.

The threshold test runs on whichever of the two counts is larger for the
fight: a boss the bags paid 8 into is flagged even when nobody rose.  Shop
lines ("row 5 is Fenix Down = 240"), the driver's plan line ("revive entity
1 with Fenix Down: raise to ...") and a custom driver's plan line ("revive:
e0 is down -- FENIX DOWN") are not uses.  The frame-stamped `[ot6note]`
mirror of the `[ot6]` stream is skipped.

WHICH FIGHT: an in-battle use belongs to the driver tag on its line; a
`used $F0` line is a field-care stop whatever its tag (`care after battle
(navTo)`, `fc-care r10`, `post-train care`) and its Fenix, like every bag
drop seen outside a battle, belongs to the nearest preceding
`[<tag>] battle f+1` line in the same attempt -- the fight that killed the
member -- not to the care tag (a post-boss field care used to read as
"Fenix in randoms").  A fight the audit never saw open (no `battle f+1`
line before the care stop) leaves its Fenix unattributed, kind `?`.  The
custom set-piece drivers (the Ghost Train, Vargas, the Whelk, ...) write
that line and the lib driver's `[death]` line themselves since #220, so a
death in one of those fights and the Fenix that answered it are both
visible; the deaths seen in a fight are printed beside a bag drop no
landing line accounts for.

WHICH LOGS: every log is its own segment (build/states/cuts/x.log is
`cuts/x`, never folded into its directory), and a retried run is split at
its `[retry] attempt n/N FAILED` lines so each attempt's Fenix is counted
on its own, with the verdict's attempts=n/N beside it.  A ninja log (a
retained qualification run under build/attempts) holds every edge's run
output after that edge's `[k/N] generate <state> <- <gen>` line, so it is
split into one segment per edge, `<log>:<state>`; edges with no run
output (latches, checks) are dropped.  The default scan is the CURRENT
state logs only: build/states/<state>.log for every state in
tools/tests/savestate_graph.py.  Name globs to scan anything else
(build/test-runs/*/run.log, build/attempts/v018-qual1.log, a lab
directory); --since 2h / --since 2026-09-16 / --newer <file> keep only
logs written since then.

A fight is BOSS when its driver tag is a custom set-piece driver or a
spared/event formation; RANDOM when it is ordinary traversal (navTo /
worldNavTo / advanceStory / rideOut / a world walk); `?` otherwise.
"""
import argparse
import contextlib
import datetime as dt
import glob
import io
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FENIX_ID = 0xF0

# the resolved-revive signals
CARE_USED = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] used \$F0 on char (?P<char>\d+): "
                       r"(?P<from>\d+) -> (?P<to>\d+) hp")
LANDED = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] actor (?P<actor>\d+)'s Fenix Down landed: "
                    r"entity (?P<e>\d+) is at (?P<hp>\d+)/(?P<max>\d+)")
# a Fenix the driver confirmed and then gave up on: the bag paid, nobody rose
NEVER_LANDED = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] actor (?P<actor>\d+)'s Fenix Down "
                          r"on entity (?P<e>\d+) never landed \((?P<ticks>\d+) ticks\)")
# the running bag count, wherever it is printed: the `fenix=<n>` field of a
# care/shop line, and the `<n> left` tail a care use writes after spending one
BAG_FENIX = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] .*\bfenix=(?P<n>\d+)")
BAG_LEFT = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] used \$F0 on char \d+: .*?, "
                      r"(?P<n>\d+) left")
TRACE = "[ot6action] "
# the fight a care stop follows: the driver's own f+1 line
BATTLE_UP = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] battle f\+1 ")
# a party death, the lib driver's line and the custom drivers' copy of it
DEATH = re.compile(r"^\[ot6\] \[(?P<tag>[^\]]+)\] \[death\] f\+(?P<tick>\d+) entity (?P<e>\d) "
                   r"char (?P<char>\d+) from (?P<from>\d+)/(?P<max>\d+) by ")
# the attempt boundaries and the verdict (tools/audit_retries.py's shapes)
ATTEMPT_FAILED = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) FAILED class=(\S+)")
RUNNER = re.compile(r"^\[ot6\] \[retry\] segment runner: \S+, up to (\d+) attempt")
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)(?: attempts=(\d+)/(\d+))?")
FAIL = re.compile(r"^\[ot6\] FAIL: ")
# a ninja log's edge line; the edge's run output follows it
NINJA_EDGE = re.compile(r"^\[\d+/\d+\] (?P<verb>\S+) (?P<name>\S+)")

# custom set-piece / boss driver tags (extend as the route grows)
BOSS_HINT = re.compile(
    r"\bb\d+\b|FlameEater|ambush|Ultros|Kefka|Vargas|Whelk|Dadaluma|TunnelArmr|"
    r"Ifrit|Shiva|Number|Cranes|Atma|pursuit|boss|magitek|"
    r"\bIAF\b|Nerapa|Rizopas|Leader|Guardian|"
    r"\bescape\b|\bcamp\b|\bdescent\b|\bmarshal\b|\brapids\b|\briver\b", re.I)
# ordinary traversal drivers.  NOT "care after"/"care before": a care stop
# is attributed to the fight before it (#154, third defect).
RANDOM_HINT = re.compile(
    r"navTo|worldNavTo|advanceStory|rideOut|the ride|climb|cross|ledge|"
    r"world walk|world grind|followPath|Follow\b|phaseWalk|trash|"
    r"ride battle|rafters|draw \d+-win|gau walk|gau grind", re.I)


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


def segments_of(path):
    """One log -> [(segment, lines)].  A run log is one segment.  A ninja
    log is one segment per edge whose run output follows its `[k/N] <verb>
    <name>` line (ninja prints an edge's line again, ahead of its output,
    when the edge finishes); the edges that printed no `[ot6]` line and
    the preamble before the first edge are dropped."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return []
    seg = segment_of(path)
    edges = [i for i, l in enumerate(lines) if NINJA_EDGE.match(l)]
    if not edges:
        return [(seg, lines)]
    out = []
    for k, start in enumerate(edges):
        end = edges[k + 1] if k + 1 < len(edges) else len(lines)
        body = lines[start + 1:end]
        if not any(l.startswith("[ot6] ") for l in body):
            continue
        out.append((f"{seg}:{NINJA_EDGE.match(lines[start]).group('name')}", body))
    return out


def scan_lines(lines):
    """One segment's lines -> (uses, verdict, spends, deaths).  uses is a
    list of dicts (attempt, line, fight, cls, kind, text): the revives that
    landed, plus the confirmed ones that never did (kind 'failed').  spends
    is the bag drops, same dict shape plus n (how many left the bag).
    deaths is the [death] lines, same shape.  verdict is the attempts n/N
    (or the count seen when the log has no verdict)."""
    traced = any(l.startswith(TRACE) for l in lines)
    uses = []
    spends = []
    deaths = []
    bag = None                  # the running fenix= count within this attempt
    attempt, max_attempts = 1, None
    last_battle = None          # the most recent [tag] battle f+1 in this attempt
    verdict = None

    def bag_now(line, n):
        """A drop in the running count is Fenix that left the bag, paid for
        by the fight before the line that printed the count."""
        nonlocal bag
        if bag is not None and n < bag:
            spends.append(dict(attempt=attempt, line=line, fight=last_battle,
                               cls=classify(last_battle), n=bag - n, text=None))
        bag = n
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
            # the retry reloads the checkpoint, so the bag comes back with
            # it: start the next attempt's baseline from its own first count
            bag = None
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
        m = DEATH.match(line)
        if m:
            fight = m.group("tag")
            deaths.append(dict(attempt=attempt, line=i, fight=fight,
                               cls=classify(fight), kind="death", text=line))
            continue
        # the bag, before the use rules: a care use prints the count it left
        # behind, every other care/shop line prints the count it saw
        m = BAG_LEFT.match(line)
        if m:
            # this line is itself proof that one left the bag, so when it is
            # the attempt's first sighting the baseline is the count before
            # it rather than after -- otherwise an attempt whose first care
            # stop revives someone would start counting from zero
            if bag is None:
                bag = int(m.group("n")) + 1
            bag_now(i, int(m.group("n")))
        else:
            m = BAG_FENIX.match(line)
            if m:
                bag_now(i, int(m.group("n")))
        m = NEVER_LANDED.match(line)
        if m:
            fight = m.group("tag")
            uses.append(dict(attempt=attempt, line=i, fight=fight,
                             cls=classify(fight), kind="failed", text=line))
            continue
        m = CARE_USED.match(line)
        if m:
            # a care stop's revival is the preceding fight's Fenix, whatever
            # the stop is called
            uses.append(dict(attempt=attempt, line=i, fight=last_battle,
                             cls=classify(last_battle), kind="care", text=line))
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
    return uses, verdict, spends, deaths


def scan(path):
    """One run log -> scan_lines of its lines (a ninja log's first segment)."""
    segs = segments_of(path)
    if not segs:
        return [], "?", [], []
    return scan_lines(segs[0][1])


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


def tally(paths):
    """Every segment of every log, scanned: {segment: dict(verdict, uses,
    spends, deaths)} in path order."""
    out = {}
    for p in paths:
        for seg, lines in segments_of(p):
            uses, verdict, spends, deaths = scan_lines(lines)
            out[seg] = dict(verdict=verdict, uses=uses, spends=spends, deaths=deaths)
    return out


def report(paths, verbose=False, boost=True):
    segs = tally(paths)
    # (segment, attempt, cls) -> counts; a fight's flag reads the larger of
    # what landed and what left the bag
    landed = defaultdict(int)
    spent = defaultdict(int)
    failed = defaultdict(int)
    # (segment, attempt, fight) -> counts, for the lines that name a fight
    by_fight = defaultdict(lambda: defaultdict(int))
    for seg, s in segs.items():
        for u in s["uses"]:
            key = (seg, u["attempt"], u["cls"])
            fkey = (seg, u["attempt"], u["fight"])
            if u["kind"] == "failed":
                failed[key] += 1
                by_fight[fkey]["failed"] += 1
            else:
                landed[key] += 1
                by_fight[fkey]["landed"] += 1
        for sp in s["spends"]:
            spent[(seg, sp["attempt"], sp["cls"])] += sp["n"]
            by_fight[(seg, sp["attempt"], sp["fight"])]["spent"] += sp["n"]
        for d in s["deaths"]:
            by_fight[(seg, d["attempt"], d["fight"])]["deaths"] += 1

    # what the fight cost: every confirmed throw left the bag whether or not
    # it landed, and the bag's own count can lag them when an attempt ends
    # before the next care line reads it, so the larger reading is the cost
    def paid(l, f, sp):
        return max(l + f, sp)
    flagged = []
    for key in sorted(set(landed) | set(spent) | set(failed)):
        seg, attempt, cls = key
        n = paid(landed[key], failed[key], spent[key])
        violation = (cls == "BOSS" and n > 2) or (cls == "RANDOM" and n >= 1)
        if violation or (cls == "?" and n > 2):
            flagged.append((seg, attempt, n, landed[key], spent[key], cls))

    total = sum(landed.values())
    from_bags = sum(spent.values())
    nolanding = sum(failed.values())
    bags = (f"{total} landed, {from_bags} left the bags"
            + (f", {nolanding} confirmed and never landed" if nolanding else ""))
    where = (f"{len(paths)} logs" if len(segs) == len(paths)
             else f"{len(paths)} logs, {len(segs)} segments")

    def att(seg, attempt):
        v = segs[seg]["verdict"]
        return f"{attempt}/{v.split('/')[1].split()[0]}" if "/" in v else str(attempt)
    if not flagged:
        print(f"Fenix audit: no threshold violations in the scanned logs "
              f"({where}, {bags}).")
    else:
        print(f"Fenix audit: {len(flagged)} flagged segment/kind(s) "
              f"(>2 Fenix in a boss, or any in a random, counting what left "
              f"the bag) across {where}, {bags}.\n")
        print(f"{'segment':36} {'attempt':>7} {'fenix':>5} {'landed':>6} {'bag':>4}  {'kind':7} why")
        for seg, attempt, n, l, sp, cls in sorted(flagged, key=lambda x: (-x[2], x[0], x[1])):
            why = ("boss burned >2 -- underleveled or needs a strategy lab"
                   if cls == "BOSS"
                   else "Fenix in randoms -- underleveled or lab these encounters"
                   if cls == "RANDOM"
                   else "review: classify boss vs random")
            print(f"{seg[:36]:36} {att(seg, attempt):>7} {n:>5} {l:>6} {sp:>4}  {cls:7} {why}")
    # Fenix the bags paid for that raised nobody (#220).  Every one of these
    # is a turn and an item spent on a member the throw could not raise --
    # Zombie, or a fight already lost -- which is a strategy gap rather than
    # a supply one, and the landed count alone hides it.
    wasted = [(k, c) for k, c in sorted(by_fight.items(), key=lambda kv: (kv[0][0], kv[0][1], str(kv[0][2])))
              if paid(c["landed"], c["failed"], c["spent"]) > c["landed"]]
    if wasted:
        print()
        print("spent without raising anyone (bag drop above landed revives, per fight):")
        for (seg, attempt, fight), c in wasted:
            cost = paid(c["landed"], c["failed"], c["spent"])
            n = cost - c["landed"]
            if c["failed"]:
                why = f"{c['failed']} confirmed and never landed"
            elif c["deaths"]:
                why = (f"no landing line accounts for them; {c['deaths']} death(s) "
                       f"logged in that fight")
            else:
                why = "no landing line accounts for them"
            seen = f" (bag lines saw {c['spent']})" if c["spent"] < cost else ""
            print(f"  {seg} attempt {att(seg, attempt)} [{fight or '?'}]: {cost} left "
                  f"the bag{seen}, {c['landed']} landed -- {n} raised nobody ({why})")
    if nolanding:
        print()
        print("thrown and never landed (the driver confirmed the Fenix, gave up "
              "waiting, nobody rose):")
        for seg, s in segs.items():
            for u in s["uses"]:
                if u["kind"] == "failed":
                    print(f"  {seg} attempt {att(seg, u['attempt'])} L{u['line']} "
                          f"[{u['fight']}] {u['cls']}: {u['text'][6:120]}")

    keys = sorted(set(landed) | set(spent) | set(failed))
    used = sorted({seg for seg, _, _ in keys})
    if used:
        print()
        print("per log (attempts=n/N is the verdict's; a use is listed under the "
              "attempt it happened in; landed / left the bag):")
        for seg in used:
            parts = []
            for seg2, attempt, cls in keys:
                if seg2 != seg:
                    continue
                key = (seg, attempt, cls)
                parts.append(f"attempt {attempt}: {cls} {landed[key]}/"
                             f"{paid(landed[key], failed[key], spent[key])}")
            print(f"  {seg}: attempts={segs[seg]['verdict']}; " + "; ".join(parts))
    if verbose:
        detail = [(seg, u) for seg, s in segs.items() for u in s["uses"] + s["deaths"]]
        if detail:
            print()
            print("every Fenix Down that resolved or was confirmed and lost, and "
                  "every death (segment attempt line fight kind: the log line):")
            for seg, u in detail:
                print(f"  {seg} a{u['attempt']} L{u['line']} [{u['fight'] or '?'}] "
                      f"{u['cls']} {u['kind']}: {u['text'][:160]}")
    # The sibling audit (#175): boost left on the table at every death and
    # the classification of every wipe, over the same logs.  Wherever the
    # Fenix audit runs, this runs beside it.
    if boost:
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
        # the bag between the two fights, unchanged since that use
        "[ot6] [transit a2 care 1] nothing to do: c0 241/241 hp | tonic=67 potion=21 fenix=14 antidote=4 soft=2 remedy=1",
        # a random, an in-battle plan that landed (one use), and a care stop
        "[ot6] [worldNavTo] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=447,443 roundcost=0,0 monhp=s2:288/sh2 monsters=1",
        "[ot6] [worldNavTo] actor=1 revive entity 0 with Fenix Down: raise to 55 HP (1/8 of 447), the living enemy's smallest hit 175",
        "[ot6] [worldNavTo] actor 1's Fenix Down landed: entity 0 is at 55/447 at tick 5017 -- a top-up is owed (the care budget opens for it)",
        # a Fenix confirmed but never landed raises nobody and still costs
        # the bag one (#220): 14 - 1 (the raise above) - 1 (this) - 1 (the
        # care stop below) = 11
        "[ot6] [worldNavTo] actor 2's Fenix Down on entity 3 never landed (840 ticks) -- forgetting it",
        # a care stop under any name is the preceding fight's (fc-care is
        # gen_fc_alcove's own tag for H.fieldCare)
        "[ot6] [fc-care r10] used $F0 on char 4: 0 -> 44 hp, status1 80 -> 00, 11 left",
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
    # a custom set-piece driver (the Ghost Train, gen_sabin_train) writing
    # the lib driver's battle-open, [death] and landing lines itself (#220):
    # the bag pays 2 into b68, one lands, one is thrown at a member the
    # train kills again before it lands and is forgotten
    custom = "\n".join([
        "[ot6] [retry] segment runner: gen_sabin_train, up to 3 attempt(s), seed shift 0, watchdogs ON (no-effect 300 frames, no-progress 1800)",
        "[ot6] [pre-smokestack care] done: c2 358/358 hp 96/96 mp | tonic=86 potion=30 fenix=15 antidote=4 soft=2 remedy=0",
        "[ot6] [b68] battle f+1 partyhp=363,282,358,0 party_bp=1,1,1,0",
        "[ot6] [b68] [death] f+900 entity 0 char 5 from 231/363 by nobody (no monster action attributed) bp=1 party_bp=1,2,1,0",
        # the plan line is not a use
        "[ot6] [b68] revive: e0 is down -- FENIX DOWN [0/363(64mp,s00) 282/282(77mp,s00) 358/358(96mp,s00) 0/0(0mp,s00)]",
        "[ot6] [b68] actor 2's Fenix Down landed: entity 0 is at 45/363 at tick 1300",
        "[ot6] [b68] [death] f+2100 entity 0 char 5 from 45/363 by nobody (no monster action attributed) bp=3 party_bp=3,2,1,0 -- died holding 3 BP",
        "[ot6] [b68] actor 1's Fenix Down on entity 0 never landed (841 ticks) -- forgetting it",
        # the same death, mirrored: not a second one
        "[ot6note] 40000 [b68] [death] f+2100 entity 0 char 5 from 45/363 by nobody (no monster action attributed) bp=3 party_bp=3,2,1,0 -- died holding 3 BP",
        # a line with the word but not the shape is not a death
        "[ot6] [b68] LOST -- b68: the [death] count is not a line",
        "[ot6] [post-train care] done: c2 358/358 hp 96/96 mp | tonic=77 potion=27 fenix=13 antidote=4 soft=2 remedy=0",
        "[ot6] PASS (frame 47820) attempts=1/3",
    ])
    # a ninja log: two generate edges' run output, a latch, a check, and an
    # edge line printed at its start with no output (ninja prints it again,
    # ahead of the output, when the edge finishes)
    ninja = "\n".join([
        "[1/9] latch tools/tests/gen_x.lua",
        "[2/9] generate x <- gen_x",
        "[3/9] generate y <- gen_y",
        "[2/9] generate x <- gen_x",
        "composed build/test-runs/x.abc/composed.lua (0 embedded savestate(s))",
    ] + untraced.split("\n") + [
        "[4/9] check something",
        "[3/9] generate y <- gen_y",
    ] + traced.split("\n") + [
        "[5/9] suite battle_z",
        "[ot6] [retry] segment runner: battle_z, up to 1 attempt(s), seed shift 0, watchdogs ON (no-effect 300 frames, no-progress 1800)",
        "[ot6] PASS (frame 100) attempts=1/1",
    ])
    # a boss whose attempt ended before any care line re-read the bag: the
    # three confirmed throws are its cost, not the bag's unchanged count
    lagged = "\n".join([
        "[ot6] [retry] segment runner: gen_z, up to 1 attempt(s), seed shift 0, watchdogs ON (no-effect 300 frames, no-progress 1800)",
        "[ot6] [care before b72] done: c0 500/500 hp | tonic=50 potion=10 fenix=9 antidote=4 soft=2 remedy=0",
        "[ot6] [b72] battle f+1 menu=00 state=00 actor=0 cursor=0 cmds=00,01,02,03 partyhp=500,500 roundcost=0,0 monhp=s0:9999/sh6 monsters=1",
        "[ot6] [b72] actor 1's Fenix Down on entity 0 never landed (841 ticks) -- forgetting it",
        "[ot6] [b72] actor 2's Fenix Down on entity 0 never landed (841 ticks) -- forgetting it",
        "[ot6] [b72] actor 3's Fenix Down on entity 0 never landed (841 ticks) -- forgetting it",
        "[ot6] [retry] attempt 1/1 FAILED class=wipe frame=9000 totalframes=9000 shift=0 phase=1: GAME OVER fired",
        "[ot6] FAIL: GAME OVER fired",
    ])
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "build", "states", "cuts"))
        os.makedirs(os.path.join(d, "build", "attempts"))
        p = os.path.join(d, "build", "states", "x.log")
        open(p, "w").write(untraced + "\n")
        q = os.path.join(d, "build", "states", "cuts", "y.log")
        open(q, "w").write(traced + "\n")
        r = os.path.join(d, "build", "states", "train_done.log")
        open(r, "w").write(custom + "\n")
        z = os.path.join(d, "build", "states", "z.log")
        open(z, "w").write(lagged + "\n")
        n = os.path.join(d, "build", "attempts", "qual.log")
        open(n, "w").write(ninja + "\n")
        uses, verdict, spends, deaths = scan(p)
        tuses, tverdict, tspends, tdeaths = scan(q)
        buses, bverdict, bspends, bdeaths = scan(r)
        zuses, zverdict, zspends, zdeaths = scan(z)
        nsegs = segments_of(n)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            report([p, q, r, z], boost=False)
        printed = out.getvalue()
        nout = io.StringIO()
        with contextlib.redirect_stdout(nout):
            report([n], boost=False)
        nprinted = nout.getvalue()
        # --since / --newer selection
        os.utime(p, (1_000_000, 1_000_000))
        newer = select_logs([os.path.join(d, "build", "states", "*.log"),
                             os.path.join(d, "build", "states", "cuts", "*.log")], newer=p)
    # the untraced log: 4 uses -- b70 care (BOSS), the landed random raise
    # (RANDOM), its care stop (RANDOM), the IAF between-waves care (BOSS);
    # the unattributed care before any fight is '?'
    got = [(u["attempt"], u["fight"], u["cls"], u["kind"]) for u in uses]
    want = [(1, "b70", "BOSS", "care"),
            (1, "worldNavTo", "RANDOM", "battle"),
            (1, "worldNavTo", "RANDOM", "failed"),
            (1, "worldNavTo", "RANDOM", "care"),
            (2, None, "?", "care"),
            (2, "IAF", "BOSS", "care")]
    assert got == want, got
    assert verdict == "2/3", verdict
    # the [ot6note] mirror was not a seventh; the shop/bag lines were none
    assert len(uses) == 6, len(uses)
    # the bags (#220): 15 -> 14 across the b70 care (1), 14 -> 11 across the
    # random (the raise, the Fenix that never landed, the care stop = 3),
    # then the retry reloads and attempt 2 spends 1 + 1.  Six left the bags,
    # five raised someone, and the difference is the one that never landed.
    gotspend = [(s["attempt"], s["fight"], s["cls"], s["n"]) for s in spends]
    wantspend = [(1, "b70", "BOSS", 1),
                 (1, "worldNavTo", "RANDOM", 3),
                 (2, None, "?", 1),
                 (2, "IAF", "BOSS", 1)]
    assert gotspend == wantspend, gotspend
    assert sum(s["n"] for s in spends) == 6, spends
    assert len([u for u in uses if u["kind"] != "failed"]) == 5
    assert len([u for u in uses if u["kind"] == "failed"]) == 1
    assert [(d["attempt"], d["fight"]) for d in deaths] == [(1, "b70")], deaths
    # the traced log: exactly one Fenix, from the trace; the landing line
    # and the dropped plan add nothing; the Potion is not one
    tgot = [(u["attempt"], u["fight"], u["cls"], u["kind"]) for u in tuses]
    assert tgot == [(1, "b70", "BOSS", "battle")], tgot
    assert tverdict == "1/3", tverdict
    # a traced log that never prints a bag count reports no consumption
    # rather than guessing one
    assert tspends == [], tspends
    assert tdeaths == [], tdeaths
    # the custom driver's log: its battle-open line attributes the bag's
    # 2 to b68 (BOSS), one landed, one never landed, two deaths, and the
    # mirrored death and the LOST line are not deaths
    bgot = [(u["attempt"], u["fight"], u["cls"], u["kind"]) for u in buses]
    assert bgot == [(1, "b68", "BOSS", "battle"), (1, "b68", "BOSS", "failed")], bgot
    assert [(s["fight"], s["n"]) for s in bspends] == [("b68", 2)], bspends
    assert [(d["fight"], d["line"]) for d in bdeaths] == [("b68", 4), ("b68", 7)], bdeaths
    assert bverdict == "1/3", bverdict
    # the report: the flag counts what left the bag (b68 paid 2, under the
    # boss threshold, so not flagged; the random's 3 is), every fight that
    # spent more than it raised is listed by name with its deaths, and
    # every Fenix that never landed is listed by name
    # the lagged log: three confirmed throws, a bag never re-read
    assert [(u["fight"], u["kind"]) for u in zuses] == [("b72", "failed")] * 3, zuses
    assert zspends == [] and zverdict == "1/1", (zspends, zverdict)
    assert "4 logs, 7 landed, 8 left the bags, 5 confirmed and never landed" in printed, printed
    assert "x                                        1/3     3      2    3  RANDOM" in printed, printed
    assert "z                                        1/1     3      0    0  BOSS" in printed, printed
    assert ("  z attempt 1/1 [b72]: 3 left the bag (bag lines saw 0), 0 landed -- 3 raised "
            "nobody (3 confirmed and never landed)") in printed, printed
    assert "  z: attempts=1/1; attempt 1: BOSS 0/3" in printed, printed
    assert "train_done" not in printed.split("spent without")[0], printed
    assert ("  x attempt 1/3 [worldNavTo]: 3 left the bag, 2 landed -- 1 raised nobody "
            "(1 confirmed and never landed)") in printed, printed
    assert ("  train_done attempt 1/3 [b68]: 2 left the bag, 1 landed -- 1 raised nobody "
            "(1 confirmed and never landed)") in printed, printed
    assert "thrown and never landed" in printed, printed
    assert "  train_done attempt 1/3 L8 [b68] BOSS: [b68] actor 1's Fenix Down on entity 0 never landed (841 ticks)" in printed, printed
    assert "  train_done: attempts=1/3; attempt 1: BOSS 1/2" in printed, printed
    # a bag drop with no landing line at all names the deaths seen in the fight
    out2 = io.StringIO()
    with contextlib.redirect_stdout(out2):
        segs = {"t": dict(verdict="1/3", uses=[],
                          spends=[dict(attempt=1, line=9, fight="b68", cls="BOSS", n=2, text=None)],
                          deaths=[dict(attempt=1, line=4, fight="b68", cls="BOSS", kind="death", text="")])}
        tally_was = globals()["tally"]
        globals()["tally"] = lambda paths: segs
        try:
            report(["t"], boost=False)
        finally:
            globals()["tally"] = tally_was
    assert ("  t attempt 1/3 [b68]: 2 left the bag, 0 landed -- 2 raised nobody "
            "(no landing line accounts for them; 1 death(s) logged in that fight)") in out2.getvalue(), out2.getvalue()
    # the ninja log: one segment per edge with run output, named by the
    # edge; the latch, the check and the edge line with nothing after it
    # are not segments, and the suite edge is one
    assert [s for s, _ in nsegs] == ["attempts/qual:x", "attempts/qual:y", "attempts/qual:battle_z"], nsegs
    assert scan_lines(nsegs[0][1])[1] == "2/3" and scan_lines(nsegs[1][1])[1] == "1/3"
    assert "1 logs, 3 segments, 6 landed, 6 left the bags, 1 confirmed and never landed" in nprinted, nprinted
    assert "attempts/qual:x                          1/3     3      2    3  RANDOM" in nprinted, nprinted
    # keys: a cuts/ log is its own segment
    assert segment_of(os.path.join(ROOT, "build/states/cuts/y.log")) == "cuts/y"
    assert segment_of(os.path.join(ROOT, "build/states/zozo_arrival.log")) == "zozo_arrival"
    assert segment_of(os.path.join(ROOT, "build/test-runs/fc_landing.abc/run.log")) \
        == "test-runs/fc_landing.abc/run"
    # --newer kept only the log written after p
    assert [os.path.basename(n) for n in newer] == ["y.log", "train_done.log", "z.log"], newer
    # a care tag alone is no longer a random
    assert classify("care after battle (worldNavTo)") == "RANDOM"   # by its fight, when that is all we have
    assert classify("care before the climb") == "RANDOM"           # 'climb' is traversal
    assert classify("b72") == "BOSS" and classify("Kefka vs Leo") == "BOSS"
    assert classify("world walk -> Jidoor approach (27,129)") == "RANDOM"
    assert classify("healerdown") == "?"
    # the custom drivers' tags (#220)
    for tag in ("b47", "b68", "vargas", "whelk", "marshal", "escape", "camp",
                "descent", "kefka", "ultros2", "rapids", "river"):
        assert classify(tag) == "BOSS", tag
    assert classify("gau walk") == "RANDOM" and classify("gau grind") == "RANDOM"
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
                    help="list every resolved Fenix Down and every death with its log line")
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
