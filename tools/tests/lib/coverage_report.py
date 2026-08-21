#!/usr/bin/env python3
"""coverage_report.py -- union per-test CDL bitmaps and report OT6 blind spots.

Mesen keeps a Code/Data Log (CDL) per emulator process: one flag byte per
PRG-ROM offset, bit0 set once that byte has been fetched as an opcode.  The lib
(tools/tests/lib/ot6.lua, coverageFlush) dumps the executed-code bitmap for the
OT6 code ranges at each run's teardown when OT6_COVERAGE is set; because the CDL
is per-process, one bitmap covers only the code that one test reached.  This
script unions the per-test bitmaps across a coverage run and maps the set bits
back to OT6 routine names, so it can report which routines the run never
executed -- the suite's blind spots.

    coverage_report.py <ff6-en.map> <path> [<path> ...]

Each <path> is a *.coverage.cdl bitmap or a directory to search for them.  The
report goes to stdout; exit status is 0 unless no bitmaps were found.

The ranges below MUST match COVERAGE_RANGES in tools/tests/lib/ot6.lua, in the
same order: the lib packs a single bitmap by walking the ranges and this script
unpacks it the same way.  They are ff6/rom/ff6-en.map's ot6_code and ot6_c1
segments as PRG-ROM offsets (CPU addr & 0x3FFFFF).
"""
import os
import re
import sys

# (prg_base, length) -- keep in lockstep with COVERAGE_RANGES in ot6.lua.
RANGES = [(0x300000, 0x2C5C), (0x01FFE8, 0x0D)]
TOTAL_BITS = sum(length for _, length in RANGES)
NBYTES = (TOTAL_BITS + 7) // 8

# The main OT6 code segment (range 0), where the named routines live.
CODE_BASE, CODE_LEN = RANGES[0]
CODE_END = CODE_BASE + CODE_LEN        # one past the last OT6 code byte
C1_BASE, C1_LEN = RANGES[1]
C1_BIT0 = RANGES[0][1]                 # range 1 starts at this concatenated bit


def bit_index_for_prg(prg):
    """Concatenated-bitmap bit index for a PRG offset, or None if out of range."""
    off = 0
    for base, length in RANGES:
        if base <= prg < base + length:
            return off + (prg - base)
        off += length
    return None


def parse_routines(map_path):
    """OT6 code routines from the map's exports-by-value, sorted by address.

    Returns [(cpu_addr, name, size)], each routine spanning to the next export
    (the last to the segment end).  Only exports whose CPU address lands in the
    ot6_code segment are kept -- that is the named-routine granularity the
    report buckets executed bytes into.
    """
    text = open(map_path, encoding="utf-8", errors="replace").read()
    m = re.search(r"Exports list by value:(.*?)Imports list:", text, re.S)
    if not m:
        sys.exit("coverage_report: no 'Exports list by value' section in map")
    entries = re.findall(r"([A-Za-z0-9_]+)\s+([0-9A-Fa-f]{6})\s+RLA", m.group(1))
    routines = []
    for name, addr_hex in entries:
        addr = int(addr_hex, 16)
        prg = addr & 0x3FFFFF
        if CODE_BASE <= prg < CODE_END:
            routines.append((addr, name))
    routines.sort()
    out = []
    for i, (addr, name) in enumerate(routines):
        nxt = routines[i + 1][0] if i + 1 < len(routines) else (CODE_END | 0xF00000)
        out.append((addr, name, nxt - addr))
    return out


def load_union(paths):
    """Bit-OR every *.coverage.cdl under the given paths into one integer."""
    files = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in names
                          if n.endswith("coverage.cdl")]
        elif p.endswith("coverage.cdl"):
            files.append(p)
        else:
            sys.exit(f"coverage_report: not a coverage bitmap or directory: {p}")
    union = 0
    for f in sorted(set(files)):
        data = open(f, "rb").read()
        if len(data) != NBYTES:
            sys.exit(f"coverage_report: {f} is {len(data)} bytes, expected "
                     f"{NBYTES} -- bitmap format drift vs ot6.lua COVERAGE_RANGES")
        union |= int.from_bytes(data, "little")
    return union, sorted(set(files))


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: coverage_report.py <ff6-en.map> <path> [<path> ...]")
    map_path, paths = argv[1], argv[2:]
    routines = parse_routines(map_path)
    union, files = load_union(paths)
    if not files:
        sys.exit("coverage_report: no coverage.cdl bitmaps found under the "
                 "given path(s) -- run `make coverage` (or a suite with "
                 "OT6_COVERAGE=1 set) first")

    def bit(i):
        return (union >> i) & 1

    # Per-routine coverage: a routine is covered if any byte in its span ran.
    covered_routines, uncovered = [], []
    for addr, name, size in routines:
        prg = addr & 0x3FFFFF
        start = bit_index_for_prg(prg)
        # max(size, 1): two exports at one address (an _ext alias beside the
        # internal label) leave the second with size 0; test at least its entry
        # byte so an alias reports the same coverage as the routine it names,
        # not a false blind spot.
        hit = sum(bit(start + k) for k in range(max(size, 1))
                  if start + k < C1_BIT0)
        (covered_routines if hit else uncovered).append((addr, name, size, hit))

    # Byte totals over the code segment.
    code_exec = sum(bit(i) for i in range(CODE_LEN))
    c1_exec = sum(bit(C1_BIT0 + i) for i in range(C1_LEN))

    print("OT6 code coverage (#130) -- CDL union across the test run")
    print("  metric: a byte is 'touched' if the run fetched it as code (CDL")
    print("          0x01) or read it as data (0x02); a routine is touched if")
    print("          any byte in its span was.")
    print(f"  bitmaps unioned : {len(files)}")
    print(f"  routines        : {len(covered_routines)}/{len(routines)} "
          f"touched ({len(uncovered)} never touched)")
    print(f"  ot6_code bytes  : {code_exec}/{CODE_LEN} "
          f"({100 * code_exec / CODE_LEN:.1f}%) touched")
    print(f"  ot6_c1 bytes    : {c1_exec}/{C1_LEN} touched")
    print()
    if uncovered:
        print("Never touched by any script in this run (blind spots):")
        width = max(len(n) for _, n, _, _ in uncovered)
        for addr, name, size, _ in sorted(uncovered):
            print(f"  {addr:06X}  {name:<{width}}  {size:5d} bytes")
    else:
        print("Every ot6_code export was touched at least once in this run.")
    print()
    print("Contributing bitmaps:")
    for f in files:
        print(f"  {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
