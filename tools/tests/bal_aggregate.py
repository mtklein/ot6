#!/usr/bin/env python3
"""Aggregate bal_mines.lua [metrics] blocks into a per-policy summary table.

Usage: bal_aggregate.py <log> [<log> ...]

Each log carries per-battle lines of the form
    [ot6] [metrics] b=<k> <key>=<value>
one policy per log (the policy key repeats per battle). Voided samples
(key `void`) are tallied separately and excluded from averages.
"""
import re
import sys
from collections import defaultdict

SPECIES = {"0013": "Rat", "0046": "Vap", "004D": "Repo"}


def parse(path):
    battles = defaultdict(dict)
    for line in open(path):
        m = re.match(r"\[ot6\] \[metrics\] b=(\d+) (\w+)=(.*)", line.strip())
        if not m:
            continue
        k, key, val = int(m.group(1)), m.group(2), m.group(3)
        if key == "mon_detail":
            battles[k].setdefault("mon_detail", []).append(val)
        else:
            battles[k][key] = val
    return battles


def fnum(b, key):
    return float(b.get(key, 0) or 0)


def main():
    rows = []
    for path in sys.argv[1:]:
        battles = parse(path)
        if not battles:
            print(f"{path}: no metrics lines", file=sys.stderr)
            continue
        policy = next(iter(battles.values())).get("policy", path)
        valid = [b for b in battles.values() if "void" not in b]
        voids = [b for b in battles.values() if "void" in b]
        n = len(valid)
        forms = defaultdict(int)
        for b in valid:
            f = ",".join(SPECIES.get(s, s) for s in b.get("formation", "").split(","))
            forms[f] += 1
        boosts = defaultdict(int)
        for b in valid:
            for part in b.get("boosts_spent", "").split(","):
                lvl, cnt = part.split(":")
                boosts[lvl] += int(cnt)
        row = {
            "policy": policy,
            "battles": n,
            "voids": len(voids),
            "formations": " ".join(f"{v}x[{k}]" for k, v in sorted(forms.items())),
            "won": sum(1 for b in valid if b.get("result") == "won"),
            "wiped": sum(1 for b in valid if b.get("result") == "wiped"),
            "other": sum(1 for b in valid if b.get("result") not in ("won", "wiped")),
            "avg_turns": sum(fnum(b, "player_actions") for b in valid) / n,
            "avg_frames": sum(fnum(b, "frames") for b in valid) / n,
            "avg_dmg_dealt": sum(fnum(b, "player_dmg") for b in valid) / n,
            "avg_dmg_taken": sum(fnum(b, "enemy_dmg") for b in valid) / n,
            "chips": sum(int(fnum(b, "shield_chips")) for b in valid),
            "breaks": sum(int(fnum(b, "breaks")) for b in valid),
            "boosts": ",".join(f"{k}:{v}" for k, v in sorted(boosts.items())),
            "bp_regen": sum(int(fnum(b, "bp_regen")) for b in valid),
            "avg_mp_spent": sum(34 - fnum(b, "terra_mp_end") for b in valid) / n,
            "min_hp_end": min((int(fnum(b, "terra_hp_end")) for b in valid), default=0),
        }
        rows.append(row)
        # per-battle detail line for the appendix
        print(f"## {policy} ({path})")
        for k in sorted(battles):
            b = battles[k]
            if "void" in b:
                print(f"  b={k} VOID {b['void']} (steps={b.get('steps_paced')})")
                continue
            f = ",".join(SPECIES.get(s, s) for s in b.get("formation", "").split(","))
            print(
                f"  b={k} {f:<10} {b.get('result'):<6} turns={b.get('player_actions'):>2}"
                f" frames={b.get('frames'):>5} dealt={b.get('player_dmg'):>3}"
                f" taken={b.get('enemy_dmg'):>2} chips={b.get('shield_chips')}"
                f" breaks={b.get('breaks')} boosts={b.get('boosts_spent')}"
                f" regen={b.get('bp_regen')} hp_end={b.get('terra_hp_end')}"
                f" mp_end={b.get('terra_mp_end')} bp={b.get('bp_curve')}"
            )
        print()

    hdr = ["policy", "battles", "voids", "won", "wiped", "other", "avg_turns",
           "avg_frames", "avg_dmg_dealt", "avg_dmg_taken", "chips", "breaks",
           "boosts", "bp_regen", "avg_mp_spent", "min_hp_end"]
    widths = {h: max(len(h), *(len(f"{r[h]:.1f}" if isinstance(r[h], float) else str(r[h]))
                               for r in rows)) for h in hdr}
    print(" | ".join(h.ljust(widths[h]) for h in hdr))
    print("-+-".join("-" * widths[h] for h in hdr))
    for r in rows:
        cells = [f"{r[h]:.1f}" if isinstance(r[h], float) else str(r[h]) for h in hdr]
        print(" | ".join(c.ljust(widths[h]) for c, h in zip(cells, hdr)))
    print()
    print("formation mixes:")
    for r in rows:
        print(f"  {r['policy']}: {r['formations']}")


if __name__ == "__main__":
    main()
