#!/usr/bin/env python3
"""Validate and materialize OT6's small, versioned battery-save anchors."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

SCHEMA = "ot6.sram-anchor/v1"
SRAM_SIZE = 32768


class AnchorError(ValueError):
    pass


def load(anchor: Path, expected_layout: str | None = None) -> tuple[dict, Path]:
    """Validate an anchor directory; return (manifest, payload path).

    expected_layout is the persistent-SRAM layout string the CONSUMING LEG
    declares support for (issue #25, leg-fixtures.md "Anchors carry a
    version").  None means "no consumer, structural checks only" (the bare
    CLI `validate ANCHOR` form).  Anything else -- including the empty
    string, i.e. a leg that declares nothing -- must match the manifest's
    persistent_layout exactly, and the refusal names both strings.  This
    gate runs BEFORE the emulator boots: a layout mismatch is a schema-drift
    correctness bug and must never surface as an in-emulator timeout.
    """
    manifest_path = anchor / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise AnchorError(f"cannot read {manifest_path}: {exc}") from exc
    if manifest.get("schema") != SCHEMA:
        raise AnchorError(f"unsupported schema {manifest.get('schema')!r}")
    payload_name = manifest.get("payload")
    if not isinstance(payload_name, str) or Path(payload_name).name != payload_name:
        raise AnchorError("payload must be one plain filename")
    payload = anchor / payload_name
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise AnchorError(f"cannot read payload: {exc}") from exc
    if manifest.get("size") != SRAM_SIZE or len(data) != SRAM_SIZE:
        raise AnchorError(
            f"SRAM size mismatch: manifest={manifest.get('size')!r}, actual={len(data)}"
        )
    actual = hashlib.sha256(data).hexdigest()
    if manifest.get("sha256") != actual:
        raise AnchorError("payload SHA-256 mismatch")
    layout = manifest.get("persistent_layout")
    if not isinstance(layout, str) or not layout:
        # An anchor without a layout string can never be refused by version,
        # which defeats the whole #25 schema-drift gate.  Fail closed.
        raise AnchorError(f"{manifest_path} declares no persistent_layout")
    if expected_layout is not None and layout != expected_layout:
        raise AnchorError(
            f"persistent_layout mismatch: anchor {anchor} declares "
            f"{layout!r}, but this leg declares support for "
            + (f"{expected_layout!r}" if expected_layout
               else "NO layout (no 'OT6_ANCHOR_LAYOUT:' marker in the "
                    "script; a leg that consumes an anchor must declare "
                    "the layout it understands)")
        )
    return manifest, payload


def materialize(anchor: Path, destination: Path,
                expected_layout: str | None = None) -> None:
    _, payload = load(anchor, expected_layout)
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
        base = {
            "schema": SCHEMA,
            "payload": "save.srm",
            "size": SRAM_SIZE,
            "sha256": hashlib.sha256(payload).hexdigest(),
            "persistent_layout": "ot6-test-layout/v1",
        }
        (root / "manifest.json").write_text(json.dumps(base))
        load(root)
        load(root, "ot6-test-layout/v1")   # a leg that declares support
        out = root / "out.srm"
        materialize(root, out, "ot6-test-layout/v1")
        assert out.read_bytes() == payload

        for field, bad in (
            ("schema", "ot6.sram-anchor/v99"),
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
            except AnchorError:
                pass
            else:
                raise AssertionError(f"negative validation accepted bad {field}")

        # THE LAYOUT GATE (#25).  A mismatch must refuse AND NAME BOTH
        # strings -- asserting the raise alone would pass a mute refusal.
        (root / "manifest.json").write_text(json.dumps(base))
        for expected, must_name in (
            ("ot6-test-layout/v2", ["ot6-test-layout/v1", "ot6-test-layout/v2"]),
            ("", ["ot6-test-layout/v1", "NO layout"]),
        ):
            try:
                load(root, expected)
            except AnchorError as exc:
                for needle in must_name:
                    assert needle in str(exc), (
                        f"layout refusal does not name {needle!r}: {exc}")
            else:
                raise AssertionError(
                    f"layout gate accepted expected={expected!r} against "
                    f"anchor layout 'ot6-test-layout/v1'")
        print("sram_anchor selftest: PASS (schema, size, hash, path, "
              "persistent_layout negatives)")


def main(argv: list[str]) -> int:
    try:
        if argv == ["selftest"]:
            selftest()
        elif len(argv) in (2, 3) and argv[0] == "validate":
            # The optional third argument is the consuming leg's declared
            # persistent_layout; run.sh passes it (possibly empty, meaning
            # the leg declared nothing -- refused) so the gate fires before
            # the emulator boots.  Absent entirely = structural checks only.
            manifest, _ = load(Path(argv[1]),
                               argv[2] if len(argv) == 3 else None)
            print(
                f"valid {manifest['schema']}: {manifest['size']} bytes "
                f"sha256={manifest['sha256']} "
                f"persistent_layout={manifest['persistent_layout']}"
            )
        elif len(argv) in (3, 4) and argv[0] == "materialize":
            materialize(Path(argv[1]), Path(argv[2]),
                        argv[3] if len(argv) == 4 else None)
        else:
            print(
                "usage: sram_anchor.py validate ANCHOR [LEG_LAYOUT] | "
                "materialize ANCHOR DEST [LEG_LAYOUT] | selftest",
                file=sys.stderr,
            )
            return 2
    except AnchorError as exc:
        print(f"sram anchor: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
