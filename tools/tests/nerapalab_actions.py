#!/usr/bin/env python3
"""nerapalab_actions.py -- per-seed action tables for the Nerapa lab.

Folds each build/nerapalab/<tag>_i<idle>.log into one row per party action:
what each actor did on each turn ([act] start/end lines, ExecCmd/SaveForMimic
observers in lab_nerapa_template.lua), what it did to Nerapa ([hit] lines
inside the action's window), what it did to the party ([hp] lines inside
the window, a reflected spell shows here), and the driver's own reasons
([Nerapa] PRESS / no press / refused / Fighting (#156)) uttered since the
previous party action.  Deaths and raises are listed where they land.

    python3 tools/tests/nerapalab_actions.py [logdir] [--tag control] [--tag treat]
    python3 tools/tests/nerapalab_actions.py --compare control treat

--compare prints one line per seed for each tag side by side (outcome,
frames, Fenix, deaths, the action sequence), matched by the seed the log's
[result] line names, so the same InitBattle seed is read across policies
or driver versions.  Everything printed is quoted or folded from the log;
nothing is inferred.
"""
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

CHAR = {0: "TERRA", 1: "LOCKE", 2: "EDGAR", 3: "CELES"}   # doorstep party slots
CMD = {0x00: "Fight", 0x01: "Item", 0x02: "Magic", 0x09: "Tools",
       0x0A: "Blitz", 0x0C: "Lore", 0x12: "dead-entity", 0x19: "Summon"}
SPELL = {0x00: "Fire", 0x01: "Ice", 0x02: "Bolt", 0x05: "Fire2", 0x06: "Ice2",
         0x07: "Bolt2", 0x09: "Fire3", 0x0A: "Ice3", 0x0B: "Bolt3",
         0x2D: "Cure", 0x2E: "Cure2", 0x2F: "Cure3", 0x33: "Life",
         0x38: "Shiva", 0xAA: "AutoCrossbow", 0xA4: "BioBlaster",
         0xE8: "Tonic", 0xE9: "Potion", 0xF0: "FenixDown"}

ACT = re.compile(r"\[act\] t=(\d+) (start|end)\s+e(\d) (.*)")
ACT_START = re.compile(r"cmd=\$([0-9A-F]+) atk=\$([0-9A-F]+) tgt=\$([0-9A-F]+) "
                       r"nerapa=(\d+)/sh(\d+) st=([0-9A-F,]+) hp=([\d,]+) bp=(\d+)")
HIT = re.compile(r"\[hit\] t=(\d+) nerapa hp=(\d+) \(([-+]\d+)\) sh=(\d+) \(([-+]\d+)\)")
HP = re.compile(r"\[hp\] t=(\d+) entity (\d) (\d+) -> (\d+) \(([-+]\d+)\)")
DEATH = re.compile(r"\[death\] t=(\d+) entity (\d) \((\w+);")
RAISE = re.compile(r"\[raise\] t=(\d+) entity (\d) to (\d+) hp")
RESULT = re.compile(r"\[result\] (.*)")
DRIVER = re.compile(r"\[Nerapa\] (actor=\d PRESS:.*|actor=\d no press:.*|"
                    r"(?:nuke|cast|lore) \$[0-9A-F]+ refused:.*|"
                    r"actor=\d Fight at \d BP chips .*Fighting \(#156\)|"
                    r"actor=\d's \w+ took .*)")


def describe(cmd, atk, boost):
    name = CMD.get(cmd, f"cmd${cmd:02X}")
    if cmd == 0x00:
        what = "Fight"
    elif cmd in (0x01, 0x02, 0x09, 0x19, 0x0C):
        what = f"{name} {SPELL.get(atk, f'${atk:02X}')}"
    elif cmd == 0x12:
        # the engine runs $12 for a member at 0 HP (every occurrence in the
        # lab logs has that entity's hp=0 at start); no player input behind it
        what = "dead-entity cmd $12"
    else:
        what = f"{name} ${atk:02X}"
    return f"{what}@{boost}BP" if boost else what


def parse(path):
    """One log -> dict(result=kv, actions=[...], notes=[...])."""
    result, actions, notes = None, [], []
    pending = {}          # entity -> open action
    since = []            # driver lines since the last party action started
    for line in path.read_text(errors="replace").splitlines():
        m = RESULT.search(line)
        if m:
            result = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
            continue
        m = DRIVER.search(line)
        if m:
            since.append(m.group(1))
            continue
        m = ACT.search(line)
        if m:
            t, phase, e, rest = int(m.group(1)), m.group(2), int(m.group(3)), m.group(4)
            if e > 3:
                continue
            if phase == "start":
                s = ACT_START.search(rest)
                cmd, atk, boost = int(s.group(1), 16), int(s.group(2), 16), int(s.group(8))
                a = {"t": t, "e": e, "what": describe(cmd, atk, boost),
                     "hp0": int(s.group(4)), "sh0": int(s.group(5)),
                     "party0": s.group(7), "hits": [], "party": [], "why": since,
                     "end": None}
                since = []
                pending[e] = a
                actions.append(a)
            else:
                a = pending.pop(e, None)
                if a:
                    a["end"] = t
            continue
        m = HIT.search(line)
        if m:
            t = int(m.group(1))
            # credit to the open action that started most recently
            open_ = [a for a in pending.values()]
            if open_:
                a = max(open_, key=lambda a: a["t"])
                a["hits"].append((int(m.group(3)), int(m.group(5)), int(m.group(2)), int(m.group(4))))
            else:
                notes.append(f"t={t} hit outside any party action: {line.split('] ', 2)[-1]}")
            continue
        m = HP.search(line)
        if m:
            t, e, d = int(m.group(1)), int(m.group(2)), int(m.group(5))
            open_ = [a for a in pending.values()]
            if open_:
                a = max(open_, key=lambda a: a["t"])
                a["party"].append((e, d))
            continue
        m = DEATH.search(line)
        if m:
            notes.append(f"t={m.group(1)} DEATH {CHAR[int(m.group(2))]} ({m.group(3)})")
            continue
        m = RAISE.search(line)
        if m:
            notes.append(f"t={m.group(1)} RAISE {CHAR[int(m.group(2))]} to {m.group(3)}")
    return {"result": result, "actions": actions, "notes": notes}


def fold(a):
    dmg = sum(-d for d, _, _, _ in a["hits"] if d < 0)
    chips = sum(-c for _, c, _, _ in a["hits"] if c < 0)
    s = f"t={a['t']} {CHAR[a['e']]} {a['what']}"
    if a["hits"]:
        last = a["hits"][-1]
        s += f" -> nerapa -{dmg} ({len(a['hits'])} hit{'s' if len(a['hits']) != 1 else ''}, sh {a['sh0']}->{last[3]}, hp {a['hp0']}->{last[2]})"
    else:
        s += f" -> nerapa untouched ({a['hp0']}/sh{a['sh0']})"
    party = [f"{CHAR[e]}{d:+d}" for e, d in a["party"]]
    if party:
        s += " party " + ",".join(party)
    return s


def rows(logdir, tag):
    out = OrderedDict()
    for log in sorted(logdir.glob(f"{tag}_i*.log"), key=lambda p: int(re.search(r"_i(\d+)", p.name).group(1))):
        d = parse(log)
        if d["result"] is None:
            print(f"[no result] {log}")
            continue
        out[d["result"]["seed"]] = (log, d)
    return out


def print_tag(logdir, tag):
    for seed, (log, d) in rows(logdir, tag).items():
        r = d["result"]
        print(f"== {tag} idle={r['idle']} seed={seed} {r['outcome']} t={r['t']} fenix={r['fenix']} "
              f"potion={r['potion']} deaths={r['deaths']} ({log.name})")
        for a in d["actions"]:
            for w in a["why"]:
                print(f"     | {w}")
            print("   " + fold(a))
        for n in d["notes"]:
            print("   " + n)


def compare(logdir, tags):
    tables = {t: rows(logdir, t) for t in tags}
    seeds = []
    for t in tags:
        for s in tables[t]:
            if s not in seeds:
                seeds.append(s)
    for s in seeds:
        print(f"== seed {s}")
        for t in tags:
            got = tables[t].get(s)
            if not got:
                print(f"   {t:8} (no run)")
                continue
            log, d = got
            r = d["result"]
            seq = "; ".join(f"{CHAR[a['e']]} {a['what']}" for a in d["actions"] if not a["what"].startswith("dead-entity"))
            print(f"   {t:8} idle={r['idle']:>2} {r['outcome']:<14} t={r['t']:>5} fenix={r['fenix']} potion={r['potion']} "
                  f"deaths={r['deaths']}")
            print(f"   {'':8} {seq}")


def main():
    args = sys.argv[1:]
    tags, paths, cmp_ = [], [], False
    i = 0
    while i < len(args):
        if args[i] == "--tag":
            tags.append(args[i + 1]); i += 2
        elif args[i] == "--compare":
            cmp_ = True; i += 1
        elif args[i].startswith("--"):
            i += 1
        else:
            paths.append(args[i]); i += 1
    if cmp_:
        tags = tags or paths
        logdir = Path("build/nerapalab")
        compare(logdir, tags)
        return
    logdir = Path(paths[0]) if paths else Path("build/nerapalab")
    for t in tags or ["control"]:
        print_tag(logdir, t)


if __name__ == "__main__":
    main()
