#!/usr/bin/env python3
"""Save-layout contract check: the ROM's save-touching addresses against the
frozen layout in docs/design/save-layout.md (#389).

The doc carries three machine-read tables; this check holds the build to
each of them, so the persistent layout cannot drift from its documentation
unnoticed:

  Battery map (section "## Battery map"): every byte of the 32 KiB battery,
    one row per range, with its scope, its anchor and the moments today's
    ROM writes it.  Checked:
      * the rows tile battery offsets $0000-$7FFF exactly (no gap, no
        overlap), each width matches its range, scope and write tokens are
        known ones;
      * each row's anchor, an expression of assembled symbols
        (ff6/rom/ff6-en.dbg) or `SRAMSlotPtrs[n]` (the word the built ROM
        holds there), resolves to the row's first battery offset;
      * every OT6 symbol the build places in SRAM ($30-$33:$6000-$7FFF)
        lands in a row today's ROM writes, and so does every literal SRAM
        address in the source (ff6/src/**/*.asm, code and .assert lines;
        comments ignored);
      * the vanilla save code still has the shape the map assumes: the slot
        copy is $0A00 bytes, the checksum sums $09FE of them, ClearSRAM
        clears $2000, and the header declares 32 KiB of SRAM.
  Magic words (section "## Magic words"): each symbol's assembled value.
  Save-block fields (section "## Save-block fields"): the OT6 fields inside
    the vanilla $1600-$1FFF block, as before: every OT6 symbol the build
    resolves into the block has a row at its address, every row's width
    matches its range, rows do not overlap, and every row lies inside a
    scrap the doc declares (a "Scrap `$xxxx-$xxxx`" line).

Nothing is written.  Exit status 0 = clean.

Usage:  python3 tools/check_save_layout.py [--repo ROOT] [--dbg PATH]
                [--doc PATH] [--rom PATH] [--selftest]
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

DOC = "docs/design/save-layout.md"
DBG = "ff6/rom/ff6-en.dbg"
ROM = "ff6/rom/ff6-en.sfc"
SRC = "ff6/src"

SAVE_LO = 0x1600
SAVE_HI = 0x1FFF
WRAM_BANKS = (0x00, 0x7E)
BATTERY = 0x8000

SCOPES = {"slot1", "slot2", "slot3", "newgame", "shared"}
WRITES = {"save", "load", "title", "play", "newgame", "clear", "zero", "never"}

# a save-block address cell: $16xx..$1Fxx, single or inclusive range.
ADDR = r"\$(1[6-9A-Fa-f][0-9A-Fa-f]{2})"
ADDR_CELL = re.compile(r"^%s(?:-%s)?$" % (ADDR, ADDR))
SCRAP = re.compile(r"Scrap\s+`%s-%s`" % (ADDR, ADDR))
BAT_CELL = re.compile(r"^\$([0-7][0-9A-Fa-f]{3})(?:-\$([0-7][0-9A-Fa-f]{3}))?$")
HEADING = re.compile(r"^(#{2,3})\s+(.*?)\s*$")

# ff6-en.dbg records, matched exactly as tools/tests/lib/compose.py does.
_VAL = re.compile(r"\bval=0x([0-9A-Fa-f]+)")
_NAME = re.compile(r'\bname="([^"]*)"')
# a literal long address into the battery's SRAM windows
SRAM_LIT = re.compile(r"\$(3[0-3][67][0-9A-Fa-f]{3})\b")

# The vanilla save code's shape, as instruction bytes at each routine (the
# window searched is the routine's first 128 bytes).
SHAPES = [
    ("CopyGameDataToSRAM", bytes.fromhex("c0000a"), "the slot copy stops at $0A00 bytes (cpy #$0a00)"),
    ("LoadSaveSlot", bytes.fromhex("c0000a"), "the slot load stops at $0A00 bytes (cpy #$0a00)"),
    ("CalcSaveSlotChecksum", bytes.fromhex("e0fe09"), "the checksum sums $09FE bytes (cpx #$09fe)"),
    ("ClearSRAM", bytes.fromhex("e00020"), "ClearSRAM clears $2000 bytes of bank $30 (cpx #$2000)"),
]
HEADER_SRAM = (0xFFD8, 0x05, "the header declares 256 kbit (32 KiB) of SRAM")


def sections(text):
    """[(heading, [(lineno, line)])] split at ## and ### headings."""
    out = [("", [])]
    for i, raw in enumerate(text.splitlines(), 1):
        m = HEADING.match(raw)
        if m:
            out.append((m.group(2), []))
        else:
            out[-1][1].append((i, raw))
    return out


def table_rows(lines):
    for i, raw in lines:
        if not raw.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in raw.strip().strip("|").split("|")]
        yield i, cells


def section(text, name):
    for h, lines in sections(text):
        if h.lower().startswith(name.lower()):
            return lines
    return []


# ------------------------------------------------------------- dbg / rom --
def parse_dbg_all(text):
    """{name: value} of every type=lab/equ symbol (the last one wins)."""
    out = {}
    for line in text.splitlines():
        if not line.startswith("sym"):
            continue
        v, n = _VAL.search(line), _NAME.search(line)
        if v and n:
            out[n.group(1)] = int(v.group(1), 16)
    return out


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


def sram_symbols(text):
    """OT6 type=lab symbols whose value is an SRAM address: {name: battery offset}."""
    out = {}
    for line in text.splitlines():
        if "type=lab" not in line:
            continue
        v, n = _VAL.search(line), _NAME.search(line)
        if not v or not n or not n.group(1).startswith("OT6_"):
            continue
        b = battery_offset(int(v.group(1), 16))
        if b is not None:
            out[n.group(1)] = b
    return out


def battery_offset(addr):
    """The battery offset an SNES address names, or None outside SRAM."""
    bank, low = (addr >> 16) & 0xFF, addr & 0xFFFF
    if 0x30 <= bank <= 0x33 and 0x6000 <= low <= 0x7FFF:
        return (bank - 0x30) * 0x2000 + (low - 0x6000)
    return None


def rom_offset(addr):
    return addr & 0x3FFFFF


# ----------------------------------------------------------- the doc -----
def parse_doc(text):
    """(rows, scraps) of the save-block fields section; scraps from anywhere.

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
    for i, cells in table_rows(section(text, "Save-block fields")):
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


def parse_battery(text):
    """(rows, problems) of the battery map table.

    Columns: Battery | Bytes | Scope | Holds | Anchor | Written | Absent.
    rows: [{start, end, width, scope, anchor, written (set), line}].
    """
    rows, problems = [], []
    for i, cells in table_rows(section(text, "Battery map")):
        if not cells or not BAT_CELL.match(cells[0]):
            continue
        if len(cells) < 7:
            problems.append("%s:%d battery row has %d cells, not 7" % (DOC, i, len(cells)))
            continue
        m = BAT_CELL.match(cells[0])
        start = int(m.group(1), 16)
        end = int(m.group(2), 16) if m.group(2) else start
        width = cells[1].replace(",", "")
        scope = cells[2].strip("`")
        written = {w.strip().strip("`") for w in cells[5].split(",") if w.strip()}
        if not width.isdigit():
            problems.append("%s:%d battery width %r is not a number" % (DOC, i, cells[1]))
            continue
        if scope not in SCOPES:
            problems.append("%s:%d scope %r is not one of %s" % (DOC, i, scope, sorted(SCOPES)))
        if not written or written - WRITES or ("never" in written and len(written) > 1):
            problems.append("%s:%d written %r: tokens must come from %s, never alone"
                            % (DOC, i, cells[5], sorted(WRITES)))
        rows.append({"start": start, "end": end, "width": int(width), "scope": scope,
                     "anchor": cells[4].strip("`").strip(), "written": written, "line": i})
    return rows, problems


def parse_magic(text):
    out = []
    for i, cells in table_rows(section(text, "Magic words")):
        if len(cells) >= 2 and re.match(r"^`?OT6_\w+`?$", cells[0]):
            m = re.match(r"^`?\$([0-9A-Fa-f]{4})`?$", cells[1])
            if m:
                out.append((cells[0].strip("`"), int(m.group(1), 16), i))
    return out


# ------------------------------------------------------------ the checks --
def check_data(rows, scraps, syms):
    """Compare parsed doc rows/scraps against parsed dbg symbols.

    Returns a list of problem strings; empty means the contract holds.
    """
    problems = []
    by_symbol = {}
    for r in rows:
        span = r["end"] - r["start"] + 1
        if span != r["width"]:
            problems.append(
                "%s:%d field %s: width column says %d but $%04X-$%04X is %d "
                "byte(s)" % (DOC, r["line"], r["symbol"] or "(reserved)",
                             r["width"], r["start"], r["end"], span))
        if not any(a <= r["start"] and r["end"] <= b for a, b in scraps):
            problems.append(
                "%s:%d field %s ($%04X-$%04X) sits outside every documented "
                "scrap %s" % (DOC, r["line"], r["symbol"] or "(reserved)",
                              r["start"], r["end"],
                              ", ".join("$%04X-$%04X" % s for s in scraps)
                              or "(none)"))
        if r["symbol"].startswith("OT6_"):
            by_symbol.setdefault(r["symbol"], []).append(r)

    ordered = sorted(rows, key=lambda r: r["start"])
    for prev, cur in zip(ordered, ordered[1:]):
        if cur["start"] <= prev["end"]:
            problems.append(
                "%s: fields %s ($%04X-$%04X) and %s ($%04X-$%04X) overlap"
                % (DOC, prev["symbol"] or "(reserved)", prev["start"],
                   prev["end"], cur["symbol"] or "(reserved)", cur["start"],
                   cur["end"]))

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

    for name, docrows in sorted(by_symbol.items()):
        if name not in syms:
            problems.append(
                "%s:%d field %s is in the table but the build assembled no "
                "such save-block symbol" % (DOC, docrows[0]["line"], name))
    return problems


def check_lengths(rows, allsyms):
    """A field whose symbol has a `<symbol>_LEN` equate (the length the code
    loops over) is documented at that width."""
    problems = []
    for r in rows:
        n = allsyms.get(r["symbol"] + "_LEN")
        if n is not None and n != r["width"]:
            problems.append("%s:%d field %s is %d byte(s) in the doc, but the build's %s_LEN is %d"
                            % (DOC, r["line"], r["symbol"], r["width"], r["symbol"], n))
    return problems


def eval_anchor(expr, allsyms, rom, rom_syms):
    """The battery offset an anchor names, or (None, why)."""
    m = re.match(r"^SRAMSlotPtrs\[([1-3])\]$", expr)
    if m:
        if rom is None or "SRAMSlotPtrs" not in rom_syms:
            return None, "no ROM / SRAMSlotPtrs to read"
        o = rom_offset(rom_syms["SRAMSlotPtrs"]) + 2 * int(m.group(1))
        return rom[o] | (rom[o + 1] << 8), None
    total = 0
    for term in expr.split("+"):
        term = term.strip()
        if re.match(r"^\$[0-9A-Fa-f]+$", term):
            total += int(term[1:], 16)
        elif re.match(r"^\d+$", term):
            total += int(term)
        elif term in allsyms:
            total += allsyms[term]
        else:
            return None, "unknown symbol %s" % term
    b = battery_offset(total)
    if b is None:
        return None, "$%06X is not an SRAM address" % total
    return b, None


def source_literals(src_root):
    """[(path, line, battery offset, text)] for every literal SRAM address in code."""
    out = []
    for path in sorted(glob.glob(os.path.join(src_root, "**", "*.asm"), recursive=True)) + \
            sorted(glob.glob(os.path.join(src_root, "**", "*.inc"), recursive=True)):
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, raw in enumerate(f, 1):
                code = raw.split(";", 1)[0]
                for m in SRAM_LIT.finditer(code):
                    b = battery_offset(int(m.group(1), 16))
                    if b is not None:
                        out.append((path, i, b, raw.strip()))
    return out


def check_battery(rows, magic, allsyms, sram_syms, literals, rom, rom_syms):
    problems = []
    rows = sorted(rows, key=lambda r: r["start"])
    at = 0
    for r in rows:
        if r["end"] - r["start"] + 1 != r["width"]:
            problems.append("%s:%d battery $%04X-$%04X: width column says %d, the range is %d"
                            % (DOC, r["line"], r["start"], r["end"], r["width"],
                               r["end"] - r["start"] + 1))
        if r["start"] != at:
            problems.append("%s:%d battery map %s at $%04X (the rows before end at $%04X)"
                            % (DOC, r["line"], "overlaps" if r["start"] < at else "has a gap",
                               r["start"], at))
        at = max(at, r["end"] + 1)
        if r["anchor"] and r["anchor"] != "-":
            b, why = eval_anchor(r["anchor"], allsyms, rom, rom_syms)
            if b is None:
                problems.append("%s:%d anchor %s: %s" % (DOC, r["line"], r["anchor"], why))
            elif b != r["start"]:
                problems.append("%s:%d anchor %s is battery $%04X in the build, the row starts at $%04X"
                                % (DOC, r["line"], r["anchor"], b, r["start"]))
    if at != BATTERY:
        problems.append("%s: the battery map ends at $%04X, not $8000" % (DOC, at))

    def row_at(b):
        for r in rows:
            if r["start"] <= b <= r["end"]:
                return r
        return None

    for name, b in sorted(sram_syms.items()):
        r = row_at(b)
        if r is None or "never" in r["written"]:
            problems.append("%s: symbol %s is battery $%04X, which the map %s"
                            % (DBG, name, b, "does not cover" if r is None else
                               "says today's ROM never writes (row %d)" % r["line"]))
    for path, line, b, text in literals:
        r = row_at(b)
        if r is None or "never" in r["written"]:
            problems.append("%s:%d literal SRAM address (battery $%04X) %s: %s"
                            % (path, line, b, "is outside the map" if r is None else
                               "is in a range the map says is never written", text))
    for name, val, line in magic:
        if name not in allsyms:
            problems.append("%s:%d magic %s: the build has no such symbol" % (DOC, line, name))
        elif allsyms[name] != val:
            problems.append("%s:%d magic %s is $%04X in the doc, $%04X in the build"
                            % (DOC, line, name, val, allsyms[name]))
    if rom is not None:
        for name, pat, what in SHAPES:
            if name not in rom_syms:
                problems.append("%s: no symbol %s to check that %s" % (DBG, name, what))
                continue
            o = rom_offset(rom_syms[name])
            if pat not in rom[o:o + 128]:
                problems.append("%s: %s no longer holds that %s" % (ROM, name, what))
        o, want, what = HEADER_SRAM
        if rom[o] != want:
            problems.append("%s: header byte $%04X is $%02X, not $%02X: %s" % (ROM, o, rom[o], want, what))
    return problems


def check(repo, dbg_path, doc_path, rom_path):
    with open(doc_path, encoding="utf-8") as f:
        text = f.read()
    rows, scraps = parse_doc(text)
    brows, problems = parse_battery(text)
    magic = parse_magic(text)
    with open(dbg_path, encoding="utf-8") as f:
        dbg = f.read()
    syms = parse_dbg(dbg)
    allsyms = parse_dbg_all(dbg)
    rom = open(rom_path, "rb").read() if rom_path and os.path.exists(rom_path) else None
    if not scraps:
        raise SystemExit("check_save_layout: %s declares no free scrap "
                         "(no 'Scrap `$xxxx-$xxxx`' line)" % doc_path)
    if not syms:
        raise SystemExit("check_save_layout: %s named no OT6 save-block "
                         "symbol -- is the ROM built?" % dbg_path)
    if not brows:
        raise SystemExit("check_save_layout: %s has no battery map rows" % doc_path)
    if rom is None:
        raise SystemExit("check_save_layout: no built ROM at %s" % rom_path)
    problems += check_data(rows, scraps, syms)
    problems += check_lengths(rows, allsyms)
    problems += check_battery(brows, magic, allsyms, sram_symbols(dbg),
                              source_literals(os.path.join(repo, SRC)), rom, allsyms)
    return problems, rows, syms, brows


# ------------------------------------------------------------- selftest --
SELF_DOC = """\
## Battery map
| Battery | Bytes | Scope | Holds | Anchor | Written | Absent |
|---|---|---|---|---|---|---|
| $0000-$09FF | 2560 | slot1 | slot | SRAMSlotPtrs[1] | save, clear | empty |
| $0A00-$13FF | 2560 | slot2 | slot | SRAMSlotPtrs[2] | save, clear | empty |
| $1400-$1DFF | 2560 | slot3 | slot | SRAMSlotPtrs[3] | save, clear | empty |
| $1E00-$1FFF | 512 | shared | misc | - | save, title, clear | - |
| $2000-$2001 | 2 | slot1 | magic | OT6_CODEX_MAGIC | load, play | wipe |
| $2002-$2FFF | 4094 | shared | reserved | - | never | - |
| $3000-$3001 | 2 | slot1 | magic | OT6_ESPER_ROOT | save | none |
| $3002-$3BFF | 3070 | shared | reserved | - | never | - |
| $3C00-$3C01 | 2 | shared | magic | OT6_ESPER_LIVE+OT6_ESPER_MAGIC | load | none |
| $3C02-$7FFF | 17406 | shared | reserved | - | never | - |

## Magic words
| Symbol | Value |
|---|---|
| OT6_CODEX_V2 | $384F |

## Save-block fields
| Address | Bytes | Symbol | Meaning |
|---|---|---|---|
| $1E1D-$1E1E | 2 | OT6_LOADOUT | x |
| $1E1F-$1E26 | 8 | `OT6_RAGELOAD` | x |
| $1E27-$1E2B | 5 | OT6_LORELOAD | x |
| $1E2F-$1E3F | 17 | OT6_SAVERSV | x |
- Scrap `$1E1D-$1E3F` (35 bytes).
"""
SELF_DBG = (
    'sym\tname="OT6_LOADOUT",val=0x7E1E1D,type=lab\n'
    'sym\tname="OT6_RAGELOAD",val=0x7E1E1F,type=lab\n'
    'sym\tname="OT6_LORELOAD",val=0x7E1E27,type=lab\n'
    'sym\tname="OT6_SAVERSV",val=0x7E1E2F,type=lab\n'
    'sym\tname="OT6_SAVERSV_LEN",val=0x11,type=equ\n'
    'sym\tname="OT6_CODEX_MAGIC",val=0x316000,type=lab\n'
    'sym\tname="OT6_ESPER_ROOT",val=0x317000,type=lab\n'
    'sym\tname="OT6_ESPER_LIVE",val=0x317C00,type=lab\n'
    'sym\tname="OT6_ESPER_MAGIC",val=0x0,type=lab\n'
    'sym\tname="OT6_CODEX_V2",val=0x384F,type=lab\n'
    'sym\tname="SRAMSlotPtrs",val=0xC31572,type=lab\n'
    'sym\tname="CopyGameDataToSRAM",val=0xC30100,type=lab\n'
    'sym\tname="LoadSaveSlot",val=0xC30140,type=lab\n'
    'sym\tname="CalcSaveSlotChecksum",val=0xC30180,type=lab\n'
    'sym\tname="ClearSRAM",val=0xC301C0,type=lab\n')


def _self_rom():
    rom = bytearray(0x40000)
    o = 0x031572
    rom[o:o + 8] = bytes.fromhex("00000000000a0014")
    rom[0x030100 + 10:0x030100 + 13] = bytes.fromhex("c0000a")
    rom[0x030140 + 10:0x030140 + 13] = bytes.fromhex("c0000a")
    rom[0x030180 + 10:0x030180 + 13] = bytes.fromhex("e0fe09")
    rom[0x0301C0 + 10:0x0301C0 + 13] = bytes.fromhex("e00020")
    rom[0xFFD8] = 5
    return rom


def _run_self(doc=SELF_DOC, dbg=SELF_DBG, rom=None, literals=()):
    rom = rom if rom is not None else _self_rom()
    rows, scraps = parse_doc(doc)
    brows, problems = parse_battery(doc)
    allsyms = parse_dbg_all(dbg)
    problems += check_data(rows, scraps, parse_dbg(dbg))
    problems += check_lengths(rows, allsyms)
    problems += check_battery(brows, parse_magic(doc), allsyms, sram_symbols(dbg),
                              list(literals), rom, allsyms)
    return problems


def selftest():
    rows, scraps = parse_doc(SELF_DOC)
    assert [(r["start"], r["end"], r["width"], r["symbol"]) for r in rows] == [
        (0x1E1D, 0x1E1E, 2, "OT6_LOADOUT"),
        (0x1E1F, 0x1E26, 8, "OT6_RAGELOAD"),
        (0x1E27, 0x1E2B, 5, "OT6_LORELOAD"),
        (0x1E2F, 0x1E3F, 17, "OT6_SAVERSV")], rows
    assert scraps == [(0x1E1D, 0x1E3F)], scraps
    brows, bp = parse_battery(SELF_DOC)
    assert bp == [] and len(brows) == 10, (bp, len(brows))
    assert battery_offset(0x317C00) == 0x3C00 and battery_offset(0x307FF0) == 0x1FF0
    assert battery_offset(0x326000) == 0x4000 and battery_offset(0x7E1E1D) is None
    clean = _run_self()
    assert clean == [], clean

    def red(want, **kw):
        probs = _run_self(**kw)
        assert any(want in p for p in probs), (want, probs)

    # save-block fields: an address one byte off, a symbol with no row, a
    # row the build lacks, an overlap, a field outside the scrap, a width
    red("assembled it at $1E20", dbg=SELF_DBG.replace("0x7E1E1F", "0x7E1E20"))
    red("OT6_NEWFIELD", dbg=SELF_DBG + 'sym\tname="OT6_NEWFIELD",val=0x7E1E2C,type=lab\n')
    red("no such save-block symbol", dbg=SELF_DBG.replace('name="OT6_LORELOAD"', 'name="X"'))
    red("overlap", doc=SELF_DOC.replace("| $1E27-$1E2B | 5 |", "| $1E26-$1E2A | 5 |"))
    red("outside every documented scrap", doc=SELF_DOC.replace("Scrap `$1E1D-$1E3F`", "Scrap `$1E1D-$1E26`"))
    red("width column says 3", doc=SELF_DOC.replace("| $1E1D-$1E1E | 2 |", "| $1E1D-$1E1E | 3 |"))
    # a reserve the code zeroes over a different length than the doc says
    red("OT6_SAVERSV_LEN is 16", dbg=SELF_DBG.replace("val=0x11,type=equ", "val=0x10,type=equ"))
    # battery map: the codex moved by a page in the build (the mutant ROM
    # whose save-touching address drifted from the frozen layout)
    red("anchor OT6_CODEX_MAGIC is battery $2400",
        dbg=SELF_DBG.replace("0x316000", "0x316400"))
    # the esper live page moved
    red("anchor OT6_ESPER_LIVE+OT6_ESPER_MAGIC is battery $3800",
        dbg=SELF_DBG.replace("0x317C00", "0x317800"))
    # the slot table changed in the ROM
    bad = _self_rom()
    bad[0x031572 + 7] = 0x15
    red("anchor SRAMSlotPtrs[3] is battery $1500", rom=bad)
    # a new OT6 SRAM symbol in reserved space
    red("never writes", dbg=SELF_DBG + 'sym\tname="OT6_NEWPAGE",val=0x326000,type=lab\n')
    # a literal SRAM address in the source pointing into reserve
    red("never written", literals=[("x.asm", 7, 0x4000, "sta $326000")])
    red("outside the map", doc=SELF_DOC.replace("| $3C02-$7FFF | 17406 |", "| $3C02-$7FFE | 17405 |"),
        literals=[("x.asm", 7, 0x7FFF, "sta $337fff")])
    # gaps, overlaps and widths in the map
    red("has a gap", doc=SELF_DOC.replace("| $2002-$2FFF | 4094 |", "| $2003-$2FFF | 4093 |"))
    red("width column says 4095", doc=SELF_DOC.replace("| $2002-$2FFF | 4094 |", "| $2002-$2FFF | 4095 |"))
    red("ends at $7FFF", doc=SELF_DOC.replace("| $3C02-$7FFF | 17406 |", "| $3C02-$7FFE | 17405 |"))
    red("scope 'slot4'", doc=SELF_DOC.replace("| 2 | slot1 | magic | OT6_CODEX_MAGIC", "| 2 | slot4 | magic | OT6_CODEX_MAGIC"))
    red("tokens must come from", doc=SELF_DOC.replace("| never | - |\n| $3000", "| never, save | - |\n| $3000"))
    # a magic word that changed
    red("magic OT6_CODEX_V2 is $384F in the doc, $3850", dbg=SELF_DBG.replace("0x384F", "0x3850"))
    # the vanilla save code's shape
    bad = _self_rom()
    bad[0x030180 + 11] = 0xFC
    red("CalcSaveSlotChecksum no longer holds", rom=bad)
    bad = _self_rom()
    bad[0xFFD8] = 3
    red("header byte $FFD8 is $03", rom=bad)
    # the source scan finds a literal in code and skips one in a comment
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "a.asm"), "w") as f:
            f.write("        lda $307ff1  ; seed\n; sta $326000 only a comment\n")
        lits = source_literals(d)
        assert [(x[1], x[2]) for x in lits] == [(1, 0x1FF1)], lits
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
    ap.add_argument("--rom", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    dbg_path = args.dbg or os.environ.get("OT6_DBG") or \
        os.path.join(args.repo, DBG)
    doc_path = args.doc or os.path.join(args.repo, DOC)
    rom_path = args.rom or os.path.join(args.repo, ROM)
    problems, rows, syms, brows = check(args.repo, dbg_path, doc_path, rom_path)
    for p in problems:
        print("check_save_layout: " + p)
    if problems:
        return 1
    print("check_save_layout OK: %d save-block field(s), %d assembled symbol(s); "
          "%d battery ranges tile $0000-$7FFF, anchors, SRAM symbols, source "
          "literals and the vanilla save code agree with ff6-en.dbg and the ROM"
          % (len(rows), len(syms), len(brows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
