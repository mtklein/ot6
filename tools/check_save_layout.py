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
  Magic words (section "## Magic words"): each symbol's assembled value;
    every codex magic the build assembles (OT6_CODEX_V<n>, OT6_CODEX_GLOBAL)
    has a row; a codex magic whose row says "migrated" is retired: the
    source only compares against it (`cmp #`), and the one that is not is
    the magic the source signs with (`lda #`).
  The six-class codex (section "## The six-class codex", #566): the table
    of the class byte's six bits, which an O9 page fixes.  Checked: six
    rows, bits $01 $02 $04 $08 $10 $20; each row's symbol assembles to its
    bit, and OT6_CLASSES to all six; the built ROM's Ot6ClassSplitTbl (what
    a four-class page's bits become: four bytes a species) is 384 x 4 bytes
    of those six bits and byte for byte the source's
    (ff6/src/battle/ot6_class_split.inc); OT6_CODEX_FOUR is $0F and
    OT6_CODEX_SPECIES 384.

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
SWITCH_CELL = re.compile(r"^`?\$([0-9A-Fa-f]{4})`?$")
SWITCH_LO, SWITCH_HI = 0x1E80, 0x1F5F
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


def parse_switches(text):
    """[{switch, byte, bit, symbol, line}] of the event-switch table."""
    out = []
    for i, cells in table_rows(section(text, "Event switches")):
        if len(cells) < 4:
            continue
        m = SWITCH_CELL.match(cells[0])
        b = SWITCH_CELL.match(cells[1])
        if not m or not b or not cells[2].strip("`").isdigit():
            continue                      # header, separator, prose row
        out.append({"switch": int(m.group(1), 16), "byte": int(b.group(1), 16),
                    "bit": int(cells[2].strip("`")), "symbol": cells[3].strip("`").strip(), "line": i})
    return out


def switch_values(dbg_text, name):
    """Every value a symbol of this name has in the dbg (one per module that defines it)."""
    return sorted({int(m.group(1), 16) for m in
                   re.finditer(r'\bname="%s",[^\n]*\bval=0x([0-9A-Fa-f]+)' % re.escape(name), dbg_text)})


def check_switch_equates(srows, dbg_text):
    """Each claimed switch's `<name>_SWITCH` equate, in every module that defines one (the code's
    code_ext.inc and the event script's own), is the row's switch (#552)."""
    problems = []
    for r in srows:
        if not r["symbol"].endswith("_FLAG"):
            continue
        name = r["symbol"][:-len("_FLAG")] + "_SWITCH"
        vals = switch_values(dbg_text, name)
        if vals and vals != [r["switch"]]:
            problems.append("%s:%d switch $%04X: %s is %s in the build" % (DOC, r["line"], r["switch"], name,
                                                                      ", ".join("$%04X" % v for v in vals)))
    return problems


def check_switches(srows, syms, allsyms):
    """The event-switch rows against the build; returns (problems, the symbols
    they cover, which need no save-block field row)."""
    problems, covered = [], set()
    for r in srows:
        if r["byte"] != SWITCH_LO + (r["switch"] >> 3) or r["bit"] != (r["switch"] & 7):
            problems.append("%s:%d switch $%04X is byte $%04X bit %d, not $%04X bit %d"
                            % (DOC, r["line"], r["switch"], SWITCH_LO + (r["switch"] >> 3),
                               r["switch"] & 7, r["byte"], r["bit"]))
        if not SWITCH_LO <= r["byte"] <= SWITCH_HI:
            problems.append("%s:%d switch byte $%04X is outside the switch array $%04X-$%04X"
                            % (DOC, r["line"], r["byte"], SWITCH_LO, SWITCH_HI))
        addrs = syms.get(r["symbol"])
        if not addrs:
            problems.append("%s:%d switch $%04X: the build assembled no save-block symbol %s"
                            % (DOC, r["line"], r["switch"], r["symbol"]))
            continue
        covered.add(r["symbol"])
        if addrs != [r["byte"]]:
            problems.append("%s:%d switch $%04X: %s assembles at %s, not the switch's byte $%04X"
                            % (DOC, r["line"], r["switch"], r["symbol"],
                               ", ".join("$%04X" % a for a in addrs), r["byte"]))
        if r["symbol"].endswith("_FLAG"):
            bit = allsyms.get(r["symbol"][:-len("_FLAG")] + "_BIT")
            if bit is not None and bit != 1 << r["bit"]:
                problems.append("%s:%d switch $%04X: %s_BIT is $%02X, not bit %d's $%02X"
                                % (DOC, r["line"], r["switch"], r["symbol"][:-5], bit, r["bit"],
                                   1 << r["bit"]))
    for name, addrs in sorted(syms.items()):
        if name not in covered and all(SWITCH_LO <= a <= SWITCH_HI for a in addrs):
            problems.append("%s: symbol %s is in the event-switch array at %s but has no row in %s's "
                            "Event switches table" % (DBG, name, ", ".join("$%04X" % a for a in addrs), DOC))
            covered.add(name)
    return problems, covered


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


def parse_magic_meaning(text):
    """{symbol: meaning cell} of the Magic words table."""
    out = {}
    for _, cells in table_rows(section(text, "Magic words")):
        if len(cells) >= 3 and re.match(r"^`?OT6_\w+`?$", cells[0]):
            out[cells[0].strip("`")] = cells[2]
    return out


CODEX_MAGIC_SYM = re.compile(r"^OT6_CODEX_(?:V\d+|GLOBAL)$")
SPLIT_INC = "ff6/src/battle/ot6_class_split.inc"
SPLIT_LINE = re.compile(r"^\s+\.byte\b([^;]*)")
CLASS_ROW = re.compile(r"^`?(OT6_\w+)`?$")
SPECIES = 384
SIX_BITS = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20]


def parse_classes(text):
    """The six-class codex table: [(bit, symbol, line)]."""
    out = []
    for i, cells in table_rows(section(text, "The six-class codex")):
        if len(cells) < 2:
            continue
        b = re.match(r"^`?\$([0-9A-Fa-f]{2})`?$", cells[0])
        m = CLASS_ROW.match(cells[1])
        if b and m:
            out.append((int(b.group(1), 16), m.group(1), i))
    return out


def parse_split_inc(text):
    """Every byte of the source table's `.byte $xx, ...` lines, in order."""
    out = []
    for line in text.splitlines():
        m = SPLIT_LINE.match(line)
        if m:
            out += [int(x, 16) for x in re.findall(r"\$([0-9A-Fa-f]{2})\b", m.group(1))]
    return out


def source_uses(src_root, names):
    """[(path, line, code)] for every code line (comment stripped) naming one of `names`."""
    out = []
    pat = re.compile(r"\b(%s)\b" % "|".join(re.escape(n) for n in names)) if names else None
    if pat is None:
        return out
    for path in sorted(glob.glob(os.path.join(src_root, "**", "*.asm"), recursive=True)) + \
            sorted(glob.glob(os.path.join(src_root, "**", "*.inc"), recursive=True)):
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, raw in enumerate(f, 1):
                code = raw.split(";", 1)[0]
                if pat.search(code):
                    out.append((path, i, code.strip()))
    return out


def check_codex(text, allsyms, rom, uses, split_src):
    """The codex magics' roles and the six-class migration's tables (#566).
    `uses` is source_uses() of the doc's codex magic symbols; `split_src`
    the source split table's bytes (parse_split_inc), or None when the
    source file is missing."""
    problems = []
    meaning = parse_magic_meaning(text)
    doc_codex = [n for n in meaning if CODEX_MAGIC_SYM.match(n)]
    for n in sorted(allsyms):
        if CODEX_MAGIC_SYM.match(n) and n not in meaning:
            problems.append("%s: the build assembles codex magic %s ($%04X), which has no Magic words row"
                            % (DOC, n, allsyms[n]))
    current = [n for n in doc_codex if "migrated" not in meaning[n].lower()]
    if doc_codex and len(current) != 1:
        problems.append("%s: Magic words must name exactly one codex magic that is not \"migrated\" (the one "
                        "today's ROM signs with); it names %s" % (DOC, ", ".join(current) or "none"))
    signed = False
    for path, line, code in uses:
        for n in doc_codex:
            if not re.search(r"\b%s\b" % re.escape(n), code):
                continue
            if re.match(r"^%s\s*:?=" % re.escape(n), code):
                continue                        # its definition
            if n in current:
                signed = signed or bool(re.search(r"\blda\s+#%s\b" % re.escape(n), code))
            elif not re.search(r"\bcmp\s+#%s\b" % re.escape(n), code):
                problems.append("%s:%d uses the migrated codex magic %s other than to compare against it "
                                "(a migrated magic is never written again): %s" % (path, line, n, code))
    if len(current) == 1 and not signed:
        problems.append("%s: no source line signs a codex page with %s (`lda #%s`)" % (SRC, current[0], current[0]))

    classes = parse_classes(text)
    if not classes:
        if section(text, "The six-class codex"):
            problems.append("%s: \"The six-class codex\" has no table of the class byte's six bits" % DOC)
        return problems
    if [c[0] for c in classes] != SIX_BITS:
        problems.append("%s: the six-class codex table must hold the bits $01 $02 $04 $08 $10 $20 in order, one "
                        "row each; it holds %s" % (DOC, " ".join("$%02X" % c[0] for c in classes)))
        return problems
    for bit, sym, line in classes:
        if sym not in allsyms:
            problems.append("%s:%d class %s: the build has no such symbol" % (DOC, line, sym))
        elif allsyms[sym] != bit:
            problems.append("%s:%d class %s is bit $%02X in the doc, $%02X in the build (an O9 page fixes the "
                            "class byte's bits)" % (DOC, line, sym, bit, allsyms[sym]))
    for name, want in (("OT6_CLASSES", 0x3F), ("OT6_CODEX_FOUR", 0x0F), ("OT6_CODEX_SPECIES", SPECIES)):
        if allsyms.get(name) != want:
            problems.append("%s: %s is %s, not $%X" % (DBG, name, "missing" if name not in allsyms
                                                        else "$%X" % allsyms[name], want))
    for name in ("Ot6ClassSplitTbl", "Ot6CodexSix"):
        if name not in allsyms:
            problems.append("%s: no symbol %s (the six-class migration)" % (DBG, name))
    if rom is None or "Ot6ClassSplitTbl" not in allsyms:
        return problems
    o = rom_offset(allsyms["Ot6ClassSplitTbl"])
    table = list(rom[o:o + SPECIES * 4])
    wide = [i for i, b in enumerate(table) if b & ~0x3F]
    if wide:
        problems.append("%s: Ot6ClassSplitTbl holds a bit past the six classes (species %d, four-class bit $%02X: "
                        "$%02X)" % (ROM, wide[0] // 4, 1 << (wide[0] % 4), table[wide[0]]))
    if split_src is None:
        problems.append("%s is missing (Ot6ClassSplitTbl's source)" % SPLIT_INC)
    elif len(split_src) != SPECIES * 4:
        problems.append("%s holds %d bytes, not four per codex species (%d)"
                        % (SPLIT_INC, len(split_src), SPECIES * 4))
    elif split_src != table:
        d = [i for i in range(SPECIES * 4) if split_src[i] != table[i]]
        problems.append("%s: Ot6ClassSplitTbl is not %s's bytes (%d differ; species %d, four-class bit $%02X is "
                        "$%02X in the ROM, $%02X in the source): is the ROM built from this tree?"
                        % (ROM, SPLIT_INC, len(d), d[0] // 4, 1 << (d[0] % 4), table[d[0]], split_src[d[0]]))
    return problems


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
    sprobs, covered = check_switches(parse_switches(text), syms, allsyms)
    problems += sprobs
    problems += check_switch_equates(parse_switches(text), dbg)
    problems += check_data(rows, scraps, {k: v for k, v in syms.items() if k not in covered})
    problems += check_lengths(rows, allsyms)
    problems += check_battery(brows, magic, allsyms, sram_symbols(dbg),
                              source_literals(os.path.join(repo, SRC)), rom, allsyms)
    codex_names = [n for n in parse_magic_meaning(text) if CODEX_MAGIC_SYM.match(n)]
    inc = os.path.join(repo, SPLIT_INC)
    split_src = parse_split_inc(open(inc, encoding="utf-8").read()) if os.path.exists(inc) else None
    problems += check_codex(text, allsyms, rom, source_uses(os.path.join(repo, SRC), codex_names), split_src)
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
| Symbol | Value | Meaning |
|---|---|---|
| OT6_CODEX_V3 | $394F | six classes |
| OT6_CODEX_V2 | $384F | four classes, migrated on first touch |

## The six-class codex
| Bit | Symbol | Class |
|---|---|---|
| $01 | OT6_SWORD | Sword |
| $02 | OT6_DAGGER | Dagger |
| $04 | OT6_BLUNT | Blunt |
| $08 | OT6_RANGED | Ranged |
| $10 | OT6_KATANA | Katana |
| $20 | OT6_SPEAR | Spear |

## Save-block fields
| Address | Bytes | Symbol | Meaning |
|---|---|---|---|
| $1E1D-$1E1E | 2 | OT6_LOADOUT | x |
| $1E1F-$1E26 | 8 | `OT6_RAGELOAD` | x |
| $1E27-$1E2B | 5 | OT6_LORELOAD | x |
| $1E2F-$1E3F | 17 | OT6_SAVERSV | x |
- Scrap `$1E1D-$1E3F` (35 bytes).

## Event switches
| Switch | Byte | Bit | Symbol | Meaning |
|---|---|---|---|---|
| $00E0 | $1E9C | 0 | OT6_LEO_FLAG | x |
"""
SELF_DBG = (
    'sym\tname="OT6_LOADOUT",val=0x7E1E1D,type=lab\n'
    'sym\tname="OT6_RAGELOAD",val=0x7E1E1F,type=lab\n'
    'sym\tname="OT6_LORELOAD",val=0x7E1E27,type=lab\n'
    'sym\tname="OT6_SAVERSV",val=0x7E1E2F,type=lab\n'
    'sym\tname="OT6_SAVERSV_LEN",val=0x11,type=equ\n'
    'sym\tname="OT6_LEO_FLAG",val=0x7E1E9C,type=lab\n'
    'sym\tname="OT6_LEO_BIT",val=0x1,type=equ\n'
    'sym\tname="OT6_LEO_SWITCH",val=0xE0,type=equ\n'
    'sym\tname="OT6_LEO_SWITCH",val=0xE0,type=equ\n'
    'sym\tname="OT6_CODEX_MAGIC",val=0x316000,type=lab\n'
    'sym\tname="OT6_ESPER_ROOT",val=0x317000,type=lab\n'
    'sym\tname="OT6_ESPER_LIVE",val=0x317C00,type=lab\n'
    'sym\tname="OT6_ESPER_MAGIC",val=0x0,type=lab\n'
    'sym\tname="OT6_CODEX_V2",val=0x384F,type=lab\n'
    'sym\tname="OT6_CODEX_V3",val=0x394F,type=lab\n'
    'sym\tname="OT6_CODEX_FOUR",val=0xF,type=equ\n'
    'sym\tname="OT6_CODEX_SPECIES",val=0x180,type=equ\n'
    'sym\tname="OT6_SWORD",val=0x1,type=lab\n'
    'sym\tname="OT6_DAGGER",val=0x2,type=lab\n'
    'sym\tname="OT6_BLUNT",val=0x4,type=lab\n'
    'sym\tname="OT6_RANGED",val=0x8,type=lab\n'
    'sym\tname="OT6_CLASSES",val=0x3F,type=lab\n'
    'sym\tname="OT6_KATANA",val=0x10,type=lab\n'
    'sym\tname="OT6_SPEAR",val=0x20,type=lab\n'
    'sym\tname="Ot6CodexSix",val=0xC32000,type=lab\n'
    'sym\tname="Ot6ClassSplitTbl",val=0xC32200,type=lab\n'
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
    rom[0x032200:0x032200 + SPECIES * 4] = bytes(SELF_SPLIT)     # Ot6ClassSplitTbl
    return rom


SELF_SPLIT = [(i * 7) & 0x3F for i in range(SPECIES * 4)]
SELF_USES = [("ot6_codex.asm", 22, "OT6_CODEX_V3     := $394f"), ("ot6_codex.asm", 23, "OT6_CODEX_V2     := $384f"),
             ("ot6_codex.asm", 77, "cmp     #OT6_CODEX_V3"), ("ot6_codex.asm", 80, ":       cmp     #OT6_CODEX_V2"),
             ("ot6_codex.asm", 117, "lda     #OT6_CODEX_V3")]


def _run_self(doc=SELF_DOC, dbg=SELF_DBG, rom=None, literals=(), uses=SELF_USES, split=SELF_SPLIT):
    rom = rom if rom is not None else _self_rom()
    rows, scraps = parse_doc(doc)
    brows, problems = parse_battery(doc)
    allsyms = parse_dbg_all(dbg)
    syms = parse_dbg(dbg)
    sprobs, covered = check_switches(parse_switches(doc), syms, allsyms)
    problems += sprobs
    problems += check_switch_equates(parse_switches(doc), dbg)
    problems += check_data(rows, scraps, {k: v for k, v in syms.items() if k not in covered})
    problems += check_lengths(rows, allsyms)
    problems += check_battery(brows, parse_magic(doc), allsyms, sram_symbols(dbg),
                              list(literals), rom, allsyms)
    problems += check_codex(doc, allsyms, rom, list(uses), split)
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
    # event switches (#552): a claimed switch's symbol off its byte, a row whose byte is not the
    # switch's, a bit equate that disagrees, a switch symbol with no row, a row the build lacks
    red("assembles at $1E9D", dbg=SELF_DBG.replace("0x7E1E9C", "0x7E1E9D"),
        doc=SELF_DOC.replace("| $00E0 | $1E9C |", "| $00E0 | $1E9C |"))
    red("is byte $1E9C bit 0, not $1E9D bit 0", doc=SELF_DOC.replace("| $00E0 | $1E9C |", "| $00E0 | $1E9D |"))
    red("OT6_LEO_BIT is $02", dbg=SELF_DBG.replace('"OT6_LEO_BIT",val=0x1', '"OT6_LEO_BIT",val=0x2'))
    red("Event switches table", doc=SELF_DOC.replace("| $00E0 | $1E9C | 0 | OT6_LEO_FLAG | x |\n", ""))
    red("OT6_LEO_SWITCH is $00E0, $00E1", dbg=SELF_DBG + 'sym\tname="OT6_LEO_SWITCH",val=0xE1,type=equ\n')
    red("assembled no save-block symbol OT6_X_FLAG", doc=SELF_DOC.replace("| 0 | OT6_LEO_FLAG |", "| 0 | OT6_X_FLAG |"))
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
    # the codex magics (#566): an assembled one with no row; two current ones;
    # a migrated one written; the current one never signed
    red("the build assembles codex magic OT6_CODEX_V4 ($3A4F), which has no Magic words row",
        dbg=SELF_DBG + 'sym\tname="OT6_CODEX_V4",val=0x3A4F,type=lab\n')
    red("must name exactly one codex magic that is not \"migrated\"",
        doc=SELF_DOC.replace("four classes, migrated on first touch", "four classes"))
    red("ot6_codex.asm:138 uses the migrated codex magic OT6_CODEX_V2 other than to compare against it",
        uses=SELF_USES + [("ot6_codex.asm", 138, "lda     #OT6_CODEX_V2")])
    red("no source line signs a codex page with OT6_CODEX_V3", uses=SELF_USES[:-1])
    # the six-class codex: a class off its bit, a row missing, the split
    # table against its source, a bit past the six, the constants
    red("class OT6_KATANA is bit $10 in the doc, $40 in the build",
        dbg=SELF_DBG.replace('name="OT6_KATANA",val=0x10', 'name="OT6_KATANA",val=0x40'))
    red("class OT6_BLUNT: the build has no such symbol",
        dbg=SELF_DBG.replace('name="OT6_BLUNT"', 'name="OT6_FIST"'))
    red("must hold the bits $01 $02 $04 $08 $10 $20 in order",
        doc=SELF_DOC.replace("| $08 | OT6_RANGED | Ranged |\n", ""))
    bad = _self_rom()
    bad[0x032200 + 50 * 4 + 1] ^= 0x01
    red("Ot6ClassSplitTbl is not ff6/src/battle/ot6_class_split.inc's bytes (1 differ; species 50, four-class bit "
        "$02", rom=bad)
    bad = _self_rom()
    bad[0x032200 + 9 * 4 + 3] = 0x7F
    red("Ot6ClassSplitTbl holds a bit past the six classes (species 9, four-class bit $08: $7F)", rom=bad)
    red("holds 1535 bytes, not four per codex species", split=SELF_SPLIT[:-1])
    red("ot6_class_split.inc is missing", split=None)
    red("OT6_CODEX_FOUR is $1F, not $F", dbg=SELF_DBG.replace('name="OT6_CODEX_FOUR",val=0xF', 'name="OT6_CODEX_FOUR",val=0x1F'))
    red("OT6_CLASSES is $7F, not $3F", dbg=SELF_DBG.replace('name="OT6_CLASSES",val=0x3F', 'name="OT6_CLASSES",val=0x7F'))
    assert parse_split_inc("Tbl:\n        .byte   $0a, $00, $3f, $01 ;  1 x $55\n; .byte $01\n        .byte   $03\n") == \
        [0x0A, 0x00, 0x3F, 0x01, 0x03]
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
          "literals and the vanilla save code agree with ff6-en.dbg and the ROM; "
          "the codex signs one magic and only compares the migrated ones, the six "
          "classes sit on the doc's bits, and the migration's table is the source's"
          % (len(rows), len(syms), len(brows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
