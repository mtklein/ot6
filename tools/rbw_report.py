#!/usr/bin/env python3
"""rbw_report.py -- read a read-before-write run's log (OT6_RBW=1,
lib/read_before_write.lua) and report each reading instruction once, by
source line, with the addresses it read before anything wrote them.

    tools/rbw_report.py LOG [--dbg ff6/rom/ff6-en.dbg] [--waivers FILE] [--all]
    tools/rbw_report.py --selftest

The instrument logs `[rbw] f<frame> <ram> $<addr> pc $<pc> v=$<value>`,
where pc is the CPU's program counter during the access: past the opcode
and its operands, so the instruction is the one whose bytes end at or
before pc (a DMA is charged to the store that started it).  The ROM's ca65
debug file names the source line.

tools/uninit_waivers.txt lists the reads proven benign, one per line:

    read <file>:<line> <ram> <reason>     one instruction
    unread <ram> <lo>[-<hi>] <reason>      any instruction's read of these offsets
    fill <ram> <lo>[-<hi>] <reason>        (the fill's own waivers count too)

A waived line's reads are counted and not listed (--all lists them too).
Exit status 1 when an unwaived read remains.
"""
import argparse
import bisect
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HIT = re.compile(r"^\[rbw\] f(\d+) (wram|sram) \$([0-9A-F]+) pc \$([0-9A-F]{6}) v=\$([0-9A-F]{2})( via WMDATA)?")


class Dbg:
    """Address -> (file, line) from a ca65 .dbg: every span placed in a ROM
    segment, and the source lines that cite it (the innermost: a macro's
    own line beats the line that invoked it, type=0 beats type=1/2)."""

    def __init__(self, path):
        files, segs, spans, lines = {}, {}, {}, defaultdict(list)
        for raw in Path(path).read_text().splitlines():
            kind, _, rest = raw.partition("\t")
            if kind not in ("file", "seg", "span", "line"):
                continue
            f = dict(kv.split("=", 1) for kv in rest.split(","))
            i = int(f["id"])
            if kind == "file":
                files[i] = f["name"].strip('"')
            elif kind == "seg":
                segs[i] = int(f["start"], 16)
            elif kind == "span":
                spans[i] = (int(f["seg"]), int(f["start"], 0), int(f["size"], 0))
            elif "span" in f:
                for s in f["span"].split("+"):
                    lines[int(s)].append((int(f.get("type", 0)), files.get(int(f["file"])), int(f["line"])))
        self.files = files
        table = []
        for sid, (seg, start, size) in spans.items():
            if sid in lines and size > 0:
                a = segs.get(seg, 0) + start
                table.append((a, a + size, sid))
        table.sort()
        self.starts = [t[0] for t in table]
        self.table = table
        self.lines = lines

    def at(self, addr):
        """The innermost line whose span holds addr, smallest span first."""
        i = bisect.bisect_right(self.starts, addr)
        best = None
        j = i - 1
        while j >= 0 and j > i - 4000:
            a, b, sid = self.table[j]
            if a <= addr < b:
                for typ, f, ln in self.lines[sid]:
                    cand = (b - a, typ, f, ln)
                    if f and (best is None or cand < best):
                        best = cand
            j -= 1
            if best and a < addr - 0x10000:
                break
        return (best[2], best[3]) if best else (None, None)

    def instruction(self, pc):
        """The instruction a read-time pc belongs to: the one ending at or
        just before pc (pc - 1), else the one at pc."""
        f, ln = self.at(pc - 1)
        return (f, ln) if f else self.at(pc)


def load_waivers(path):
    out = {}
    if not path or not Path(path).exists():
        return out
    for raw in Path(path).read_text().splitlines():
        f = raw.split(None, 3)
        if len(f) == 4 and f[0] == "read":
            out[(f[1], f[2])] = f[3]
        elif len(f) == 4 and f[0] in ("fill", "unread"):
            # an address waiver: any instruction's read of these offsets
            # (`fill` lines too: what the fill leaves zero is understood)
            lo, _, hi = f[2].partition("-")
            reason = f[3].split(None, 1)
            out.setdefault(("*", f[1]), []).append((int(lo, 16), int(hi or lo, 16), f[3]))
    return out


def ranges(addrs):
    out = []
    for a in sorted(addrs):
        if out and a <= out[-1][1] + 1:
            out[-1][1] = a
        else:
            out.append([a, a])
    return out


def report(log_lines, dbg, waivers, show_all=False, out=print):
    groups = {}
    for line in log_lines:
        m = HIT.match(line)
        if not m:
            continue
        frame, ram, addr, pc = int(m.group(1)), m.group(2), int(m.group(3), 16), int(m.group(4), 16)
        f, ln = dbg.instruction(pc) if dbg else (None, None)
        where = f"{f}:{ln}" if f else f"${pc:06X}"
        g = groups.setdefault((where, ram), {"first": frame, "addrs": set(), "pcs": set(), "via": set()})
        g["addrs"].add(addr)
        g["pcs"].add(pc)
        if m.group(6):
            g["via"].add("WMDATA")
    open_, waived = [], []
    for (where, ram), g in sorted(groups.items(), key=lambda kv: kv[1]["first"]):
        reason = waivers.get((where, ram))
        if not reason:
            spans = waivers.get(("*", ram), [])
            # every offset under some waiver (overlapping waivers count once)
            hit = [next((r for lo, hi, r in spans if lo <= a <= hi), None) for a in sorted(g["addrs"])]
            if all(hit):
                reason = hit[0]
        (waived if reason else open_).append((where, ram, g, reason))
    for where, ram, g, reason in open_ + (waived if show_all else []):
        rs = ranges(g["addrs"])
        shown = " ".join(f"${a:05X}" if a == b else f"${a:05X}-${b:05X}" for a, b in rs[:8])
        if len(rs) > 8:
            shown += f" (+{len(rs) - 8} ranges)"
        pcs = " ".join(f"${p:06X}" for p in sorted(g["pcs"])[:3])
        tag = f"  [waived: {reason}]" if reason else ""
        out(f"{where}  {ram} {shown}  first f{g['first']}, pc {pcs}{tag}")
    out(f"rbw_report: {len(open_)} unwaived reading line(s), {len(waived)} waived")
    return open_, waived


def selftest():
    import tempfile
    fails = []

    def check(what, ok):
        print(("  pass  " if ok else "  FAIL  ") + what)
        if not ok:
            fails.append(what)

    with tempfile.TemporaryDirectory() as t:
        dbg = Path(t, "x.dbg")
        dbg.write_text(
            'version\tmajor=2,minor=0\n'
            'file\tid=0,name="src/a.asm",size=1,mtime=0x0,mod=0\n'
            'seg\tid=0,name="CODE",start=0xC00000,size=0x100,addrsize=absolute,type=ro\n'
            'span\tid=0,seg=0,start=0x10,size=3\n'
            'span\tid=1,seg=0,start=0x13,size=2\n'
            'line\tid=0,file=0,line=7,span=0\n'
            'line\tid=1,file=0,line=8,span=1\n')
        d = Dbg(dbg)
        check("an address inside a span names its line", d.at(0xC00011) == ("src/a.asm", 7))
        check("a read-time pc names the instruction before it",
              d.instruction(0xC00013) == ("src/a.asm", 7))
        log = ["[rbw] f20 wram $01FD3 pc $C00013 v=$00",
               "[rbw] f21 wram $01FD4 pc $C00013 v=$00",
               "[rbw] f30 sram $04000 pc $C00015 v=$FF",
               "[ot6] unrelated"]
        w = Path(t, "w.txt")
        w.write_text("# comment\nfill wram 1F6E a fill line\nread src/a.asm:8 sram the magic check reads before it signs\n"
                     "unread wram 1FD3 an address waiver covering half the group\n")
        lines = []
        o, wv = report(log, d, load_waivers(w), out=lines.append)
        check("reads group by source line", len(o) == 1 and o[0][0] == "src/a.asm:7")
        check("consecutive addresses print as a range", "$01FD3-$01FD4" in lines[0])
        check("a waived line is counted, not listed; a half-covered group stays listed", len(wv) == 1 and len(lines) == 2)
        w.write_text("unread wram 1FD0-1FDF every read of these\n")
        o, wv = report(log, d, load_waivers(w), out=[].append)
        check("an address waiver covering a group's every address waives it",
              [x[0] for x in o] == ["src/a.asm:8"] and len(wv) == 1)
        w.write_text("unread wram 1FD0-1FDF every read of these\nunread wram 1FD3 one of them again\n")
        o, wv = report(log, d, load_waivers(w), out=[].append)
        check("overlapping address waivers still waive the group",
              [x[0] for x in o] == ["src/a.asm:8"] and len(wv) == 1)
    print("rbw_report selftest: " + ("OK" if not fails else f"{len(fails)} FAILURE(S)"))
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?")
    ap.add_argument("--dbg", default=str(ROOT / "ff6/rom/ff6-en.dbg"))
    ap.add_argument("--waivers", default=str(ROOT / "tools/uninit_waivers.txt"))
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.log:
        ap.error("LOG is required")
    dbg = Dbg(a.dbg) if Path(a.dbg).exists() else None
    o, _ = report(Path(a.log).read_text(errors="replace").splitlines(), dbg,
                  load_waivers(a.waivers), a.all)
    return 1 if o else 0


if __name__ == "__main__":
    sys.exit(main())
