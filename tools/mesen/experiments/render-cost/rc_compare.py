#!/usr/bin/env python3
"""rc_compare.py <run dir A> <run dir B> -- is emulation identical between two runs?

Compares, between A/run.log and B/run.log:
  verdict    the [ot6] PASS/FAIL line and its frame
  ot6        every [ot6] line (the harness's narration and verdict)
  notes      every [ot6note] line (frame-stamped)
  pads       every [ot6pad] line (the input the harness sent, frame-stamped)
  rcdump     WRAM, ARAM, VRAM, OAM, CGRAM, SRAM bytes at the verdict, per region
  rcstate    emu.getState() at the verdict, per key (lists the keys that differ)
  shots      [ot6shot] PNGs (frame stamps and bytes)
and each *.mss savestate both runs published: header video block vs the
serialized machine state, the latter per key.
"""
import os, re, sys, zlib, struct, glob

def lines(path, tag):
    return [l for l in open(path, errors="replace").read().splitlines() if l.startswith(tag)]

def dump(path):
    d = {}
    for l in lines(path, "[rcdump] "):
        _, reg, base, hx = l.split(" ", 3)
        d.setdefault(reg, []).append((int(base, 16), hx))
    return {r: bytes.fromhex("".join(h for _, h in sorted(v))) for r, v in d.items()}

def state(path):
    return dict(l[len("[rcstate] "):].split("=", 1) for l in lines(path, "[rcstate] "))

def mss(path):
    b = open(path, "rb").read()
    assert b[:3] == b"MSS", path
    o = 3
    emuv, fmt, ctype = struct.unpack_from("<III", b, o); o += 12
    fbsize, w, h, scale, csize = struct.unpack_from("<IIIII", b, o); o += 20
    video = zlib.decompress(b[o:o + csize]); o += csize
    (nlen,) = struct.unpack_from("<I", b, o); o += 4
    rom = b[o:o + nlen]; o += nlen
    comp = b[o]; o += 1
    if comp:
        orig, cs = struct.unpack_from("<II", b, o); o += 8
        data = zlib.decompress(b[o:o + cs])
    else:
        data = b[o:]
    kv, i = {}, 0
    while i < len(data):
        j = data.index(b"\0", i)
        key = data[i:j].decode(); i = j + 1
        (sz,) = struct.unpack_from("<I", data, i); i += 4
        kv[key] = data[i:i + sz]; i += sz
    return {"emuv": emuv, "fmt": fmt, "video": video, "wh": (w, h), "rom": rom, "state": kv}

def main():
    a, b = sys.argv[1], sys.argv[2]
    la, lb = os.path.join(a, "run.log"), os.path.join(b, "run.log")
    same = True
    def rep(name, ok, extra=""):
        nonlocal same
        same = same and ok
        print(f"  {name:8s} {'SAME' if ok else 'DIFFERENT'} {extra}")
    print(f"compare {a}\n     vs {b}")
    va = [l for l in lines(la, "[ot6] ") if re.match(r"\[ot6\] (PASS \(frame |FAIL: )", l)]
    vb = [l for l in lines(lb, "[ot6] ") if re.match(r"\[ot6\] (PASS \(frame |FAIL: )", l)]
    rep("verdict", va == vb, f"| {va[-1][:90] if va else None} | {vb[-1][:90] if vb else None}")
    for tag, name in (("[ot6] ", "ot6"), ("[ot6note] ", "notes"), ("[ot6pad] ", "pads"), ("[rcchk] ", "rcchk")):
        xa, xb = lines(la, tag), lines(lb, tag)
        first = next((k for k in range(min(len(xa), len(xb))) if xa[k] != xb[k]), None)
        ok = xa == xb
        extra = f"({len(xa)} vs {len(xb)} lines)"
        if not ok and first is not None:
            extra += f" first difference at line {first}: {xa[first][:100]!r} vs {xb[first][:100]!r}"
        rep(name, ok, extra)
    da, db = dump(la), dump(lb)
    if da or db:
        for r in sorted(set(da) | set(db)):
            x, y = da.get(r, b""), db.get(r, b"")
            nd = sum(1 for p, q in zip(x, y) if p != q) + abs(len(x) - len(y))
            rep("rcdump", nd == 0, f"{r} {len(x)} bytes, {nd} differ")
        sa, sb = state(la), state(lb)
        dk = sorted(k for k in set(sa) | set(sb) if sa.get(k) != sb.get(k))
        rep("rcstate", not dk, f"{len(sa)} keys, {len(dk)} differ {dk[:12]}")
    sha = [l.split(" ", 2)[1:] for l in lines(la, "[ot6shot] ")]
    shb = [l.split(" ", 2)[1:] for l in lines(lb, "[ot6shot] ")]
    fa, fb = [s[0] for s in sha], [s[0] for s in shb]
    nsame = sum(1 for p, q in zip(sha, shb) if p == q)
    print(f"  shots    frames {'same' if fa == fb else 'DIFFERENT'} ({len(fa)} vs {len(fb)}), "
          f"{nsame} of {min(len(sha), len(shb))} identical PNGs (pixels are not emulation state)")
    for pa in sorted(glob.glob(os.path.join(a, "*.mss"))):
        pb = os.path.join(b, os.path.basename(pa))
        if not os.path.exists(pb):
            rep("mss", False, f"{os.path.basename(pa)} missing in B"); continue
        ma, mb = mss(pa), mss(pb)
        ka, kb = ma["state"], mb["state"]
        dk = sorted(k for k in set(ka) | set(kb) if ka.get(k) != kb.get(k))
        raw = open(pa, "rb").read() == open(pb, "rb").read()
        print(f"  mss      {os.path.basename(pa)}: file bytes {'identical' if raw else 'differ'}; "
              f"video block {'same' if ma['video'] == mb['video'] else 'differs'}; "
              f"{len(ka)} state keys, {len(dk)} differ: {dk[:20]}")
        same = same and not dk
    print("RESULT", "IDENTICAL" if same else "DIFFERENT")

main()
