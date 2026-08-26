#!/usr/bin/env python3
"""verify_panel.py <out.mp4> <inputs.tsv> [--shift N] -- prove the panel
tracks the input log.

Samples pad intervals from the sidecar input log, extracts the video frame in
the middle of each, and checks every button cell in the panel: a button the
log says is held must show lit (amber) pixels, and a button the log says is
idle must not.  The frame counter region is checked too, by rendering the
expected digits with compose.py's own font and requiring most of their lit
pixels to be lit in the extracted frame.

--shift N reads the video N frames away from where the log says to look; a
nonzero shift MUST make the check fail (that is the self-test proving this
program can detect misalignment -- a check that cannot fail is not a check):

    python3 tools/stream/verify_panel.py out.mp4 out.inputs.tsv            # PASS
    python3 tools/stream/verify_panel.py out.mp4 out.inputs.tsv --shift 30 # must FAIL

Exit 0 = every sampled frame agrees with the log; 1 = any disagreement.
"""
import subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from compose import (MFRAME_OF_TAPE0, GAME_H, PANEL_W, PANEL_H, BUTTONS,
                     BTN_TEXT, FONT, CTR_X, CTR_Y)

OUT_W, OUT_H = 512, GAME_H + PANEL_H
SAMPLES = 12


def extract(mp4, n):
    out = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", mp4,
         "-vf", f"select=eq(n\\,{n})", "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, capture_output=True).stdout
    if len(out) != OUT_W * OUT_H * 3:
        sys.exit(f"verify: frame {n}: got {len(out)} bytes, "
                 f"want {OUT_W * OUT_H * 3} (video too short?)")
    return out


def amber_count(img, x, y, w, h):
    n = 0
    for py in range(y, y + h):
        row = (py * OUT_W + x) * 3
        for px in range(w):
            o = row + px * 3
            r, g, b = img[o], img[o + 1], img[o + 2]
            if r > 180 and g > 150 and b < 160:
                n += 1
    return n


def cell(name):
    glyph, x, y = BUTTONS[name]
    y += GAME_H
    if glyph is None:                       # SEL/ST small text
        return x, y, 8 * len(BTN_TEXT[name]), 16
    return x, y, 16, 16


def expected_counter_pixels(mframe):
    """(x,y) of every pixel compose.py lights for this counter value."""
    pts = []
    s = str(mframe).rjust(7)
    x0, y0 = CTR_X - 8, GAME_H + CTR_Y
    for i, ch in enumerate(s):
        rows = FONT[ch]
        for gy in range(8):
            for gx in range(8):
                if rows[gy] & (0x80 >> gx):
                    for sy in range(2):
                        for sx in range(2):
                            pts.append((x0 + i * 16 + gx * 2 + sx,
                                        y0 + gy * 2 + sy))
    return pts


def bright(img, x, y):
    o = (y * OUT_W + x) * 3
    return img[o] > 120 and img[o + 1] > 120


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    shift = 0
    for i, a in enumerate(sys.argv):
        if a == "--shift":
            shift = int(sys.argv[i + 1])
            args.remove(sys.argv[i + 1])
    if len(args) != 2:
        sys.exit(__doc__)
    mp4, tsv = args

    events = []
    for line in Path(tsv).read_text().splitlines():
        f, s = line.split("\t")
        events.append((int(f), s))
    if not events:
        sys.exit("verify: empty input log")

    # sample the middle of intervals at least 3 frames long, spread evenly,
    # preferring intervals where something is held
    intervals = []
    for i, (f, s) in enumerate(events):
        f2 = events[i + 1][0] if i + 1 < len(events) else f + 4
        if f2 - f >= 3:
            intervals.append((f, f2, s))
    held_iv = [iv for iv in intervals if iv[2] != "--"]
    idle_iv = [iv for iv in intervals if iv[2] == "--"]
    pick = (held_iv[:: max(1, len(held_iv) // (SAMPLES * 2 // 3)) or 1]
            [: SAMPLES * 2 // 3]
            + idle_iv[:: max(1, len(idle_iv) // (SAMPLES // 3)) or 1]
            [: SAMPLES // 3])

    fails = 0
    for f, f2, s in pick:
        mid_mframe = (f + f2 - 1) // 2
        n = mid_mframe - MFRAME_OF_TAPE0 + shift
        img = extract(mp4, n)
        held = set() if s == "--" else set(s.split("+"))
        for name in BUTTONS:
            x, y, w, h = cell(name)
            lit = amber_count(img, x, y, w, h) >= 6
            want = name in held
            if lit != want:
                print(f"  FAIL frame {n}: button {name} "
                      f"{'lit' if lit else 'dark'}, log says "
                      f"{'held' if want else 'idle'} ({s})")
                fails += 1
        # The counter must show exactly the log's frame number: at least 90%
        # of the digits' pixels lit, and at most 10% as many lit pixels
        # elsewhere in the counter region.  The second clause is what makes
        # nearby values fail -- digit glyphs overlap heavily ('2' and '3'
        # share their top and bottom bars), so "most expected pixels lit"
        # alone scored an off-by-thirty counter as correct.
        want_ctr = n + MFRAME_OF_TAPE0 - shift
        pts = set(expected_counter_pixels(want_ctr))
        hit = sum(1 for (x, y) in pts if bright(img, x, y))
        rx, ry = CTR_X - 8, GAME_H + CTR_Y
        stray = sum(1 for yy in range(ry, ry + 16)
                    for xx in range(rx, rx + 7 * 16)
                    if bright(img, xx, yy) and (xx, yy) not in pts)
        if hit < len(pts) * 0.9 or stray > len(pts) * 0.1:
            print(f"  FAIL frame {n}: counter is not {want_ctr} "
                  f"({hit}/{len(pts)} expected pixels lit, {stray} stray)")
            fails += 1
        else:
            print(f"  ok frame {n}: pad={s} counter={want_ctr}")

    if fails:
        sys.exit(f"verify_panel: {fails} FAILURE(S) across {len(pick)} "
                 f"sampled frames")
    print(f"verify_panel: OK ({len(pick)} frames sampled, "
          f"12 buttons + counter each)")


if __name__ == "__main__":
    main()
