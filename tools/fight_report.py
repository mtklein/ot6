#!/usr/bin/env python3
"""fight_report.py -- what makes a fight good, measured from harness logs (#422).

    python3 tools/fight_report.py [--min N] [--story] [--tsv OUT] [--fights OUT]
        [LABEL=]PATH ...

Each PATH is a log (a state's .log, a sweep's <state>.seedNN.log, .gz
too) or a directory searched for them; LABEL names the policy that played
it (real, naive, nocare, ...; default real).  LABEL@14B,1B6 says the
policy was limited to those formations (OT6_POLICY_FORMS): the run's other
fights are counted as real.  Every battle in the logs --
from its `[key] battle key` line to its `[outcome]` or `[wipe]` -- becomes
one fight, read off lines the harness already writes:

  [board]    the board at each plan (lib/ot6.lua Driver:sayTurn): party
             HP/max/BP, monsters HP/max/shields.  Logs without it fall
             back to the 300-frame `battle f+N ... partyhp= monhp=` lines,
             the `[open]` line's max HP and the `plan=` lines' turn count.
  [death]    members felled;  [outcome] / [wipe]  how it ended.

Per fight: won, party low point (the least party HP fraction seen, and the
most members down at once), deaths, turns (party plans), ticks, and the
balance lead = party HP fraction - enemy HP fraction at each turn: doubt
turns (the party behind, lead < 0) and lead changes (its sign flips).

Per formation and policy, counting each distinct battle key once (docs/
TESTING.md "Tests that survive any draw"): keys, wins, the low point's
range, deaths, turns and doubt.  The five questions of docs/design/
fight-quality.md read off these columns:
  Resistance   low point (median, worst) in won fights
  Surmountable win rate by key; luck = keys lost under the same policy,
               levels and gear (0 < losses < keys)
  Drama        doubt turns and lead changes
  Power        turns (and ticks) to the kill, in route order
  Agency       the same keys under the real policy and a weaker one
               (naive, nocare, ...): win rate and turns side by side, and
               the keys both played, paired

--min N drops formations seen in fewer than N keys; --events keeps only
event battles -- formations no random-encounter group in the built ROM
(RandBattleGroup, tools/route_data.py) can deal: the bosses -- plus any
formation named with --form (a notable random).
"""
import argparse
import gzip
import json
import os
import re
import statistics
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

P = r"^\[ot6\] "
KEY = re.compile(P + r"(?:\[key\] battle key |\[seed\] (?:first )?battle: .* key )(be[0-9A-F]{2}-g[0-9A-F]{4})")
TAG = re.compile(P + r"\[([^]]+)\] ")
TURN = re.compile(P + r"\[[^]]+\] \[(?:board|turn)\] n=(\d+) tick=(\d+) form=\$([0-9A-F]+) actor=(\d+) "
                  r"char=(\d+) plan=(\S+) bp=(\d+) party=(\S*) mons=(\S*)")
PERIODIC = re.compile(P + r"\[[^]]+\] battle f\+(\d+) .*partyhp=(\S+) roundcost=\S+ monhp=(\S*) monsters")
OPEN = re.compile(P + r"\[[^]]+\] \[open\] party HP as the battle opens: (.*)")
PLAN = re.compile(P + r"\[[^]]+\] actor=\d+ char=\d+ plan=\S+$")
DEATH = re.compile(P + r"\[[^]]+\] \[death\]")
WIPE = re.compile(P + r"\[[^]]+\] \[wipe\]")
OUTCOME = re.compile(P + r"\[([^]]+)\] \[outcome\] battle \$([0-9A-F]{3}) (WON|LOST|PARTY LEFT) "
                     r"after (\d+) ticks[^:]*: killed (.*?); escaped")
FAILED = re.compile(P + r"\[retry\] attempt \d+/\d+ FAILED class=(\S+)")
POLICY = re.compile(P + r"\[[^]]+\] \[policy\] ")


def mon_names():
    try:
        with open(os.path.join(ROOT, "ff6/src/text/monster_name_en.json"), encoding="utf-8") as f:
            return [re.sub(r"\{[^}]*\}", "", s).strip() for s in json.load(f)["text"]]
    except OSError:
        return []


def random_forms():
    """every formation a random-encounter group can deal (needs build/ot6.sfc)"""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import route_data
    d = route_data.Data()
    return {w & 0x1FF for g in range(256) for w in d.group_words(g)}


def opener(path):
    return gzip.open(path, "rt", errors="replace") if path.endswith(".gz") else \
        open(path, errors="replace")


def arc_of(path):
    b = os.path.basename(path)
    b = re.sub(r"\.gz$", "", b)
    b = re.sub(r"\.log$", "", b)
    return re.sub(r"\.seed\d+$", "", b)


class Fight:
    def __init__(self, key, arc, path, policy):
        self.key, self.arc, self.path, self.policy = key, arc, path, policy
        self.form, self.result, self.ticks, self.story = None, None, None, False
        self.samples = []          # (party_frac, enemy_frac, down)
        self.pmax = {}             # entity -> max hp (fallback path)
        self.mmax = {}             # slot -> max hp seen
        self.turns, self.plans, self.deaths, self.policy_lines = 0, 0, 0, 0
        self.kills = ""
        self.lines = []            # raw evidence: key, worst turn, outcome

    def sample(self, party, mons):
        """party: [(hp, max)], mons: {slot: (hp, max)}"""
        php = sum(min(h, m) for h, m in party)
        pm = sum(m for _, m in party)
        down = sum(1 for h, _ in party if h == 0)
        for s, (h, m) in mons.items():
            self.mmax[s] = max(self.mmax.get(s, 0), m, h)
        em = sum(self.mmax.values())
        eh = sum(min(mons[s][0], self.mmax[s]) for s in mons)
        if pm <= 0:
            return
        self.samples.append((php / pm, (eh / em) if em else 0.0, down))

    def metrics(self):
        if not self.samples:
            return None
        pf = [s[0] for s in self.samples]
        lead = [s[0] - s[1] for s in self.samples]
        flips = sum(1 for a, b in zip(lead, lead[1:]) if (a < 0) != (b < 0))
        return {"low": min(pf), "down": max(s[2] for s in self.samples),
                "doubt": sum(1 for x in lead if x < 0), "flips": flips,
                "lead_min": min(lead)}


def parse(path, policy, out):
    arc = arc_of(path)
    f = None
    have_turn = False
    with opener(path) as fh:
        for line in fh:
            if not line.startswith("[ot6] "):
                continue
            m = KEY.match(line)
            if m:
                if f is not None and f.key == m.group(1) and not f.samples:
                    continue           # the [seed] and [key] lines name one battle
                f = Fight(m.group(1), arc, path, policy)
                f.lines.append(line.rstrip())
                have_turn = False
                continue
            if f is None:
                continue
            m = TURN.match(line)
            if m:
                have_turn = True
                f.turns += 1
                f.form = int(m.group(3), 16)
                party = []
                for p in m.group(8).split(","):
                    if p:
                        _, h, mx, _bp = re.match(r"e(\d+):(\d+)/(\d+)/(\d+)", p).groups()
                        party.append((int(h), int(mx)))
                mons = {}
                for q in m.group(9).split(","):
                    if q:
                        s, h, mx, _sh = re.match(r"s(\d+):(\d+)/(\d+)/(\d+)", q).groups()
                        mons[int(s)] = (int(h), int(mx))
                f.sample(party, mons)
                f._worst = getattr(f, "_worst", None)
                if f.samples and (f._worst is None or f.samples[-1][0] < f._worst[0]):
                    f._worst = (f.samples[-1][0], line.rstrip())
                continue
            m = OPEN.match(line)
            if m:
                for e, h, mx in re.findall(r"e(\d+) (\d+)/(\d+)", m.group(1)):
                    f.pmax[int(e)] = int(mx)
                continue
            if PLAN.match(line):
                f.plans += 1
                if "[advanceStory]" in line:
                    f.story = True
                continue
            m = PERIODIC.match(line)
            if m:
                if "[advanceStory]" in line:
                    f.story = True
                if not have_turn and f.pmax:
                    hp = [int(x) for x in m.group(2).split(",")]
                    party = [(hp[e], f.pmax[e]) for e in sorted(f.pmax) if e < len(hp)]
                    mons = {}
                    for s, h in re.findall(r"s(\d+):(\d+)/sh\d+", m.group(3)):
                        mons[int(s)] = (int(h), max(int(h), f.mmax.get(int(s), 0)))
                    f.sample(party, mons)
                continue
            if DEATH.match(line):
                f.deaths += 1
                continue
            if POLICY.match(line):
                f.policy_lines += 1
                continue
            m = FAILED.match(line)
            if m:
                # the runner gave up inside the battle: its wipe watchdog
                # fires before the driver's [wipe] line can; any other
                # class leaves the fight unfinished (not a loss, not a win)
                if f.form is not None:
                    f.result = "LOST" if m.group(1) == "wipe" else "ABORT"
                    f.lines.append(line.rstrip()[:300])
                    out.append(f)
                f = None
                continue
            m = WIPE.match(line)
            if m:
                f.result, f.ticks = "LOST", None
                f.lines.append(line.rstrip())
                if f.form is not None:
                    out.append(f)
                f = None
                continue
            m = OUTCOME.match(line)
            if m:
                f.form = int(m.group(2), 16)
                f.result = m.group(3)
                f.ticks = int(m.group(4))
                f.kills = m.group(5)
                if m.group(1) == "advanceStory":
                    f.story = True
                f.lines.append(line.rstrip())
                if not have_turn:
                    f.turns = f.plans
                out.append(f)
                f = None


def files_of(path):
    if os.path.isdir(path):
        for d, _, names in os.walk(path):
            for n in sorted(names):
                if re.search(r"\.log(\.gz)?$", n):
                    yield os.path.join(d, n)
    else:
        yield path


def med(xs):
    return statistics.median(xs) if xs else None


def pct(x):
    return "-" if x is None else "%d%%" % round(100 * x)


def num(x, fmt="%.1f"):
    return "-" if x is None else (fmt % x)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--min", type=int, default=1)
    ap.add_argument("--events", action="store_true")
    ap.add_argument("--form", action="append", default=[], help="formation (hex) to keep with --events")
    ap.add_argument("--tsv", help="write the per-formation table here")
    ap.add_argument("--fights", help="write one row per fight, with its raw lines, here")
    a = ap.parse_args()
    names = mon_names()
    fights = []
    order = []
    for spec in a.inputs:
        label, _, path = spec.partition("=") if "=" in spec else ("real", "", spec)
        label, _, scope = label.partition("@")
        forms = {int(x, 16) for x in scope.split(",") if x}
        for p in files_of(path):
            got = []
            parse(p, label or "real", got)
            for f in got:
                if forms and f.form not in forms:
                    f.policy = "real"
            fights.extend(got)
    keep_forms = {int(x, 16) for x in a.form}
    if a.events:
        rnd = random_forms()
        fights = [f for f in fights if f.form not in rnd or f.form in keep_forms]
    # one fight per (policy, formation, key): repeats of a key are not new draws
    by = {}
    for f in fights:
        k = (f.policy, f.form, f.key)
        if k not in by:
            by[k] = f
        if (f.form, f.arc) not in order:
            order.append((f.form, f.arc))
    groups = defaultdict(list)
    for f in by.values():
        groups[(f.form, f.policy)].append(f)
    fname = {}
    for f in fights:
        if f.kills and f.form not in fname:
            sp = [int(x, 16) for x in re.findall(r"\$([0-9A-F]{3})", f.kills)]
            nm = sorted({names[s] if s < len(names) else "$%03X" % s for s in sp})
            fname[f.form] = "+".join(nm)
    arcs = defaultdict(list)
    for form, arc in order:
        if arc not in arcs[form]:
            arcs[form].append(arc)
    policies = sorted({f.policy for f in by.values()}, key=lambda p: (p != "real", p))
    hdr = ["formation", "fight", "arc", "policy", "keys", "won", "unfinished", "low_med", "low_worst", "down_max",
           "deaths/fight", "turns_med", "ticks_med", "doubt_med", "flips_med", "paired"]
    rows = []
    seen_forms = []
    for form, _arc in order:
        if form in seen_forms:
            continue
        seen_forms.append(form)
        real = {f.key: f for f in groups.get((form, "real"), []) if f.result != "ABORT"}
        for pol in policies:
            g = groups.get((form, pol), [])
            unfinished = sum(f.result == "ABORT" for f in g)
            g = [f for f in g if f.result != "ABORT"]
            if len(g) < a.min:
                continue
            won = [f for f in g if f.result == "WON"]
            mw = [f.metrics() for f in won if f.metrics()]
            mall = [f.metrics() for f in g if f.metrics()]
            paired = ""
            if pol != "real":
                both = [f for f in g if f.key in real]
                if both:
                    rw = sum(real[f.key].result == "WON" for f in both)
                    pw = sum(f.result == "WON" for f in both)
                    paired = "%d keys: real %d won, %s %d won" % (len(both), rw, pol, pw)
            rows.append(["$%03X" % form, fname.get(form, "?"), ",".join(arcs[form]), pol, len(g),
                         len(won), unfinished, pct(med([m["low"] for m in mw])),
                         pct(min([m["low"] for m in mw]) if mw else None),
                         max([m["down"] for m in mall]) if mall else "-",
                         num(sum(f.deaths for f in g) / len(g), "%.2f"),
                         num(med([f.turns for f in won]), "%g"),
                         num(med([f.ticks for f in won if f.ticks]), "%g"),
                         num(med([m["doubt"] for m in mw]), "%g"),
                         num(med([m["flips"] for m in mw]), "%g"), paired])
    w = [max(len(str(r[i])) for r in rows + [hdr]) for i in range(len(hdr))]
    for r in [hdr] + rows:
        print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(r)).rstrip())
    if a.tsv:
        with open(a.tsv, "w") as fh:
            for r in [hdr] + rows:
                fh.write("\t".join(str(c) for c in r) + "\n")
    if a.fights:
        with open(a.fights, "w") as fh:
            fh.write("policy\tformation\tkey\tarc\tresult\tturns\tticks\tlow\tdown\tdeaths\tdoubt\tflips\tlog\n")
            for f in sorted(by.values(), key=lambda f: (f.form, f.policy, f.key)):
                m = f.metrics() or {}
                fh.write("%s\t$%03X\t%s\t%s\t%s\t%d\t%s\t%s\t%s\t%d\t%s\t%s\t%s\n" % (
                    f.policy, f.form, f.key, f.arc, f.result, f.turns, f.ticks, pct(m.get("low")),
                    m.get("down", "-"), f.deaths, m.get("doubt", "-"), m.get("flips", "-"), f.path))
                for ln in f.lines + ([f._worst[1]] if getattr(f, "_worst", None) else []):
                    fh.write("\t" + ln + "\n")


if __name__ == "__main__":
    sys.exit(main())
