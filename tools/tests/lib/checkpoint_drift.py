#!/usr/bin/env python3
"""checkpoint_drift.py -- how far a tracked checkpoint has drifted from the
save the graph's play makes today, and the re-cut.

Every tracked checkpoint (tools/tests/checkpoints/<key>/) is made by one run
on the savestate graph (savestate_ninja.py): a cut's prev, its cutter=, a
saves= state, or a CAPTURES cutter.  That run captures the battery into
build/checkpoints/<key>/, a seal edge makes it a checkpoint, and the cut
after it Continues that capture.  The tracked copy is what suites and
by-hand runs boot; this compares the two.

The verdict is byte for byte: the graph is deterministic, so a tracked
battery that is today's play is the capture's bytes, play time and slot
checksums included (43 of 43 captures replayed to the same bytes on the
Air, on px13 and against the tracked copies:
build/attempts/wt/one-graph/{air,px13}/after-full.payload-cmp.txt).
Anything that differs -- a slot, the OT6 codex in bank $31, the battery's
own bytes -- is drift.

The report explains a drift in play terms, decoded from the last-saved slot:
where the save is; all sixteen character records (level, experience, max
HP/MP, gear, the rest of the record) and party/row bytes; gil and the bag;
story switches; the encounter counters ($1FA1-$1FA5); espers, spells,
SwdTech, Blitz, Lore, Rage and Dance; then every remaining differing slot
byte, other slot, codex byte and battery byte by address.

    checkpoint_drift.py KEY...            report; exit 0
    checkpoint_drift.py --strict KEY...   report; exit 1 if any KEY drifted
                                          (the gate, build/checks/
                                          checkpoint_drift.ok in `ninja`)
    checkpoint_drift.py --recut KEY...    copy each capture over its tracked
                                          checkpoint, refused unless the
                                          capture's record is current
                                          (lib/stamps.py), then report
    checkpoint_drift.py --selftest

The gate runs after the captures it reads, so they are current by
construction.  A by-hand --recut asks lib/stamps.py, the same question
`ninja` answers by the same inputs.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(HERE))
import sram_checkpoint as sc  # noqa: E402

TRACKED = ROOT / "tools" / "tests" / "checkpoints"
FRESH = ROOT / "build" / "checkpoints"
NAMES = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES",
         "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO",
         "char14", "char15"]
SLOT_LEN = 0xA00                       # WRAM $1600-$1FFF, CopyGameDataToSRAM
def byte_diffs(fresh: bytes, tracked: bytes) -> list[int]:
    """Payload offsets that differ."""
    return [i for i in range(sc.SRAM_SIZE) if fresh[i] != tracked[i]]


def sram_addr(off: int) -> str:
    return f"${0x30 + off // 0x2000:02X}{0x6000 + off % 0x2000:04X}"


# ---------------------------------------------------------- the explanation --
# Named ranges of a slot's WRAM copy: (first, last, label).  Anything a
# report finds outside them is listed by address.
CHAR_LEN = 37
RANGES = [(0x1600, 0x1600 + 16 * CHAR_LEN - 1, "character records"),
          (0x1850, 0x185F, "party/row bytes"),
          (0x1860, 0x1862, "gil"),
          (0x1863, 0x1865, "play time"),
          (0x1869, 0x1A68, "bag"),
          (0x1A69, 0x1A6C, "espers"),
          (0x1A6E, 0x1CF5, "spells learned"),
          (0x1CF7, 0x1CF7, "SwdTech"),
          (0x1D28, 0x1D28, "Blitz"),
          (0x1D29, 0x1D2B, "Lore"),
          (0x1D2C, 0x1D4B, "Rage"),
          (0x1D4C, 0x1D4C, "Dance"),
          (0x1E80, 0x1EFF, "story switches"),
          (0x1F60, 0x1F61, "world tile"), (0x1F64, 0x1F65, "map"),
          (0x1FC0, 0x1FC1, "field tile"),
          (0x1FA1, 0x1FA5, "encounter counters"),
          (0x1FFE, 0x1FFF, "slot checksum")]


def explain(fresh: bytes, tracked: bytes, offs: list[int]) -> list[str]:
    lines = []
    last = fresh[sc._LAST_SLOT]
    ptr = sc.SLOT_PTR.get(last)
    if ptr is None or tracked[sc._LAST_SLOT] != last:
        lines.append(f"last-saved slot: fresh {fresh[sc._LAST_SLOT]}, "
                     f"tracked {tracked[sc._LAST_SLOT]}")
    f = (lambda a: fresh[ptr + a - 0x1600]) if ptr is not None else None
    t = (lambda a: tracked[ptr + a - 0x1600]) if ptr is not None else None
    covered = set()

    def rng(a, b):
        covered.update(range(a, b + 1))

    if ptr is not None:
        fw, tw = (sc.describe_saved(sc.saved_state(fresh)),
                  sc.describe_saved(sc.saved_state(tracked)))
        if fw != tw:
            lines.append(f"where: fresh {fw}, tracked {tw}")
        for a, b in ((0x1F60, 0x1F61), (0x1F64, 0x1F65), (0x1FC0, 0x1FC1)):
            rng(a, b)

        def w(get, a):
            return get(a) | (get(a + 1) << 8)
        for c in range(16):
            o = 0x1600 + CHAR_LEN * c
            rng(o, o + CHAR_LEN - 1)
            rng(0x1850 + c, 0x1850 + c)
            name = NAMES[c]
            fields = [("level", lambda g: g(o + 8)),
                      ("exp", lambda g: g(o + 0x11) | (g(o + 0x12) << 8)
                       | (g(o + 0x13) << 16)),
                      ("hp", lambda g: w(g, o + 9)),
                      ("max hp", lambda g: w(g, o + 11)),
                      ("mp", lambda g: w(g, o + 13)),
                      ("max mp", lambda g: w(g, o + 15)),
                      ("gear", lambda g: " ".join(f"{g(o + s):02X}"
                                                  for s in range(0x1F, 0x25))),
                      ("status", lambda g: f"{g(o + 0x14):02X}"),
                      ("party/row byte", lambda g: f"{g(0x1850 + c):02X}")]
            named = ({8, 9, 10, 11, 12, 13, 14, 15, 16, 0x11, 0x12, 0x13, 0x14}
                     | set(range(0x1F, 0x25)))
            for label, get in fields:
                if get(f) != get(t):
                    lines.append(f"{name} {label}: fresh {get(f)}, tracked {get(t)}")
            rest = [k for k in range(CHAR_LEN) if k not in named
                    and f(o + k) != t(o + k)]
            if rest:
                lines.append(f"{name} record bytes {', '.join(f'+${k:02X}' for k in rest)}: "
                             f"fresh {' '.join(f'{f(o + k):02X}' for k in rest)}, "
                             f"tracked {' '.join(f'{t(o + k):02X}' for k in rest)}")
        rng(0x1860, 0x1862)
        fg = f(0x1860) | (f(0x1861) << 8) | (f(0x1862) << 16)
        tg = t(0x1860) | (t(0x1861) << 8) | (t(0x1862) << 16)
        if fg != tg:
            lines.append(f"gil: fresh {fg}, tracked {tg}")
        rng(0x1869, 0x1A68)

        def bag(get):
            out = {}
            for i in range(256):
                it, n = get(0x1869 + i), get(0x1969 + i)
                if it != 0xFF and n:
                    out[it] = out.get(it, 0) + n
            return out
        fb, tb = bag(f), bag(t)
        for it in sorted(set(fb) | set(tb)):
            if fb.get(it, 0) != tb.get(it, 0):
                lines.append(f"item ${it:02X}: fresh {fb.get(it, 0)}, "
                             f"tracked {tb.get(it, 0)}")
        if not any(l.startswith("item") for l in lines) and any(
                f(a) != t(a) for a in range(0x1869, 0x1A69)):
            lines.append("bag: the same counts in a different order")
        rng(0x1A6E, 0x1CF5)
        for c in range(12):
            base = 0x1A6E + 54 * c
            ch = [s for s in range(54) if f(base + s) != t(base + s)]
            if ch:
                lines.append(f"{NAMES[c]} spells learned: {len(ch)} differ, "
                             + ", ".join(f"spell {s} fresh {f(base + s)} tracked "
                                         f"{t(base + s)}" for s in ch[:6])
                             + (" ..." if len(ch) > 6 else ""))
        for a, b, label in RANGES:
            if label in ("character records", "party/row bytes", "gil", "bag",
                         "spells learned", "world tile", "map", "field tile"):
                continue
            rng(a, b)
            if label == "story switches":
                for i in range(a, b + 1):
                    x, y = f(i), t(i)
                    for bit in range(8):
                        if ((x ^ y) >> bit) & 1:
                            lines.append(f"switch ${(i - a) * 8 + bit:03X}: "
                                         f"fresh {(x >> bit) & 1}, tracked {(y >> bit) & 1}")
                continue
            fv = " ".join(f"{f(i):02X}" for i in range(a, b + 1))
            tv = " ".join(f"{t(i):02X}" for i in range(a, b + 1))
            if fv != tv:
                lines.append(f"{label} (${a:04X}-${b:04X}): fresh {fv}, tracked {tv}")
    # everything else, by address
    rest = []
    for off in offs:
        in_last = ptr is not None and ptr <= off < ptr + SLOT_LEN
        if in_last and (0x1600 + off - ptr) in covered:
            continue
        slot = next((s for s, p in sc.SLOT_PTR.items() if p <= off < p + SLOT_LEN), None)
        if slot is not None:
            where = f"slot {slot} ${0x1600 + off - sc.SLOT_PTR[slot]:04X}"
        elif 0x2000 <= off < 0x4000:
            where = f"codex {sram_addr(off)}"
        else:
            where = f"sram {sram_addr(off)}"
        rest.append(f"{where}: fresh {fresh[off]:02X}, tracked {tracked[off]:02X}")
    lines += rest[:40]
    if len(rest) > 40:
        lines.append(f"... and {len(rest) - 40} more byte(s) by address")
    return lines


# ------------------------------------------------------------------ verbs --
def compare(key: str, fresh_root=FRESH, tracked_root=TRACKED):
    """(differing offsets, explanation lines)."""
    _, fp = sc.load(fresh_root / key)
    _, tp = sc.load(tracked_root / key)
    fb, tb = fp.read_bytes(), tp.read_bytes()
    offs = byte_diffs(fb, tb)
    return offs, (explain(fb, tb, offs) if offs else [])


def capture_problem(key: str, root=ROOT) -> str | None:
    """Why the graph's capture of `key` is not today's, or None: its record
    (build/checkpoints/<key>.stamp) asked the question `ninja` answers."""
    import stamps
    v, msg = stamps.stamp_status(f"build/checkpoints/{key}.stamp", root)
    if v is None:
        return "no capture record (build/checkpoints/<key>.stamp): run ninja"
    return None if v == stamps.FRESH else msg


def recut(key: str, fresh_root=FRESH, tracked_root=TRACKED,
          problem=capture_problem) -> None:
    """Copy the graph's sealed capture (manifest.json and payload) over the
    tracked checkpoint.  Validated first; refused when the capture is not
    today's.  A provenance sidecar the old capture path left beside a
    tracked payload is removed: the manifest carries the record."""
    src, dst = fresh_root / key, tracked_root / key
    why = problem(key)
    if why:
        raise sc.CheckpointError(f"refusing to re-cut from a capture that is "
                                 f"not today's: {why}")
    manifest, payload = sc.load(src)
    for name in ("manifest.json", payload.name):
        shutil.copyfile(src / name, dst / name)
    side = dst / (payload.name + ".provenance.json")
    if side.exists():
        side.unlink()
    sc.load(dst)


def main(argv: list[str]) -> int:
    if argv == ["--selftest"]:
        return selftest()
    strict = "--strict" in argv
    do_recut = "--recut" in argv
    keys = [a for a in argv if not a.startswith("--")]
    if not keys:
        print(__doc__.strip().split("\n\n")[4], file=sys.stderr)
        return 2
    bad = refused = 0
    for key in keys:
        try:
            if do_recut:
                recut(key)
            offs, lines = compare(key)
        except sc.CheckpointError as exc:
            print(f"checkpoint drift {key}: cannot compare -- {exc}")
            bad += 1
            refused += do_recut
            continue
        if offs:
            bad += 1
            print(f"checkpoint drift {key}: {len(offs)} byte(s) differ from the "
                  f"graph's capture (build/checkpoints/{key}):")
            for line in lines:
                print(f"  {line}")
        else:
            print(f"checkpoint drift {key}: none -- the tracked save is the "
                  f"one the graph makes today")
    if strict and bad:
        print(f"checkpoint drift: {bad} of {len(keys)} tracked checkpoint(s) "
              f"are not today's play; re-cut them from the graph's captures "
              f"and commit:\n"
              f"  python3 tools/tests/lib/checkpoint_drift.py --recut "
              + " ".join(keys))
        return 1
    if refused:
        print(f"checkpoint drift: {refused} of {len(keys)} re-cut(s) refused; "
              f"the tracked checkpoint(s) named above are unchanged")
        return 1
    return 0


def selftest() -> int:
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    base = sc.SLOT_PTR[3] - 0x1600

    def battery(**edits):
        d = bytearray(sc.SRAM_SIZE)
        d[sc._LAST_SLOT] = 3
        d[base + 0x1851] = 1                     # LOCKE in party 1
        d[base + 0x1600 + 37 + 8] = 12           # LOCKE L12
        for i in range(256):
            d[base + 0x1869 + i] = 0xFF
        d[base + 0x1869], d[base + 0x1969] = 0xE8, 40   # 40 Tonics
        for a, v in edits.items():             # a<WRAM address>: slot 3's copy
            d[base + int(a[1:], 16)] = v
        return bytes(d)

    def raw(**edits):
        """edits by payload offset (o<hex>)."""
        d = bytearray(battery())
        for a, v in edits.items():
            d[int(a[1:], 16)] = v
        return bytes(d)
    a = battery()
    check("a save is not drift against itself", byte_diffs(a, a) == [])
    pt = battery(a1863=5, a1865=7, a1FFE=1, a1FFF=2)
    offs = byte_diffs(pt, a)
    check("MUTANT play time and the checksum are drift (the replay is "
          "deterministic: no exemption)", len(offs) == 4)
    check("...and the report names them", any("play time" in l for l in
                                               explain(pt, a, offs)))
    # the reviewer's blind spots, each alone
    celes_exp = 0x1600 + 37 * 6 + 0x11           # CELES is not in the party
    offs = byte_diffs(battery(**{f"a{celes_exp:X}": 9}), a)
    lines = explain(battery(**{f"a{celes_exp:X}": 9}), a, offs)
    check("an off-party character's experience alone is drift", len(offs) == 1)
    check("...and the report names it", any("CELES exp" in l for l in lines))
    codex = raw(o2B06=1)                          # $316B06, bank $31
    offs = byte_diffs(codex, a)
    lines = explain(codex, a, offs)
    check("a codex byte alone is drift", len(offs) == 1)
    check("...and the report names it", any("codex $316B06" in l for l in lines))
    ctr = battery(a1FA5=5)
    check("an encounter counter alone is drift, named",
          any("encounter counters" in l for l in explain(ctr, a, byte_diffs(ctr, a))))
    gear = battery(a1644=2)                       # LOCKE's weapon ($1600+37+$1F)
    check("an off-diagonal gear byte is named",
          any("LOCKE gear" in l for l in explain(gear, a, byte_diffs(gear, a))))
    sp = battery(a1AA4=100)                       # LOCKE's spell table
    check("a learned spell is named",
          any("LOCKE spells learned" in l for l in explain(sp, a, byte_diffs(sp, a))))
    other = raw(o0003=1)                          # slot 1, not the last saved
    check("another slot's byte is drift, by address",
          any(l.startswith("slot 1 ") for l in explain(other, a, byte_diffs(other, a))))
    for label, e in (("a level", {"a162D": 13}), ("a bag count", {"a1969": 41}),
                     ("gil", {"a1860": 5}), ("a story switch", {"a1E83": 0x40}),
                     ("a member joining", {"a1852": 1})):
        check(f"{label} is drift", byte_diffs(battery(**e), a) != [])
    import tempfile
    import hashlib
    import json
    with tempfile.TemporaryDirectory() as td:
        t = Path(td)
        for root, data in (("fresh", battery(a162D=13)), ("tracked", battery())):
            d = t / root / "k-v1"
            d.mkdir(parents=True)
            (d / "k.sram").write_bytes(data)
            (d / "manifest.json").write_text(json.dumps({
                "schema": sc.SCHEMA, "payload": "k.sram", "size": sc.SRAM_SIZE,
                "sha256": hashlib.sha256(data).hexdigest(),
                "persistent_layout": "x",
                "provenance": {"format": sc.PROVENANCE_FORMAT,
                               "payload_sha256": hashlib.sha256(data).hexdigest(),
                               "generator_sig": "0" * 64 + " gen_selftest",
                               "ancestors": []}}))
        (t / "tracked" / "k-v1" / "k.sram.provenance.json").write_text("{}")
        offs, lines = compare("k-v1", t / "fresh", t / "tracked")
        check("the report names the drift", any("LOCKE level" in l for l in lines))
        try:
            recut("k-v1", t / "fresh", t / "tracked",
                  problem=lambda k: "its ROM moved")
            refused = False
        except sc.CheckpointError as exc:
            refused = "its ROM moved" in str(exc)
        check("MUTANT --recut refuses a capture whose record is not current",
              refused)
        check("...and leaves the tracked checkpoint alone",
              compare("k-v1", t / "fresh", t / "tracked")[0] != [])
        recut("k-v1", t / "fresh", t / "tracked", problem=lambda k: None)
        check("--recut copies a current capture over the tracked checkpoint",
              compare("k-v1", t / "fresh", t / "tracked")[0] == [])
        check("...and drops the old provenance sidecar beside it",
              not (t / "tracked" / "k-v1" / "k.sram.provenance.json").exists())
    check("a key with no capture record is refused",
          capture_problem("selftest-no-such-v1") is not None)
    check("--recut exits non-zero when it refuses (no capture to copy)",
          main(["--recut", "selftest-no-such-v1"]) == 1)
    print("checkpoint_drift selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
