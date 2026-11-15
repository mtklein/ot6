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
          * the slot's codex page is the file's;
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
    golden_saves.py negative FIXTURE LOG BATTERY
        a run whose check must FAIL (the corrupted fixture): exit 0 only
        when check refuses it, naming the esper page
    golden_saves.py --selftest
        the check against in-memory mutants
"""

from __future__ import annotations

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
ESPER_MAGIC = 0x3145
CTR, CTR_END = 0x0010, 0x0280
# what a Continue of slot 3 and a save into it may touch (the battery map's
# Written tokens; newgame and clear rows are not exercised)
RUN_WRITES = {"save", "load", "title", "play"}
DUMP = re.compile(r"^\[golden\] dump (\S+) (\S+) ([0-9A-F]{4}) ([0-9A-F]+)\s*$")


class GoldenError(Exception):
    pass


def w16(b, o):
    return b[o] | (b[o + 1] << 8)


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


def allowed_offsets(rows, slot):
    """Battery offsets today's ROM may write in a Continue of `slot` and a save into it."""
    scopes = {"shared", f"slot{slot}"}
    ok = bytearray(sc.SRAM_SIZE)
    for r in rows:
        if r["scope"] in scopes and r["written"] & RUN_WRITES:
            for o in range(r["start"], r["end"] + 1):
                ok[o] = 1
    return ok


def check_run(fixture_bytes, roster_rows, esper, dumps, after, rows):
    """Problems (strings) for one run; empty = the save is compatible."""
    p = []
    f = fixture_bytes
    slot = f[0x1FF0]
    if slot not in SLOT_PTR:
        return [f"the fixture's battery names slot {slot} ($1FF0), not 1..3"]
    for tag in ("load1", "load2"):
        for what, n in (("wram", BLOCK), ("codex", 0x400), ("live", 0x400)):
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

    # 2. codex carries over
    cpage = CODEX + (slot - 1) * 0x400
    if d1["codex"] != f[cpage:cpage + 0x400]:
        p.append(f"load1: slot {slot}'s codex page is not the file's")

    # 3. esper progress: the slot's signed page, or none
    epage = ESPER + (slot - 1) * 0x400
    signed = w16(f, epage) == ESPER_MAGIC
    live = d1["live"][CTR:CTR_END]
    if esper == "signed":
        if not signed:
            p.append(f"esper: this release signs its esper pages, but the fixture's slot {slot} page "
                     f"is unsigned (${w16(f, epage):04X}); the run read {sum(live)} in the live page")
        elif live != f[epage + CTR:epage + CTR_END]:
            p.append("esper: the live page after the load is not the slot's esper page")
    elif esper == "none":
        if signed:
            p.append(f"esper: a save from before esper progress has a signed page at ${epage:04X}")
        if any(live):
            p.append("esper: a save from before esper progress loaded with esper progress")
    else:
        p.append(f"esper: unknown expectation {esper!r}")

    # 4. outside what today's ROM writes, the battery is the file's
    ok = allowed_offsets(rows, slot)
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

    # 5. the round trip: what the save wrote, and the second load
    ablock = block_of(after, slot)
    compare(p, "saved slot roster", roster_rows, roster_of_block(ablock))
    compare(p, "load2 roster", roster_rows, roster_of_block(d2["wram"]))
    # between the load and the save the field has run (a map's entry events
    # set switches, the random byte moves), so the save is held to the file
    # only in what standing still cannot change, and the reload to the save
    # byte for byte
    fa, f1 = facts(ablock), facts(fblock)
    compare(p, "saved slot", {k: f1[k] for k in STILL}, {k: fa[k] for k in STILL})
    compare(p, "load2", fa, facts(d2["wram"]))
    if d2["wram"] != ablock:
        n = sum(1 for a, b in zip(d2["wram"], ablock) if a != b)
        p.append(f"load2: the reloaded block differs from the slot the save wrote in {n} byte(s)")
    if w16(after, epage) != ESPER_MAGIC:
        p.append(f"after the save, slot {slot}'s esper page is unsigned")
    if after[epage + CTR:epage + CTR_END] != live:
        p.append("after the save, the slot's esper page is not the live page the load made")
    if d2["live"][CTR:CTR_END] != live:
        p.append("load2: the live esper page is not what was saved")
    if d2["codex"] != d1["codex"]:
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
    return check_run(f, roster_of_file(payload), g["esper"], dumps, after, doc_rows())


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
    print(f"golden saves: {n} fixtures from {len(m['sets'])} releases match MANIFEST.json; "
          f"the negative is v0.44/wor-cyan-v1 with slot 3's esper signature zeroed")
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


# ----------------------------------------------------------------- selftest --
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
    f[cp], f[cp + 1] = 0x4F, 0x38
    f[cp + 0x20] = 5
    ep = ESPER + 0x800
    f[ep], f[ep + 1] = 0x45, 0x31
    f[ep + 0x12] = 7
    f[LIVE], f[LIVE + 1] = 0x45, 0x31
    f[LIVE + 0x12] = 7
    after = bytearray(f)
    after[0x1FF1] = 9               # title seed (shared, title)
    after[b + 0x1863 - 0x1600] = 1  # play time moved (slot3, save)
    def dumps(blk_after):
        return {"load1": {"wram": bytes(block_of(f, 3)), "codex": bytes(f[cp:cp + 0x400]),
                          "live": bytes(f[LIVE:LIVE + 0x400])},
                "load2": {"wram": bytes(blk_after), "codex": bytes(f[cp:cp + 0x400]),
                          "live": bytes(f[LIVE:LIVE + 0x400])}}
    return f, after, dumps


def selftest():
    rows = doc_rows()
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

    # a write into slot 1, the codex tail, the reserve past $4000, $1E00
    for o in (0x0005, CODEX + 0x800 + 0x310, 0x4000, 0x1E00, ESPER + 0x800 + 0x280):
        bad(mut_after=lambda a, o=o: a.__setitem__(o, 0xAA), want="outside the documented writes")
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
    bad(mut_dumps=cod, want="codex page is not the file's")
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
    print("golden_saves selftest OK")
    return 0


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    try:
        if argv[:1] == ["verify"]:
            return verify()
        if argv[:1] == ["list"]:
            for d in fixture_dirs():
                print(d.relative_to(ROOT))
            return 0
        if argv[:1] in (["check"], ["negative"]) and len(argv) == 4:
            fx, log, bat = Path(argv[1]), Path(argv[2]), Path(argv[3])
            probs = check(fx, log, bat)
            if argv[0] == "negative":
                if any("esper" in x for x in probs):
                    print(f"golden negative: refused as it must be: {probs[0]}")
                    return 0
                print(f"golden negative: FAIL -- {fx} was not refused for its esper page: {probs}")
                return 1
            for x in probs:
                print(f"golden: FAIL {fx.relative_to(ROOT) if fx.is_absolute() else fx}: {x}")
            if probs:
                return 1
            print(f"golden: PASS {fx}: loads, matches the file, carries its codex and esper pages, "
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
