#!/usr/bin/env python3
"""rizopaslab_actions.py -- per-run boss-phase digests for the Rizopas lab.

For each build/rizopaslab/<tag>_i<idle>.log: the [result] line, then one
line per action from Rizopas's surfacing on -- party actions ([act] start
lines for entities 0/1: command, attack, BP) with what they did to Rizopas
([hit] lines until the next action), Rizopas's own actions (entity 9:
attack id -> name) with what they did to the party ([hp] lines), deaths,
raises, and the driver's own care lines.  Everything printed is quoted or
folded from the log; nothing is inferred.

    python3 tools/tests/rizopaslab_actions.py [logdir] [--tag control] [--tag care]
    python3 tools/tests/rizopaslab_actions.py --compare control care bankboss

--compare prints one line per seed for each tag: outcome, frames, Fenix,
deaths, and the boss-phase action sequence.
"""
import re
import sys
from collections import OrderedDict
from pathlib import Path

CHAR = {0: "SABIN", 1: "CYAN", 9: "RIZOPAS"}
ATK = {0xEE: "Battle", 0xEF: "Special", 0xB8: "MegaVolt", 0x01: "Ice", 0x6F: "ElNino",
       0x5D: "Pummel", 0x5E: "AuraBolt", 0x5F: "Suplex", 0xE8: "Tonic", 0xE9: "Potion",
       0xF0: "FenixDown", 0xFF: "Fight", 0x0C: "death-script"}
CMD = {0x00: "Fight", 0x01: "Item", 0x02: "Magic", 0x0A: "Blitz", 0x0C: "MonMagic",
       0x12: "dead", 0x24: "script"}

RESULT = re.compile(r"\[result\] (.*)")
ACT = re.compile(r"\[act\] t=(\d+) start e(\d) cmd=\$([0-9A-F]+) atk=\$([0-9A-F]+) tgt=\$([0-9A-F]+) rizo=(\d+)/sh(\d+) brk=(\d+) .* hp=(\d+),(\d+) bp=(\d+)")
HIT = re.compile(r"\[hit\] t=(\d+) rizopas hp=(\d+) \(([-+]\d+)\) sh=(\d+) \(([-+]\d+)\) brk=(\d+)")
HP = re.compile(r"\[hp\] t=(\d+) entity (\d) (\d+) -> (\d+) \(([-+]\d+)\)")
DEATH = re.compile(r"\[death\] t=(\d+) entity (\d)")
RAISE = re.compile(r"\[raise\] t=(\d+) entity (\d) to (\d+)")
SURF = re.compile(r"\[lab\] t=(\d+) slot 5 SURFACED")
CARE = re.compile(r"\[(?:Rizopas|falls)\] (actor=\d (?:heal|revive|cure) .*|actor=\d PRESS: .*|actor=\d no press: .*|heal f\d+ e\d .*)")


def parse(path):
    result, events, surfaced = None, [], None
    for line in path.read_text(errors="replace").splitlines():
        m = RESULT.search(line)
        if m:
            result = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
            continue
        m = SURF.search(line)
        if m:
            surfaced = int(m.group(1))
            events.append(("surface", surfaced, "Rizopas surfaces"))
            continue
        m = ACT.search(line)
        if m:
            t, e, cmd, atk, tgt, rhp, rsh, brk, hp0, hp1, bp = m.groups()
            e = int(e)
            if e not in CHAR:
                continue
            cmd, atk = int(cmd, 16), int(atk, 16)
            if cmd == 0x12:
                continue
            what = ATK.get(atk, f"${atk:02X}")
            if cmd == 0x01:
                what = "Item " + what
            elif cmd == 0x0A:
                what = "Blitz " + what
            elif cmd == 0x24:
                what = "death script"
            bp = int(bp)
            s = f"{CHAR[e]} {what}" + (f"@{bp}BP" if e < 2 and bp else "")
            s += f" [rizo {rhp}/sh{rsh}{' BROKEN' if int(brk) else ''}; party {hp0},{hp1}]"
            events.append(("act", int(t), s))
            continue
        m = HIT.search(line)
        if m:
            t, hp, d, sh, ds, brk = m.groups()
            events.append(("hit", int(t), f"  -> rizopas {d} hp={hp} sh={sh} ({ds}){' BROKEN' if int(brk) else ''}"))
            continue
        m = HP.search(line)
        if m:
            t, e, a, b, d = m.groups()
            events.append(("hp", int(t), f"  -> {CHAR.get(int(e), e)} {a}->{b} ({d})"))
            continue
        m = DEATH.search(line)
        if m:
            events.append(("death", int(m.group(1)), f"  ** {CHAR.get(int(m.group(2)))} DIES"))
            continue
        m = RAISE.search(line)
        if m:
            events.append(("raise", int(m.group(1)), f"  ** {CHAR.get(int(m.group(2)))} raised to {m.group(3)}"))
            continue
        m = CARE.search(line)
        if m:
            events.append(("care", None, f"  | {m.group(1)}"))
    return result, events, surfaced


def rows(logdir, tag):
    out = OrderedDict()
    for log in sorted(logdir.glob(f"{tag}_i*.log"), key=lambda p: [int(x) for x in re.findall(r"\d+", p.name[len(tag):])]):
        r, ev, surf = parse(log)
        if r is None:
            print(f"[no result] {log}")
            continue
        out[r["seed"]] = (log, r, ev, surf)
    return out


def boss_phase(ev, surf):
    if surf is None:
        return ev
    keep, on = [], False
    for kind, t, s in ev:
        if kind == "surface":
            on = True
        if on:
            keep.append((kind, t, s))
    return keep


def print_tag(logdir, tag):
    for seed, (log, r, ev, surf) in rows(logdir, tag).items():
        print(f"== {tag} idle={r['idle']} seed={seed} be_up={r['be_up']} {r['outcome']} t={r['t']} boss={r['t_boss']} "
              f"fenix={r['fenix']} potion={r['potion']} deaths={r['deaths']} ({log.name})")
        for kind, t, s in boss_phase(ev, surf):
            print(f"   t={t if t is not None else '':>5} {s}")


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
                print(f"   {t:9} (no run)")
                continue
            log, r, ev, surf = got
            seq = "; ".join(x[2].split(" [")[0] for x in boss_phase(ev, surf) if x[0] == "act")
            print(f"   {t:9} idle={r['idle']:>2} {r['outcome']:<12} t={r['t']:>5} boss={r['t_boss']:>5} fenix={r['fenix']} "
                  f"potion={r['potion']} deaths={r['deaths']} bp@surface={r['bp_at_surface']}")
            print(f"   {'':9} {seq}")


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
    logdir = Path("build/rizopaslab")
    if cmp_:
        compare(logdir, tags or paths)
        return
    if paths:
        logdir = Path(paths[0])
    for t in tags or ["control"]:
        print_tag(logdir, t)


if __name__ == "__main__":
    main()
