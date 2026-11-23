#!/usr/bin/env python3
"""Golden saves: published releases' battery saves, held to today's ROM (#389).

tools/tests/golden-saves/ keeps a few saves from each release's saves/
folder (MANIFEST.json lists them with their hashes and the zip they came
from).  Each fixture is a checkpoint directory (manifest.json in the
ot6.sram-checkpoint/v1 schema and battery.sram), so run.sh can Continue it.
tools/tests/save_golden.lua plays each one on today's ROM: Continue, read
the loaded game out, save into the same slot through the Save menu, Reset,
Continue again.  This script holds that run to the fixture file:

    golden_saves.py verify
        every fixture is the bytes MANIFEST.json records, and validates
    golden_saves.py check FIXTURE LOG BATTERY
        the run's log and the battery the run left (run.sh's
        OT6_CAPTURE_SRM) against FIXTURE's battery.sram:
          * the game the Continue loaded holds what tools/roster.py reads
            from the file (every character's level, HP, MP, experience,
            esper and gear), and the file's gil, bag, map, tile, story
            switches and treasure bits;
          * the slot's codex page is the file's, migrated: byte for byte
            the file's page as today's ROM leaves it at the load (an O8
            page's revealed classes rewritten for the six classes by the
            built ROM's own Ot6ClassSplitTbl, the element table and the
            reserves as they were, the magic O9; an O9 page as it is; a page
            with no magic zeroed and signed), and the same after the saves;
          * the live esper page is the slot's page (a release from v0.44
            on), or empty for an older save, whose page is unsigned;
          * the battery after the save differs from the file only inside
            the ranges docs/design/save-layout.md's battery map says today's
            ROM writes on a Continue of slot 3 and a save into it
            (scope slot3 or shared, written at save, load, title or play);
          * the save round-trips: the slot it wrote holds the file's roster,
            gil, bag and espers (the field has run between the load and the
            save, so story switches may move), the second load reads that
            slot back byte for byte, and the slot's esper page is now
            signed and holds the live page.
    golden_saves.py add VERSION ZIP KEY...
        the release step: copy KEY's save (release_saves.py's name for it)
        out of the release zip's saves/ folder into golden-saves/VERSION/
        and record it in MANIFEST.json
    golden_saves.py negative FIXTURE LOG BATTERY [WANT]
        a run whose check must FAIL (the corrupted fixture, or a mutant
        ROM's run): exit 0 only when check refuses it with a problem naming
        WANT (default "esper")
    golden_saves.py firstsave CAPTURE_DIR
        a New Game's first save (the play from power-on's world-narshe-v1
        capture): its slot is signed $5653 version 2, its reserve, tail
        and page reserves are zero, and its loadouts are AUTO
    golden_saves.py synthetic
        (re)build the three synthetic codex fixtures, which verify holds to
        their sources:
          golden-saves/junk/v0.46-kolts-six3f, for a six-class page whose
            species answer to less than it holds: v0.46/kolts-summit-v1 with
            slot 3's codex page signed O9 and every byte of its class table
            $3F (all six classes revealed; a load must leave it as it is,
            and a battle must draw only what each body's row answers to);
          golden-saves/junk/v0.46-kolts-classff, for the six-class
            migration: v0.46/kolts-summit-v1 with every byte of slot 3's
            revealed-class table $FF (every four-class bit, and the four
            bits no four-class build wrote);
          golden-saves/junk/v0.50-kolts-unsigned, for a page with no
            magic: v0.50/kolts-summit-v1 with slot 3's codex magic zeroed
            (its tables left as they were: the load must zero them)
    golden_saves.py notes NOTES.md
        the release notes' save line: "Saves from vX.Y and later load in
        this release", vX.Y the oldest release in the golden set, and no
        "save layout" (a release's saves are named by what loads, never by
        a layout: up to v0.30 that line only named the previous release,
        and from then on it stayed at v0.29)
    golden_saves.py --selftest
        the check against in-memory mutants
"""

from __future__ import annotations

import functools
import hashlib
import json
import os
import re
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "tests" / "lib"))
import check_save_layout as csl  # noqa: E402
import roster  # noqa: E402
import sram_checkpoint as sc  # noqa: E402

GOLDEN = ROOT / "tools" / "tests" / "golden-saves"
MANIFEST = GOLDEN / "MANIFEST.json"
SCHEMA = "ot6.golden-saves/v1"
LAYOUT = "ot6-codex-o8-v1"
SLOT_PTR = sc.SLOT_PTR
BLOCK = 0x0A00
CODEX, ESPER, LIVE = 0x2000, 0x3000, 0x3C00
# the codex page's magics (docs/design/save-layout.md "Magic words"), its
# two tables, and the four-to-six class rule (ot6_codex.asm Ot6CodexSix)
CODEX_SIX, CODEX_FOUR, CODEX_GLOBAL = 0x394F, 0x384F, 0x374F
ELEMS, CLASSES, TABLES_END, SPECIES = 0x010, 0x190, 0x310, 384
SIX_CLASSES = 0x3F                          # Sword Dagger Blunt Ranged Katana Spear
ESPER_MAGIC = 0x3145
CTR, CTR_END = 0x0010, 0x02B4      # 13 rows of 26 words
LEO = 0x0280                        # row 12 (actor 12): read from a version-2 block only (#552)
# what a Continue of slot 3 and a save into it may touch (the battery map's
# Written tokens; newgame and clear rows are not exercised)
RUN_WRITES = {"save", "load", "title", "play", "zero"}
SIG, SIGWORD, SIGVER = 0x1E2C, 0x5653, 2
LEOVER = 2                          # the layout version whose pages hold row 12
DUMP = re.compile(r"^\[golden\] dump (\S+) (\S+) ([0-9A-F]{4}) ([0-9A-F]+)\s*$")


class GoldenError(Exception):
    pass


def w16(b, o):
    return b[o] | (b[o + 1] << 8)


def six_class(b, became):
    """A four-class revealed byte as the six classes hold it: the OR of
    `became[k]` (the species' four Ot6ClassSplitTbl bytes: the six-class
    bits its weakness of four-class bit k became, $00 where it had none)
    for each of bits 0-3 set in `b`; every other bit of `b` is dropped."""
    n = 0
    for k in range(4):
        if b >> k & 1:
            n |= became[k]
    return n


def rom_split(rom=None, dbg=None):
    """Ot6ClassSplitTbl, read from the built ROM (the bytes the migration
    itself reads; tools/check_save_layout.py holds them to the source): one
    4-tuple per species."""
    rom = Path(rom or os.environ.get("OT6_ROM") or ROOT / "build" / "ot6.sfc")
    dbg = Path(dbg or os.environ.get("OT6_DBG") or ROOT / csl.DBG)
    try:
        syms = csl.parse_dbg_all(dbg.read_text(encoding="utf-8"))
        data = rom.read_bytes()
    except OSError as e:
        raise GoldenError(f"the class split table: {e}")
    if "Ot6ClassSplitTbl" not in syms:
        raise GoldenError(f"{dbg} has no Ot6ClassSplitTbl")
    o = csl.rom_offset(syms["Ot6ClassSplitTbl"])
    t = data[o:o + SPECIES * 4]
    if len(t) != SPECIES * 4 or any(x & ~SIX_CLASSES for x in t):
        raise GoldenError(f"{rom}: Ot6ClassSplitTbl is not {SPECIES} x 4 bytes of six class bits")
    return [tuple(t[i * 4:i * 4 + 4]) for i in range(SPECIES)]


def codex_loaded(f, slot, split):
    """Slot `slot`'s $400-byte codex page as today's ROM leaves it when it
    loads battery `f` (Ot6CodexEnsure): an O9 page as it is; an O8 page with
    its class table rewritten for the six classes; an O7 cartridge-wide
    codex (page 1) cloned and rewritten; anything else zeroed.  The magic is
    O9, and the pad and tail are the file's (a save zeroes them, not a
    load)."""
    base = CODEX + (slot - 1) * 0x400
    page = bytearray(f[base:base + 0x400])
    magic = w16(f, base)
    if w16(f, CODEX) == CODEX_GLOBAL:
        page[ELEMS:TABLES_END] = f[CODEX + ELEMS:CODEX + TABLES_END]
        magic = CODEX_FOUR
    if magic == CODEX_FOUR:
        for sp in range(SPECIES):
            page[CLASSES + sp] = six_class(page[CLASSES + sp], split[sp])
    elif magic != CODEX_SIX:
        page[ELEMS:TABLES_END] = bytes(TABLES_END - ELEMS)
    page[0:2] = CODEX_SIX.to_bytes(2, "little")
    return bytes(page)


def magic_and_tables(page):
    """A codex page with its reserves (the pad and the tail, which a save
    zeroes) blanked: what a save must carry."""
    b = bytearray(0x400)
    b[0:2] = page[0:2]
    b[ELEMS:TABLES_END] = page[ELEMS:TABLES_END]
    return bytes(b)


def page_diff(what, want, got):
    """One problem line naming where a codex page departs from `want`."""
    bad = [o for o in range(len(want)) if want[o] != got[o]]
    o = bad[0]
    if o < 2:
        where = f"its magic is ${w16(got, 0):04X}, not ${w16(want, 0):04X}"
    elif ELEMS <= o < CLASSES:
        where = f"species {o - ELEMS}'s elements read ${got[o]:02X}, not ${want[o]:02X}"
    elif CLASSES <= o < TABLES_END:
        where = f"species {o - CLASSES}'s classes read ${got[o]:02X}, not ${want[o]:02X}"
    else:
        where = f"its reserve byte +${o:03X} reads ${got[o]:02X}, not ${want[o]:02X}"
    return f"{what} ({len(bad)} byte(s) differ; the first: {where})"


def parse_log(text):
    """{tag: {what: bytes}} from the run's [golden] dump lines."""
    raw = {}
    for line in text.splitlines():
        m = DUMP.match(line.strip())
        if not m:
            continue
        tag, what, addr, hx = m.group(1), m.group(2), int(m.group(3), 16), m.group(4)
        raw.setdefault(tag, {}).setdefault(what, {})[addr] = bytes.fromhex(hx)
    out = {}
    for tag, whats in raw.items():
        for what, parts in whats.items():
            lo = min(parts)
            buf = bytearray()
            for a in sorted(parts):
                if a != lo + len(buf):
                    raise GoldenError(f"log: {tag} {what} dump has a gap at ${a:04X}")
                buf += parts[a]
            out.setdefault(tag, {})[what] = bytes(buf)
    return out


def block_of(battery, slot):
    p = SLOT_PTR[slot]
    return battery[p:p + BLOCK]


def block_version(block):
    """The block's layout version as Ot6SaveSign reads it: 0 when unsigned."""
    v = block[SIG + 2 - 0x1600]
    if w16(block, SIG - 0x1600) != SIGWORD or not 1 <= v <= SIGVER:
        return 0
    return v


def roster_of_block(block):
    """tools/roster.py's reading of a bare $1600-$1FFF block."""
    with tempfile.NamedTemporaryFile(suffix=".sram", delete=False) as f:
        f.write(block)
        path = f.name
    try:
        rows, err = roster.roster(path)
    finally:
        os.unlink(path)
    if err:
        raise GoldenError("roster: " + err)
    return rows


def roster_of_file(path):
    rows, err = roster.roster(str(path))
    if err:
        raise GoldenError(f"roster {path}: {err}")
    return rows


def facts(block):
    """Gil, bag, map, tiles, story switches and treasure bits of a block."""
    def by(a, n=1):
        return block[a - 0x1600:a - 0x1600 + n]
    return {
        "gil": int.from_bytes(by(0x1860, 3), "little"),
        "bag items": by(0x1869, 256).hex(),
        "bag counts": by(0x1969, 256).hex(),
        "map word": w16(block, 0x1F64 - 0x1600),
        "field tile": tuple(by(0x1FC0, 2)),
        "world tile": tuple(by(0x1F60, 2)),
        "story switches": by(0x1E80, 0xE0).hex(),
        "treasure bits": by(0x1E40, 0x40).hex(),
        "espers held": by(0x1A69, 4).hex(),
    }


# what a save made standing where the load put the party holds as the file did
STILL = ("gil", "bag items", "bag counts", "espers held")


def compare(problems, what, want, got):
    if want == got:
        return
    if isinstance(want, dict):
        for k in want:
            if want[k] != got.get(k):
                problems.append(f"{what}: {k}: the file holds {want[k]!r}, the run read {got.get(k)!r}")
        return
    if isinstance(want, list):
        for a, b in zip(want, got):
            if a != b:
                problems.append(f"{what}: {a['name']}: the file holds {a}, the run read {b}")
        if len(want) != len(got):
            problems.append(f"{what}: the file lists {len(want)} characters, the run {len(got)}")
        return
    problems.append(f"{what}: the file holds {want!r}, the run read {got!r}")


def allowed_offsets(rows, slot, also=()):
    """Battery offsets today's ROM may write in a Continue of `slot` and a
    save into it (and into each slot in `also`)."""
    scopes = {"shared", f"slot{slot}"} | {f"slot{x}" for x in also}
    ok = bytearray(sc.SRAM_SIZE)
    for r in rows:
        if r["scope"] in scopes and r["written"] & RUN_WRITES:
            for o in range(r["start"], r["end"] + 1):
                ok[o] = 1
    return ok


def check_run(fixture_bytes, roster_rows, esper, dumps, after, rows, also=(), split=None):
    """Problems (strings) for one run; empty = the save is compatible."""
    p = []
    f = fixture_bytes
    slot = f[0x1FF0]
    if slot not in SLOT_PTR:
        return [f"the fixture's battery names slot {slot} ($1FF0), not 1..3"]
    for tag, what, n in (("load1", "wram", BLOCK), ("load1", "codex", 0x400), ("load1", "live", 0x400),
                         ("save1", "slot", BLOCK),
                         ("load2", "wram", BLOCK), ("load2", "codex", 0x400), ("load2", "live", 0x400)):
        if len(dumps.get(tag, {}).get(what, b"")) != n:
            p.append(f"log: no complete {tag} {what} dump (the run stopped before it)")
    if p:
        return p
    d1, d2 = dumps["load1"], dumps["load2"]
    fblock = block_of(f, slot)

    # 1. the load: roster, gil, bag, story position
    compare(p, "load1 roster (tools/roster.py)", roster_rows, roster_of_block(d1["wram"]))
    compare(p, "load1", facts(fblock), facts(d1["wram"]))
    if d1["wram"] != fblock:
        n = sum(1 for a, b in zip(d1["wram"], fblock) if a != b)
        p.append(f"load1: the loaded $1600-$1FFF block differs from the slot in {n} byte(s)")

    # 2. the codex carries over: the page the load leaves is the file's as
    # today's ROM reads it, exactly (an O8 page's classes rewritten for the
    # six, nothing else moved), and the saves keep its magic and tables
    cpage = CODEX + (slot - 1) * 0x400
    if split is None:
        split = rom_split()
    cwant = codex_loaded(f, slot, split)
    if d1["codex"] != cwant:
        p.append(page_diff(f"load1: slot {slot}'s codex page is not the file's, migrated", cwant, d1["codex"]))
    if magic_and_tables(after[cpage:cpage + 0x400]) != magic_and_tables(cwant):
        p.append(page_diff(f"after the saves, slot {slot}'s codex magic and tables are not the file's, migrated",
                           magic_and_tables(cwant), magic_and_tables(after[cpage:cpage + 0x400])))

    # 3. esper progress: the slot's signed page, or none; its row 12 only from
    # a block of layout version 2 or more (an older page held reserve there)
    epage = ESPER + (slot - 1) * 0x400
    signed = w16(f, epage) == ESPER_MAGIC
    live = d1["live"][CTR:CTR_END]
    fver = block_version(fblock)
    leo_held = signed and fver >= LEOVER
    if any(d1["live"][LEO:CTR_END]) and not leo_held:
        p.append(f"esper: row 12 loaded {sum(d1['live'][LEO:CTR_END])} from a layout-version-{fver} block "
                 f"(the slot's page holds {sum(f[epage + LEO:epage + CTR_END])} there): it must read as no progress")
    if esper == "signed":
        if not signed:
            p.append(f"esper: this release signs its esper pages, but the fixture's slot {slot} page "
                     f"is unsigned (${w16(f, epage):04X}); the run read {sum(live)} in the live page")
        elif live[:LEO - CTR] != f[epage + CTR:epage + LEO]:
            p.append("esper: the live page after the load is not the slot's esper page")
        elif leo_held and d1["live"][LEO:CTR_END] != f[epage + LEO:epage + CTR_END]:
            p.append("esper: the live row 12 after the load is not the slot's (a version-2 block)")
    elif esper == "none":
        if signed:
            p.append(f"esper: a save from before esper progress has a signed page at ${epage:04X}")
        if any(live):
            p.append("esper: a save from before esper progress loaded with esper progress")
    else:
        p.append(f"esper: unknown expectation {esper!r}")

    # 4. outside what today's ROM writes, the battery is the file's
    ok = allowed_offsets(rows, slot, also)
    stray = [o for o in range(sc.SRAM_SIZE) if f[o] != after[o] and not ok[o]]
    if stray:
        spans = []
        for o in stray:
            if spans and o == spans[-1][1] + 1:
                spans[-1][1] = o
            else:
                spans.append([o, o])
        p.append("the battery changed outside the documented writes: " +
                 ", ".join("$%04X-$%04X" % tuple(s) for s in spans[:8]))

    # 5. the round trip: what the first save wrote, the second load, and the
    # second save (the battery the run left)
    s1 = dumps["save1"]["slot"]
    ablock = block_of(after, slot)
    for name, blk in (("the first save", s1), ("the second save", ablock)):
        if w16(blk, SIG - 0x1600) != SIGWORD or blk[SIG + 2 - 0x1600] != SIGVER:
            p.append(f"{name}: the block is not signed $5653 version {SIGVER}")
        if any(blk[0x1E2F - 0x1600:0x1E40 - 0x1600]) or any(blk[0x1FF7 - 0x1600:0x1FFE - 0x1600]):
            p.append(f"{name}: the reserve $1E2F-$1E3F or the tail $1FF7-$1FFD is not zero")
    for r in rows:
        for x in (slot,) + tuple(also):
            if r["scope"] == f"slot{x}" and "zero" in r["written"] and any(after[r["start"]:r["end"] + 1]):
                p.append(f"after the save, slot {x}'s reserve ${r['start']:04X}-${r['end']:04X} is not zero")
    for x in also:      # a save over slot x: its codex magic and tables are the source's
        src, dst = CODEX + (slot - 1) * 0x400, CODEX + (x - 1) * 0x400
        if after[dst:dst + 2] + after[dst + 0x10:dst + 0x310] != after[src:src + 2] + after[src + 0x10:src + 0x310]:
            p.append(f"after the save over slot {x}, its codex page is not slot {slot}'s")
    compare(p, "saved slot roster", roster_rows, roster_of_block(ablock))
    compare(p, "load2 roster", roster_rows, roster_of_block(d2["wram"]))
    # between the load and the save the field has run (a map's entry events
    # set switches, the random byte moves), so the save is held to the file
    # only in what standing still cannot change, and the reload to the save
    # byte for byte
    fa, f1 = facts(ablock), facts(fblock)
    compare(p, "saved slot", {k: f1[k] for k in STILL}, {k: fa[k] for k in STILL})
    compare(p, "first save", {k: f1[k] for k in STILL}, {k: facts(s1)[k] for k in STILL})
    compare(p, "load2", facts(s1), facts(d2["wram"]))
    if d2["wram"] != s1:
        n = sum(1 for a, b in zip(d2["wram"], s1) if a != b)
        p.append(f"load2: the reloaded block differs from the slot the first save wrote in {n} byte(s)")
    if w16(after, epage) != ESPER_MAGIC:
        p.append(f"after the save, slot {slot}'s esper page is unsigned")
    if after[epage + CTR:epage + CTR_END] != live:
        p.append("after the save, the slot's esper page is not the live page the load made")
    if d2["live"][CTR:CTR_END] != live:
        p.append("load2: the live esper page is not what was saved")
    # (magic and tables; the pad and tail are the reserve a save zeroes)
    if d2["codex"][:2] + d2["codex"][0x10:0x310] != d1["codex"][:2] + d1["codex"][0x10:0x310]:
        p.append("load2: the codex page changed across the round trip")
    return p


def load_manifest():
    return json.loads(MANIFEST.read_text())


def expectation(fixture: Path):
    m = json.loads((fixture / "manifest.json").read_text())
    g = m.get("golden")
    if not isinstance(g, dict) or g.get("esper") not in ("signed", "none"):
        raise GoldenError(f"{fixture}/manifest.json has no golden.esper expectation")
    return g


def doc_rows():
    with open(ROOT / csl.DOC, encoding="utf-8") as fh:
        rows, problems = csl.parse_battery(fh.read())
    if problems:
        raise GoldenError("battery map: " + "; ".join(problems))
    return rows


def check(fixture: Path, log: Path, battery: Path):
    g = expectation(fixture)
    _, payload = sc.load(fixture, LAYOUT)
    f = payload.read_bytes()
    after = battery.read_bytes()
    if len(after) != sc.SRAM_SIZE:
        return [f"{battery}: {len(after)} bytes, not a 32 KiB battery"]
    dumps = parse_log(log.read_text(errors="replace"))
    # a junk fixture's run also saves over slot 1 (save_golden.lua)
    also = (1,) if "/junk/" in str(fixture) else ()
    return check_run(f, roster_of_file(payload), g["esper"], dumps, after, doc_rows(), also)


def verify():
    m = load_manifest()
    if m.get("schema") != SCHEMA:
        raise GoldenError(f"{MANIFEST}: schema {m.get('schema')!r}")
    n, seen = 0, set()
    for s in m["sets"]:
        for fx in s["fixtures"]:
            d = GOLDEN / s["version"] / fx["key"]
            seen.add(d)
            _, payload = sc.load(d, LAYOUT)
            h = hashlib.sha256(payload.read_bytes()).hexdigest()
            if h != fx["sha256"]:
                raise GoldenError(f"{d}: battery sha256 {h} is not MANIFEST's {fx['sha256']}")
            if expectation(d)["esper"] != s["esper"]:
                raise GoldenError(f"{d}: esper expectation differs from its set's")
            n += 1
    for d in GOLDEN.glob("v*/*/manifest.json"):
        if d.parent not in seen:
            raise GoldenError(f"{d.parent} is not in MANIFEST.json")
    # the negative is its source with only the esper page's signature gone
    neg = GOLDEN / "negative" / "esper-unsigned-v0.44"
    _, npay = sc.load(neg, LAYOUT)
    a, b = (GOLDEN / "v0.44" / "wor-cyan-v1" / "battery.sram").read_bytes(), npay.read_bytes()
    diff = [o for o in range(sc.SRAM_SIZE) if a[o] != b[o]]
    if diff != [0x3800, 0x3801] or w16(b, 0x3800) != 0:
        raise GoldenError(f"{neg}: must be v0.44/wor-cyan-v1 with $3800-$3801 zeroed, differs at {diff[:6]}")
    # the six-class migration's fixture is its source with the class table $FF
    _, cpay = sc.load(GOLDEN / CLASSFF[0], LAYOUT)
    if cpay.read_bytes() != classff_bytes()[0]:
        raise GoldenError(f"{GOLDEN / CLASSFF[0]}: must be {CLASSFF[1]} with slot 3's class table all $FF "
                          f"(python3 tools/golden_saves.py synthetic)")
    _, spay = sc.load(GOLDEN / SIX3F[0], LAYOUT)
    if spay.read_bytes() != six3f_bytes()[0]:
        raise GoldenError(f"{GOLDEN / SIX3F[0]}: must be {SIX3F[1]} with slot 3's codex page signed O9 and its "
                          f"class table all $3F (python3 tools/golden_saves.py synthetic)")
    _, upay = sc.load(GOLDEN / UNSIGNED[0], LAYOUT)
    if upay.read_bytes() != unsigned_bytes()[0]:
        raise GoldenError(f"{GOLDEN / UNSIGNED[0]}: must be {UNSIGNED[1]} with slot 3's codex magic zeroed "
                          f"(python3 tools/golden_saves.py synthetic)")
    print(f"golden saves: {n} fixtures from {len(m['sets'])} releases match MANIFEST.json; "
          f"the negative is v0.44/wor-cyan-v1 with slot 3's esper signature zeroed; "
          f"{CLASSFF[0]} is {CLASSFF[1]} with slot 3's class table $FF; "
          f"{UNSIGNED[0]} is {UNSIGNED[1]} with slot 3's codex magic zeroed; "
          f"{SIX3F[0]} is {SIX3F[1]} with slot 3's page O9 and its class table $3F")
    return 0


# The six-class migration's synthetic fixture (#566): a real four-class
# save whose class table holds everything a byte can.  Every species then
# has a revealed bit its six-class row does not answer to (a species has at
# most four children and few rows hold them all), and four bits the
# migration must drop.
CLASSFF = ("junk/v0.46-kolts-classff", "v0.46/kolts-summit-v1")


def classff_bytes():
    src = bytearray((GOLDEN / CLASSFF[1] / "battery.sram").read_bytes())
    slot = src[0x1FF0]
    base = CODEX + (slot - 1) * 0x400
    if w16(src, base) != CODEX_FOUR:
        raise GoldenError(f"{CLASSFF[1]}: slot {slot}'s codex page is not a four-class (O8) page")
    src[base + CLASSES:base + TABLES_END] = b"\xff" * SPECIES
    return bytes(src), slot


# A codex page with no magic (a battery whose bank $31 another program or a
# vanilla cartridge left): "the page is zeroed and signed before use".  The
# tables keep the release's bytes, so a load that signed the page without
# zeroing it would show them.
UNSIGNED = ("junk/v0.50-kolts-unsigned", "v0.50/kolts-summit-v1")


def unsigned_bytes():
    src = bytearray((GOLDEN / UNSIGNED[1] / "battery.sram").read_bytes())
    slot = src[0x1FF0]
    base = CODEX + (slot - 1) * 0x400
    if w16(src, base) != CODEX_FOUR or not any(src[base + ELEMS:base + TABLES_END]):
        raise GoldenError(f"{UNSIGNED[1]}: slot {slot}'s codex page is not a four-class page with reveals")
    src[base:base + 2] = b"\x00\x00"
    return bytes(src), slot


# A six-class page holding more than its species answer to (what a v0.51
# save becomes when a later release takes a class from a row): every class
# revealed for every species.  A load leaves an O9 page alone, and the seed
# draws a body only the revealed classes its row holds.
SIX3F = ("junk/v0.46-kolts-six3f", "v0.46/kolts-summit-v1")


def six3f_bytes():
    src = bytearray((GOLDEN / SIX3F[1] / "battery.sram").read_bytes())
    slot = src[0x1FF0]
    base = CODEX + (slot - 1) * 0x400
    if w16(src, base) != CODEX_FOUR:
        raise GoldenError(f"{SIX3F[1]}: slot {slot}'s codex page is not a four-class (O8) page")
    src[base:base + 2] = CODEX_SIX.to_bytes(2, "little")
    src[base + CLASSES:base + TABLES_END] = bytes([SIX_CLASSES]) * SPECIES
    return bytes(src), slot


def synthetic():
    data, slot = six3f_bytes()
    base = CODEX + (slot - 1) * 0x400
    prov = (f"a synthetic fixture for a six-class codex page (#566), not a release save: "
            f"golden-saves/{SIX3F[1]} with slot {slot}'s codex magic (${base:04X}-${base + 1:04X}) set to "
            f"$394F ('O9') and every byte of its revealed-class table "
            f"(${base + CLASSES:04X}-${base + TABLES_END - 1:04X}) set to $3F: all six classes revealed for "
            f"every species; nothing else differs (tools/golden_saves.py synthetic rebuilds it)")
    write_fixture(GOLDEN / SIX3F[0], data, prov, expectation(GOLDEN / SIX3F[1])["esper"])
    print(f"golden saves: wrote {SIX3F[0]} from {SIX3F[1]}")
    data, slot = classff_bytes()
    base = CODEX + (slot - 1) * 0x400
    prov = (f"a synthetic fixture for the six-class codex migration (#566), not a release save: "
            f"golden-saves/{CLASSFF[1]} with every byte of slot {slot}'s revealed-class table "
            f"(${base + CLASSES:04X}-${base + TABLES_END - 1:04X}) "
            f"set to $FF: all four classes revealed for every species, and the four bits no four-class "
            f"build wrote; nothing else differs (tools/golden_saves.py synthetic rebuilds it)")
    write_fixture(GOLDEN / CLASSFF[0], data, prov, expectation(GOLDEN / CLASSFF[1])["esper"])
    print(f"golden saves: wrote {CLASSFF[0]} from {CLASSFF[1]}")
    data, slot = unsigned_bytes()
    base = CODEX + (slot - 1) * 0x400
    prov = (f"a synthetic fixture for a codex page with no magic (#566), not a release save: "
            f"golden-saves/{UNSIGNED[1]} with slot {slot}'s codex magic (${base:04X}-${base + 1:04X}) zeroed "
            f"and its two tables left as the release wrote them; nothing else differs "
            f"(tools/golden_saves.py synthetic rebuilds it)")
    write_fixture(GOLDEN / UNSIGNED[0], data, prov, expectation(GOLDEN / UNSIGNED[1])["esper"])
    print(f"golden saves: wrote {UNSIGNED[0]} from {UNSIGNED[1]}")
    return 0


def fixture_dirs():
    m = load_manifest()
    return [GOLDEN / s["version"] / fx["key"] for s in m["sets"] for fx in s["fixtures"]]


def write_fixture(d: Path, data: bytes, provenance: str, esper: str):
    d.mkdir(parents=True, exist_ok=True)
    (d / "battery.sram").write_bytes(data)
    m = {"schema": sc.SCHEMA, "payload": "battery.sram", "slot": data[0x1FF0],
         "persistent_layout": LAYOUT, "size": len(data),
         "sha256": hashlib.sha256(data).hexdigest(), "provenance": provenance,
         "golden": {"esper": esper}}
    (d / "manifest.json").write_text(json.dumps(m, indent=2) + "\n")
    sc.load(d, LAYOUT)


def add(version, zpath, keys, esper):
    import release_saves as rs
    zdata = Path(zpath).read_bytes()
    zsha = hashlib.sha256(zdata).hexdigest()
    m = load_manifest() if MANIFEST.exists() else {"schema": SCHEMA, "sets": []}
    sets = [s for s in m["sets"] if s["version"] != version]
    entry = {"version": version, "zip": Path(zpath).name, "zip_sha256": zsha,
             "esper": esper, "fixtures": []}
    with zipfile.ZipFile(zpath) as z:
        names = {Path(n).name: n for n in z.namelist() if n.startswith("saves/") and n.endswith(".srm")}
        for key in keys:
            title = rs.TITLES.get(key)
            hit = [n for n in names if title and n.split(" - ", 1)[-1] == title + ".srm"]
            if len(hit) != 1:
                raise GoldenError(f"{zpath}: no single saves/NN - {title}.srm for {key}")
            data = z.read(names[hit[0]])
            prov = (f"{version} release zip {Path(zpath).name} (sha256 {zsha}), saves/{hit[0]}, "
                    f"as published; a release artifact, not a capture")
            write_fixture(GOLDEN / version / key, data, prov, esper)
            entry["fixtures"].append({"key": key, "file": hit[0],
                                      "sha256": hashlib.sha256(data).hexdigest()})
    sets.append(entry)
    sets.sort(key=lambda s: [int(x) for x in s["version"][1:].split(".")])
    m["sets"] = sets
    MANIFEST.write_text(json.dumps(m, indent=2) + "\n")
    print(f"golden saves: {version}: {len(keys)} fixture(s) from {Path(zpath).name}")
    return 0


NOTES_LINE = re.compile(r"^Saves from (v\d+\.\d+) and later load in this release\b", re.M)


def notes_problems(text, oldest):
    p = []
    if re.search(r"save layout", text, re.I):
        p.append('the notes name a "save layout"; say which saves load instead')
    m = NOTES_LINE.search(text)
    if not m:
        p.append(f'no line "Saves from {oldest} and later load in this release"')
    elif m.group(1) != oldest:
        p.append(f"the notes say saves from {m.group(1)} load; the oldest golden saves are {oldest}'s")
    return p


def firstsave_problems(b, rows):
    p = []
    slot = b[0x1FF0]
    if slot not in SLOT_PTR:
        return [f"the battery names slot {slot} ($1FF0), not 1..3"]
    blk = block_of(b, slot)
    if w16(blk, SIG - 0x1600) != SIGWORD or blk[SIG + 2 - 0x1600] != SIGVER:
        p.append(f"slot {slot} is not signed $5653 version {SIGVER} "
                 f"(${w16(blk, SIG - 0x1600):04X}, version {blk[SIG + 2 - 0x1600]})")
    if any(blk[0x1E2F - 0x1600:0x1E40 - 0x1600]) or any(blk[0x1FF7 - 0x1600:0x1FFE - 0x1600]):
        p.append(f"slot {slot}'s reserve $1E2F-$1E3F or tail $1FF7-$1FFD is not zero")
    if any(blk[0x1E1D - 0x1600:0x1E2C - 0x1600]):
        p.append(f"slot {slot}'s loadouts $1E1D-$1E2B are not AUTO (zero)")
    for r in rows:
        if r["scope"] == f"slot{slot}" and "zero" in r["written"] and any(b[r["start"]:r["end"] + 1]):
            p.append(f"slot {slot}'s page reserve ${r['start']:04X}-${r['end']:04X} is not zero")
    return p


def oldest_golden():
    return load_manifest()["sets"][0]["version"]


# ----------------------------------------------------------------- selftest --
# a split table for the selftest: every weakness its own bit (Sword,
# Dagger, Blunt, Ranged), but species 5's slash became Katana, species 6
# had no slash and its bludgeon and special both became Ranged, and species
# 8's slash became every class
SELF_SPLIT = [(0x01, 0x02, 0x04, 0x08)] * SPECIES
SELF_SPLIT[5], SELF_SPLIT[6], SELF_SPLIT[8] = (0x10, 0x02, 0x04, 0x08), (0x00, 0x02, 0x08, 0x08), (0x3F, 0, 0, 0)


def _synthetic():
    """A battery with slot 3 populated, signed pages, and a matching run."""
    f = bytearray(sc.SRAM_SIZE)
    f[0x1FF0] = 3
    b = SLOT_PTR[3]
    for c in range(14):             # an actor table roster.py can find
        f[b + 37 * c] = c
        f[b + 37 * c + 8] = 10 + c  # level
        f[b + 37 * c + 0x1E] = 0xFF
        for o in range(0x1F, 0x25):
            f[b + 37 * c + o] = 0xFF
    f[b + 0x1EDE - 0x1600] = 0x0F   # recruited: four characters
    f[b + 0x1860 - 0x1600] = 0x34
    f[b + 0x1F64 - 0x1600] = 0x20
    cp = CODEX + 0x800
    f[cp], f[cp + 1] = 0x4F, 0x38   # O8: a four-class page
    f[cp + 0x20] = 5
    # revealed classes: slash and pierce where slash became Katana and
    # pierce stayed Dagger; bludgeon and special where both became Ranged
    # and a revealed slash the species never answered to; slash under four
    # bits no four-class build wrote (Sword); every bit, where any weapon
    # breaks the species
    f[cp + CLASSES + 5], f[cp + CLASSES + 6], f[cp + CLASSES + 7], f[cp + CLASSES + 8] = 0x03, 0x0D, 0xF1, 0x01
    page = codex_loaded(f, 3, SELF_SPLIT)
    assert (page[0:2], bytes(page[CLASSES + 5:CLASSES + 9]), page[0x20]) == \
        (b"\x4f\x39", bytes([0x12, 0x08, 0x01, 0x3F]), 5), page[CLASSES:CLASSES + 9].hex()
    ep = ESPER + 0x800
    f[ep], f[ep + 1] = 0x45, 0x31
    f[ep + 0x12] = 7
    f[LIVE], f[LIVE + 1] = 0x45, 0x31
    f[LIVE + 0x12] = 7
    after = bytearray(f)
    after[cp:cp + 0x400] = page     # the load migrated the page in place
    after[0x1FF1] = 9               # title seed (shared, title)
    after[b + 0x1863 - 0x1600] = 1  # play time moved (slot3, save)
    after[b + SIG - 0x1600] = 0x53  # signed $5653, version 1
    after[b + SIG + 1 - 0x1600] = 0x56
    after[b + SIG + 2 - 0x1600] = SIGVER
    def dumps(blk_after):
        return {"load1": {"wram": bytes(block_of(f, 3)), "codex": page,
                          "live": bytes(f[LIVE:LIVE + 0x400])},
                "save1": {"slot": bytes(blk_after)},
                "load2": {"wram": bytes(blk_after), "codex": page,
                          "live": bytes(f[LIVE:LIVE + 0x400])}}
    return f, after, dumps


def selftest():
    rows = doc_rows()
    check_run = functools.partial(globals()["check_run"], split=SELF_SPLIT)
    f, after, dumps = _synthetic()
    rr = roster_of_block(block_of(f, 3))
    assert len(rr) == 4, rr
    ok = check_run(bytes(f), rr, "signed", dumps(block_of(after, 3)), bytes(after), rows)
    assert ok == [], ok

    def bad(mut_after=None, mut_dumps=None, esper="signed", fx=None, want=""):
        a = bytearray(after)
        if mut_after:
            mut_after(a)
        d = dumps(block_of(a, 3))
        if mut_dumps:
            mut_dumps(d)
        probs = check_run(bytes(fx or f), rr, esper, d, bytes(a), rows)
        assert any(want in x for x in probs), (want, probs)

    # a write into slot 1, slot 1's codex tail, the reserve past $4000, $1E00,
    # the live page's reserve
    for o in (0x0005, CODEX + 0x310, 0x4000, 0x1E00, LIVE + 0x380):
        bad(mut_after=lambda a, o=o: a.__setitem__(o, 0xAA), want="outside the documented writes")
    # the saved slot's own page reserves left non-zero
    for o in (CODEX + 0x800 + 0x310, CODEX + 0x800 + 0x5, ESPER + 0x800 + 0x2B4, ESPER + 0x800 + 0x3FF):
        bad(mut_after=lambda a, o=o: a.__setitem__(o, 0xAA), want="reserve $")
    # the save did not sign the block
    bad(mut_after=lambda a: a.__setitem__(SLOT_PTR[3] + SIG - 0x1600, 0), want="not signed $5653")
    # the block's reserve or tail left non-zero by the save
    for a0 in (0x1E2F, 0x1E3F, 0x1FF7, 0x1FFD):
        bad(mut_after=lambda a, a0=a0: a.__setitem__(SLOT_PTR[3] + a0 - 0x1600, 0xFF), want="the tail $1FF7-$1FFD is not zero")
    # the reload is not what the first save wrote
    def rl(d):
        w = bytearray(d["load2"]["wram"]); w[0x10] ^= 1; d["load2"]["wram"] = bytes(w)
    bad(mut_dumps=rl, want="load2: the reloaded block differs")
    # a level misread at the load
    def lvl(d):
        w = bytearray(d["load1"]["wram"]); w[8] = 99; d["load1"]["wram"] = bytes(w)
    bad(mut_dumps=lvl, want="load1 roster")
    # gil misread
    def gil(d):
        w = bytearray(d["load1"]["wram"]); w[0x1860 - 0x1600] = 1; d["load1"]["wram"] = bytes(w)
    bad(mut_dumps=gil, want="gil")
    # the codex not carried over
    def cod(d):
        w = bytearray(d["load1"]["codex"]); w[0x20] = 0; d["load1"]["codex"] = bytes(w)
    bad(mut_dumps=cod, want="codex page is not the file's, migrated (1 byte(s) differ; the first: species 16's elements")
    # the six-class migration (#566), each way it can be wrong
    cp = CODEX + 0x800
    def page_as(fn):
        def mut(d):
            w = bytearray(d["load1"]["codex"]); fn(w); d["load1"]["codex"] = bytes(w)
        return mut
    # ... not run at all: the file's own page
    bad(mut_dumps=lambda d: d["load1"].__setitem__("codex", bytes(f[cp:cp + 0x400])),
        want="not the file's, migrated (5 byte(s) differ; the first: its magic is $384F, not $394F")
    # ... the tables rewritten but the page still signed O8
    bad(mut_dumps=page_as(lambda w: w.__setitem__(1, 0x38)), want="its magic is $384F, not $394F")
    # ... a weakness that moved left where its four-class bit was (slash read as Sword)
    bad(mut_dumps=page_as(lambda w: w.__setitem__(CLASSES + 5, 0x03)), want="species 5's classes read $03, not $12")
    # ... a revealed bit the species never answered to kept (slash as Sword)
    bad(mut_dumps=page_as(lambda w: w.__setitem__(CLASSES + 6, 0x09)), want="species 6's classes read $09, not $08")
    # ... a bit past the four kept
    bad(mut_dumps=page_as(lambda w: w.__setitem__(CLASSES + 7, 0xF1)), want="species 7's classes read $F1, not $01")
    # ... a weakness that kept its bit dropped
    bad(mut_dumps=page_as(lambda w: w.__setitem__(CLASSES + 5, 0x10)), want="species 5's classes read $10, not $12")
    # ... the species any weapon breaks given one class
    bad(mut_dumps=page_as(lambda w: w.__setitem__(CLASSES + 8, 0x01)), want="species 8's classes read $01, not $3F")
    # ... run a second time by a later touch (the Katana bit read as four-class and dropped)
    bad(mut_after=lambda a: a.__setitem__(cp + CLASSES + 5, 0x02),
        want="after the saves, slot 3's codex magic and tables are not the file's, migrated (1 byte(s) differ; "
             "the first: species 5's classes read $02, not $12")
    # ... the load touching the page's reserve
    bad(mut_dumps=page_as(lambda w: w.__setitem__(0x320, 1)), want="its reserve byte +$320 reads $01, not $00")
    # an O9 page is left as it is, an unsigned one reads empty, an O7 codex is cloned
    g9 = bytearray(f); g9[cp + 1] = 0x39
    assert codex_loaded(g9, 3, SELF_SPLIT) == bytes(g9[cp:cp + 0x400])
    gu = bytearray(f); gu[cp] = 0
    assert codex_loaded(gu, 3, SELF_SPLIT) == b"\x4f\x39" + bytes(0x3FE)
    g7 = bytearray(f); g7[CODEX:CODEX + 0x400] = f[cp:cp + 0x400]; g7[CODEX + 1] = 0x37
    g7[cp:cp + 0x400] = bytes(0x400)
    assert codex_loaded(g7, 3, SELF_SPLIT) == codex_loaded(f, 3, SELF_SPLIT)
    assert [six_class(1 << k, (0x10, 0x20, 0x08, 0x04)) for k in range(4)] == [0x10, 0x20, 0x08, 0x04]
    assert six_class(0xFF, (0x10, 0x00, 0x08, 0x08)) == 0x18 and six_class(0xF0, (1, 2, 4, 8)) == 0
    # esper ranks lost on the load
    def esp(d):
        w = bytearray(d["load1"]["live"]); w[0x12] = 0; d["load1"]["live"] = bytes(w)
    bad(mut_dumps=esp, want="live page after the load is not the slot's")
    # an unsigned page where the release signs them (the negative fixture's case)
    g = bytearray(f); g[ESPER + 0x800] = 0
    bad(fx=g, want="but the fixture's slot 3 page is unsigned")
    # a pre-v0.44 save that loads with progress
    h = bytearray(f); h[ESPER + 0x800] = 0
    bad(fx=h, esper="none", want="loaded with esper progress")
    # row 12 (#552): a version-1 (or unsigned) block's page tail loaded as progress
    def leo(d):
        w = bytearray(d["load1"]["live"]); w[LEO + 4] = 9; d["load1"]["live"] = bytes(w)
    bad(mut_dumps=leo, want="row 12 loaded")
    # junk in an unsigned block's page row 12 is no progress: the run that reads zeros passes
    j = bytearray(f); j[ESPER + 0x800 + LEO + 4] = 0xFF
    assert check_run(bytes(j), rr, "signed", dumps(block_of(after, 3)), bytes(after), rows) == [], \
        check_run(bytes(j), rr, "signed", dumps(block_of(after, 3)), bytes(after), rows)
    # a version-2 block's row 12 is the slot's: carried, and refused when lost
    cp = CODEX + 0x800
    v2 = bytearray(f)
    v2[SLOT_PTR[3] + SIG - 0x1600:SLOT_PTR[3] + SIG + 3 - 0x1600] = bytes([0x53, 0x56, 2])
    v2[ESPER + 0x800 + LEO + 6] = 3
    v2[LIVE + LEO + 6] = 3
    a2 = bytearray(after)
    a2[ESPER + 0x800 + LEO + 6] = 3
    a2[LIVE + LEO + 6] = 3

    def dv2(blk, live=None):
        lv = bytes(live if live is not None else v2[LIVE:LIVE + 0x400])
        return {"load1": {"wram": bytes(block_of(v2, 3)), "codex": codex_loaded(v2, 3, SELF_SPLIT), "live": lv},
                "save1": {"slot": bytes(blk)},
                "load2": {"wram": bytes(blk), "codex": codex_loaded(v2, 3, SELF_SPLIT),
                          "live": bytes(v2[LIVE:LIVE + 0x400])}}
    rr2 = roster_of_block(block_of(v2, 3))
    ok2 = check_run(bytes(v2), rr2, "signed", dv2(block_of(a2, 3)), bytes(a2), rows)
    assert ok2 == [], ok2
    lost = bytearray(v2[LIVE:LIVE + 0x400]); lost[LEO + 6] = 0
    probs = check_run(bytes(v2), rr2, "signed", dv2(block_of(a2, 3), lost), bytes(a2), rows)
    assert any("live row 12 after the load" in x for x in probs), probs
    m = bytearray(a2); m[ESPER + 0x800 + LEO + 6] = 0
    probs = check_run(bytes(v2), rr2, "signed", dv2(block_of(m, 3)), bytes(m), rows)
    assert any("esper page is not the live page" in x for x in probs), probs
    # the save left the esper page unsigned
    bad(mut_after=lambda a: a.__setitem__(ESPER + 0x800, 0), want="esper page is unsigned")
    # a truncated log
    def trunc(d):
        del d["load2"]
    bad(mut_dumps=trunc, want="no complete load2")
    # the log parser round-trips and refuses a gap
    text = "\n".join("[golden] dump load1 wram %04X %s" % (0x1600 + i, "00" * 64) for i in range(0, 0xA00, 64))
    assert len(parse_log(text)["load1"]["wram"]) == BLOCK
    try:
        parse_log(text.replace("[golden] dump load1 wram 1640", "x"))
        raise AssertionError("gap accepted")
    except GoldenError:
        pass
    # a New Game's first save
    fsb = bytearray(after)
    assert firstsave_problems(bytes(fsb), rows) == [], firstsave_problems(bytes(fsb), rows)
    for o, want in ((SLOT_PTR[3] + SIG - 0x1600, "not signed"), (SLOT_PTR[3] + 0x1E30 - 0x1600, "reserve"),
                    (SLOT_PTR[3] + 0x1E20 - 0x1600, "not AUTO"), (CODEX + 0x800 + 0x320, "page reserve")):
        m = bytearray(fsb); m[o] ^= 0x5A
        assert any(want in x for x in firstsave_problems(bytes(m), rows)), (want, firstsave_problems(bytes(m), rows))
    # a save over slot 1: its reserves and its codex
    a1 = bytearray(after)
    a1[CODEX:CODEX + 0x400] = after[CODEX + 0x800:CODEX + 0xC00]
    a1[ESPER:ESPER + 0x400] = after[ESPER + 0x800:ESPER + 0xC00]
    d1 = dumps(block_of(a1, 3))
    assert check_run(bytes(f), rr, "signed", d1, bytes(a1), rows, (1,)) == [], \
        check_run(bytes(f), rr, "signed", d1, bytes(a1), rows, (1,))
    m = bytearray(a1); m[CODEX + 0x312] = 0xFF
    assert any("slot 1's reserve" in x for x in check_run(bytes(f), rr, "signed", d1, bytes(m), rows, (1,)))
    m = bytearray(a1); m[CODEX + 0x20] ^= 1
    assert any("not slot 3's" in x for x in check_run(bytes(f), rr, "signed", d1, bytes(m), rows, (1,)))
    good = "## Saves\n\nSaves from v0.28 and later load in this release. A save from before v0.44...\n"
    assert notes_problems(good, "v0.28") == [], notes_problems(good, "v0.28")
    assert any("save layout" in x for x in notes_problems(good + "This release uses the v0.29 save layout.\n", "v0.28"))
    assert any("no line" in x for x in notes_problems("## Saves\n\nOlder saves load.\n", "v0.28"))
    assert any("oldest golden" in x for x in notes_problems(good.replace("v0.28", "v0.40"), "v0.28"))
    print("golden_saves selftest OK")
    return 0


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    try:
        if argv[:1] == ["verify"]:
            return verify()
        if argv[:1] == ["notes"] and len(argv) == 2:
            probs = notes_problems(Path(argv[1]).read_text(), oldest_golden())
            for x in probs:
                print(f"golden notes: FAIL {argv[1]}: {x}")
            if probs:
                return 1
            print(f"golden notes: {argv[1]} says saves from {oldest_golden()} and later load")
            return 0
        if argv[:1] == ["firstsave"] and len(argv) == 2:
            srams = sorted(Path(argv[1]).glob("*.sram"))
            if len(srams) != 1:
                print(f"golden firstsave: FAIL {argv[1]} holds {len(srams)} batteries, not one")
                return 1
            probs = firstsave_problems(srams[0].read_bytes(), doc_rows())
            for x in probs:
                print(f"golden firstsave: FAIL {srams[0]}: {x}")
            if probs:
                return 1
            print(f"golden firstsave: {srams[0]}: the New Game's first save is signed $5653 version {SIGVER}, its "
                  f"reserves zero and its loadouts AUTO")
            return 0
        if argv[:1] == ["synthetic"]:
            return synthetic()
        if argv[:1] == ["list"]:
            for d in fixture_dirs():
                print(d.relative_to(ROOT))
            return 0
        if (argv[:1] == ["check"] and len(argv) == 4) or (argv[:1] == ["negative"] and len(argv) in (4, 5)):
            fx, log, bat = Path(argv[1]), Path(argv[2]), Path(argv[3])
            probs = check(fx, log, bat)
            if argv[0] == "negative":
                want = argv[4] if len(argv) == 5 else "esper"
                hit = [x for x in probs if want in x]
                if hit:
                    print(f"golden negative: refused as it must be: {hit[0]}")
                    return 0
                print(f"golden negative: FAIL -- {fx} was not refused for {want!r}: {probs}")
                return 1
            for x in probs:
                print(f"golden: FAIL {fx.relative_to(ROOT) if fx.is_absolute() else fx}: {x}")
            if probs:
                return 1
            print(f"golden: PASS {fx}: loads, matches the file, carries its codex (migrated) and esper pages, "
                  f"writes only the documented ranges, and round-trips")
            return 0
        if argv[:1] == ["add"] and len(argv) >= 4:
            esper = "signed"
            keys = argv[3:]
            if "--no-esper" in keys:
                keys = [k for k in keys if k != "--no-esper"]
                esper = "none"
            return add(argv[1], argv[2], keys, esper)
    except (GoldenError, sc.CheckpointError) as e:
        print(f"golden: FAIL {e}")
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
