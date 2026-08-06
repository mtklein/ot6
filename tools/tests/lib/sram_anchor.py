#!/usr/bin/env python3
"""Validate and materialize OT6's small, versioned battery-save anchors.

PROVENANCE (issue #75 step 5).  An anchor is a frontier ancestor: states
mint from it, and states mint from those, so anchor honesty is the root of
every chain above it.  Historically the manifest's `provenance` field was
PROSE -- a paragraph describing the leg that cut the battery -- which a
human can read and nothing can verify.  The mechanical form is a dict:

    "provenance": {
      "format": "ot6-provenance/v1",
      "payload_sha256": "<sha256 of the .sram bytes>",
      "mint_sig": "<sig> <gen> [extras]",     # frontier_stamp.sh sig of the
                                              # generator that drove the
                                              # capture run, verbatim
      "ancestors": [                          # what the capture run booted:
        {"path": "build/states/x.stamp",      # the stamp of each embedded
         "sha256": "<sha256 of that file>"},  # state, and/or the manifest of
        ...                                   # the anchor it Continued from
      ]
    }

run.sh's OT6_CAPTURE_SRM mode writes exactly this object to
`<payload>.provenance.json` beside the captured battery, hashed from the
real files of the capture run -- no hand-typing.  `seal ANCHOR` folds the
sidecar into manifest.json (recomputing size/sha256 while it is there), so
re-cutting an anchor honestly is: run the capture, run seal, commit.

A manifest whose `provenance` is still prose (or absent) is LEGACY-V0:
grandfathered with a loud warning, never a failure, because the existing
anchors' generators are still being converted to honest play (#75) and
re-cutting them is the burn-down, not a precondition.  A manifest whose
`provenance` IS a dict gets verified at load -- i.e. before every boot that
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

SCHEMA = "ot6.sram-anchor/v1"
# Must match frontier_stamp.sh's GATE_CONTRACT -- the one version string the
# whole provenance program bumps together (issue #75).
PROVENANCE_FORMAT = "ot6-provenance/v1"
SRAM_SIZE = 32768
_HEX64 = re.compile(r"[0-9a-f]{64}")


class AnchorError(ValueError):
    pass


def provenance_problem(prov: dict, payload_sha256: str) -> str | None:
    """Why `prov` is not a valid mechanical provenance record, or None.

    Shape-checks everything and cross-checks the one hash that is locally
    checkable (the payload's).  Ancestor FILES are deliberately not re-read
    here: the record documents what the capture run saw in ITS tree, and
    the consuming tree's build/states legitimately moves on every re-mint.
    """
    if prov.get("format") != PROVENANCE_FORMAT:
        return (f"provenance format {prov.get('format')!r} is not "
                f"{PROVENANCE_FORMAT!r}")
    if prov.get("payload_sha256") != payload_sha256:
        return "provenance payload_sha256 does not match the payload bytes"
    sig = prov.get("mint_sig")
    if not isinstance(sig, str) or len(sig.split()) < 2 \
            or not _HEX64.fullmatch(sig.split()[0]):
        return f"provenance mint_sig {sig!r} is not '<64-hex> <gen> ...'"
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
    # Provenance (issue #75): a mechanical record is verified, right here,
    # before any boot; a prose one is grandfathered LOUDLY.  See the module
    # docstring for the record's shape and the legacy-v0 policy.
    prov = manifest.get("provenance")
    if isinstance(prov, dict):
        problem = provenance_problem(prov, actual)
        if problem:
            raise AnchorError(f"{manifest_path}: {problem}")
    else:
        print(
            f"sram anchor: WARNING: {anchor} carries legacy-v0 provenance "
            f"(prose, nothing mechanically verifiable).  Grandfathered "
            f"under issue #75 -- the burn-down is re-cutting it honestly "
            f"(capture run, then `sram_anchor.py seal`), not editing the "
            f"manifest.",
            file=sys.stderr,
        )
    return manifest, payload


def capture(root: Path, out: Path, payload: Path, mint_sig: str,
            ancestors: list[str]) -> None:
    """Write the mechanical provenance sidecar for a just-captured battery.

    Called by run.sh's OT6_CAPTURE_SRM mode, right after the payload is
    published: every hash is taken from the real file at capture time, so
    the record can never be typed wrong.  `ancestors` are tree-relative
    paths (stamps of the states the capture run booted, and/or the manifest
    of the anchor it Continued from); they are hashed against `root`.
    The finished record is self-checked through the same validator load()
    uses -- a sidecar this function emits can never be one seal() refuses.
    """
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise AnchorError(f"cannot read captured payload: {exc}") from exc
    rec: dict = {"format": PROVENANCE_FORMAT,
                 "payload_sha256": hashlib.sha256(data).hexdigest(),
                 "mint_sig": mint_sig,
                 "ancestors": []}
    for rel in ancestors:
        try:
            blob = (root / rel).read_bytes()
        except OSError as exc:
            raise AnchorError(f"cannot read ancestor {rel}: {exc}") from exc
        rec["ancestors"].append(
            {"path": rel, "sha256": hashlib.sha256(blob).hexdigest()})
    problem = provenance_problem(rec, rec["payload_sha256"])
    if problem:
        raise AnchorError(f"refusing to write a bad sidecar: {problem}")
    out.write_text(json.dumps(rec, indent=2) + "\n")


def seal(anchor: Path) -> None:
    """Fold a capture's provenance sidecar into the anchor's manifest.

    The re-cut flow's second half: the capture run published
    `<payload>` and `<payload>.provenance.json` into the anchor directory;
    seal verifies the sidecar against the payload bytes actually there,
    recomputes size/sha256, and writes the manifest with `provenance` as
    the mechanical record.  The authored fields (schema, slot, milestone,
    persistent_layout...) pass through untouched -- those are the human's
    claims; the hashes are the machine's.
    """
    manifest_path = anchor / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise AnchorError(f"cannot read {manifest_path}: {exc}") from exc
    payload_name = manifest.get("payload")
    if not isinstance(payload_name, str) or Path(payload_name).name != payload_name:
        raise AnchorError("payload must be one plain filename")
    payload = anchor / payload_name
    try:
        data = payload.read_bytes()
    except OSError as exc:
        raise AnchorError(f"cannot read payload: {exc}") from exc
    if len(data) != SRAM_SIZE:
        raise AnchorError(f"payload is {len(data)} bytes, not {SRAM_SIZE}")
    sidecar = anchor / (payload_name + ".provenance.json")
    try:
        prov = json.loads(sidecar.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise AnchorError(
            f"cannot read {sidecar}: {exc} -- a seal needs the capture "
            f"run's sidecar (run.sh OT6_CAPTURE_SRM writes it beside the "
            f"payload); there is deliberately no way to author one by hand"
        ) from exc
    actual = hashlib.sha256(data).hexdigest()
    problem = provenance_problem(prov, actual) if isinstance(prov, dict) \
        else "sidecar is not a JSON object"
    if problem:
        raise AnchorError(f"{sidecar}: {problem}")
    manifest["size"] = SRAM_SIZE
    manifest["sha256"] = actual
    manifest["provenance"] = prov
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


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
        # The positive-control manifest carries MECHANICAL provenance (#75)
        # built by the real capture path, so every clean load below is also
        # the proof that a well-formed record loads silently.
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

        # ---- provenance (issue #75 step 5) --------------------------------
        import contextlib
        import io

        def load_warns(anchor: Path) -> str:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                load(anchor)
            return err.getvalue()

        # 1. a mechanical record is the QUIET state; legacy prose (or no
        #    provenance at all) is grandfathered, but LOUDLY -- the warning
        #    must name the marker and the burn-down.
        (root / "manifest.json").write_text(json.dumps(base))
        assert load_warns(root) == "", (
            "a mechanically-provenanced anchor must load silently")
        stripped = {k: v for k, v in base.items() if k != "provenance"}
        for legacy in (dict(stripped, provenance="cut by hand, trust me"),
                       stripped):
            (root / "manifest.json").write_text(json.dumps(legacy))
            warned = load_warns(root)
            assert "legacy-v0" in warned and "issue #75" in warned, (
                f"legacy anchor did not warn loudly: {warned!r}")

        # 2. seal folds the capture sidecar into the manifest -- the re-cut
        #    flow's second half -- recomputing the payload hash on the way.
        (root / "manifest.json").write_text(json.dumps(stripped))
        seal(root)
        sealed = json.loads((root / "manifest.json").read_text())
        assert sealed["provenance"] == rec, "seal did not fold the sidecar in"
        assert sealed["sha256"] == base["sha256"], "seal recompute wrong"
        assert sealed["persistent_layout"] == "ot6-test-layout/v1", (
            "seal must pass authored fields through untouched")
        assert load_warns(root) == "", "a sealed anchor must load silently"

        # 3. malformed MECHANICAL provenance fails closed -- only the
        #    explicitly-legacy prose shape is excused, never a bad record.
        for tweak, why in (
            ({"format": "ot6-provenance/v99"}, "unknown format"),
            ({"payload_sha256": "0" * 64}, "payload hash mismatch"),
            ({"mint_sig": "not-a-sig"}, "malformed mint_sig"),
            ({"mint_sig": "f" * 64}, "sig with no generator name"),
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
            except AnchorError:
                pass
            else:
                raise AssertionError(f"bad provenance accepted: {why}")

        # 4. seal only trusts a sidecar that matches the payload NOW: a
        #    payload swapped after capture must be refused, not re-blessed.
        (root / "manifest.json").write_text(json.dumps(base))
        (root / "save.srm").write_bytes(bytes(SRAM_SIZE))
        try:
            seal(root)
        except AnchorError:
            pass
        else:
            raise AssertionError("seal accepted a payload the sidecar "
                                 "never hashed")

        print("sram_anchor selftest: PASS (schema, size, hash, path, "
              "persistent_layout negatives; provenance capture/seal "
              "round-trip, legacy-v0 warning, malformed-record refusals)")


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
            prov = manifest.get("provenance")
            print(
                f"valid {manifest['schema']}: {manifest['size']} bytes "
                f"sha256={manifest['sha256']} "
                f"persistent_layout={manifest['persistent_layout']} "
                f"provenance="
                + (PROVENANCE_FORMAT if isinstance(prov, dict)
                   else "legacy-v0")
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
                "usage: sram_anchor.py validate ANCHOR [LEG_LAYOUT] | "
                "materialize ANCHOR DEST [LEG_LAYOUT] | "
                "capture ROOT OUT_JSON PAYLOAD MINT_SIG [ANCESTOR_REL...] | "
                "seal ANCHOR | selftest",
                file=sys.stderr,
            )
            return 2
    except AnchorError as exc:
        print(f"sram anchor: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
