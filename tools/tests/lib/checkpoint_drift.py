#!/usr/bin/env python3
"""checkpoint_drift.py -- how far a tracked checkpoint has drifted from the
play the graph makes today, and the re-cut.

The savestate graph (tools/tests/savestate_graph.py) is played once from
power-on: at a cut (prev= with checkpoint=), the run before it saves through
the real Save UI and its battery is captured and sealed into
build/checkpoints/<key>/ (savestate_ninja.py), and the next leg Continues
that capture.  The capture comes from the run of prev's state, from a
cutter= script booted from it, or, for a frontier checkpoint nothing boots
yet, from the state whose entry says saves=.  The tracked checkpoint in
tools/tests/checkpoints/<key>/ is the committed copy of that capture;
nothing in the graph boots it.

The verdict is byte for byte: the play is deterministic, so a tracked
battery that is today's play is the fresh capture's bytes.  Only each save
slot's play time ($1863-$1865) and checksum ($1FFE-$1FFF) are left out.
Anything else that differs -- a slot, the OT6 codex in bank $31, the
battery's own bytes -- is drift.

The report explains a drift in play terms, decoded from the last-saved slot:
where the save is; all sixteen character records (level, experience, max
HP/MP, gear, the rest of the record) and party/row bytes; gil and the bag;
story switches; the encounter counters ($1FA1-$1FA5); espers, spells,
SwdTech, Blitz, Lore, Rage and Dance; then every remaining differing slot
byte, other slot, codex byte and battery byte by address.

A capture is only compared or copied while it is today's: the run that made
it is current -- for a producer's run, its stamp (build/states/<state>.stamp)
verifies by the same rule as every fixture (compose.py stamp_status: the
ROM, the emulator pin, the generator, the artifact and what it booted,
transitively), and its sig line is the one the capture recorded; for a
cutter, its record (build/checkpoints/<key>.record) names this ROM, today's
cutter, the capture's payload and a current stamp for the state it booted.
A moved lib half is provenance drift there as everywhere in the graph
(#363): it does not stale a capture.

    checkpoint_drift.py KEY...            report; exit 0
    checkpoint_drift.py --strict KEY...   report; exit 1 if any KEY drifted
                                          or its capture is stale (the
                                          release gate, configure.py)
    checkpoint_drift.py --recut KEY...    copy each sealed capture over its
                                          tracked checkpoint (refused when
                                          stale), then report
    checkpoint_drift.py --selftest

Re-cut at every release, and during a cycle whenever the report shows a
material change (docs/TOOLING.md).  A suite that depends on a level or an
item asserts its own precondition; the contracts stay light.
"""

from __future__ import annotations

import shutil
import subprocess
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
SKIP_IN_SLOT = (0x1863, 0x1864, 0x1865, 0x1FFE, 0x1FFF)   # play time, checksum


def skipped_offsets() -> set[int]:
    out = set()
    for ptr in set(sc.SLOT_PTR.values()):
        for a in SKIP_IN_SLOT:
            out.add(ptr + a - 0x1600)
    return out


SKIP = skipped_offsets()


def byte_diffs(fresh: bytes, tracked: bytes) -> list[int]:
    """Payload offsets that differ, play time and checksums left out."""
    return [i for i in range(sc.SRAM_SIZE)
            if fresh[i] != tracked[i] and i not in SKIP]


def sram_addr(off: int) -> str:
    return f"${0x30 + off // 0x2000:02X}{0x6000 + off % 0x2000:04X}"


# ---------------------------------------------------------- the explanation --
# Named ranges of a slot's WRAM copy: (first, last, label).  Anything a
# report finds outside them is listed by address.
CHAR_LEN = 37
RANGES = [(0x1600, 0x1600 + 16 * CHAR_LEN - 1, "character records"),
          (0x1850, 0x185F, "party/row bytes"),
          (0x1860, 0x1862, "gil"),
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
          (0x1FA1, 0x1FA5, "encounter counters")]


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


# ---------------------------------------------------- is the capture today's --
def stamp_tool(*args) -> str:
    r = subprocess.run(["sh", str(HERE / "savestate_stamp.sh"), *args],
                       capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        raise sc.CheckpointError(f"savestate_stamp.sh {' '.join(args)}: "
                                 f"{r.stderr.strip()}")
    return r.stdout.strip()


def producer_record(key: str, root: Path = ROOT) -> Path | None:
    """The record of the run that saves `key` (savestate_ninja.py
    producers): build/states/<state>.stamp of the state whose run saves it,
    or build/checkpoints/<key>.record for a cutter, which publishes no
    state.  None when no run on the graph saves `key`."""
    import savestate_ninja as sn
    run = sn.producers(sn.load(root)).get(key)
    if run is None:
        return None
    return root / sn.capture_record(key, run)


# One verdict per stamp per process: every capture's check walks its
# producer's ancestry from power-on, and the 38 keys share it.
_STATUS_MEMO: dict = {}


def stale_reason(key: str, fresh_root=FRESH, root: Path = ROOT) -> str | None:
    """Why the capture in fresh_root/key is not today's, or None."""
    import compose
    import savestate_ninja as sn
    manifest, payload = sc.load(fresh_root / key)
    prov = manifest.get("provenance")
    if not isinstance(prov, dict):
        return "it carries no mechanical provenance"
    run = sn.producers(sn.load(root)).get(key)
    if run is None:
        return "no run on the savestate graph saves it"
    record = root / sn.capture_record(key, run)
    if not record.exists():
        return f"{record.relative_to(root)}, the record of the run that captured it, is missing"
    lines = record.read_text().splitlines()
    ok = (compose.FRESH, compose.DRIFT)
    if run[0] == "run":
        state = run[1]
        if not lines or lines[0].strip() != prov.get("generator_sig", ""):
            return (f"build/states/{state}.stamp does not record the run that "
                    f"captured it (the stamp's sig and the capture's "
                    f"generator_sig differ): regenerate {state}")
        verdict, msg = compose.stamp_status(state, root, _STATUS_MEMO)
        if verdict not in ok:
            return f"the run that captured it is not current: {msg}"
        return None
    _, gen, boot = run
    fields = {}
    for line in lines:
        parts = line.split()
        if parts:
            fields[parts[0]] = parts[1:]
    now_rom = stamp_tool("romsig")
    if fields.get("rom") != [now_rom]:
        return (f"its cutter {gen} ran on ROM "
                f"{str((fields.get('rom') or ['?'])[0])[:12]} and this tree's "
                f"is {now_rom[:12]}")
    now_gen = stamp_tool("gensig", gen)
    if fields.get("generator") != [now_gen]:
        return f"its cutter {gen} changed since it ran"
    import hashlib
    if fields.get("payload") != [hashlib.sha256(payload.read_bytes()).hexdigest()]:
        return f"the payload is not the one its cutter {gen} recorded"
    anc = fields.get("ancestor") or []
    stamp = root / f"build/states/{boot}.stamp"
    if (len(anc) != 2 or anc[0] != f"build/states/{boot}.stamp"
            or not stamp.exists()
            or hashlib.sha256(stamp.read_bytes()).hexdigest() != anc[1]):
        return (f"its cutter {gen} booted a {boot} that has since moved; "
                f"capture it again")
    verdict, msg = compose.stamp_status(boot, root, _STATUS_MEMO)
    if verdict not in ok:
        return f"the state its cutter booted is not current: {msg}"
    return None


# ------------------------------------------------------------------ verbs --
def compare(key: str, fresh_root=FRESH, tracked_root=TRACKED):
    """(differing offsets, explanation lines)."""
    _, fp = sc.load(fresh_root / key)
    _, tp = sc.load(tracked_root / key)
    fb, tb = fp.read_bytes(), tp.read_bytes()
    offs = byte_diffs(fb, tb)
    return offs, (explain(fb, tb, offs) if offs else [])


def recut(key: str, fresh_root=FRESH, tracked_root=TRACKED) -> None:
    """Copy build/checkpoints/<key>/ over the tracked checkpoint: the
    manifest, the payload and its provenance sidecar, as the chain sealed
    them.  Validated first; refused when the capture is not today's."""
    src, dst = fresh_root / key, tracked_root / key
    why = stale_reason(key, fresh_root)
    if why:
        raise sc.CheckpointError(f"refusing to re-cut from a stale capture: {why}")
    manifest, payload = sc.load(src)
    for name in ("manifest.json", payload.name, payload.name + ".provenance.json"):
        shutil.copyfile(src / name, dst / name)
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
            why = stale_reason(key) if (strict or do_recut) else None
            offs, lines = compare(key)
        except sc.CheckpointError as exc:
            print(f"checkpoint drift {key}: cannot compare -- {exc}")
            bad += 1
            refused += do_recut
            continue
        if why:
            bad += 1
            print(f"checkpoint drift {key}: the capture is stale -- {why}; "
                  f"run `ninja` first")
            continue
        if offs:
            bad += 1
            print(f"checkpoint drift {key}: {len(offs)} byte(s) differ from the "
                  f"fresh capture (build/checkpoints/{key}), play time "
                  f"and checksums aside:")
            for line in lines:
                print(f"  {line}")
        else:
            print(f"checkpoint drift {key}: none -- the tracked save is the "
                  f"one the graph's play makes today")
    if strict and bad:
        print(f"checkpoint drift: {bad} of {len(keys)} tracked checkpoint(s) "
              f"are not today's play; run `ninja`, then re-cut them "
              f"before releasing:\n"
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
    offs = byte_diffs(battery(a1863=5, a1865=7, a1FFE=1, a1FFF=2), a)
    check("play time and the checksum are not drift", offs == [])
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
            (d / "k.sram.provenance.json").write_text("{}")
        offs, lines = compare("k-v1", t / "fresh", t / "tracked")
        check("the report names the drift", any("LOCKE level" in l for l in lines))
        why = stale_reason("k-v1", t / "fresh")
        check("a capture no run on the graph saves is stale",
              why == "no run on the savestate graph saves it")
        try:
            recut("k-v1", t / "fresh", t / "tracked")
            refused = False
        except sc.CheckpointError:
            refused = True
        check("--recut refuses a stale capture", refused)
    # where each capture's record lives, on this tree's graph: the stamp of
    # the state whose run saved it, or a cutter's own record (it publishes
    # no state)
    rec = {k: producer_record(k) for k in ("wor-tomb-v1", "post-opera-v1",
                                           "wor-falcon-v1")}
    check("a WoR leg's capture is recorded by the state whose run saved it",
          str(rec["wor-tomb-v1"]).endswith("build/states/wor_tomb.stamp"))
    check("a cutter's capture is recorded beside it",
          str(rec["post-opera-v1"]).endswith("build/checkpoints/post-opera-v1.record"))
    check("the frontier's capture is recorded by its saves= state",
          str(rec["wor-falcon-v1"]).endswith("build/states/wor_falcon.stamp"))
    check("a checkpoint no run saves has no record",
          producer_record("negative-stale-check-v1") is None)
    check("--recut exits non-zero when it refuses (no capture to copy)",
          main(["--recut", "selftest-no-such-v1"]) == 1)
    print("checkpoint_drift selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
