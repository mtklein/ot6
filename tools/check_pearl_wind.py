"""Build gate (#388): Strago's Pearl Wind heals each member as much as his MAX HP;
a monster's Pearl Wind stays vanilla's.

Vanilla's attacker effect $1b (AttackerEffect_1b, battle_main.asm) loads
the caster's current HP ($3BF4,y) as the heal, so the lore was weakest when
Strago was hurt.  OT6 keeps that load and, for a party caster (y < 8),
replaces it with his max HP ($3C1C,y):

    longa; lda $3bf4,y; cpy #$08; bcs +; lda $3c1c,y; +: sta $11b0
    C2 20  B9 F4 3B     C0 08     B0 03  B9 1C 3C       8D B0 11

so the Sprinter, Harpiai, Peepers and the last battle's Girl heal as in
vanilla.  This reads the built ROM at the symbol ff6-en.dbg gives the routine.

    python3 tools/check_pearl_wind.py [--rom R] [--dbg D]   check
    python3 tools/check_pearl_wind.py --selftest            two mutants, each red:
        the vanilla load (nobody at max) and the ungated max load (monsters too)
"""
import argparse
import re
import sys

WANT = bytes([0xC2, 0x20, 0xB9, 0xF4, 0x3B, 0xC0, 0x08, 0xB0, 0x03, 0xB9, 0x1C, 0x3C, 0x8D, 0xB0, 0x11])
VANILLA = bytes([0xC2, 0x20, 0xB9, 0xF4, 0x3B, 0x8D, 0xB0, 0x11])
UNGATED = bytes([0xC2, 0x20, 0xB9, 0x1C, 0x3C, 0x8D, 0xB0, 0x11])


def routine(dbg):
    pat = re.compile(r'^sym\t.*name="AttackerEffect_1b".*val=0x([0-9A-F]+),seg=\d+,type=lab')
    with open(dbg, encoding="latin-1") as f:
        for line in f:
            m = pat.match(line)
            if m:
                return int(m.group(1), 16) & 0x3FFFFF
    raise SystemExit("check_pearl_wind: AttackerEffect_1b not in %s" % dbg)


def check(rom, at):
    """the problems with the routine at `at` (empty when it heals max HP)"""
    body = bytes(rom[at:at + 24])
    i = body.find(bytes([0xC2, 0x20]))
    if i < 0:
        return ["no `longa` in the routine's first 16 bytes: %s" % body.hex()]
    got = body[i:i + len(WANT)]
    if got == WANT:
        return []
    if body[i:i + len(VANILLA)] == VANILLA:
        return ["Pearl Wind loads every caster's CURRENT HP ($3BF4,y), vanilla's heal, Strago's too"]
    if body[i:i + len(UNGATED)] == UNGATED:
        return ["Pearl Wind loads every caster's MAX HP ($3C1C,y) with no party gate: monsters heal at max too"]
    return ["Pearl Wind's heal load reads %s, want %s" % (got.hex(), WANT.hex())]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default="build/ot6.sfc")
    ap.add_argument("--dbg", default="ff6/rom/ff6-en.dbg")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    rom = bytearray(open(a.rom, "rb").read())
    at = routine(a.dbg)
    if a.selftest:
        i = bytes(rom[at:at + 24]).find(bytes([0xC2, 0x20]))
        for name, mut in (("the vanilla load", VANILLA), ("the ungated max load", UNGATED)):
            bad = bytearray(rom)
            bad[at + i:at + i + len(mut)] = mut
            if not check(bad, at):
                sys.exit("check_pearl_wind selftest: %s passed" % name)
            print("check_pearl_wind selftest: %s is red: %s" % (name, check(bad, at)[0]))
        return
    problems = check(rom, at)
    if problems:
        sys.exit("check_pearl_wind: " + "; ".join(problems))
    print("check_pearl_wind: ok, a party caster's Pearl Wind heals his max HP ($3C1C,y), a monster's its current HP, at $%06X" % at)


if __name__ == "__main__":
    main()
