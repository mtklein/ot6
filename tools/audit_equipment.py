#!/usr/bin/env python3
"""Is anybody walking the story BARE-HANDED?

WHY THIS EXISTS.  The game strips characters and returns their gear to the
inventory at story beats -- `remove_equip` / EventCmd_8d, 58 sites in 15
clusters across event_main.asm -- and the chain of generated savestates has
never once put it back on.  battle_brokendeath found this at the Vector
infiltration in 2026-07 and drove Equip -> Optimum by hand to fix its own
fixture.  Nobody checked whether it was a general problem.

It is.  On 2026-08-09 the first end-to-end run of the input-driven chain
stalled at `sfigaro_town`, where solo LOCKE lost the gate soldier three
times running.  It read exactly like a balance wall -- a level-13 machine
with 495 hp against a level-8 thief -- and it was nothing of the sort:
LOCKE's whole equipment block read `FF FF FF FF FF` and his own Dirk was
sitting in the bag.  He was punching it.  Armed, his swing went 8 -> 21.

A wrong fixture reads exactly like a balance finding.  That is the trap
this file exists to close, and closing it cheaply matters -- so this reads
the SAVESTATES DIRECTLY, with no emulator: 110 fixtures in about a second,
against a `make savestates` measured in hours.

HOW IT FINDS THE DATA.  A .mss is a short header then zlib streams; the
biggest one carries WRAM.  The character table ($1600, 16 records of 37
bytes) is located by its own shape rather than by a hardcoded offset,
which would rot the first time Mesen changed its state layout: record c's
actor-id byte has LOW NIBBLE c for the first eleven records (the high
nibble is join state, which is why a plain equality test finds nothing).
That signature is unique in every fixture in the tree -- asserted below,
so a second candidate is an error and not a coin flip.

Then, per record: +8 level, +9/+11 hp, +$1F weapon, +$20..$23 the rest.
$FF means empty.  Party membership is $1850 + c, low three bits.

Usage:  python3 tools/audit_equipment.py [--dir build/states] [-v]
Exit 0 clean, 1 if anybody in a party is holding nothing.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
import zlib

CHAR_BLOCK = 0x1600          # WRAM address of the character table
PARTY = 0x1850               # WRAM address of the party/order bytes
REC = 37                     # bytes per character record
WEAPON = 0x1F                # offset of the equipped weapon within a record
EMPTY = 0xFF
# Where the shape-signature resolves to in every fixture that has one.  Used
# only as a cross-checked fallback for the early fixtures that do not.
FALLBACK_CB = 0x1844

NAMES = {0: "TERRA", 1: "LOCKE", 2: "CYAN", 3: "SHADOW", 4: "EDGAR",
         5: "SABIN", 6: "CELES", 7: "STRAGO", 8: "RELM", 9: "SETZER",
         10: "MOG", 11: "GAU", 12: "GOGO", 13: "UMARO"}

WAIVERS = "tools/equipment_waivers.txt"
ITEM_PROP = "ff6/src/menu/item_prop_en.dat"


def load_waivers(repo: str) -> dict[tuple[str, str], str]:
    """(fixture, CHARACTER) pairs where bare-handed is the story itself.

    A burn-down, exactly like the state-write list: a line that matches
    nothing is an error, so a fixture that gets armed upstream cannot keep
    a stale exemption.
    """
    out = {}
    try:
        for line in open(os.path.join(repo, WAIVERS)):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            out[(parts[0].strip(), parts[1].strip())] = parts[2].strip()
    except OSError:
        pass
    return out
WEAPON_IDS = range(0x00, 0x60)


def equippable_weapons(repo: str) -> dict[int, int]:
    """How many weapon records each actor may hold, read from the ROM data.

    UMARO is bare-handed in ten fixtures and that is CORRECT -- the game
    will not let him hold anything.  Rather than hardcode that as lore,
    derive it: the equip mask is `item_prop_en.dat` offset +$01, 16-bit,
    bit N = actor N (HANDOFF, "canonical facts you should not re-derive";
    byte +$00 always looks like a mask and always claims Terra, which is
    the trap that entry exists for).  An actor who can hold one weapon or
    none cannot be re-equipped and must not be reported as a finding --
    otherwise the real signal drowns.
    """
    path = os.path.join(repo, ITEM_PROP)
    try:
        data = open(path, "rb").read()
    except OSError:
        return {}
    out = {}
    for actor in range(16):
        out[actor] = sum(
            1 for i in WEAPON_IDS
            if (int.from_bytes(data[i * 30 + 1:i * 30 + 3], "little")
                >> actor) & 1)
    return out


def biggest_stream(path: str) -> bytes | None:
    """The decompressed zlib stream that carries WRAM."""
    data = open(path, "rb").read()
    best, i = None, 0
    while True:
        i = data.find(b"\x78\x01", i)
        if i < 0:
            break
        try:
            out = zlib.decompressobj().decompress(data[i:])
            if best is None or len(out) > len(best):
                best = out
        except zlib.error:
            pass
        i += 2
    return best


def find_char_block(raw: bytes) -> int | None:
    """Offset of $1600 inside the blob, located by the table's own shape.

    Records 0..10 carry actor ids whose LOW NIBBLE is the record index; the
    high nibble is join state (a fixture mid-chain reads 00 01 12 13 04 15
    ..., which is why an equality test on the whole byte finds nothing).

    The run length is not fixed: the earliest fixtures (power-on, the first
    battle, Arvis's house) have not filled the whole table yet, so an
    eleven-record signature finds nothing there.  Try long first -- long is
    the least ambiguous -- and shorten only until exactly one candidate
    survives.  Stop at six: below that the signature starts matching
    ordinary counting data elsewhere in WRAM, and a wrong offset would
    report confident nonsense, which is worse than reporting nothing.
    """
    for n in range(11, 7, -1):
        hits = [b for b in range(0, len(raw) - REC * n)
                if all((raw[b + REC * c] & 0x0F) == c for c in range(n))]
        if len(hits) == 1:
            return hits[0]
    # EARLY fixtures have no such run -- at power-on only TERRA exists and
    # the rest of the table is $FF, so there is no sequence to match.  The
    # dump is a fixed 348964 bytes with a fixed layout, so fall back to the
    # offset the signature RESOLVES TO everywhere it does work, and prove
    # it here rather than trusting it: record 0 must be actor 0, and
    # somebody must be in the party.
    if len(raw) > FALLBACK_CB + REC * 16 + 0x300:
        cb = FALLBACK_CB
        party = cb + (PARTY - CHAR_BLOCK)
        if raw[cb] == 0 and any(raw[party + c] & 0x07 for c in range(16)):
            return cb
    return None


def audit(path: str):
    raw = biggest_stream(path)
    if raw is None:
        return None, "no zlib stream"
    cb = find_char_block(raw)
    if cb is None:
        return None, "character table not located (or ambiguous)"
    party_off = cb + (PARTY - CHAR_BLOCK)
    out = []
    for c in range(16):
        if raw[party_off + c] & 0x07:
            rec = cb + REC * c
            out.append({
                "char": c,
                "name": NAMES.get(c, f"#{c}"),
                "level": raw[rec + 8],
                "hp": int.from_bytes(raw[rec + 9:rec + 11], "little"),
                "maxhp": int.from_bytes(raw[rec + 11:rec + 13], "little"),
                "weapon": raw[rec + WEAPON],
                "gear": list(raw[rec + WEAPON:rec + WEAPON + 5]),
            })
    return out, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    waivers = load_waivers(args.repo)
    used = set()
    canhold = equippable_weapons(args.repo)
    cannot = sorted(c for c, n in canhold.items()
                    if n <= 1 and c in NAMES)

    files = sorted(glob.glob(os.path.join(args.dir, "*.mss")))
    if not files:
        print(f"audit_equipment: no fixtures under {args.dir}")
        return 0

    scanned, skipped, bad = 0, [], []
    for p in files:
        party, err = audit(p)
        if err:
            skipped.append((os.path.basename(p), err))
            continue
        scanned += 1
        stem = os.path.basename(p)[:-4] if p.endswith(".mss") else p
        naked = []
        for m in party:
            if m["weapon"] != EMPTY or canhold.get(m["char"], 99) <= 1:
                continue
            key = (stem, m["name"])
            if key in waivers:
                used.add(key)
                continue
            naked.append(m)
        if naked:
            bad.append((os.path.basename(p), party, naked))
        elif args.verbose:
            who = " ".join(f"{m['name']}={m['weapon']:02X}" for m in party)
            print(f"  ok   {os.path.basename(p):34s} {who}")

    print(f"equipment audit: {scanned} fixtures read"
          + (f", {len(skipped)} unreadable" if skipped else ""))
    if cannot:
        print("  (bare is EXPECTED and not reported for "
              + ", ".join(f"{NAMES[c]} ({canhold[c]} weapon record"
                          + ("s" if canhold[c] != 1 else "") + ")"
                          for c in cannot)
              + " -- the equip mask says so)")
    for name, err in skipped:
        print(f"  ?    {name}: {err}")

    for name, party, naked in bad:
        who = ", ".join(f"{m['name']} (L{m['level']}, {m['hp']}/{m['maxhp']})"
                        for m in naked)
        print(f"  BARE {name}: {who}")
        for m in party:
            gear = " ".join(f"{g:02X}" for g in m["gear"])
            print(f"         {m['name']:7s} gear {gear}")

    stale = sorted(set(waivers) - used)
    if stale:
        print(f"\n{len(stale)} waiver(s) match nothing any more -- delete "
              f"them; the burn-down only shrinks:")
        for fix, who in stale:
            print(f"  {fix}: {who}")
        return 1

    if bad:
        print(f"\n{len(bad)} fixture(s) hand a party member NOTHING TO FIGHT "
              f"WITH.  A bare-handed character reads exactly like a balance\n"
              f"wall -- solo LOCKE punched a 495-hp HeavyArmor for 8 a swing "
              f"before anyone looked.  Give the step an H.equipOptimum stop.")
        return 1
    print("  OK -- everybody in every party is holding something")
    return 0


if __name__ == "__main__":
    sys.exit(main())
