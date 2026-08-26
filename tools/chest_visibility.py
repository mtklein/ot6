#!/usr/bin/env python3
"""Which chests did the route SEE, and are therefore expected to open.

Takes the tiles the party actually stood on (the [tiles] trace lines M.run
emits, harvested from a regen log), widens each to what the screen actually
shows, and intersects with the treasure table audit_chests.py decodes.

The camera model: with the party at pixel (px,py) the BG1 scroll is
(px-112, py-112), clamped at zero on each axis; the view is 256x224.  A
chest tile is visible from a party tile iff the chest's 16px rect overlaps
that view.  The far-edge clamp (scroll <= map size - view) is not applied,
since map pixel sizes are not decoded here; that only ever shows MORE map
for a party hugging a right/bottom border, so the report can UNDER-count
visibility there, and the nearest-approach distances flag anything close.

Usage:
  python3 tools/chest_visibility.py [--repo ROOT] LOG [LOG...]
  python3 tools/chest_visibility.py --selftest

LOGs are any files carrying [tiles] lines -- a full savestate-regeneration
log covers the whole route.  Output: per map the route walked, every chest with its
verdict (VISIBLE / not seen), kind, contents and nearest approach.  Exit 0
always (a report, not a gate); --selftest exits 1 on parser/math drift.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from audit_chests import load_chests, map_titles

# The measured camera (probe_chestcam.lua): scroll = party px - CAM_OFF,
# clamped at 0; the visible rect is VIEW_W x VIEW_H from there.
CAM_OFF_X, CAM_OFF_Y = 112, 112
VIEW_W, VIEW_H = 256, 224
TILE = 16
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


def visible_from(tx, ty, cx, cy):
    """Is chest tile (cx,cy) inside the measured view from party tile
    (tx,ty)?  Pixel math throughout: the party pixel is tile*16, the scroll
    is that minus the measured offset (clamped at 0), the chest occupies its
    full 16px tile and any overlap counts -- a sliver of chest in frame is a
    chest a human notices."""
    sx = max(tx * TILE - CAM_OFF_X, 0)
    sy = max(ty * TILE - CAM_OFF_Y, 0)
    return (cx * TILE + TILE - 1 >= sx and cx * TILE <= sx + VIEW_W - 1
            and cy * TILE + TILE - 1 >= sy and cy * TILE <= sy + VIEW_H - 1)


def nearest(walked, cx, cy):
    """Per-axis tile distances at the closest approach, for the report."""
    best = None
    for x, y in walked:
        raw = (abs(cx - x), abs(cy - y))
        if best is None or max(raw) < max(best):
            best = raw
    return best if best else (999, 999)


def visible(walked, cx, cy):
    return any(visible_from(x, y, cx, cy) for x, y in walked)


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
    # party tile (13,31) -> scroll (96,384); the Flame Sabre chest (3,25) at
    # px 48..63 x 400..415 sits left of the view.
    check("the measured mid-chute frame excludes the Flame Sabre",
          visible_from(13, 31, 3, 25), False)
    # One tile changes it: from (10,32) the view starts at (48,400) and the
    # chest's rect starts exactly there -- visible on both axes.
    check("from (10,32) the Flame Sabre is exactly in frame",
          visible_from(10, 32, 3, 25), True)
    check("from (10,33) the chest row is 1px above the view",
          visible_from(10, 33, 3, 25), False)
    # The zero clamp: a party against the top-left corner sees the corner.
    check("corner clamp shows tile (0,0)", visible_from(3, 3, 0, 0), True)
    check("far chest is out", visible_from(10, 10, 40, 10), False)

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
              "lines (a savestate-generation log covers the route)")
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
