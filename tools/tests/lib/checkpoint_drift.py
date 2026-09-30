#!/usr/bin/env python3
"""checkpoint_drift.py -- how far a tracked cut checkpoint has drifted from
the play the chain from power-on makes today, and the re-cut.

A cut (tools/tests/savestate_graph.py, prev= with checkpoint=) boots its leg
from the TRACKED checkpoint in tools/tests/checkpoints/<key>/.  `ninja
chain` captures and seals a fresh one at the same save into
build/checkpoints/<key>/ (savestate_ninja.py chain_plan).  This compares the
two saves, decoded from the slot each battery last saved to:

    where      the saved map and tile (field and world)
    party      who is in it, and each member's level, experience, max HP/MP
               and the six equipment slots
    gil        and every item count in the bag
    switches   every story switch that differs ($1E80-$1EFF)

Play time is left out (any replay moves it).  Usage:

    checkpoint_drift.py KEY...            report; exit 0
    checkpoint_drift.py --strict KEY...   report; exit 1 if any KEY drifted
                                          (the release gate, configure.py)
    checkpoint_drift.py --recut KEY...    copy each sealed capture over its
                                          tracked checkpoint (validated
                                          first), then report
    checkpoint_drift.py --selftest

Re-cut at every release, and during a cycle whenever the report shows a
material change (docs/TOOLING.md).  A suite that depends on a level or an
item asserts its own precondition; the contracts stay light.
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


def decode(data: bytes) -> dict:
    """The fields the report compares, out of the last-saved slot."""
    slot = data[sc._LAST_SLOT]
    ptr = sc.SLOT_PTR.get(slot)
    if ptr is None:
        raise sc.CheckpointError(f"battery byte $307ff0 reads {slot}, not a slot")

    def by(a):
        return data[ptr + (a - 0x1600)]

    def wd(a):
        return by(a) | (by(a + 1) << 8)
    out = {"where": sc.describe_saved(sc.saved_state(data))}
    party = {}
    for c in range(16):
        if by(0x1850 + c) & 7:
            o = 0x1600 + 37 * c
            party[NAMES[c]] = {
                "level": by(o + 8),
                "exp": by(o + 0x11) | (by(o + 0x12) << 8) | (by(o + 0x13) << 16),
                "max hp": wd(o + 11), "max mp": wd(o + 15),
                "gear": " ".join(f"{by(o + s):02X}" for s in range(0x1F, 0x25)),
            }
    out["party"] = party
    out["gil"] = by(0x1860) | (by(0x1861) << 8) | (by(0x1862) << 16)
    bag = {}
    for i in range(256):
        it, n = by(0x1869 + i), by(0x1969 + i)
        if it != 0xFF and n:
            bag[it] = bag.get(it, 0) + n
    out["bag"] = bag
    out["switches"] = bytes(by(a) for a in range(0x1E80, 0x1F00))
    return out


def diff(fresh: dict, tracked: dict) -> list[str]:
    """One line per differing field, 'field: fresh X, tracked Y'."""
    lines = []
    if fresh["where"] != tracked["where"]:
        lines.append(f"where: fresh {fresh['where']}, tracked {tracked['where']}")
    fp, tp = fresh["party"], tracked["party"]
    if sorted(fp) != sorted(tp):
        lines.append(f"party: fresh {' '.join(sorted(fp))}, "
                     f"tracked {' '.join(sorted(tp))}")
    for who in sorted(set(fp) & set(tp)):
        for k in ("level", "exp", "max hp", "max mp", "gear"):
            if fp[who][k] != tp[who][k]:
                lines.append(f"{who} {k}: fresh {fp[who][k]}, tracked {tp[who][k]}")
    if fresh["gil"] != tracked["gil"]:
        lines.append(f"gil: fresh {fresh['gil']}, tracked {tracked['gil']}")
    for it in sorted(set(fresh["bag"]) | set(tracked["bag"])):
        a, b = fresh["bag"].get(it, 0), tracked["bag"].get(it, 0)
        if a != b:
            lines.append(f"item ${it:02X}: fresh {a}, tracked {b}")
    for i, (a, b) in enumerate(zip(fresh["switches"], tracked["switches"])):
        for bit in range(8):
            if ((a ^ b) >> bit) & 1:
                lines.append(f"switch ${i * 8 + bit:03X}: fresh {(a >> bit) & 1}, "
                             f"tracked {(b >> bit) & 1}")
    return lines


def report(key: str, fresh_root=FRESH, tracked_root=TRACKED) -> list[str]:
    _, fp = sc.load(fresh_root / key)
    _, tp = sc.load(tracked_root / key)
    return diff(decode(fp.read_bytes()), decode(tp.read_bytes()))


def recut(key: str, fresh_root=FRESH, tracked_root=TRACKED) -> None:
    """Copy build/checkpoints/<key>/ over the tracked checkpoint: the
    manifest, the payload and its provenance sidecar, as the chain sealed
    them.  The capture is validated first; a tracked file with no fresh
    counterpart is left alone."""
    src, dst = fresh_root / key, tracked_root / key
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
        print(__doc__.strip().split("\n\n")[2], file=sys.stderr)
        return 2
    drifted = 0
    for key in keys:
        try:
            if do_recut:
                recut(key)
            lines = report(key)
        except sc.CheckpointError as exc:
            print(f"checkpoint drift {key}: cannot compare -- {exc}")
            drifted += 1
            continue
        if lines:
            drifted += 1
            print(f"checkpoint drift {key}: {len(lines)} field(s) differ from "
                  f"the chain's fresh capture (build/checkpoints/{key}):")
            for line in lines:
                print(f"  {line}")
        else:
            print(f"checkpoint drift {key}: none -- the tracked save is the "
                  f"one the chain makes today")
    if strict and drifted:
        print(f"checkpoint drift: {drifted} of {len(keys)} tracked checkpoint(s) "
              f"differ from today's play; re-cut them before releasing:\n"
              f"  python3 tools/tests/lib/checkpoint_drift.py --recut "
              + " ".join(keys))
        return 1
    return 0


def selftest() -> int:
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    def battery(**edits):
        d = bytearray(sc.SRAM_SIZE)
        d[sc._LAST_SLOT] = 3
        base = sc.SLOT_PTR[3] - 0x1600
        d[base + 0x1851] = 1                     # LOCKE in party 1
        d[base + 0x1600 + 37 + 8] = 12           # LOCKE L12
        for i in range(256):
            d[base + 0x1869 + i] = 0xFF
        d[base + 0x1869], d[base + 0x1969] = 0xE8, 40   # 40 Tonics
        for a, v in edits.items():
            d[base + int(a[1:], 16)] = v
        return bytes(d)
    a = decode(battery())
    check("a save compares equal to itself", diff(a, a) == [])
    check("a level is a drift",
          any("LOCKE level" in l for l in diff(decode(battery(a162D=13)), a)))
    check("a bag count is a drift",
          any("item $E8" in l for l in diff(decode(battery(a1969=41)), a)))
    check("gil is a drift",
          any(l.startswith("gil") for l in diff(decode(battery(a1860=5)), a)))
    check("a story switch is a drift (switch $01E is bit 6 of $1E83)",
          any("switch $01E" in l for l in diff(decode(battery(a1E83=0x40)), a)))
    check("a member joining is a drift",
          any(l.startswith("party") for l in diff(decode(battery(a1852=1)), a)))
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        t = Path(td)
        for root, data in (("fresh", battery(a162D=13)), ("tracked", battery())):
            d = t / root / "k-v1"
            d.mkdir(parents=True)
            (d / "k.sram").write_bytes(data)
            import hashlib
            import json
            (d / "manifest.json").write_text(json.dumps({
                "schema": sc.SCHEMA, "payload": "k.sram", "size": sc.SRAM_SIZE,
                "sha256": hashlib.sha256(data).hexdigest(),
                "persistent_layout": "x",
                "provenance": {"format": sc.PROVENANCE_FORMAT,
                               "payload_sha256": hashlib.sha256(data).hexdigest(),
                               "generator_sig": "0" * 64 + " gen_selftest",
                               "ancestors": []}}))
            (d / "k.sram.provenance.json").write_text("{}")
        check("the report names the drift",
              any("LOCKE level" in l for l in report("k-v1", t / "fresh", t / "tracked")))
        recut("k-v1", t / "fresh", t / "tracked")
        check("a re-cut leaves no drift", report("k-v1", t / "fresh", t / "tracked") == [])
    print("checkpoint_drift selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
