#!/usr/bin/env python3
"""compose.py <run.log> <tape.avi> <out.mp4> -- render the watchable video.

Stacks the game video (512x448, 2x nearest) over a drawn pad + frame-counter
panel (512x112) via ffmpeg, with notes as a mov_text subtitle track. The
tape's 0-based frame n holds the frame during which M.frame read n+1.
Sidecars <name>.inputs.tsv and <name>.notes.srt land next to the output MP4.
"""
import json, re, subprocess, sys
from fractions import Fraction
from pathlib import Path

MFRAME_OF_TAPE0 = 1              # M.frame stamp of tape frame 0

GAME_W, GAME_H = 512, 448        # 256x224 doubled, nearest-neighbor
PANEL_W, PANEL_H = 512, 112

BG = (0x14, 0x14, 0x1C)          # panel ground
IDLE = (0x4A, 0x4A, 0x58)        # a button nobody is holding
HELD = (0xFF, 0xD7, 0x5A)        # a held button
TEXT = (0xB0, 0xB0, 0xBE)        # labels and the frame counter

# 8x8 glyphs, one byte per row, bit 7 = leftmost pixel.
FONT = {
    "0": [0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00],
    "1": [0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00],
    "2": [0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00],
    "3": [0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00],
    "4": [0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00],
    "5": [0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00],
    "6": [0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00],
    "7": [0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00],
    "8": [0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00],
    "9": [0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00],
    "A": [0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00],
    "B": [0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00],
    "E": [0x7E,0x60,0x60,0x78,0x60,0x60,0x7E,0x00],
    "F": [0x7E,0x60,0x60,0x78,0x60,0x60,0x60,0x00],
    "L": [0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00],
    "M": [0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00],
    "R": [0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00],
    "S": [0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00],
    "T": [0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00],
    "X": [0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00],
    "Y": [0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00],
    "up":    [0x18,0x3C,0x7E,0x18,0x18,0x18,0x18,0x00],
    "down":  [0x18,0x18,0x18,0x18,0x7E,0x3C,0x18,0x00],
    "left":  [0x00,0x10,0x30,0x7E,0x7E,0x30,0x10,0x00],
    "right": [0x00,0x08,0x0C,0x7E,0x7E,0x0C,0x08,0x00],
    " ": [0]*8,
}

# Button name -> (glyph key, x, y) in the panel, 2x glyph scale (16px cells).
# The d-pad is a cross, the face buttons the SNES diamond (X top, Y left,
# A right, B bottom), shoulders and Select/Start to the right of them.
BUTTONS = {
    "up":     ("up",    58, 20), "left":  ("left",  34, 44),
    "right":  ("right", 82, 44), "down":  ("down",  58, 68),
    "x":      ("X",    172, 20), "y":     ("Y",    148, 44),
    "a":      ("A",    196, 44), "b":     ("B",    172, 68),
    "l":      ("L",    258, 20), "r":     ("R",    286, 20),
    "select": (None,   248, 68), "start": (None,   248, 44),
}
BTN_TEXT = {"select": "SEL", "start": "ST"}   # drawn as small words
CTR_X, CTR_Y = 360, 44                        # "FRAME" label + counter


def blit(buf, glyph, x, y, color, scale=2):
    r, g, b = color
    rows = FONT[glyph]
    for gy in range(8):
        bits = rows[gy]
        if not bits:
            continue
        for gx in range(8):
            if bits & (0x80 >> gx):
                for sy in range(scale):
                    py = y + gy * scale + sy
                    base = (py * PANEL_W + x + gx * scale) * 3
                    for sx in range(scale):
                        o = base + sx * 3
                        buf[o] = r; buf[o + 1] = g; buf[o + 2] = b


def text(buf, s, x, y, color, scale=1):
    for i, ch in enumerate(s):
        blit(buf, ch, x + i * 8 * scale, y, color, scale)


def draw_button(buf, name, color):
    glyph, x, y = BUTTONS[name]
    if glyph is None:
        text(buf, BTN_TEXT[name], x, y + 4, color, scale=1)
    else:
        blit(buf, glyph, x, y, color, scale=2)


def base_panel():
    buf = bytearray(PANEL_W * PANEL_H * 3)
    for o in range(0, len(buf), 3):
        buf[o], buf[o + 1], buf[o + 2] = BG
    for name in BUTTONS:
        draw_button(buf, name, IDLE)
    text(buf, "FRAME", CTR_X, CTR_Y - 14, TEXT, scale=1)
    return bytes(buf)


def probe(tape):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_streams",
         "-count_packets", "-of", "json", tape],
        check=True, capture_output=True).stdout
    st = json.loads(out)["streams"][0]
    fps = Fraction(st["r_frame_rate"])
    frames = int(st.get("nb_read_packets") or st.get("nb_frames") or 0)
    return int(st["width"]), int(st["height"]), fps, frames


def parse_log(path):
    pads, notes = [], []
    pad_re = re.compile(r"^\[ot6pad\] (\d+) (\S+)")
    note_re = re.compile(r"^\[ot6note\] (\d+) (.*)")
    for line in Path(path).read_text(errors="replace").splitlines():
        m = pad_re.match(line)
        if m:
            pads.append((int(m.group(1)), m.group(2)))
            continue
        m = note_re.match(line)
        if m:
            notes.append((int(m.group(1)), m.group(2).strip()))
    # several setPad calls can land on one frame; the last one wins
    dedup = {}
    for f, s in pads:
        dedup[f] = s
    return sorted(dedup.items()), notes


def srt_ts(t):
    ms = round(t * 1000)
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"


def build_srt(notes, fps, total_frames):
    out, end_t = [], float(total_frames / fps)
    for i, (frame, note) in enumerate(notes):
        t0 = float(max(0, frame - MFRAME_OF_TAPE0) / fps)
        if i + 1 < len(notes):
            t1 = float(max(0, notes[i + 1][0] - MFRAME_OF_TAPE0) / fps)
        else:
            t1 = end_t
        t1 = min(t1, t0 + 4.0)
        if t1 <= t0:
            t1 = t0 + 0.5
        out.append(f"{i + 1}\n{srt_ts(t0)} --> {srt_ts(t1)}\n{note}\n")
    return "\n".join(out) + "\n"


def stream_panel(pipe, pads, frames, base):
    """Write one 512x112 rgb24 panel per tape frame into ffmpeg's stdin."""
    ev = [(max(0, f - MFRAME_OF_TAPE0), s) for f, s in pads]
    idx, held, interval = 0, frozenset(), None
    for n in range(frames):
        while idx < len(ev) and ev[idx][0] <= n:
            s = ev[idx][1]
            held = frozenset() if s == "--" else frozenset(s.split("+"))
            idx += 1
            interval = None
        if interval is None:
            buf = bytearray(base)
            for name in held:
                if name in BUTTONS:
                    draw_button(buf, name, HELD)
            interval = bytes(buf)
        frame = bytearray(interval)
        text(frame, str(n + MFRAME_OF_TAPE0).rjust(7), CTR_X - 8, CTR_Y,
             TEXT, scale=2)
        pipe.write(frame)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    log, tape, out_mp4 = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    out_mp4.parent.mkdir(parents=True, exist_ok=True)

    w, h, fps, frames = probe(tape)
    if frames == 0:
        sys.exit(f"compose.py: {tape} holds no frames")
    if (w, h) == (256, 224):
        # mesen_record already crops to the game area (7-top/8-bottom overscan)
        crop = ""
    elif (w, h) == (256, 239):
        # an uncropped tape: the 224-line picture sits at rows 7..230
        crop = "crop=256:224:0:7,"
    else:
        # an unmeasured geometry; scale without cropping
        print(f"compose.py: unexpected tape geometry {w}x{h} "
              f"(expected 256x224); skipping the game-area crop",
              file=sys.stderr)
        crop = ""

    pads, notes = parse_log(log)
    stem = str(out_mp4.with_suffix(""))
    inputs_tsv = Path(stem + ".inputs.tsv")
    notes_srt = Path(stem + ".notes.srt")
    inputs_tsv.write_text("".join(f"{f}\t{s}\n" for f, s in pads))
    notes_srt.write_text(build_srt(notes, fps, frames) if notes else "")
    have_notes = notes_srt.stat().st_size > 0

    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-i", tape,
           "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-video_size", f"{PANEL_W}x{PANEL_H}",
           "-framerate", f"{fps.numerator}/{fps.denominator}",
           "-i", "pipe:0"]
    if have_notes:
        cmd += ["-i", str(notes_srt)]
    # Both vstack inputs share an explicit timebase (pts = frame index), so
    # vstack's framesync pairs frame n with frame n exactly.
    grid = f"settb={fps.denominator}/{fps.numerator},setpts=N"
    cmd += ["-filter_complex",
            f"[0:v]{crop}scale={GAME_W}:{GAME_H}:flags=neighbor,"
            f"format=rgb24,{grid}[g];[1:v]{grid}[p];[g][p]vstack[v]",
            "-map", "[v]", "-map", "0:a"]
    if have_notes:
        cmd += ["-map", "2:s", "-c:s", "mov_text",
                "-metadata:s:s:0", "language=eng"]
    cmd += ["-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            # 1 output frame per tape frame (passthrough avoids CFR rounding)
            "-fps_mode", "passthrough",
            "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart",
            # no -shortest: the tape's audio track runs slightly shorter
            # than its video (the recorder stops taking sound first)
            str(out_mp4)]

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        stream_panel(proc.stdin, pads, frames, base_panel())
        proc.stdin.close()
    except BrokenPipeError:
        pass
    if proc.wait() != 0:
        sys.exit(f"compose.py: ffmpeg failed (exit {proc.returncode})")

    print(f"compose.py: wrote {out_mp4} ({frames} frames, "
          f"{float(frames / fps):.1f}s, {len(pads)} pad events, "
          f"{len(notes)} notes)")


if __name__ == "__main__":
    main()
