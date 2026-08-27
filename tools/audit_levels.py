#!/usr/bin/env python3
"""Measure the ACTUAL party levels the route banks at every checkpoint.

Read-only companion to audit_party_hp.py: reads the same .mss fixtures and
tracked SRAM checkpoints with no emulator, but reports progression rather
than casualties -- per enrolled character LEVEL, max HP, max MP, and
experience (record offset +$11, three bytes; ff6/notes/field-ram.txt:898),
so the table joins mechanically against a healthy-curve table keyed by
savestate-graph name.

Three views:

  - the table: one row per on-disk state/checkpoint, in savestate-graph
    play order (tools/tests/savestate_graph.py STATES order), each row
    listing every enrolled character (party byte $1850+c low 3 bits
    nonzero, audit_party_hp's convention) as NAME Lnn maxhp/maxmp, plus
    total party XP;
  - the deltas: for consecutive rows in play order, which characters
    gained how many levels across that segment;
  - the stragglers: any state where an enrolled character's level trails
    the party's best by STRAGGLER_GAP or more (split-party artifacts).

Usage:  python3 tools/audit_levels.py [--dir build/states] [--repo .]
                                      [--csv] [--selftest]
Always exits 0 (measurement, not a gate) unless --selftest fails.
"""

from __future__ import annotations

import argparse
import glob
import importlib.util
import os
import re
import sys

# Explicit rather than relying on sys.path[0], which PYTHONSAFEPATH and
# `python3 -P` both switch off.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (CHAR_BLOCK, REC, biggest_stream,
                             checkpoint_payloads, find_char_block, party_at,
                             split_orphans, stem_of)

GRAPH = "tools/tests/savestate_graph.py"
EXP_OFF = 0x11        # experience, 3 bytes, $1611 (ff6/notes/field-ram.txt)
STRAGGLER_GAP = 3     # levels behind the party's best that earns a flag


def graph_states(repo: str) -> list[dict]:
    """The savestate graph's STATES list, in play order; [] if unreadable."""
    path = os.path.join(repo, GRAPH)
    try:
        spec = importlib.util.spec_from_file_location("savestate_graph", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return list(mod.STATES)
    except Exception:
        return []


def with_exp(raw: bytes, cb: int) -> list[dict]:
    """party_at()'s records, each with the 3-byte experience word added."""
    party = party_at(raw, cb)
    for m in party:
        rec = cb + REC * m["char"] + EXP_OFF
        m["exp"] = int.from_bytes(raw[rec:rec + 3], "little")
    return party


def read_state(path: str):
    """Enrolled characters (with exp) in one .mss, or (None, reason)."""
    raw = biggest_stream(path)
    if raw is None:
        return None, "no zlib stream"
    cb = find_char_block(raw)
    if cb is None:
        return None, "character table not located (or ambiguous)"
    return with_exp(raw, cb), None


def plausible_table(raw: bytes, b: int) -> bool:
    """True when the first 8 records at b carry levels the game allows.

    Disambiguates the two-hit case in the late-WoB checkpoints: the alias
    one byte in (through the graphic-index column, which also counts
    0,1,2,... for the canonical cast) reads garbage levels like 133 and
    232 where the real table reads 14..17.
    """
    return all(1 <= raw[b + REC * c + 8] <= 99 for c in range(8))


def resolve_char_block(raw: bytes) -> int | None:
    """find_char_block, then the plausibility filter over an ambiguous scan.

    Same shape signature as savestate_party.find_char_block (records 0..n
    carry actor ids whose low nibble is the record index); where that scan
    finds several candidates, keep only the ones whose levels are legal.
    """
    cb = find_char_block(raw, allow_fallback=False)
    if cb is not None:
        return cb
    for n in range(11, 7, -1):
        hits = [b for b in range(0, len(raw) - REC * n)
                if all((raw[b + REC * c] & 0x0F) == c for c in range(n))
                and plausible_table(raw, b)]
        if len(hits) == 1:
            return hits[0]
    return None


def read_checkpoint(path: str):
    """Enrolled characters (with exp) in one tracked SRAM payload."""
    try:
        raw = open(path, "rb").read()
    except OSError as e:
        return None, str(e)
    cb = resolve_char_block(raw)
    if cb is None:
        return None, "character table not located (or ambiguous)"
    return with_exp(raw, cb), None


def collect(repo: str, states_dir: str):
    """Every readable measurement, ordered by the graph's play order.

    Returns (rows, skipped, orphans).  A row is (key, kind, party) where
    key is the savestate-graph name for fixtures and the checkpoint
    directory name for SRAM payloads (slotted at the graph position of the
    first state that boots from it).  Fixtures and the checkpoint they
    boot from measure the same story moment from different files, so both
    appear; the kind column tells them apart.
    """
    states = graph_states(repo)
    order: dict[str, float] = {}
    for i, s in enumerate(states):
        order[s["state"]] = i
        for extra in s.get("also") or []:
            order.setdefault(extra, i + 0.5)
    cp_order = {s["checkpoint"]: i for i, s in enumerate(states)
                if s.get("checkpoint")}

    rows, skipped = [], []
    files = sorted(glob.glob(os.path.join(states_dir, "*.mss")))
    files, orphans = split_orphans(files, set(order) or set())
    for p in files:
        party, err = read_state(p)
        stem = stem_of(p)
        if err:
            skipped.append((stem, err))
            continue
        rows.append((stem, "fixture", party))
    for name, payload in checkpoint_payloads(repo):
        party, err = read_checkpoint(payload)
        if err:
            skipped.append((f"checkpoint {name}", err))
            continue
        rows.append((name, "checkpoint", party))

    big = len(states) + len(rows) + 1

    def slot(row):
        key, kind, _ = row
        if kind == "fixture":
            return (order.get(key, big), 1)
        # A checkpoint measures the moment BEFORE the state that boots it;
        # one no state boots (a capture parked for a later edge) sits just
        # after the state it is named for, if the graph knows that name.
        if key in cp_order:
            return (cp_order[key], 0)
        named = re.sub(r"-v\d+$", "", key).replace("-", "_")
        if named in order:
            return (order[named], 2)
        return (big, 0)

    rows.sort(key=slot)
    on_route = [r for r in rows if slot(r)[0] < big]
    return rows, on_route, skipped, orphans


def fmt_row(key: str, kind: str, party: list[dict]) -> str:
    who = "  ".join(f"{m['name']} L{m['level']:<2d} "
                    f"{m['maxhp']}hp/{m['maxmp']}mp"
                    for m in party)
    xp = sum(m["exp"] for m in party)
    tag = "c" if kind == "checkpoint" else " "
    return f"  {tag} {key:26s} xp={xp:<8d} {who}"


def deltas(rows) -> list[str]:
    """Level gains between consecutive rows, for characters both carry."""
    out = []
    prev_key, prev = None, None
    for key, kind, party in rows:
        cur = {m["name"]: m["level"] for m in party}
        if prev is not None:
            gains = [(n, cur[n] - prev[n]) for n in cur
                     if n in prev and cur[n] != prev[n]]
            if gains:
                gains.sort(key=lambda g: -g[1])
                s = " ".join(f"{n}{d:+d}" for n, d in gains)
                out.append(f"  {prev_key} -> {key}: {s}")
        prev_key, prev = key, cur
    return out


def stragglers(rows) -> list[str]:
    out = []
    for key, kind, party in rows:
        if len(party) < 2:
            continue
        best = max(m["level"] for m in party)
        for m in party:
            if best - m["level"] >= STRAGGLER_GAP:
                out.append(f"  {key}: {m['name']} L{m['level']} trails the "
                           f"party's best L{best} by {best - m['level']}")
    return out


# ---------------------------------------------------------------- selftest --

def selftest(repo: str) -> int:
    bad = []
    states = graph_states(repo)
    if not states or states[0]["state"] != "battle_entry":
        bad.append(f"graph_states should start at battle_entry, "
                   f"got {states[:1]}")
    cps = dict(checkpoint_payloads(repo))
    if "n024-entry-save-v1" in cps:
        party, err = read_checkpoint(cps["n024-entry-save-v1"])
        # Levels and exp cross-checked against the same four records
        # audit_party_hp's selftest pins by HP for this checkpoint.
        got = {m["name"]: m["level"] for m in (party or [])}
        if err or set(got) != {"LOCKE", "EDGAR", "SABIN", "CELES"}:
            bad.append(f"n024-entry-save-v1 should carry Locke, Edgar, "
                       f"Sabin, Celes; got {err or got}")
        elif any(not (1 <= lv <= 99) for lv in got.values()):
            bad.append(f"levels out of range: {got}")
        if party and any(m["exp"] == 0 or m["exp"] > 0xFFFFFF
                         for m in party):
            bad.append(f"exp out of range: "
                       f"{[(m['name'], m['exp']) for m in party]}")
    else:
        bad.append("checkpoint n024-entry-save-v1 not found")
    for line in bad:
        print(f"  SELFTEST FAIL {line}")
    print(f"audit_levels selftest: {3 if not bad else len(bad)} checks, "
          f"{len(bad)} failed")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--csv", action="store_true",
                    help="machine-readable long form: key,kind,char,level,"
                         "maxhp,maxmp,exp")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest(args.repo)

    rows, on_route, skipped, orphans = collect(args.repo, args.dir)

    if args.csv:
        print("key,kind,char,level,maxhp,maxmp,exp,party,active")
        for key, kind, party in rows:
            for m in party:
                print(f"{key},{kind},{m['name']},{m['level']},{m['maxhp']},"
                      f"{m['maxmp']},{m['exp']},{m['party']},"
                      f"{int(m['active'])}")
        return 0

    print(f"actual levels: {len(rows)} state(s)/checkpoint(s) read, in "
          f"savestate-graph play order (c = tracked SRAM checkpoint)")
    for key, kind, party in rows:
        print(fmt_row(key, kind, party))
    for name, err in skipped:
        print(f"  ?  {name}: {err}")
    if orphans:
        print(f"  ({len(orphans)} file(s) the graph no longer declares, "
              f"skipped: " + ", ".join(orphans) + ")")

    off = [key for key, kind, _ in rows
           if (key, kind) not in {(k, kd) for k, kd, _ in on_route}]
    if off:
        print(f"  (off-route, excluded from deltas: " + ", ".join(off) + ")")

    d = deltas(on_route)
    print(f"\nper-segment level gains ({len(d)} segment(s) with a change):")
    for line in d or ["  (none)"]:
        print(line)

    s = stragglers(rows)
    print(f"\nstragglers ({STRAGGLER_GAP}+ levels behind the party's best):")
    for line in s or ["  (none)"]:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
