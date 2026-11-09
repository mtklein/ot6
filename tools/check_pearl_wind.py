"""Build gate (#388): Pearl Wind heals each member as much as Strago's MAX HP.

Vanilla's attacker effect $1b (AttackerEffect_1b, battle_main.asm) loads
the caster's current HP ($3BF4,y) as the heal, so the lore was weakest when
Strago was hurt.  OT6 loads his max HP ($3C1C,y): `lda $3c1c,y` (B9 1C 3C)
right after `longa` (C2 20), then `sta $11b0` (8D B0 11).  This reads the
built ROM at the symbol ff6-en.dbg gives the routine.

    python3 tools/check_pearl_wind.py [--rom R] [--dbg D]   check
    python3 tools/check_pearl_wind.py --selftest            the vanilla load is red
"""
import argparse
import re
import sys

WANT = bytes([0xC2, 0x20, 0xB9, 0x1C, 0x3C, 0x8D, 0xB0, 0x11])
VANILLA = bytes([0xC2, 0x20, 0xB9, 0xF4, 0x3B, 0x8D, 0xB0, 0x11])


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
    body = bytes(rom[at:at + 16])
    i = body.find(bytes([0xC2, 0x20]))
    if i < 0:
        return ["no `longa` in the routine's first 16 bytes: %s" % body.hex()]
    got = body[i:i + len(WANT)]
    if got == WANT:
        return []
    if got == VANILLA:
        return ["Pearl Wind loads the caster's CURRENT HP ($3BF4,y), vanilla's heal"]
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
        bad = bytearray(rom)
        i = bytes(bad[at:at + 16]).find(bytes([0xC2, 0x20]))
        bad[at + i:at + i + len(VANILLA)] = VANILLA
        if not check(bad, at):
            sys.exit("check_pearl_wind selftest: the vanilla current-HP load passed")
        print("check_pearl_wind selftest: the vanilla load is red: %s" % check(bad, at)[0])
        return
    problems = check(rom, at)
    if problems:
        sys.exit("check_pearl_wind: " + "; ".join(problems))
    print("check_pearl_wind: ok, Pearl Wind heals the caster's max HP ($3C1C,y) at $%06X" % at)


if __name__ == "__main__":
    main()
