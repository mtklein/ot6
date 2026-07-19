#!/usr/bin/env python3
"""Aggregate bal_*.lua [metrics] blocks into a per-policy summary table.

Usage: bal_aggregate.py <log> [<log> ...]

Each log carries per-battle lines of the form
    [ot6] [metrics] b=<k> <key>=<value>
one policy per log (the policy key repeats per battle). Voided samples
(key `void`) are tallied separately and excluded from averages.
player_actions/enemy_actions are real actions (the drivers de-duplicate
the two-queue dequeue count as of 2026-07-17; logs from before then
carry 2x on those two keys).

MULTI-CHARACTER (2026-07-18). bal_party.lua adds a per-party-slot fan-out
on top of the same protocol, using the `sN:value` CSV convention the
monster lines already used, e.g.

    char_dmg=s0:15,s1:18        char_actions=s0:1,s1:1
    party=s0:01:LOCKE,s1:00:TERRA

Nothing was renamed: the aggregate keys keep their old meaning, so
bal_mines and metrics_battle logs from before the fan-out still tabulate
exactly as they did -- the per-character sections simply do not render
for a log that has no char_* lines. Where a column was solo-Terra
specific (MP spent, ending HP) it now reads the party lines when they are
present and falls back to the old `terra_*` keys when they are not.

The drivers also publish identity checks per battle (actions/dmg/chips/
breaks each get a _sum and a _residual, plus bp_action_skew). Those are
not averaged -- they are asserted: any nonzero residual in any battle is
reported loudly, because a fan-out that does not sum to its total is not
a measurement.
"""
import re
import sys
from collections import defaultdict

SPECIES = {"0013": "Rat", "0046": "Vap", "004D": "Repo", "0017": "0017"}

# residual keys that must be zero in every battle for the run to mean
# anything; bp_action_skew is deliberately NOT here (a steady -1 is its
# documented resting value -- see metrics_battle.lua)
RESIDUALS = ("actions_residual", "dmg_residual", "chips_residual",
             "breaks_residual", "dmg_taken_residual")


def parse(path):
    battles = defaultdict(dict)
    for line in open(path):
        m = re.match(r"\[ot6\] \[metrics\] b=(\d+) (\w+)=(.*)", line.strip())
        if not m:
            continue
        k, key, val = int(m.group(1)), m.group(2), m.group(3)
        if key in ("mon_detail", "member"):
            battles[k].setdefault(key, []).append(val)
        else:
            battles[k][key] = val
    return battles


def fnum(b, key):
    return float(b.get(key, 0) or 0)


def slotcsv(val):
    """`s0:15,s1:18` -> {0: '15', 1: '18'}. Tolerates empty and absent."""
    out = {}
    for part in (val or "").split(","):
        if not part.startswith("s") or ":" not in part:
            continue
        slot, _, rest = part.partition(":")
        try:
            out[int(slot[1:])] = rest
        except ValueError:
            pass
    return out


def slotnum(b, key, slot):
    v = slotcsv(b.get(key, "")).get(slot)
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def party_of(battles):
    """slot -> name, from the first battle that names one. {} for old logs."""
    for b in battles.values():
        p = slotcsv(b.get("party", ""))
        if p:
            # values look like "01:LOCKE"
            return {s: v.split(":", 1)[-1] for s, v in p.items()}
    return {}


def check_residuals(policy, battles):
    """Any nonzero residual is a measurement failure, not a rounding note."""
    bad = []
    for k in sorted(battles):
        b = battles[k]
        if "void" in b:
            continue
        for key in RESIDUALS:
            if key in b and fnum(b, key) != 0:
                bad.append(f"b={k} {key}={b[key]}")
    if bad:
        print(f"  !! {policy}: NONZERO RESIDUALS -- {'; '.join(bad)}")
    return not bad


def main():
    rows, charrows = [], []
    all_ok = True
    for path in sys.argv[1:]:
        battles = parse(path)
        if not battles:
            print(f"{path}: no metrics lines", file=sys.stderr)
            continue
        policy = next(iter(battles.values())).get("policy", path)
        buff = next(iter(battles.values())).get("buff_hp")
        label = policy if buff in (None, "0") else f"{policy}/hp{buff}"
        valid = [b for b in battles.values() if "void" not in b]
        voids = [b for b in battles.values() if "void" in b]
        n = len(valid) or 1
        forms = defaultdict(int)
        for b in valid:
            f = ",".join(SPECIES.get(s, s) for s in b.get("formation", "").split(","))
            forms[f] += 1
        boosts = defaultdict(int)
        for b in valid:
            for part in b.get("boosts_spent", "").split(","):
                if ":" not in part:
                    continue
                lvl, cnt = part.split(":")
                boosts[lvl] += int(cnt)
        # party HP/MP: prefer the fan-out, fall back to the solo keys
        party = party_of(battles)
        if party:
            mp_spent = [sum(slotnum(b, "char_mp_spent", s) for s in party)
                        for b in valid]
            hp_end = [min((slotnum(b, "char_hp_end", s) for s in party),
                          default=0) for b in valid]
        else:
            mp_spent = [34 - fnum(b, "terra_mp_end") for b in valid]
            hp_end = [fnum(b, "terra_hp_end") for b in valid]
        row = {
            "policy": label,
            "battles": len(valid),
            "voids": len(voids),
            "formations": " ".join(f"{v}x[{k}]" for k, v in sorted(forms.items())),
            "won": sum(1 for b in valid if b.get("result") == "won"),
            "wiped": sum(1 for b in valid if b.get("result") == "wiped"),
            "other": sum(1 for b in valid if b.get("result") not in ("won", "wiped")),
            "avg_turns": sum(fnum(b, "player_actions") for b in valid) / n,
            "avg_frames": sum(fnum(b, "frames") for b in valid) / n,
            "avg_dmg_dealt": sum(fnum(b, "player_dmg") for b in valid) / n,
            "avg_dmg_taken": sum(fnum(b, "enemy_dmg") for b in valid) / n,
            "enemyA": sum(fnum(b, "enemy_actions") for b in valid) / n,
            "chips": sum(int(fnum(b, "shield_chips")) for b in valid),
            "breaks": sum(int(fnum(b, "breaks")) for b in valid),
            "boosts": ",".join(f"{k}:{v}" for k, v in sorted(boosts.items())),
            "bp_regen": sum(int(fnum(b, "bp_regen")) for b in valid),
            "avg_mp_spent": sum(mp_spent) / n,
            "min_hp_end": int(min(hp_end, default=0)),
        }
        rows.append(row)
        all_ok &= check_residuals(label, battles)

        # per-character rollup, one row per (policy, party slot)
        for slot in sorted(party):
            plans = defaultdict(int)
            for b in valid:
                for tok in slotcsv(b.get("char_plan", "")).get(slot, "").split("+"):
                    if "*" in tok:
                        tag, cnt = tok.rsplit("*", 1)
                        plans[tag] += int(cnt)
            lvl = [0, 0, 0]
            for b in valid:
                trio = slotcsv(b.get("char_boosts", "")).get(slot, "0/0/0")
                for i, c in enumerate(trio.split("/")[:3]):
                    lvl[i] += int(c or 0)
            charrows.append({
                "policy": label,
                "slot": f"s{slot}",
                "who": party[slot],
                "actions": sum(slotnum(b, "char_actions", slot) for b in valid) / n,
                "dmg": sum(slotnum(b, "char_dmg", slot) for b in valid) / n,
                "dmg_brk": sum(slotnum(b, "char_dmg_broken", slot) for b in valid) / n,
                "chips": int(sum(slotnum(b, "char_chips", slot) for b in valid)),
                "breaks": int(sum(slotnum(b, "char_breaks", slot) for b in valid)),
                "bp_spent": int(sum(slotnum(b, "char_bp_spent", slot) for b in valid)),
                "boosts": "{}/{}/{}".format(*lvl),
                "taken": sum(slotnum(b, "char_dmg_taken", slot) for b in valid) / n,
                "mp": sum(slotnum(b, "char_mp_spent", slot) for b in valid) / n,
                "did": " ".join(f"{t}x{c}" for t, c in sorted(plans.items())) or "-",
            })

        # per-battle detail line for the appendix
        print(f"## {label} ({path})")
        for k in sorted(battles):
            b = battles[k]
            if "void" in b:
                print(f"  b={k} VOID {b['void']} (steps={b.get('steps_paced')})")
                continue
            f = ",".join(SPECIES.get(s, s) for s in b.get("formation", "").split(","))
            line = (
                f"  b={k} {f:<10} {b.get('result'):<6} turns={b.get('player_actions'):>2}"
                f" frames={b.get('frames'):>5} dealt={b.get('player_dmg'):>4}"
                f" taken={b.get('enemy_dmg'):>3} chips={b.get('shield_chips')}"
                f" breaks={b.get('breaks')} boosts={b.get('boosts_spent')}"
                f" regen={b.get('bp_regen')}"
            )
            if "char_dmg" in b:
                line += (f" | per-char dmg={b.get('char_dmg')}"
                         f" act={b.get('char_actions')}"
                         f" chips={b.get('char_chips')}"
                         f" did={b.get('char_plan')}")
            else:
                line += (f" hp_end={b.get('terra_hp_end')}"
                         f" mp_end={b.get('terra_mp_end')}")
            print(line)
        print()

    def table(hdr, data):
        if not data:
            return
        widths = {h: max(len(h), *(len(f"{r[h]:.1f}" if isinstance(r[h], float)
                                       else str(r[h])) for r in data)) for h in hdr}
        print(" | ".join(h.ljust(widths[h]) for h in hdr))
        print("-+-".join("-" * widths[h] for h in hdr))
        for r in data:
            cells = [f"{r[h]:.1f}" if isinstance(r[h], float) else str(r[h])
                     for h in hdr]
            print(" | ".join(c.ljust(widths[h]) for c, h in zip(cells, hdr)))
        print()

    table(["policy", "battles", "voids", "won", "wiped", "other", "avg_turns",
           "avg_frames", "avg_dmg_dealt", "avg_dmg_taken", "enemyA", "chips",
           "breaks", "boosts", "bp_regen", "avg_mp_spent", "min_hp_end"], rows)
    if charrows:
        print("per character (averages are per battle):")
        table(["policy", "slot", "who", "actions", "dmg", "dmg_brk", "chips",
               "breaks", "bp_spent", "boosts", "taken", "mp", "did"], charrows)
    print("formation mixes:")
    for r in rows:
        print(f"  {r['policy']}: {r['formations']}")
    if not all_ok:
        print("\nFAILED: at least one battle's per-character stats do not sum "
              "to its totals; the fan-out is not trustworthy for that run.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
