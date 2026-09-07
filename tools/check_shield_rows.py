#!/usr/bin/env python3
"""Build gate: every species appears at most once in the break tables.

Ot6SeedShields (ff6/src/battle/ot6_break.asm) scans Ot6ShieldTbl from the
top and takes the FIRST row whose species matches; Ot6ElemAdd scans
Ot6ElemAddTbl the same way.  A second row for the same species is dead
code that reads as authored -- issue #157: five keyed rows added in
c0fb032 sat under older shields-only rows for the same species and never
seeded, while the design audit (which kept the LAST row) reported the
keys as shipped.

Three checks, any failure exits 1:

  1. the Ot6ShieldTbl source (ff6/src/battle/ot6_hud.asm) lists each
     species once;
  2. the Ot6ElemAddTbl source (ff6/src/battle/ot6_break.asm) lists each
     species once;
  3. the Ot6ShieldTbl the ROM ships (build/ot6.sfc, located the way
     tools/audit_break_coverage.py locates it) is row-for-row the parsed
     source: same species order, shields and class bytes, no duplicates.

Usage:  python3 tools/check_shield_rows.py [--repo ROOT] [--rom PATH] [--selftest]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

HUD_ASM = "ff6/src/battle/ot6_hud.asm"
BREAK_ASM = "ff6/src/battle/ot6_break.asm"
ROM = "build/ot6.sfc"

CLASS_BIT = {"OT6_SLASH": 0x01, "OT6_PIERCE": 0x02, "OT6_BLUDG": 0x04,
             "OT6_SPECIAL": 0x08}


def _num(tok: str) -> int:
    tok = tok.strip()
    if tok.startswith("$"):
        return int(tok[1:], 16)
    return int(tok, 0)


def parse_rows(text: str, label: str, byte2_is_mask: bool):
    """Rows of a `.word species / .byte a, b` table, in source order.

    Returns [(species, a, b, line_no)] up to the $ffff terminator.
    """
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(label + ":"))
    rows, pending, pending_line = [], None, None
    for i in range(start + 1, len(lines)):
        code = lines[i].split(";", 1)[0]
        m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
        if m:
            v = int(m.group(1), 16)
            if v == 0xFFFF:
                break
            pending, pending_line = v, i + 1
            continue
        m = re.match(r"\s*\.byte\s+([^,]+),\s*(.+?)\s*$", code)
        if m and pending is not None:
            a = _num(m.group(1))
            b = 0
            for tok in m.group(2).split("|"):
                tok = tok.strip()
                if byte2_is_mask and tok in CLASS_BIT:
                    b |= CLASS_BIT[tok]
                else:
                    b |= _num(tok)
            rows.append((pending, a, b, pending_line))
            pending, pending_line = None, None
    return rows


def duplicates(rows):
    seen, dups = {}, []
    for sp, a, b, line in rows:
        if sp in seen:
            dups.append((sp, seen[sp], line))
        else:
            seen[sp] = line
    return dups


def rom_shield_rows(rom: bytes):
    """The shipped Ot6ShieldTbl, found by its opening rows the way
    audit_break_coverage.py finds it (guard $0000/2/PIERCE, lobo $0019/3/PIERCE)."""
    key = bytes([0x00, 0x00, 2, 0x02, 0x19, 0x00, 3, 0x02])
    i = rom.find(key)
    if i < 0:
        raise SystemExit("check_shield_rows: Ot6ShieldTbl signature not found in the ROM")
    if rom.find(key, i + 1) >= 0:
        raise SystemExit("check_shield_rows: Ot6ShieldTbl signature is not unique in the ROM")
    rows, a = [], i
    while True:
        sp = rom[a] | (rom[a + 1] << 8)
        if sp == 0xFFFF:
            break
        rows.append((sp, rom[a + 2], rom[a + 3], a))
        a += 4
    return rows


def check(root: str, rom_path: str | None) -> list[str]:
    problems = []

    def text(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()

    shield = parse_rows(text(HUD_ASM), "Ot6ShieldTbl", True)
    elem = parse_rows(text(BREAK_ASM), "Ot6ElemAddTbl", False)
    for sp, first, again in duplicates(shield):
        problems.append("Ot6ShieldTbl lists species $%04X twice: %s:%d and :%d "
                        "(the seeder takes the first; the second is dead)"
                        % (sp, HUD_ASM, first, again))
    for sp, first, again in duplicates(elem):
        problems.append("Ot6ElemAddTbl lists species $%04X twice: %s:%d and :%d "
                        "(the scan takes the first; the second is dead)"
                        % (sp, BREAK_ASM, first, again))

    rom_path = rom_path or os.path.join(root, ROM)
    if not os.path.exists(rom_path):
        problems.append("no ROM at %s to compare the shipped table against" % rom_path)
        return problems
    with open(rom_path, "rb") as f:
        rom = f.read()
    shipped = rom_shield_rows(rom)
    for sp, first, again in duplicates(shipped):
        problems.append("the ROM's Ot6ShieldTbl lists species $%04X twice (rom+$%06X and rom+$%06X)"
                        % (sp, first, again))
    if len(shipped) != len(shield):
        problems.append("the ROM's Ot6ShieldTbl has %d rows, the source %d"
                        % (len(shipped), len(shield)))
    for n, (src, ship) in enumerate(zip(shield, shipped)):
        if src[:3] != ship[:3]:
            problems.append("first differing row %d: source %s:%d $%04X/%d/$%02X, ROM rom+$%06X $%04X/%d/$%02X"
                            % (n, HUD_ASM, src[3], src[0], src[1], src[2],
                               ship[3], ship[0], ship[1], ship[2]))
            break
    return problems


def selftest() -> int:
    good = "Tbl:\n .word $0001\n .byte 2, OT6_PIERCE\n .word $0002\n .byte 3, $00\n .word $ffff\n"
    bad = "Tbl:\n .word $0001\n .byte 2, $00 ; old\n .word $0002\n .byte 3, $00\n .word $0001\n .byte 2, OT6_PIERCE|OT6_SLASH\n .word $ffff\n"
    rows = parse_rows(good, "Tbl", True)
    assert rows == [(1, 2, 2, 2), (2, 3, 0, 4)], rows
    assert duplicates(rows) == []
    rows = parse_rows(bad, "Tbl", True)
    assert rows[2] == (1, 2, 3, 6), rows
    assert duplicates(rows) == [(1, 2, 6)], duplicates(rows)
    rom = bytes([0xEE] * 16 + [0, 0, 2, 2, 0x19, 0, 3, 2, 0x34, 0x01, 4, 2, 0x34, 0x01, 4, 0, 0xFF, 0xFF])
    got = rom_shield_rows(rom)
    assert [r[:3] for r in got] == [(0, 2, 2), (0x19, 3, 2), (0x134, 4, 2), (0x134, 4, 0)], got
    assert len(duplicates(got)) == 1
    print("check_shield_rows selftest OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--rom", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    problems = check(args.repo, args.rom)
    for p in problems:
        print("check_shield_rows: " + p)
    if problems:
        return 1
    with open(os.path.join(args.repo, HUD_ASM), encoding="utf-8") as f:
        n = len(parse_rows(f.read(), "Ot6ShieldTbl", True))
    print("check_shield_rows OK: %d Ot6ShieldTbl rows, one per species, ROM matches source" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
