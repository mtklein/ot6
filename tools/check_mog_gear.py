#!/usr/bin/env python3
"""MOG's Mithril Pike and Mithril Shld are in the bag when the Moogle
defense is over (#143).

MOG enters the defense wearing both (char_prop.asm, no fixed_equip) and
leaves the party in the win path with no control in between, so whatever
he still wears at the win is gone.  gen_moogle strips him through the
Equip menu before the Marshal; this reads the fixture it generates with
no emulator (savestate_party.py locates the character table, the bag is
$1869 ids / $1969 counts past it) and reports the two counts and MOG's
slot bytes.

Usage:  python3 tools/check_mog_gear.py [build/states/moogle_cleared.mss]
Exit 0 when the bag holds at least one of each, 1 otherwise.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from audit_supplies import count_in
from savestate_party import REC, biggest_stream, find_char_block

MITHRIL_PIKE = 0x1D
MITHRIL_SHLD = 0x5C
MOG = 10
WEAPON = 0x1F
FIXTURE = "build/states/moogle_cleared.mss"


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else FIXTURE
    raw = biggest_stream(path)
    if raw is None:
        print(f"{path}: no zlib stream")
        return 1
    cb = find_char_block(raw)
    if cb is None:
        print(f"{path}: character table not located")
        return 1
    pike = count_in(raw, cb, MITHRIL_PIKE)
    shield = count_in(raw, cb, MITHRIL_SHLD)
    slots = raw[cb + REC * MOG + WEAPON:cb + REC * MOG + WEAPON + 4]
    print(f"{path}: bag Mithril Pike x{pike}, Mithril Shld x{shield}; "
          f"MOG slots {slots.hex(' ')}")
    if pike >= 1 and shield >= 1:
        print("OK: MOG's pike and shield are in the bag")
        return 0
    print("FAIL: MOG's pike and shield are not both in the bag")
    return 1


if __name__ == "__main__":
    sys.exit(main())
