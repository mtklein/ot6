#!/usr/bin/env python3
"""Which chests did the route SEE?  The owner's chest rule, made mechanical.

The rule (owner, 2026-08-16, #84): if a chest is visible on the screen, a
human walks over and opens it.  The route emulates a human, so the set of
chests the route should open is not an editorial list -- it is a measurement:
take the tiles the party actually stood on (the [tiles] trace lines M.run
emits, harvested from a regen log), widen each to what the screen shows (the
camera centers the party; the field view is 16x14 tiles, so half-extents
+-8/+-7 -- inclusive on both sides, deliberately generous by the sliver of a
tile at the frame's edge, because a human notices a chest sliding INTO frame),
and intersect with the treasure table audit_chests.py already decodes.

Near a map border the real camera clamps and shows deeper into the map than
the party-centered window, so this model can UNDER-report visibility for a
path hugging a border.  That bias is safe (it never claims a human saw what
they could not) and is noted per-chest by the nearest-approach distance: a
chest reported not-visible at distance 9-10 is worth an eyeball before
trusting.

Usage:
  python3 tools/chest_visibility.py [--repo ROOT] LOG [LOG...]
  python3 tools/chest_visibility.py --selftest

LOGs are any files carrying [tiles] lines -- a `make savestates` log covers
the whole route.  Output: per map the route walked, every chest with its
verdict (VISIBLE / not seen), kind, contents and nearest approach; then the
summary the #84 route-editing wave works from.  Exit 0 always (a report, not
a gate); --selftest exits 1 on parser/math drift.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from audit_chests import load_chests, map_titles

HALF_X, HALF_Y = 8, 7        # 16x14-tile field view, party-centered
TILES_RE = re.compile(r"\[tiles\] map=(\d+) n=\d+ xy=(\S+)")


def harvest(paths):
    """{map: set of (x, y)} unioned across every [tiles] line in the logs."""
    walked = {}
    for p in paths:
        with open(p, errors="ignore") as f:
            for line in f:
                m = TILES_RE.search(line)
                if not m:
                    continue
                tiles = walked.setdefault(int(m.group(1)), set())
                for pair in m.group(2).split(","):
                    x, _, y = pair.partition(":")
                    tiles.add((int(x), int(y)))
    return walked


def nearest(walked, cx, cy):
    """Chebyshev-ish nearest approach, reported per-axis-max so it compares
    directly against the (HALF_X, HALF_Y) window."""
    best = None
    for x, y in walked:
        d = max(abs(cx - x) * HALF_Y, abs(cy - y) * HALF_X)  # normalized
        raw = (abs(cx - x), abs(cy - y))
        if best is None or d < best[0]:
            best = (d, raw)
    return best[1] if best else (999, 999)


def visible(walked, cx, cy):
    return any(abs(cx - x) <= HALF_X and abs(cy - y) <= HALF_Y
               for x, y in walked)


def selftest():
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print(f"  SELFTEST FAIL {what}: got {got!r} want {want!r}")

    import io, tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
        f.write("[ot6] [tiles] map=242 n=2 xy=56:35,57:36\n"
                "noise line\n"
                "[ot6] [tiles] map=242 n=1 xy=10:10\n"
                "[ot6] [tiles] map=98 n=1 xy=5:5\n")
        path = f.name
    w = harvest([path])
    os.unlink(path)
    check("harvest unions per map", w[242], {(56, 35), (57, 36), (10, 10)})
    check("harvest keeps maps apart", w[98], {(5, 5)})
    check("just inside the window", visible({(10, 10)}, 18, 17), True)
    check("one past x", visible({(10, 10)}, 19, 10), False)
    check("one past y", visible({(10, 10)}, 10, 18), False)
    check("corner inclusive", visible({(10, 10)}, 2, 3), True)

    print("chest_visibility selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("logs", nargs="*")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.logs:
        print("chest_visibility: name at least one log carrying [tiles] "
              "lines (a make savestates log covers the route)")
        return 2

    walked = harvest(args.logs)
    if not walked:
        print("chest_visibility: no [tiles] lines found in the given logs -- "
              "was the tree regenerated with the tracer in lib/ot6.lua?")
        return 2
    chests, err = load_chests(args.repo)
    if err:
        print("chest_visibility: " + err)
        return 2
    titles = map_titles(args.repo)

    seen_maps = sorted(m for m in walked if any(c.map == m for c in chests))
    total_vis = 0
    total_on_route = 0
    for m in seen_maps:
        rows = [c for c in chests if c.map == m]
        total_on_route += len(rows)
        title = titles.get(m, "")
        print(f"map {m:3d} {title}  ({len(walked[m])} tiles walked)")
        for c in rows:
            if visible(walked[m], c.x, c.y):
                total_vis += 1
                verdict = "VISIBLE "
            else:
                dx, dy = nearest(walked[m], c.x, c.y)
                verdict = f"not seen (nearest {dx},{dy})"
            print(f"   ({c.x:3d},{c.y:3d}) bit {c.bit:3d} {c.kind:7s} "
                  f"{c.what:24s} {verdict}")
    walked_only = sorted(set(walked) - set(seen_maps))
    print(f"\nsummary: {total_vis} chest(s) VISIBLE along the walked route, "
          f"of {total_on_route} on walked maps "
          f"({len(chests)} in the whole game); "
          f"{len(walked_only)} walked map(s) carry no chests")
    print("A VISIBLE chest is one the owner's rule says a human opens; the "
          "#84 wave gives each an honest pickup (monster-in-a-box chests "
          "want playBattles=\"tactical\" declared).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
