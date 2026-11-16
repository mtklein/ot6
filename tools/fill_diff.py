#!/usr/bin/env python3
"""fill_diff.py -- compare a fill run of the line with the zero-fill line.

    tools/fill_diff.py REF FILL [--states a,b] [--max-ranges N] [--json OUT]
    tools/fill_diff.py --logs REF.log FILL.log...   # runs' logs only
    tools/fill_diff.py --selftest

REF and FILL are tree roots: REF a tree whose build/ holds the line as the
harness plays it (all RAM zero at power-on), FILL a fill tree
(tools/fill_line.py) that replayed the same commit under OT6_POWERON_FILL.
The line is deterministic, so every observable result must match; a
difference means some code read memory before writing it.

For every state of the graph (tools/tests/savestate_graph.py, in play
order) that both trees hold, and every checkpoint capture both hold, it
reports:

  play     the first [ot6] line of the run's log that differs (blob sizes,
           shas and snapshot sizes masked), with its frame: where the play
           itself parted;
  block    WRAM $1600-$1FFF, the save block (party, gear, bag, story
           switches): differing byte ranges;
  wram     the rest of WRAM: differing ranges, each split into bytes that
           hold the fill pattern in FILL and zero in REF (never written in
           either run: expected, and counted only) and the rest, which are
           listed: a value computed from an unwritten byte;
  sram     the battery inside the state, and each capture's battery, outside
           the ranges docs/design/save-layout.md's battery map marks
           Written `never`, and outside the pages of a slot the reference
           battery leaves empty (the map's "Absent or unsigned" rule: an
           unsaved slot's codex and esper pages are read only once signed).

The fill pattern is lib/poweron_fill.lua's, recomputed here from the mode in
FILL's build/FILL_TREE.  Exit status 0 when nothing but never-written bytes
differs, 1 otherwise.
"""
import argparse
import importlib.util
import json
import re
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "docs/design/save-layout.md"
REGION_ID = {"wram": 1, "sram": 2, "vram": 3, "oam": 4, "cgram": 5, "spc": 6, "dsp": 7}
FIELDS = {"wram": "memoryManager.workRam", "sram": "cart.saveRam"}
BLOCK = (0x1600, 0x2000)


# --------------------------------------------------------------- fill pattern
def parse_mode(text):
    """build/FILL_TREE's mode -> (kind, seed, regions)."""
    m = re.fullmatch(r"(?:(ones|alt)|rand:(\d{1,9}))(?:@([a-z0-9,:~+-]+))?", text.strip(), re.I)
    if not m:
        return None
    kind, seed = (m.group(1).lower(), 0) if m.group(1) else ("rand", int(m.group(2)))
    # a region's :<ranges> or ~<ranges> (a lab bisection) still fills with the
    # same pattern: a byte that holds it is fill-shaped either way
    return kind, seed, {re.split(r"[:~]", t)[0] for t in (m.group(3) or "wram,sram").split(",")}


def fill_value(kind, seed, region, off):
    if kind == "ones":
        return 0xFF
    if kind == "alt":
        return 0x55 if off % 2 == 0 else 0xAA
    M = 0xFFFFFFFF
    h = (off * 0x9E3779B1 + seed * 0x85EBCA77 + REGION_ID[region] * 0xC2B2AE3D) & M
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & M
    h ^= h >> 12
    h = (h * 0x297A2D39) & M
    h ^= h >> 15
    return h & 0xFF


# ------------------------------------------------------------------ savestate
def machine_stream(data):
    """The largest zlib stream in a .mss (the machine; the other is the
    screen)."""
    best, i = None, 0
    while True:
        i = data.find(b"\x78\x01", i)
        if i < 0:
            return best
        try:
            out = zlib.decompressobj().decompress(data[i:])
            if best is None or len(out) > len(best):
                best = out
        except zlib.error:
            pass
        i += 2


def state_fields(raw, names):
    """name -> bytes for each name in `names`: Mesen's serializer writes a
    field as its name, a NUL, a 32-bit little-endian size and the bytes."""
    out = {}
    for name in names:
        key = name.encode() + b"\0"
        i = raw.find(key)
        if i < 0:
            continue
        j = i + len(key)
        n = int.from_bytes(raw[j:j + 4], "little")
        out[name] = raw[j + 4:j + 4 + n]
    return out


# ------------------------------------------------------------------ the doc
def layout_rows(text):
    """The battery map's rows: (start, end, scope, holds, written)."""
    rows = []
    for line in text.splitlines():
        m = re.match(r"\|\s*\$([0-9A-F]{4})(?:-\$([0-9A-F]{4}))?\s*\|\s*(\d+)\s*\|"
                     r"\s*([a-z0-9]+)\s*\|([^|]*)\|[^|]*\|\s*([^|]*?)\s*\|", line)
        if m:
            a = int(m.group(1), 16)
            b = int(m.group(2), 16) if m.group(2) else a
            rows.append((a, b, m.group(4), m.group(5).strip(), m.group(6)))
    return rows


def excluded_ranges(rows, ref_battery):
    """The battery ranges a fill may leave holding its pattern: the map's
    `never` rows, and in banks $31-$33 the pages of every slot whose save
    block the reference battery leaves empty (never saved, so never
    signed)."""
    out = [(a, b, f"never: {h[:40]}") for a, b, s, h, w in rows if w.strip() == "never"]
    for n in (1, 2, 3):
        blk = [(a, b) for a, b, s, h, w in rows if s == f"slot{n}" and b < 0x2000]
        empty = ref_battery is not None and all(
            not any(ref_battery[a:b + 1]) for a, b in blk)
        if empty:
            out += [(a, b, f"slot {n} never saved")
                    for a, b, s, h, w in rows if s == f"slot{n}" and a >= 0x2000]
    return sorted(out)


# --------------------------------------------------------------- comparison
def ranges(addrs, gap=0):
    out = []
    for a in addrs:
        if out and a <= out[-1][1] + 1 + gap:
            out[-1][1] = a
        else:
            out.append([a, a])
    return out


SLOT_BASES = (0x0000, 0x0A00, 0x1400)   # battery offsets of slots 1-3
SLOT_SIZE = 0x0A00                    # WRAM $1600-$1FFF
CHECKSUM = 0x09FE                     # the slot's checksum word, +$9FE


def source_of(region, off):
    """Where a byte's power-on value came from: a battery byte inside a
    save slot is the save block's WRAM byte the save copied there."""
    if region == "sram":
        for base in SLOT_BASES:
            if base <= off < base + SLOT_SIZE:
                return "wram", 0x1600 + off - base
    return region, off


def classify(ref, fil, region, mode, lo=0, hi=None, skip=()):
    """Split the bytes where `fil` differs from `ref` into
    unwritten: zero in REF and the fill pattern in FILL (for a battery slot,
               the pattern of the save-block byte the save copied): no code
               wrote it in either run;
    checksum:  a slot's checksum word, which follows the bytes it sums;
    computed:  anything else: a value some code derived from a byte it read
               unwritten (or a play that went another way)."""
    hi = len(ref) if hi is None else hi
    kind, seed, regions = mode
    out = {"unwritten": [], "checksum": [], "computed": []}
    for a in range(lo, hi):
        if ref[a] == fil[a] or any(s <= a <= e for s, e, _ in skip):
            continue
        src, off = source_of(region, a)
        if src in regions and ref[a] == 0 and fil[a] == fill_value(kind, seed, src, off):
            out["unwritten"].append(a)
        elif region == "sram" and any(a - b in (CHECKSUM, CHECKSUM + 1) for b in SLOT_BASES):
            out["checksum"].append(a)
        elif region == "wram" and a in (0x1FFE, 0x1FFF):
            out["checksum"].append(a)
        else:
            out["computed"].append(a)
    return {k: ranges(v) for k, v in out.items()}


def compare_ram(ref, fil, region, mode, base=0, lo=0, hi=None, skip=()):
    """(unwritten byte count, computed ranges): classify(), summed."""
    c = classify(ref, fil, region, mode, lo, hi, skip)
    return sum(b - a + 1 for a, b in c["unwritten"]), c["computed"]


# The harness's own readings of memory the game has not set up yet (the
# map and object tiles it lists at a boot, before the game has loaded a map)
# differ under a fill without the game reading anything: they are counted
# as observations, not as the play.
OBSERVATIONS = ("[ot6] [tiles] ",)
# a snapshot's size is its compressed bytes, which the unwritten RAM it
# carries moves without the play moving
NORM = [(re.compile(r"\b\d+ bytes\b"), "N bytes"),
        (re.compile(r"sha=[0-9a-f]+"), "sha=X"),
        (re.compile(r"\b\d+(\.\d+)?s wall\b"), "Ns wall")]


def ot6_lines(path):
    out = []
    try:
        text = Path(path).read_text(errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        if not line.startswith("[ot6] ") or line.startswith("[ot6] state ") \
                or line.startswith("[ot6] provenance"):
            continue
        for rx, rep in NORM:
            line = rx.sub(rep, line)
        out.append(line)
    return out


# partiesLine names the world map since a433c08e; before it, a party on the
# world map was listed at its stale field object's map, or not shown.  A
# reference line played under the older library and a fill line that says
# "the world map" where the reference said one of those are the same play
# (the zero wave, build/attempts/wt/v046-fills-3/zero-wave/).  Remove once
# the line has been replayed under a433c08e's library.
PARTY_AT = re.compile(r"(\bparty \d+(?: \(walking\))?) at (\(not shown\)|map \d+ \(\d+,\d+\)|the world map):")


def same_line(x, y):
    if x == y:
        return True
    if "at the world map:" not in y:
        return False
    return PARTY_AT.sub(r"\1 at LOC:", x) == PARTY_AT.sub(r"\1 at LOC:", y) and \
        all(m.group(2) != "the world map" or n.group(2) == "the world map"
            for m, n in zip(PARTY_AT.finditer(x), PARTY_AT.finditer(y)))


def first_log_diff(ref_log, fil_log):
    """(line number, ref, fill, observations differing) of the first [ot6]
    line that differs outside the harness's observations; False when none
    does; None when a log is missing."""
    a, b = ot6_lines(ref_log), ot6_lines(fil_log)
    if a is None or b is None:
        return None
    obs = sum(1 for x, y in zip(a, b) if x != y and x.startswith(OBSERVATIONS))
    pa = [(i, x) for i, x in enumerate(a) if not x.startswith(OBSERVATIONS)]
    pb = [(i, x) for i, x in enumerate(b) if not x.startswith(OBSERVATIONS)]
    for (i, x), (_, y) in zip(pa, pb):
        if not same_line(x, y):
            return i + 1, x, y, obs
    if len(pa) != len(pb):
        k = min(len(pa), len(pb))
        return (pa[k][0] + 1 if k < len(pa) else len(a) + 1,
                pa[k][1] if k < len(pa) else "<end>",
                pb[k][1] if k < len(pb) else "<end>", obs)
    return (0, "", "", obs) if obs else False


def fmt_ranges(rs, n):
    s = " ".join(f"${a:05X}" if a == b else f"${a:05X}-${b:05X}" for a, b in rs[:n])
    return s + (f" (+{len(rs) - n} more)" if len(rs) > n else "")


def graph_states(root):
    spec = importlib.util.spec_from_file_location(
        "savestate_graph", Path(root) / "tools/tests/savestate_graph.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    out = []
    for s in mod.STATES:
        out.append(s["state"])
        out += s.get("also") or []
        for key in filter(None, (s.get("checkpoint"), s.get("saves"))):
            out.append("@" + key)
    seen, order = set(), []
    for s in out:
        if s not in seen:
            seen.add(s)
            order.append(s)
    return order


def capture(root, key):
    d = Path(root) / "build/checkpoints" / key
    srams = sorted(d.glob("*.sram")) if d.is_dir() else []
    return srams[0].read_bytes() if srams else None


def describe(c, n, what):
    parts = []
    if c["computed"]:
        parts.append(f"{what} computed from unwritten bytes at {fmt_ranges(c['computed'], n)}")
    if c["unwritten"]:
        k = sum(b - a + 1 for a, b in c["unwritten"])
        parts.append(f"{what} unwritten ({k} byte(s)) at {fmt_ranges(c['unwritten'], n)}")
    if c["checksum"]:
        parts.append(f"{what} checksum follows")
    return parts


def diff_trees(ref, fil, only=None, max_ranges=12, out=print):
    """Compare every state and capture both trees hold; returns (report,
    bad), bad when the play or a computed byte differs.  Unwritten bytes of
    the save block and of the battery's slots are findings too (no code
    wrote them, and a save carries them), listed but not counted as bad."""
    marker = Path(fil) / "build/FILL_TREE"
    mode = parse_mode(marker.read_text()) if marker.exists() else None
    if mode is None:
        mode = ("ones", 0, set())   # a zero or lab tree: nothing is fill-shaped
    rows = layout_rows(LAYOUT.read_text())
    report, bad = [], False
    persisted = set()
    first_play = None
    for name in graph_states(ref):
        if only and name.lstrip("@") not in only:
            continue
        if name.startswith("@"):
            key = name[1:]
            r, f = capture(ref, key), capture(fil, key)
            if r is None or f is None:
                continue
            c = classify(r, f, "sram", mode, skip=excluded_ranges(rows, r))
            bad |= bool(c["computed"])
            for a, b in c["unwritten"]:
                persisted.update(source_of("sram", x)[1] for x in range(a, b + 1)
                                 if source_of("sram", x)[0] == "wram")
            parts = describe(c, max_ranges, "battery")
            out(f"capture {key}: " + ("; ".join(parts) if parts else
                                       "battery matches outside the never-written ranges"))
            report.append({"capture": key, **{f"sram_{k}": v for k, v in c.items()}})
            continue
        rs, fs = (Path(t) / "build/states" / f"{name}.mss" for t in (ref, fil))
        if not (rs.exists() and fs.exists()):
            continue
        ent = {"state": name}
        rm, fm = (machine_stream(p.read_bytes()) for p in (rs, fs))
        ent["machine_identical"] = rm == fm
        parts = []
        d = first_log_diff(rs.with_suffix(".log"), fs.with_suffix(".log"))
        if d and d[0]:
            bad = True
            first_play = first_play or name
            ent["play"] = {"line": d[0], "ref": d[1], "fill": d[2]}
            parts.append(f"play parts at log line {d[0]}:\n      ref  {d[1][:160]}\n      fill {d[2][:160]}")
        if d:
            ent["observations"] = d[3]
            if d[3]:
                parts.append(f"{d[3]} harness observation line(s) differ")
        r = state_fields(rm or b"", FIELDS.values())
        f = state_fields(fm or b"", FIELDS.values())
        rw, fw = r.get(FIELDS["wram"]), f.get(FIELDS["wram"])
        if rw and fw:
            blk = classify(rw, fw, "wram", mode, *BLOCK)
            rest = classify(rw, fw, "wram", mode)
            rest["computed"] = [x for x in rest["computed"]
                                if not (BLOCK[0] <= x[0] and x[1] < BLOCK[1])]
            ent.update({f"block_{k}": v for k, v in blk.items()})
            ent["wram_computed"] = rest["computed"]
            ent["wram_unwritten"] = sum(b - a + 1 for a, b in rest["unwritten"])
            bad |= bool(blk["computed"] or rest["computed"])
            for a, b in blk["unwritten"]:
                persisted.update(range(a, b + 1))
            parts += describe(blk, max_ranges, "save block")
            if rest["computed"]:
                parts.append(f"wram computed from unwritten bytes at {fmt_ranges(rest['computed'], max_ranges)}")
            parts.append(f"{ent['wram_unwritten']} wram byte(s) unwritten")
        rsr, fsr = r.get(FIELDS["sram"]), f.get(FIELDS["sram"])
        if rsr and fsr:
            c = classify(rsr, fsr, "sram", mode, skip=excluded_ranges(rows, rsr))
            ent.update({f"sram_{k}": v for k, v in c.items()})
            bad |= bool(c["computed"])
            if c["computed"]:
                parts.append(f"battery computed from unwritten bytes at {fmt_ranges(c['computed'], max_ranges)}")
        if ent["machine_identical"]:
            parts = ["machine identical"]
        out(f"state {name}: " + "; ".join(parts))
        report.append(ent)
    if persisted:
        out("save-block bytes no code wrote, carried by the saves: "
            + fmt_ranges(ranges(sorted(persisted)), 64))
    if first_play:
        out(f"the play first parts in {first_play}")
    return report, bad


# ----------------------------------------------------------------- selftest
def selftest():
    import tempfile
    fails = []

    def check(what, ok):
        print(("  pass  " if ok else "  FAIL  ") + what)
        if not ok:
            fails.append(what)

    # the pattern is lib/poweron_fill.lua's: its first bytes, worked by hand
    check("ones fills $FF", fill_value("ones", 0, "wram", 7) == 0xFF)
    check("alt fills $55 at even, $AA at odd",
          (fill_value("alt", 0, "sram", 4), fill_value("alt", 0, "sram", 5)) == (0x55, 0xAA))
    vals = [fill_value("rand", 1, "wram", a) for a in range(4096)]
    check("rand:1 spreads over the byte values", len(set(vals)) > 200)
    check("rand depends on the seed",
          vals != [fill_value("rand", 2, "wram", a) for a in range(4096)])
    check("parse_mode reads regions", parse_mode("rand:7@wram,spc") == ("rand", 7, {"wram", "spc"}))
    check("parse_mode defaults to wram,sram", parse_mode("ones")[2] == {"wram", "sram"})
    check("parse_mode refuses junk", parse_mode("twos") is None)
    w = "[ot6] [wob] f1035 boot world (1,2); party 1 (walking) at %s: SABIN L14"
    check("the world map's new party text matches the old",
          same_line(w % "(not shown)", w % "the world map")
          and same_line(w % "map 3 (0,0)", w % "the world map"))
    check("a party moved off the world map still differs",
          not same_line(w % "the world map", w % "map 3 (0,0)")
          and not same_line(w % "map 3 (0,0)", w % "map 4 (0,0)"))
    check("parse_mode reads a bisection's regions",
          parse_mode("ones@wram:1D54+1FD3-1FF2,sram")[2] == {"wram", "sram"})

    # the doc: never-written rows, read from the real table
    rows = layout_rows(LAYOUT.read_text())
    check("the battery map tiles $0000-$7FFF",
          rows and rows[0][0] == 0 and rows[-1][1] == 0x7FFF
          and all(rows[i][1] + 1 == rows[i + 1][0] for i in range(len(rows) - 1)))
    bat = bytearray(0x8000)
    ex = excluded_ranges(rows, bat)
    check("$4000-$7FFF is excluded (never written)", any(a == 0x4000 and b == 0x7FFF for a, b, _ in ex))
    check("an empty slot's pages are excluded",
          any(a == 0x2000 for a, b, _ in ex) and any(a == 0x3800 for a, b, _ in ex))
    bat[0x1400] = 1                        # slot 3 saved
    ex = excluded_ranges(rows, bat)
    check("a saved slot's pages are compared", not any(a == 0x2800 for a, b, _ in ex)
          and not any(a == 0x3800 for a, b, _ in ex))
    check("the slots themselves are never excluded", not any(a < 0x2000 for a, b, _ in ex))

    # a synthetic pair of trees
    with tempfile.TemporaryDirectory() as t:
        ref, fil = Path(t, "ref"), Path(t, "fill")
        for tree in (ref, fil):
            (tree / "build/states").mkdir(parents=True)
            (tree / "build/checkpoints/k1").mkdir(parents=True)
            (tree / "tools/tests").mkdir(parents=True)
            (tree / "tools/tests/savestate_graph.py").write_text(
                "def S(state, **kw):\n    return dict(state=state, **kw)\n"
                "STATES = [S('a'), S('b', checkpoint='k1')]\n")
        (fil / "build/FILL_TREE").write_text("rand:3\n")

        def mss(wram, sram):
            body = b""
            for k, v in ((FIELDS["wram"], wram), (FIELDS["sram"], sram)):
                body += k.encode() + b"\0" + len(v).to_bytes(4, "little") + bytes(v)
            return b"MSS\x01" + zlib.compress(b"\x00" * 64 + body, 1)

        w0, s0 = bytearray(0x20000), bytearray(0x8000)
        w0[0x1600] = 0x10
        s0[0x1400] = 1
        wf = bytearray(w0)
        for a in range(0x10000, 0x10010):  # never written: holds the pattern
            wf[a] = fill_value("rand", 3, "wram", a)
        sf = bytearray(s0)
        for a in range(0x4000, 0x4100):    # never-written battery
            sf[a] = fill_value("rand", 3, "sram", a)
        log = "[ot6] one\n[ot6] emitted blob 'x.png' (100 bytes)\n[ot6] PASS (frame 9)\n"
        for name, (w, s) in {"a": (w0, s0), "b": (w0, s0)}.items():
            (ref / f"build/states/{name}.mss").write_bytes(mss(w, s))
            (ref / f"build/states/{name}.log").write_text(log)
        (ref / "build/checkpoints/k1/k1.sram").write_bytes(bytes(s0))
        (fil / "build/states/a.mss").write_bytes(mss(wf, sf))
        (fil / "build/states/a.log").write_text(log.replace("100 bytes", "104 bytes"))
        lines = []
        rep, bad = diff_trees(ref, fil, out=lines.append)
        check("never-written bytes alone are not a divergence", not bad)
        check("they are counted", rep[0].get("wram_unwritten") == 16)
        check("blob sizes are masked in the logs", "play" not in rep[0])
        # now a computed difference and a play difference
        wb = bytearray(wf)
        wb[0x1650] = 0x33                  # save block
        wb[0x7000] = 0x99                  # computed elsewhere in WRAM
        (fil / "build/states/b.mss").write_bytes(mss(wb, s0))
        (fil / "build/states/b.log").write_text(log.replace("PASS (frame 9)", "PASS (frame 10)"))
        sb = bytearray(s0)
        sb[0x1450] = 7                     # inside slot 3
        sb[0x2810] = 9                     # slot 3's codex page (slot saved: compared)
        sb[0x2010] = 9                     # slot 1's page (never saved: excluded)
        (fil / "build/checkpoints/k1/k1.sram").write_bytes(bytes(sb))
        lines = []
        rep, bad = diff_trees(ref, fil, out=lines.append)
        b = next(e for e in rep if e.get("state") == "b")
        k = next(e for e in rep if e.get("capture") == "k1")
        check("a computed difference is a divergence", bad)
        check("the save block difference is named", b["block_computed"] == [[0x1650, 0x1650]])
        check("the other WRAM difference is named", [0x7000, 0x7000] in b["wram_computed"])
        check("the play difference is named with its line", b.get("play", {}).get("line") == 3)
        check("the capture's slot and saved page differences are named",
              k["sram_computed"] == [[0x1450, 0x1450], [0x2810, 0x2810]])
        # an unwritten save-block byte the save copied into slot 3, and the
        # checksum that follows it
        sc = bytearray(s0)
        sc[0x1400 + 0x0870] = fill_value("rand", 3, "wram", 0x1E70)
        sc[0x1400 + CHECKSUM] = 0x44
        (fil / "build/checkpoints/k1/k1.sram").write_bytes(bytes(sc))
        wc = bytearray(w0)
        wc[0x1E70] = fill_value("rand", 3, "wram", 0x1E70)
        (fil / "build/states/b.mss").write_bytes(mss(wc, s0))
        (fil / "build/states/b.log").write_text(log)
        lines = []
        rep, bad = diff_trees(ref, fil, out=lines.append)
        k = next(e for e in rep if e.get("capture") == "k1")
        b = next(e for e in rep if e.get("state") == "b")
        check("a slot byte holding its save-block byte's pattern is unwritten",
              k["sram_unwritten"] == [[0x1C70, 0x1C70]] and not k["sram_computed"])
        check("the slot checksum is set apart", k["sram_checksum"] == [[0x1DFE, 0x1DFE]])
        check("an unwritten save-block byte is a finding, not a divergence",
              b["block_unwritten"] == [[0x1E70, 0x1E70]] and not bad)
        check("the report names the bytes the saves carry",
              any("carried by the saves: $01E70" in x for x in lines))
        # a harness observation alone is not the play
        (fil / "build/states/b.log").write_text("[ot6] [tiles] map=511\n" + log)
        (ref / "build/states/b.log").write_text("[ot6] [tiles] map=0\n" + log)
        rep, bad = diff_trees(ref, fil, out=[].append)
        b = next(e for e in rep if e.get("state") == "b")
        check("a differing [tiles] line is an observation", "play" not in b and b["observations"] == 1)
    print("fill_diff selftest: " + ("OK" if not fails else f"{len(fails)} FAILURE(S)"))
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", nargs="?")
    ap.add_argument("fill", nargs="?")
    ap.add_argument("--states", help="comma list of states / capture keys")
    ap.add_argument("--max-ranges", type=int, default=12)
    ap.add_argument("--json")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--logs", nargs="+", metavar="LOG",
                    help="compare run logs instead of trees: the first is the "
                         "reference; each other gets its first play difference")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.logs:
        bad = False
        for other in a.logs[1:]:
            d = first_log_diff(a.logs[0], other)
            if d is None:
                print(f"{other}: no log")
            elif d and d[0]:
                bad = True
                print(f"{other}: play parts at line {d[0]} ({d[3]} observation(s) differ)\n"
                      f"      ref  {d[1][:200]}\n      fill {d[2][:200]}")
            else:
                print(f"{other}: same play" + (f" ({d[3]} observation(s) differ)" if d else ""))
        return 1 if bad else 0
    if not (a.ref and a.fill):
        ap.error("REF and FILL are required")
    only = set(a.states.split(",")) if a.states else None
    report, bad = diff_trees(a.ref, a.fill, only, a.max_ranges)
    if a.json:
        Path(a.json).write_text(json.dumps(report, indent=1))
    print("fill_diff: " + ("DIVERGES" if bad else "no divergence beyond never-written bytes"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
