#!/usr/bin/env python3
"""Validate and materialize OT6's small, versioned battery-save checkpoints.

PROVENANCE.  A checkpoint's `provenance` field records the ancestry of the
chain of generated savestates above it, as a dict:

    "provenance": {
      "format": "ot6-provenance/v1",
      "payload_sha256": "<sha256 of the .sram bytes>",
      "generator_sig": "<sig> <gen> [extras]",     # savestate_stamp.sh sig of the
                                              # generator that drove the
                                              # capture run, verbatim
      "ancestors": [                          # what the capture run booted:
        {"path": "build/states/x.stamp",      # the stamp of each embedded
         "sha256": "<sha256 of that file>"},  # state, and/or the manifest of
        ...                                   # the checkpoint it Continued from
      ]
    }

run.sh's OT6_CAPTURE_SRM mode writes this object to
`<payload>.provenance.json` beside the captured battery.  `seal CHECKPOINT`
folds the sidecar into manifest.json and recomputes size/sha256.

A manifest whose `provenance` is prose (or absent) is LEGACY-V0:
grandfathered with a warning on stderr, never a failure.  A manifest whose
`provenance` is a dict is verified at load, before every boot that
materializes it: format string, payload hash agreement, well-formed sig and
ancestor records.  Malformed mechanical provenance fails closed; only the
explicitly-legacy shape is excused.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

SCHEMA = "ot6.sram-checkpoint/v1"
# Must match savestate_stamp.sh's GATE_CONTRACT.
PROVENANCE_FORMAT = "ot6-provenance/v1"
SRAM_SIZE = 32768
_HEX64 = re.compile(r"[0-9a-f]{64}")

# CopyGameDataToSRAM (ff6/src/menu/save.asm:42) copies WRAM $1600-$1FFF into
# $306000 + SRAMSlotPtrs[slot].  In the 32 KiB battery file that is offset
# 0x0000 for bank $30's $6000-$7FFF window, so:
#   payload[0x1ff0]                   = the slot the game last saved to
#   payload[SLOT_PTR[slot] + (a - 0x1600)] = that slot's copy of WRAM a
SLOT_PTR = {1: 0x0000, 2: 0x0A00, 3: 0x1400}
_LAST_SLOT = 0x1FF0


def saved_state(data: bytes) -> dict:
    """What save the battery holds, decoded from the payload bytes alone."""
    slot = data[_LAST_SLOT]
    ptr = SLOT_PTR.get(slot)
    if ptr is None:
        raise CheckpointError(
            f"battery byte $307ff0 reads {slot}, not a save slot 1..3")

    def by(addr: int) -> int:
        return data[ptr + (addr - 0x1600)]

    word = by(0x1F64) | (by(0x1F65) << 8)
    return {"slot": slot, "map_word": word, "map": word & 0x1FF,
            "x": by(0x1FC0), "y": by(0x1FC1),
            "world_x": by(0x1F60), "world_y": by(0x1F61)}


def describe_saved(s: dict) -> str:
    if s["map"] == 0:
        return (f"slot {s['slot']} world ({s['world_x']},{s['world_y']}) "
                f"[$1F64=${s['map_word']:04X}]")
    return (f"slot {s['slot']} map {s['map']} ({s['x']},{s['y']}) "
            f"[$1F64=${s['map_word']:04X}]")


def saved_problem(declared, data: bytes) -> str | None:
    """Why the battery does not hold the save the manifest declares.

    `saved` is authored beside the payload, not derived from it: it says
    which save the checkpoint is FOR, so a generator whose save step was
    skipped (leaving an older save in the slot) cannot be sealed and
    committed as this checkpoint.  Shape:

        "saved": {"slot": 3, "field": {"map": 88, "x": 11, "y": 34}}
        "saved": {"slot": 3, "world": {"x": 249, "y": 128}}
    """
    if not isinstance(declared, dict):
        return f"saved must be an object, not {type(declared).__name__}"
    keys = set(declared) - {"slot"}
    if keys not in ({"field"}, {"world"}):
        return ("saved must carry exactly one of 'field' or 'world' "
                f"(got {sorted(declared)})")
    actual = saved_state(data)
    slot = declared.get("slot")
    if slot is not None and slot != actual["slot"]:
        return (f"saved declares slot {slot}, but the battery's $307ff0 "
                f"names slot {actual['slot']}")
    if "field" in declared:
        want = declared["field"]
        if not isinstance(want, dict) or set(want) != {"map", "x", "y"}:
            return "saved.field must be {map, x, y}"
        if want["map"] == 0:
            return ("saved.field map 0 is how a WORLD save encodes; declare "
                    "'world' instead")
        if actual["map"] == 0:
            return (f"saved.field declares map {want['map']}, but the "
                    f"battery holds {describe_saved(actual)}")
        got = (actual["map"], actual["x"], actual["y"])
        if got != (want["map"], want["x"], want["y"]):
            return (f"saved.field declares map {want['map']} "
                    f"({want['x']},{want['y']}), but the battery holds "
                    f"{describe_saved(actual)}")
    else:
        want = declared["world"]
        if not isinstance(want, dict) or set(want) != {"x", "y"}:
            return "saved.world must be {x, y}"
        if actual["map"] != 0:
            return (f"saved.world declares a world save, but the battery "
                    f"holds {describe_saved(actual)}")
        if (actual["world_x"], actual["world_y"]) != (want["x"], want["y"]):
            return (f"saved.world declares ({want['x']},{want['y']}), but "
                    f"the battery holds {describe_saved(actual)}")
    return None


class CheckpointError(ValueError):
    pass


def provenance_problem(prov: dict, payload_sha256: str) -> str | None:
    """Why `prov` is not a valid mechanical provenance record, or None.

    Shape-checks every field and cross-checks the one hash that is locally
    checkable (the payload's).  Ancestor files are not re-read here: the
    record documents what the capture run saw in its own tree, and the
    consuming tree's build/states changes on every regeneration.
    """
    if prov.get("format") != PROVENANCE_FORMAT:
        return (f"provenance format {prov.get('format')!r} is not "
                f"{PROVENANCE_FORMAT!r}")
    if prov.get("payload_sha256") != payload_sha256:
        return "provenance payload_sha256 does not match the payload bytes"
    sig = prov.get("generator_sig")
    if not isinstance(sig, str) or len(sig.split()) < 2 \
            or not _HEX64.fullmatch(sig.split()[0]):
        return f"provenance generator_sig {sig!r} is not '<64-hex> <gen> ...'"
    ancestors = prov.get("ancestors")
    if not isinstance(ancestors, list):
        return "provenance ancestors is not a list"
    for a in ancestors:
        if not isinstance(a, dict) or not isinstance(a.get("path"), str) \
                or not a["path"] or a["path"].startswith("/") \
                or ".." in a["path"] \
                or not isinstance(a.get("sha256"), str) \
                or not _HEX64.fullmatch(a["sha256"]):
            return f"provenance ancestor record {a!r} is malformed"
    return None


def load(checkpoint: Path, expected_layout: str | None = None) -> tuple[dict, Path]:
    """Validate a checkpoint directory; return (manifest, payload path).

    expected_layout is the persistent-SRAM layout string the consuming step
    declares support for.  None means structural checks only.  Any other
    value must match the manifest's persistent_layout exactly.
    """
    manifest_path = checkpoint / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise CheckpointError(f"cannot read {manifest_path}: {exc}") from exc
    if manifest.get("schema") != SCHEMA:
        raise CheckpointError(f"unsupported schema {manifest.get('schema')!r}")
    payload_name = manifest.get("payload")
    if not isinstance(payload_name, str) or Path(payload_name).name != payload_name:
        raise CheckpointError("payload must be one plain filename")
    payload = checkpoint / payload_name
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise CheckpointError(f"cannot read payload: {exc}") from exc
    if manifest.get("size") != SRAM_SIZE or len(data) != SRAM_SIZE:
        raise CheckpointError(
            f"SRAM size mismatch: manifest={manifest.get('size')!r}, actual={len(data)}"
        )
    actual = hashlib.sha256(data).hexdigest()
    if manifest.get("sha256") != actual:
        raise CheckpointError("payload SHA-256 mismatch")
    layout = manifest.get("persistent_layout")
    if not isinstance(layout, str) or not layout:
        # Fail closed: a checkpoint without a layout string can never be
        # refused by version.
        raise CheckpointError(f"{manifest_path} declares no persistent_layout")
    if expected_layout is not None and layout != expected_layout:
        raise CheckpointError(
            f"persistent_layout mismatch: checkpoint {checkpoint} declares "
            f"{layout!r}, but this step declares support for "
            + (f"{expected_layout!r}" if expected_layout
               else "NO layout (no 'OT6_CHECKPOINT_LAYOUT:' marker in the "
                    "script; a step that consumes an checkpoint must declare "
                    "the layout it understands)")
        )
    # What save the battery holds, if the manifest says which one it should
    # (#218).  Decided from the payload bytes, so a checkpoint whose
    # generator skipped its save is refused here rather than booted.
    declared = manifest.get("saved")
    if declared is not None:
        problem = saved_problem(declared, data)
        if problem:
            raise CheckpointError(f"{manifest_path}: {problem}")
    # A mechanical record is verified here, before any boot; a prose one is
    # grandfathered with a warning.
    prov = manifest.get("provenance")
    if isinstance(prov, dict):
        problem = provenance_problem(prov, actual)
        if problem:
            raise CheckpointError(f"{manifest_path}: {problem}")
    else:
        print(
            f"sram checkpoint: WARNING: {checkpoint} carries legacy-v0 provenance "
            f"(prose, nothing mechanically verifiable).  Grandfathered "
            f"under issue #75 -- the burn-down is re-cutting it from real "
            f"play (capture run, then `sram_checkpoint.py seal`), not editing "
            f"the manifest.",
            file=sys.stderr,
        )
    return manifest, payload


def capture(root: Path, out: Path, payload: Path, generator_sig: str,
            ancestors: list[str]) -> None:
    """Write the mechanical provenance sidecar for a just-captured battery.
    `ancestors` are tree-relative paths, hashed against `root`."""
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise CheckpointError(f"cannot read captured payload: {exc}") from exc
    rec: dict = {"format": PROVENANCE_FORMAT,
                 "payload_sha256": hashlib.sha256(data).hexdigest(),
                 "generator_sig": generator_sig,
                 "ancestors": []}
    for rel in ancestors:
        try:
            blob = (root / rel).read_bytes()
        except OSError as exc:
            raise CheckpointError(f"cannot read ancestor {rel}: {exc}") from exc
        rec["ancestors"].append(
            {"path": rel, "sha256": hashlib.sha256(blob).hexdigest()})
    problem = provenance_problem(rec, rec["payload_sha256"])
    if problem:
        raise CheckpointError(f"refusing to write a bad sidecar: {problem}")
    out.write_text(json.dumps(rec, indent=2) + "\n")


def seal(checkpoint: Path) -> None:
    """Fold a capture's provenance sidecar into the checkpoint's manifest.
    Verifies the sidecar against the payload, recomputes size/sha256, and
    writes `provenance`; other authored fields pass through untouched."""
    manifest_path = checkpoint / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise CheckpointError(f"cannot read {manifest_path}: {exc}") from exc
    payload_name = manifest.get("payload")
    if not isinstance(payload_name, str) or Path(payload_name).name != payload_name:
        raise CheckpointError("payload must be one plain filename")
    payload = checkpoint / payload_name
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise CheckpointError(f"cannot read payload: {exc}") from exc
    if len(data) != SRAM_SIZE:
        raise CheckpointError(f"payload is {len(data)} bytes, not {SRAM_SIZE}")
    sidecar = checkpoint / (payload_name + ".provenance.json")
    try:
        prov = json.loads(sidecar.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise CheckpointError(
            f"cannot read {sidecar}: {exc} -- a seal needs the capture "
            f"run's sidecar (run.sh OT6_CAPTURE_SRM writes it beside the "
            f"payload); there is deliberately no way to author one by hand"
        ) from exc
    actual = hashlib.sha256(data).hexdigest()
    problem = provenance_problem(prov, actual) if isinstance(prov, dict) \
        else "sidecar is not a JSON object"
    if problem:
        raise CheckpointError(f"{sidecar}: {problem}")
    # #218: never seal a payload that does not hold the save the manifest is
    # named for.  The declaration is authored; the bytes decide.
    declared = manifest.get("saved")
    if declared is not None:
        problem = saved_problem(declared, data)
        if problem:
            raise CheckpointError(f"{manifest_path}: {problem}")
    manifest["size"] = SRAM_SIZE
    manifest["sha256"] = actual
    manifest["provenance"] = prov
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


def materialize(checkpoint: Path, destination: Path,
                expected_layout: str | None = None) -> None:
    _, payload = load(checkpoint, expected_layout)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=destination.name + ".", dir=destination.parent)
    os.close(fd)
    try:
        shutil.copyfile(payload, temporary)
        os.replace(temporary, destination)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def selftest() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        payload = bytes(range(256)) * 128
        (root / "save.srm").write_bytes(payload)
        # The positive-control manifest carries mechanical provenance built
        # by the real capture path.
        (root / "ancestor.stamp").write_text("sig gen\nartifact ab\n")
        capture(root, root / "save.srm.provenance.json", root / "save.srm",
                "ab" * 32 + " gen_cut extras", ["ancestor.stamp"])
        rec = json.loads((root / "save.srm.provenance.json").read_text())
        assert rec["payload_sha256"] == hashlib.sha256(payload).hexdigest(), \
            "capture hashed the wrong payload bytes"
        assert rec["ancestors"][0]["sha256"] == hashlib.sha256(
            (root / "ancestor.stamp").read_bytes()).hexdigest(), \
            "capture hashed the wrong ancestor bytes"
        base = {
            "schema": SCHEMA,
            "payload": "save.srm",
            "size": SRAM_SIZE,
            "sha256": hashlib.sha256(payload).hexdigest(),
            "persistent_layout": "ot6-test-layout/v1",
            "provenance": rec,
        }
        (root / "manifest.json").write_text(json.dumps(base))
        load(root)
        load(root, "ot6-test-layout/v1")   # a step that declares support
        out = root / "out.srm"
        materialize(root, out, "ot6-test-layout/v1")
        assert out.read_bytes() == payload

        for field, bad in (
            ("schema", "ot6.sram-checkpoint/v99"),
            ("size", 8192),
            ("sha256", "0" * 64),
            ("payload", "../save.srm"),
            ("persistent_layout", ""),      # empty layout: fail closed
            ("persistent_layout", None),    # json null, same
        ):
            broken = dict(base)
            broken[field] = bad
            (root / "manifest.json").write_text(json.dumps(broken))
            try:
                load(root)
            except CheckpointError:
                pass
            else:
                raise AssertionError(f"negative validation accepted bad {field}")

        # A layout mismatch must refuse and name both strings.
        (root / "manifest.json").write_text(json.dumps(base))
        for expected, must_name in (
            ("ot6-test-layout/v2", ["ot6-test-layout/v1", "ot6-test-layout/v2"]),
            ("", ["ot6-test-layout/v1", "NO layout"]),
        ):
            try:
                load(root, expected)
            except CheckpointError as exc:
                for needle in must_name:
                    assert needle in str(exc), (
                        f"layout refusal does not name {needle!r}: {exc}")
            else:
                raise AssertionError(
                    f"layout check accepted expected={expected!r} against "
                    f"checkpoint layout 'ot6-test-layout/v1'")

        # ---- provenance -----------------------------------------------
        import contextlib
        import io

        def load_warns(checkpoint: Path) -> str:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                load(checkpoint)
            return err.getvalue()

        # 1. a mechanical record loads with no output; legacy prose (or no
        #    provenance at all) is grandfathered but warns.
        (root / "manifest.json").write_text(json.dumps(base))
        assert load_warns(root) == "", (
            "a mechanically-provenanced checkpoint must load silently")
        stripped = {k: v for k, v in base.items() if k != "provenance"}
        for legacy in (dict(stripped, provenance="cut by hand, trust me"),
                       stripped):
            (root / "manifest.json").write_text(json.dumps(legacy))
            warned = load_warns(root)
            assert "legacy-v0" in warned and "issue #75" in warned, (
                f"legacy checkpoint did not warn loudly: {warned!r}")

        # 2. seal folds the capture sidecar into the manifest, recomputing
        #    the payload hash.
        (root / "manifest.json").write_text(json.dumps(stripped))
        seal(root)
        sealed = json.loads((root / "manifest.json").read_text())
        assert sealed["provenance"] == rec, "seal did not fold the sidecar in"
        assert sealed["sha256"] == base["sha256"], "seal recompute wrong"
        assert sealed["persistent_layout"] == "ot6-test-layout/v1", (
            "seal must pass authored fields through untouched")
        assert load_warns(root) == "", "a sealed checkpoint must load silently"

        # 3. malformed mechanical provenance fails closed; only the
        #    explicitly-legacy prose shape is excused, never a bad record.
        for tweak, why in (
            ({"format": "ot6-provenance/v99"}, "unknown format"),
            ({"payload_sha256": "0" * 64}, "payload hash mismatch"),
            ({"generator_sig": "not-a-sig"}, "malformed generator_sig"),
            ({"generator_sig": "f" * 64}, "sig with no generator name"),
            ({"ancestors": "nope"}, "ancestors not a list"),
            ({"ancestors": [{"path": "/abs", "sha256": "0" * 64}]},
             "absolute ancestor path"),
            ({"ancestors": [{"path": "x", "sha256": "short"}]},
             "bad ancestor hash"),
        ):
            bad = dict(base, provenance=dict(rec, **tweak))
            (root / "manifest.json").write_text(json.dumps(bad))
            try:
                load(root)
            except CheckpointError:
                pass
            else:
                raise AssertionError(f"bad provenance accepted: {why}")

        # 4. seal only trusts a sidecar that matches the payload as it is
        #    now: a payload swapped after capture is refused, not accepted.
        (root / "manifest.json").write_text(json.dumps(base))
        (root / "save.srm").write_bytes(bytes(SRAM_SIZE))
        try:
            seal(root)
        except CheckpointError:
            pass
        else:
            raise AssertionError("seal accepted a payload the sidecar "
                                 "never hashed")

        # ---- the `saved` declaration (#218) ----------------------------
        # A battery built by hand to hold a known slot-3 field save at map
        # 88 (11,34): the declaration must accept that and refuse anything
        # else, including the wrong map, the wrong tile, the wrong slot and
        # a world-save claim.
        def battery(slot: int, mapword: int, x: int, y: int,
                    wx: int = 0, wy: int = 0) -> bytes:
            b = bytearray(SRAM_SIZE)
            b[_LAST_SLOT] = slot
            p = SLOT_PTR[slot]
            b[p + (0x1F64 - 0x1600)] = mapword & 0xFF
            b[p + (0x1F65 - 0x1600)] = (mapword >> 8) & 0xFF
            b[p + (0x1FC0 - 0x1600)] = x
            b[p + (0x1FC1 - 0x1600)] = y
            b[p + (0x1F60 - 0x1600)] = wx
            b[p + (0x1F61 - 0x1600)] = wy
            return bytes(b)

        field = battery(3, 88, 11, 34)
        assert saved_state(field) == {
            "slot": 3, "map_word": 88, "map": 88, "x": 11, "y": 34,
            "world_x": 0, "world_y": 0}, "saved_state decoded the wrong cells"
        world = battery(3, 0x2000, 29, 15, 249, 128)
        assert saved_state(world)["map"] == 0, "world save decoded as a field"

        good = {"slot": 3, "field": {"map": 88, "x": 11, "y": 34}}
        assert saved_problem(good, field) is None, \
            "the declaration refused the battery it describes"
        assert saved_problem({"slot": 3, "world": {"x": 249, "y": 128}},
                             world) is None, "world declaration refused"
        for decl, blob, why in (
            ({"slot": 3, "field": {"map": 103, "x": 57, "y": 8}}, field,
             "the wrong map (#218's actual failure: the Kolts summit save)"),
            ({"slot": 3, "field": {"map": 88, "x": 11, "y": 35}}, field,
             "the wrong tile"),
            ({"slot": 2, "field": {"map": 88, "x": 11, "y": 34}}, field,
             "the wrong slot"),
            ({"slot": 3, "world": {"x": 11, "y": 34}}, field,
             "a world claim over a field save"),
            ({"slot": 3, "field": {"map": 0, "x": 29, "y": 15}}, world,
             "a field claim over a world save"),
            ({"slot": 3}, field, "neither field nor world"),
            ({"slot": 3, "field": {"map": 88}}, field, "an incomplete field"),
            ("map 88", field, "a prose declaration"),
        ):
            assert saved_problem(decl, blob) is not None, \
                f"saved declaration accepted {why}"

        # and end to end: load()/seal() refuse a manifest whose `saved`
        # block does not match the payload, and pass one that does.
        (root / "save.srm").write_bytes(field)
        capture(root, root / "save.srm.provenance.json", root / "save.srm",
                "ab" * 32 + " gen_cut extras", ["ancestor.stamp"])
        rec2 = json.loads((root / "save.srm.provenance.json").read_text())
        saved_base = dict(base, sha256=hashlib.sha256(field).hexdigest(),
                          provenance=rec2, saved=good)
        (root / "manifest.json").write_text(json.dumps(saved_base))
        load(root)
        seal(root)
        bad = dict(saved_base,
                   saved={"slot": 3, "field": {"map": 103, "x": 57, "y": 8}})
        (root / "manifest.json").write_text(json.dumps(bad))
        for fn, name in ((load, "load"), (seal, "seal")):
            try:
                fn(root)
            except CheckpointError as exc:
                assert "saved.field" in str(exc), \
                    f"{name} refusal does not name the saved block: {exc}"
            else:
                raise AssertionError(
                    f"{name} accepted a battery holding a save the manifest "
                    f"does not declare")

        print("sram_checkpoint selftest: PASS (schema, size, hash, path, "
              "persistent_layout negatives; provenance capture/seal "
              "round-trip, legacy-v0 warning, malformed-record refusals; "
              "saved-block decode and load/seal refusals)")


def main(argv: list[str]) -> int:
    try:
        if argv == ["selftest"]:
            selftest()
        elif len(argv) in (2, 3) and argv[0] == "validate":
            # The optional third argument is the consuming step's declared
            # persistent_layout; absent means structural checks only.
            manifest, payload = load(Path(argv[1]),
                                     argv[2] if len(argv) == 3 else None)
            prov = manifest.get("provenance")
            # Always say what save the battery holds (#218): a checkpoint
            # that does not yet declare `saved` still prints it, so a wrong
            # save is visible to whoever runs validate.
            held = describe_saved(saved_state(payload.read_bytes()))
            print(
                f"valid {manifest['schema']}: {manifest['size']} bytes "
                f"sha256={manifest['sha256']} "
                f"persistent_layout={manifest['persistent_layout']} "
                f"provenance="
                + (PROVENANCE_FORMAT if isinstance(prov, dict)
                   else "legacy-v0")
                + f" holds={held}"
                + (" (saved: declared and checked)"
                   if manifest.get("saved") is not None
                   else " (saved: undeclared)")
            )
        elif len(argv) in (3, 4) and argv[0] == "materialize":
            materialize(Path(argv[1]), Path(argv[2]),
                        argv[3] if len(argv) == 4 else None)
        elif len(argv) >= 5 and argv[0] == "capture":
            capture(Path(argv[1]), Path(argv[2]), Path(argv[3]), argv[4],
                    argv[5:])
        elif len(argv) == 2 and argv[0] == "seal":
            seal(Path(argv[1]))
        else:
            print(
                "usage: sram_checkpoint.py validate CHECKPOINT [LAYOUT] | "
                "materialize CHECKPOINT DEST [LAYOUT] | "
                "capture ROOT OUT_JSON PAYLOAD GENERATOR_SIG [ANCESTOR_REL...] | "
                "seal CHECKPOINT | selftest",
                file=sys.stderr,
            )
            return 2
    except CheckpointError as exc:
        print(f"sram checkpoint: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
