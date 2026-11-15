#!/usr/bin/env python3
"""fill_diff.py -- compare a fill run of the line with the zero-fill line.

    tools/fill_diff.py REF FILL [--states a,b] [--max-ranges N] [--json OUT]
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
REGION_ID = {"wram": 1, "sram": 2, "vram": 3, "oam": 4, "cgram": 5, "spc": 6}
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


def read_state(path):
    raw = machine_stream(Path(path).read_bytes())
    f = state_fields(raw or b"", FIELDS.values())
    return {k: f.get(v) for k, v in FIELDS.items()}


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


def compare_ram(ref, fil, region, mode, base=0, lo=0, hi=None, skip=()):
    """(fill-shaped count, [(start, end)] of the other differences)."""
    hi = len(ref) if hi is None else hi
    shaped, other = 0, []
    kind, seed, regions = mode
    for a in range(lo, hi):
        if ref[a] == fil[a] or any(s <= a <= e for s, e, _ in skip):
            continue
        if region in regions and ref[a] == 0 and fil[a] == fill_value(kind, seed, region, a):
            shaped += 1
        else:
            other.append(a + base)
    return shaped, ranges(other)


NORM = [(re.compile(r"\(\d+ bytes\)"), "(N bytes)"),
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


def first_log_diff(ref_log, fil_log):
    a, b = ot6_lines(ref_log), ot6_lines(fil_log)
    if a is None or b is None:
        return None
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i + 1, x, y
    if len(a) != len(b):
        i = min(len(a), len(b))
        return i + 1, a[i] if i < len(a) else "<end>", b[i] if i < len(b) else "<end>"
    return False


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


def diff_trees(ref, fil, only=None, max_ranges=12, out=print):
    marker = Path(fil) / "build/FILL_TREE"
    mode = parse_mode(marker.read_text()) if marker.exists() else None
    if mode is None:
        mode = ("ones", 0, set())   # a zero or lab tree: nothing is fill-shaped
    rows = layout_rows(LAYOUT.read_text())
    report, bad = [], False
    for name in graph_states(ref):
        if only and name.lstrip("@") not in only:
            continue
        if name.startswith("@"):
            key = name[1:]
            r, f = capture(ref, key), capture(fil, key)
            if r is None or f is None:
                continue
            skip = excluded_ranges(rows, r)
            shaped, other = compare_ram(r, f, "sram", mode, skip=skip)
            ent = {"capture": key, "sram_fill_shaped": shaped,
                   "sram_other": other}
            line = f"capture {key}: "
            if other:
                bad = True
                line += f"battery differs at {fmt_ranges(other, max_ranges)}"
            else:
                line += "battery matches outside the never-written ranges"
            if shaped:
                line += f" ({shaped} byte(s) hold the fill pattern)"
            out(line)
            report.append(ent)
            continue
        rs, fs = (Path(t) / "build/states" / f"{name}.mss" for t in (ref, fil))
        if not (rs.exists() and fs.exists()):
            continue
        ent = {"state": name}
        d = first_log_diff(rs.with_suffix(".log"), fs.with_suffix(".log"))
        if d:
            ent["play"] = {"line": d[0], "ref": d[1], "fill": d[2]}
        r, f = read_state(rs), read_state(fs)
        parts = []
        if d:
            bad = True
            parts.append(f"play parts at log line {d[0]}:\n      ref  {d[1][:160]}\n      fill {d[2][:160]}")
        if r["wram"] and f["wram"]:
            _, blk = compare_ram(r["wram"], f["wram"], "wram", mode, lo=BLOCK[0], hi=BLOCK[1])
            # the save block holds nothing never written: every difference counts
            blk = ranges([a for a in range(*BLOCK) if r["wram"][a] != f["wram"][a]])
            shaped, other = compare_ram(r["wram"], f["wram"], "wram", mode)
            other = [x for x in other if not (BLOCK[0] <= x[0] and x[1] < BLOCK[1])]
            ent.update(block=blk, wram_fill_shaped=shaped, wram_other=other)
            if blk:
                bad = True
                parts.append(f"save block differs at {fmt_ranges(blk, max_ranges)}")
            if other:
                bad = True
                parts.append(f"wram differs (not fill-shaped) at {fmt_ranges(other, max_ranges)}")
            parts.append(f"{shaped} wram byte(s) hold the fill pattern")
        if r["sram"] and f["sram"]:
            skip = excluded_ranges(rows, r["sram"])
            shaped, other = compare_ram(r["sram"], f["sram"], "sram", mode, skip=skip)
            ent.update(sram_fill_shaped=shaped, sram_other=other)
            if other:
                bad = True
                parts.append(f"battery differs at {fmt_ranges(other, max_ranges)}")
        out(f"state {name}: " + ("; ".join(parts) if parts else "identical"))
        report.append(ent)
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
        check("they are counted", rep[0].get("wram_fill_shaped") == 16)
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
        check("the save block difference is named", b["block"] == [[0x1650, 0x1650]])
        check("the other WRAM difference is named", [0x7000, 0x7000] in b["wram_other"])
        check("the play difference is named with its line", b.get("play", {}).get("line") == 3)
        check("the capture's slot and saved page differences are named",
              k["sram_other"] == [[0x1450, 0x1450], [0x2810, 0x2810]])
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
    a = ap.parse_args()
    if a.selftest:
        return selftest()
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
