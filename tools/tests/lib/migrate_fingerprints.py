#!/usr/bin/env python3
"""migrate_fingerprints.py: re-stamp build/states stamps written under the
v1 provenance scheme (a .lua input hashed as its bytes) into the v2 scheme
(hashed as its Lua token stream, lua_fingerprint.py; issue #247), without
regenerating anything.

A stamp is re-stamped only when it VERIFIES under v1 -- the exact
compose.py stamp_status() check, with the v1 digests substituted for the
generator and sig: ROM, generator, artifact and ancestor bindings, and its
whole chain.  Such a stamp records sources that are still the tree's, so
the v2 digests of those same sources restate the same fact.  A stamp that
does not verify under v1 is left exactly as it is and stays stale.  A stamp
that already verifies under v2 is left alone, so a second run is a no-op.

Per re-stamped stamp:
  - the `generator` line becomes the v2 gensig of the same generator (and
    extras);
  - the sig line becomes the v2 sig when the v1 sig matched the current
    sources; when it did not (provenance drift: a lib half moved since
    generation) it is kept, and still reads as drift;
  - each `lib` line whose hash is the current half's bytes becomes that
    half's token-stream hash; a line for a half that moved is kept;
  - `rom`, `artifact` and `ancestor` are untouched, except that an
    `ancestor` line naming a stamp this run rewrote is rebound from that
    stamp's old bytes to its new bytes (the same binding, restated), and so
    on down the chain.
Every rewrite keeps the file's mtime: ninja schedules by it, and this is
not a generation.  Checkpoint manifests are not touched: their
generator_sig is a capture-time record under the format it names, never
recomputed, and their bytes are generate-edge inputs.

Usage:
    python3 tools/tests/lib/migrate_fingerprints.py [--dry-run] [ROOT]

Exit 0 when every stamp that verified under v1 now verifies under v2.  A
one-shot tool: delete it (and compose.py's _v1_hint) once no tree carries
v1 stamps.
"""

import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compose  # noqa: E402
import lua_fingerprint  # noqa: E402

V1 = "ot6-provenance/v1"


def _v1_digest(root, rels):
    h = hashlib.sha256()
    h.update(V1.encode() + b"\n")
    for rel in rels:
        h.update((Path(root) / rel).read_bytes())
    return h.hexdigest()


def v1_sig(gen, root, extras=()):
    """savestate_stamp.sh `sig` as v1 computed it: sha256(v1 ++ the bytes of
    gen, the three lib halves, extras)."""
    return _v1_digest(root, [f"tools/tests/{gen}.lua", *compose.LIB_HALVES,
                             *extras])


def v1_gensig(gen, root, extras=()):
    """savestate_stamp.sh `gensig` as v1 computed it."""
    return _v1_digest(root, [f"tools/tests/{gen}.lua", *extras])


def _verdicts(root, names, scheme):
    """stamp_status() of every name under `scheme` ('v1' or 'v2'), sharing
    one memo so chains are followed once."""
    saved = compose.generator_sig, compose.generator_own_sig
    if scheme == "v1":
        compose.generator_sig = v1_sig
        compose.generator_own_sig = v1_gensig
    try:
        memo = {}
        return {n: compose.stamp_status(n, root, memo) for n in names}
    finally:
        compose.generator_sig, compose.generator_own_sig = saved


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def migrate(root, dry_run=False):
    root = Path(root)
    states = root / "build" / "states"
    declared = compose.declared_states(str(root))
    if not declared:
        print("migrate: no savestate graph to read; nothing to do")
        return 0
    order = [n for n in compose._graph_order(root)
             if (states / f"{n}.stamp").exists()]
    order += sorted(s.stem for s in states.glob("*.stamp")
                    if s.stem in declared and s.stem not in order)
    if not order:
        print("migrate: no generated fixtures in this tree; nothing to do")
        return 0

    v2 = _verdicts(root, order, "v2")
    v1 = _verdicts(root, order, "v1")
    ok = (compose.FRESH, compose.DRIFT)

    rebound = {}            # "build/states/x.stamp" -> (old sha, new sha)
    migrated, current, left, rebinds = [], [], [], []
    for n in order:
        path = states / f"{n}.stamp"
        text = path.read_text()
        lines = text.splitlines()
        new = list(lines)
        what = []
        if v2[n][0] in ok:
            current.append(n)
        elif v1[n][0] in ok:
            recorded, gen, *extras = lines[0].split()
            if recorded[:64] == v1_sig(gen, root, extras):
                new[0] = compose._stamp_tool(root, "sig", gen, *extras).strip()
                what.append(f"sig {recorded[:12]} -> {new[0][:12]}")
            else:
                what.append("sig kept (provenance drift predates this run)")
            for i, line in enumerate(lines[1:], 1):
                parts = line.split()
                if parts[:1] == ["generator"] and len(parts) == 2:
                    g = compose.generator_own_sig(gen, root, extras)
                    new[i] = f"generator {g}"
                    what.append(f"generator {parts[1][:12]} -> {g[:12]}")
                elif parts[:1] == ["lib"] and len(parts) == 3:
                    half = root / parts[1]
                    if half.exists() and _sha(half) == parts[2]:
                        new[i] = (f"lib {parts[1]} "
                                  f"{lua_fingerprint.filehash(half)}")
                    else:
                        what.append(f"lib {parts[1]} kept (moved since)")
            migrated.append(n)
        else:
            left.append((n, v1[n][1] or f"{v1[n][0]} under v1"))
        # Rebind an ancestor this run rewrote: the same binding, restated.
        for i, line in enumerate(new):
            parts = line.split()
            if (parts[:1] == ["ancestor"] and len(parts) == 3
                    and parts[1] in rebound
                    and rebound[parts[1]][0] == parts[2]):
                new[i] = f"ancestor {parts[1]} {rebound[parts[1]][1]}"
                rebinds.append(n)
                what.append(f"ancestor {parts[1]} rebound")
        new_text = "\n".join(new) + "\n"
        if new_text == text:
            if n in migrated:
                what.append("(no line changed)")
        else:
            rel = f"build/states/{n}.stamp"
            rebound[rel] = (hashlib.sha256(text.encode()).hexdigest(),
                            hashlib.sha256(new_text.encode()).hexdigest())
            if not dry_run:
                compose._rewrite_keeping_mtime(path, new_text)
        if n in migrated:
            print(f"migrate {n}: RE-STAMPED -- verified under v1 "
                  f"({v1[n][0]}); {'; '.join(what)}")
        elif what:
            print(f"migrate {n}: {'; '.join(what)}")

    for n, why in left:
        print(f"migrate {n}: LEFT AS IS -- does not verify under v1: {why}")
    print(f"migrate: {len(migrated)} re-stamped (v1 -> v2), "
          f"{len(current)} already v2, {len(left)} left as is (not valid "
          f"under v1), {len(set(rebinds))} ancestor line(s) rebound"
          f"{' [dry run: nothing written]' if dry_run else ''}")
    if dry_run:
        return 0
    # The migration's own postcondition: everything it re-stamped verifies
    # under v2 now.  Anything else is a defect in this script.
    after = _verdicts(root, order, "v2")
    broken = [n for n in migrated if after[n][0] not in ok]
    for n in broken:
        print(f"migrate {n}: FAILED -- re-stamped but does not verify under "
              f"v2: {after[n][1]}")
    print("re-check with: python3 tools/tests/lib/compose.py --check-states")
    return 1 if broken else 0


def main(argv):
    dry = "--dry-run" in argv
    rest = [a for a in argv if a != "--dry-run"]
    if len(rest) > 1 or any(a.startswith("-") for a in rest):
        print(__doc__.split("Usage:")[1].split("Exit")[0], file=sys.stderr)
        return 2
    return migrate(Path(rest[0]) if rest else compose.ROOT, dry)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
