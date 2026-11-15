#!/usr/bin/env python3
"""A mutant ROM for a negative: the named routines return at once.

    mutant_rom.py IN.sfc DBG OUT.sfc PROC...

Each PROC (a symbol in DBG, ff6-en.dbg) gets an `rts` ($60) as its first
byte, so a routine called with jsr does nothing.  Only for the negatives
that prove a suite notices the routine gone (#389: Ot6SaveSign,
Ot6NewGameClear); every symbol stays where the real build put it, so the
real ff6-en.dbg still describes the mutant.
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
    for p in procs:
        m = re.search(r'\bname="%s",[^\n]*\bval=0x([0-9A-Fa-f]+)' % re.escape(p), text)
        if not m:
            print(f"mutant_rom: no symbol {p} in {dbg}")
            return 1
        off = int(m.group(1), 16) & 0x3FFFFF
        print(f"mutant_rom: {p} at ROM ${off:06X}: ${rom[off]:02X} -> $60 (rts)")
        rom[off] = 0x60
    open(out, "wb").write(rom)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
