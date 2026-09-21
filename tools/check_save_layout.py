#!/usr/bin/env python3
"""Save-layout contract check.

Asserts that docs/design/save-layout.md's save-block table matches the
symbols the build actually assembled, so the persistent layout cannot drift
from its documentation unnoticed.

The build's debug file (ff6/rom/ff6-en.dbg, the same file
tools/tests/lib/ot6.lua's H.sym resolves against) names every OT6 storage
symbol and its address.  This check reads it for the OT6 symbols that resolve
into the vanilla save block -- bank $00/$7E WRAM with a low word in
$1600-$1FFF -- and requires that:

  * every such symbol appears in the doc's save-block table at the same start
    address;
  * every table row's byte width equals its inclusive address range;
  * no two table rows overlap;
  * every table row lies inside a scrap the doc declares free
    (a "Scrap `$xxxx-$xxxx`" line under Free space).

The codex in bank $31 is outside $1600-$1FFF and is validated at runtime by
its own magic word, so it is documented but not machine-checked here.

Nothing is written.  Exit status 0 = clean.

Usage:  python3 tools/check_save_layout.py [--repo ROOT] [--dbg PATH]
                [--doc PATH] [--selftest]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

DOC = "docs/design/save-layout.md"
DBG = "ff6/rom/ff6-en.dbg"

SAVE_LO = 0x1600
SAVE_HI = 0x1FFF
WRAM_BANKS = (0x00, 0x7E)

# a save-block address cell: $16xx..$1Fxx, single or inclusive range.
ADDR = r"\$(1[6-9A-Fa-f][0-9A-Fa-f]{2})"
ADDR_CELL = re.compile(r"^%s(?:-%s)?$" % (ADDR, ADDR))
SCRAP = re.compile(r"Scrap\s+`%s-%s`" % (ADDR, ADDR))

# ff6-en.dbg records, matched exactly as tools/tests/lib/compose.py does.
_VAL = re.compile(r"\bval=0x([0-9A-Fa-f]+)")
_NAME = re.compile(r'\bname="([^"]*)"')


def parse_dbg(text):
    """OT6 symbols resolving into the save block: {name: sorted [addr, ...]}.

    Only type=lab records carry an address.  A name is kept when its value is
    a WRAM address (bank $00 or $7E) whose low word is in $1600-$1FFF.
    """
    out = {}
    for line in text.splitlines():
        if "type=lab" not in line:
            continue
        v, n = _VAL.search(line), _NAME.search(line)
        if not v or not n or not n.group(1).startswith("OT6_"):
            continue
        addr = int(v.group(1), 16)
        low = addr & 0xFFFF
        if (addr >> 16) & 0xFF in WRAM_BANKS and SAVE_LO <= low <= SAVE_HI:
            out.setdefault(n.group(1), set()).add(low)
    return {k: sorted(v) for k, v in out.items()}


def parse_doc(text):
    """(rows, scraps) from the doc.

    rows: [{start, end, width, symbol, line}] for each save-block table row,
    identified by an address cell in the first column.  symbol is the ca65
    name with any backticks stripped; a reserved row names no symbol.
    scraps: [(start, end)] declared free save-block ranges.
    """
    rows, scraps = [], []
    for i, raw in enumerate(text.splitlines(), 1):
        for m in SCRAP.finditer(raw):
            a, b = int(m.group(1), 16), int(m.group(2), 16)
            if SAVE_LO <= a <= b <= SAVE_HI:
                scraps.append((a, b))
        if not raw.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in raw.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        am = ADDR_CELL.match(cells[0])
        if not am:
            continue                      # header, separator, prose row
        start = int(am.group(1), 16)
        end = int(am.group(2), 16) if am.group(2) else start
        width_cell = cells[1]
        if not width_cell.isdigit():
            raise SystemExit("check_save_layout: %s:%d width %r is not a "
                             "number" % (DOC, i, width_cell))
        symbol = cells[2].strip("`").strip()
        rows.append({"start": start, "end": end, "width": int(width_cell),
                     "symbol": symbol, "line": i})
    return rows, scraps


def check_data(rows, scraps, syms):
    """Compare parsed doc rows/scraps against parsed dbg symbols.

    Returns a list of problem strings; empty means the contract holds.
    """
    problems = []
    by_symbol = {}
    for r in rows:
        # width matches the inclusive address range
        span = r["end"] - r["start"] + 1
        if span != r["width"]:
            problems.append(
                "%s:%d field %s: width column says %d but $%04X-$%04X is %d "
                "byte(s)" % (DOC, r["line"], r["symbol"] or "(reserved)",
                             r["width"], r["start"], r["end"], span))
        # every field lies inside a declared free scrap
        if not any(a <= r["start"] and r["end"] <= b for a, b in scraps):
            problems.append(
                "%s:%d field %s ($%04X-$%04X) sits outside every documented "
                "scrap %s" % (DOC, r["line"], r["symbol"] or "(reserved)",
                              r["start"], r["end"],
                              ", ".join("$%04X-$%04X" % s for s in scraps)
                              or "(none)"))
        if r["symbol"].startswith("OT6_"):
            by_symbol.setdefault(r["symbol"], []).append(r)

    # no two rows overlap
    ordered = sorted(rows, key=lambda r: r["start"])
    for prev, cur in zip(ordered, ordered[1:]):
        if cur["start"] <= prev["end"]:
            problems.append(
                "%s: fields %s ($%04X-$%04X) and %s ($%04X-$%04X) overlap"
                % (DOC, prev["symbol"] or "(reserved)", prev["start"],
                   prev["end"], cur["symbol"] or "(reserved)", cur["start"],
                   cur["end"]))

    # every assembled save-block symbol is documented at its address
    for name, addrs in sorted(syms.items()):
        if len(addrs) > 1:
            problems.append(
                "%s: symbol %s resolves to several save-block addresses %s "
                "-- ambiguous" % (DBG, name,
                                  ", ".join("$%04X" % a for a in addrs)))
            continue
        addr = addrs[0]
        docrows = by_symbol.get(name)
        if not docrows:
            problems.append(
                "%s: symbol %s is in the save block at $%04X but has no row "
                "in %s" % (DBG, name, addr, DOC))
            continue
        for r in docrows:
            if r["start"] != addr:
                problems.append(
                    "%s:%d field %s is documented at $%04X but the build "
                    "assembled it at $%04X" % (DOC, r["line"], name,
                                               r["start"], addr))

    # every documented named symbol is a real assembled save-block symbol
    for name, docrows in sorted(by_symbol.items()):
        if name not in syms:
            problems.append(
                "%s:%d field %s is in the table but the build assembled no "
                "such save-block symbol" % (DOC, docrows[0]["line"], name))
    return problems


def check(repo, dbg_path, doc_path):
    with open(doc_path, encoding="utf-8") as f:
        rows, scraps = parse_doc(f.read())
    with open(dbg_path, encoding="utf-8") as f:
        syms = parse_dbg(f.read())
    if not scraps:
        raise SystemExit("check_save_layout: %s declares no free scrap "
                         "(no 'Scrap `$xxxx-$xxxx`' line)" % doc_path)
    if not syms:
        raise SystemExit("check_save_layout: %s named no OT6 save-block "
                         "symbol -- is the ROM built?" % dbg_path)
    return check_data(rows, scraps, syms), rows, syms


def selftest():
    doc = (
        "| Address | Bytes | Symbol | Meaning |\n"
        "|---|---|---|---|\n"
        "| $1E1D-$1E1E | 2 | OT6_LOADOUT | x |\n"
        "| $1E1F-$1E26 | 8 | `OT6_RAGELOAD` | x |\n"
        "| $1E27-$1E2B | 5 | OT6_LORELOAD | x |\n"
        "- Scrap `$1E1D-$1E3F` (35 bytes).\n"
    )
    good = ("type=lab,name=\"OT6_LOADOUT\",val=0x7E1E1D\n"
            "type=lab,name=\"OT6_RAGELOAD\",val=0x7E1E1F\n"
            "type=lab,name=\"OT6_LORELOAD\",val=0x7E1E27\n")

    rows, scraps = parse_doc(doc)
    assert [(r["start"], r["end"], r["width"], r["symbol"]) for r in rows] == [
        (0x1E1D, 0x1E1E, 2, "OT6_LOADOUT"),
        (0x1E1F, 0x1E26, 8, "OT6_RAGELOAD"),
        (0x1E27, 0x1E2B, 5, "OT6_LORELOAD")], rows
    assert scraps == [(0x1E1D, 0x1E3F)], scraps
    syms = parse_dbg(good)
    assert syms == {"OT6_LOADOUT": [0x1E1D], "OT6_RAGELOAD": [0x1E1F],
                    "OT6_LORELOAD": [0x1E27]}, syms
    assert check_data(rows, scraps, syms) == [], "clean case should pass"

    # a dbg address one byte off its documented address is caught
    off = parse_dbg(good.replace("0x7E1E1F", "0x7E1E20"))
    probs = check_data(rows, scraps, off)
    assert any("assembled it at $1E20" in p for p in probs), probs

    # a symbol with no doc row is caught
    extra = dict(syms, OT6_NEWFIELD=[0x1E2C])
    probs = check_data(rows, scraps, extra)
    assert any("OT6_NEWFIELD" in p and "no row" in p for p in probs), probs

    # a doc symbol the build never assembled is caught
    probs = check_data(rows, scraps, {"OT6_LOADOUT": [0x1E1D],
                                      "OT6_RAGELOAD": [0x1E1F]})
    assert any("OT6_LORELOAD" in p and "no such" in p for p in probs), probs

    # overlapping rows are caught
    overlap = rows + [{"start": 0x1E26, "end": 0x1E27, "width": 2,
                       "symbol": "OT6_X", "line": 99}]
    probs = check_data(overlap, scraps, syms)
    assert any("overlap" in p for p in probs), probs

    # a field outside every scrap is caught
    outside = [{"start": 0x1E70, "end": 0x1E71, "width": 2,
                "symbol": "OT6_Y", "line": 98}]
    probs = check_data(outside, scraps, {})
    assert any("outside every documented scrap" in p for p in probs), probs

    # a width that disagrees with the address range is caught
    badwidth = [{"start": 0x1E1D, "end": 0x1E1E, "width": 3,
                 "symbol": "OT6_LOADOUT", "line": 3}]
    probs = check_data(badwidth, scraps, {"OT6_LOADOUT": [0x1E1D]})
    assert any("width column says 3" in p for p in probs), probs

    print("check_save_layout selftest OK")
    return 0


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--dbg", default=None)
    ap.add_argument("--doc", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    dbg_path = args.dbg or os.environ.get("OT6_DBG") or \
        os.path.join(args.repo, DBG)
    doc_path = args.doc or os.path.join(args.repo, DOC)
    problems, rows, syms = check(args.repo, dbg_path, doc_path)
    for p in problems:
        print("check_save_layout: " + p)
    if problems:
        return 1
    print("check_save_layout OK: %d save-block field(s), %d assembled symbol(s), "
          "table and ff6-en.dbg agree" % (len(rows), len(syms)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
