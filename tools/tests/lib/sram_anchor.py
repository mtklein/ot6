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


def load(anchor: Path) -> tuple[dict, Path]:
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
    return manifest, payload


def materialize(anchor: Path, destination: Path) -> None:
    _, payload = load(anchor)
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
        }
        (root / "manifest.json").write_text(json.dumps(base))
        load(root)
        out = root / "out.srm"
        materialize(root, out)
        assert out.read_bytes() == payload

        for field, bad in (
            ("schema", "ot6.sram-anchor/v99"),
            ("size", 8192),
            ("sha256", "0" * 64),
            ("payload", "../save.srm"),
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
        print("sram_anchor selftest: PASS (schema, size, hash, path negatives)")


def main(argv: list[str]) -> int:
    try:
        if argv == ["selftest"]:
            selftest()
        elif len(argv) == 2 and argv[0] == "validate":
            manifest, _ = load(Path(argv[1]))
            print(
                f"valid {manifest['schema']}: {manifest['size']} bytes "
                f"sha256={manifest['sha256']}"
            )
        elif len(argv) == 3 and argv[0] == "materialize":
            materialize(Path(argv[1]), Path(argv[2]))
        else:
            print(
                "usage: sram_anchor.py validate ANCHOR | "
                "materialize ANCHOR DEST | selftest",
                file=sys.stderr,
            )
            return 2
    except AnchorError as exc:
        print(f"sram anchor: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
