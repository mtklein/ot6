#!/usr/bin/env python3
"""A mutant ROM for a negative.

    mutant_rom.py IN.sfc DBG OUT.sfc EDIT...

EDIT is PROC, which gets an `rts` ($60) as its first byte so a routine
called with jsr does nothing, or SYMBOL=HEX, whose bytes at SYMBOL are
replaced by HEX (a seam the source labels for this: Ot6SaveSign's VerCheck
and SlotAt), or SYMBOL+OFF=HEX, OFF bytes past SYMBOL (decimal or $hex:
an operand inside a routine, e.g. Ot6LeoBattleRow+4=E0FFFF).  SYMBOL is a name in DBG (ff6-en.dbg).  HEX may
hold {NAME}: that symbol's address, low word, little-endian (a jsr's or a
jmp's operand: LoadEnsure=20{Ot6CodexSix} calls another routine of the
same bank).  Only for the
negatives that prove a suite notices the change (#389); every symbol stays
where the real build put it, so the real ff6-en.dbg still describes the
mutant.
"""

import re
import sys


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    src, dbg, out, procs = argv[0], argv[1], argv[2], argv[3:]
    rom = bytearray(open(src, "rb").read())
    text = open(dbg, encoding="utf-8").read()
    for e in procs:
        p, _, hx = e.partition("=")
        p, _, off = p.partition("+")
        off = int(off[1:], 16) if off.startswith("$") else int(off or "0")
        m = re.search(r'\bname="%s",[^\n]*\bval=0x([0-9A-Fa-f]+)' % re.escape(p), text)
        if not m:
            print(f"mutant_rom: no symbol {p} in {dbg}")
            return 1
        off = (int(m.group(1), 16) & 0x3FFFFF) + off

        def addr(g):
            t = re.search(r'\bname="%s",[^\n]*\bval=0x([0-9A-Fa-f]+)' % re.escape(g.group(1)), text)
            if not t:
                raise SystemExit(f"mutant_rom: no symbol {g.group(1)} in {dbg}")
            return (int(t.group(1), 16) & 0xFFFF).to_bytes(2, "little").hex()

        hx = re.sub(r"\{(\w+)\}", addr, hx)
        new = bytes.fromhex(hx) if hx else b"\x60"
        print(f"mutant_rom: {e.partition('=')[0]} at ROM ${off:06X}: {rom[off:off + len(new)].hex()} -> {new.hex()}")
        rom[off:off + len(new)] = new
    open(out, "wb").write(rom)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
