#!/usr/bin/env python3
"""live.py -- watch a recording run while it happens.

    OT6_RECORD=1 tools/tests/run.sh tools/tests/<x>.lua &   # the run
    python3 tools/stream/live.py                            # the broadcast

Follows the newest (or the named) recording workspace under
build/test-runs/: the growing ZMBV tape is decoded by piping it through
ffmpeg as it is written (tail -f | ffmpeg; the AVI has no index until exit,
but the stream is sequential so none is needed), and the run log's
[ot6pad]/[ot6note] taps supply the live frame counter, the held buttons,
and the driver's notes.  Serves one page on --port (default 8611) showing
the newest decoded frame, the frame/pad state, and the last notes.

The image feed lags the emulator by at most the ffmpeg pipe (measured
negligible: ZMBV decodes faster than the emulator produces) plus the 4 fps
sampling; the pad/frame readout lags by Mesen's stdout block buffering,
which flushes in bursts.  This is a monitor, not a measurement: the
frame-exact record is the composed MP4 after the run.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PAGE = """<!doctype html><title>OT6 live</title>
<body style="margin:0;background:#111;color:#cdc;display:grid;place-items:center;min-height:100vh;font:14px ui-monospace,monospace">
<div style="text-align:center;padding:12px">
<img id=f src="latest.jpg" style="image-rendering:pixelated;width:768px;max-width:95vw">
<div style="padding:8px 0;font-size:18px"><span id=frame>-</span> <span id=pad style="color:#8ac"></span></div>
<div id=notes style="text-align:left;max-width:768px;margin:0 auto;color:#9a9;white-space:pre-wrap"></div>
<div id=s style="color:#575;padding-top:6px">connecting…</div>
</div>
<script>
const $=id=>document.getElementById(id); let n=0;
setInterval(()=>{ const u='latest.jpg?'+(n++); const t=new Image();
  t.onload=()=>{ $('f').src=u; }; t.src=u; }, 400);
setInterval(async()=>{ try{
  const r=await fetch('status.json?'+Date.now()); const j=await r.json();
  $('frame').textContent='frame '+j.frame.toLocaleString();
  $('pad').textContent=j.pad==='-'?'':('['+j.pad+']');
  $('notes').textContent=j.notes.join('\\n');
  $('s').textContent=j.test+' · live · '+new Date().toLocaleTimeString();
}catch(e){ $('s').textContent='waiting for run…'; } }, 500);
</script>"""


def newest_workspace():
    tapes = glob.glob(os.path.join(ROOT, "build/test-runs/*/record.avi"))
    if not tapes:
        sys.exit("no recording workspace found (run with OT6_RECORD=1 first)")
    return os.path.dirname(max(tapes, key=os.path.getmtime))


def follow_log(log_path, webroot, test, stop):
    pad_re = re.compile(r"\[ot6pad\] (\d+) (\S+)")
    note_re = re.compile(r"\[ot6note\] (\d+) (.*)")
    state = {"frame": 0, "pad": "-", "notes": [], "test": test}
    pos = 0
    while not stop.is_set():
        try:
            with open(log_path, errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
        except FileNotFoundError:
            chunk = ""
        changed = False
        for line in chunk.splitlines():
            m = pad_re.search(line)
            if m:
                state["frame"] = int(m.group(1))
                state["pad"] = m.group(2)
                changed = True
                continue
            m = note_re.search(line)
            if m:
                state["frame"] = max(state["frame"], int(m.group(1)))
                state["notes"] = (state["notes"] + [m.group(2)])[-8:]
                changed = True
        if changed:
            tmp = os.path.join(webroot, ".status.tmp")
            with open(tmp, "w") as f:
                json.dump(state, f)
            os.replace(tmp, os.path.join(webroot, "status.json"))
        time.sleep(0.25)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workspace", nargs="?", help="a build/test-runs/<ws> dir "
                    "(default: the one with the newest record.avi)")
    ap.add_argument("--port", type=int, default=8611)
    args = ap.parse_args()

    ws = os.path.abspath(args.workspace) if args.workspace else newest_workspace()
    tape = os.path.join(ws, "record.avi")
    log = os.path.join(ws, "run.log")
    test = os.path.basename(ws).split(".")[0]

    webroot = os.path.join(ws, "live")
    os.makedirs(webroot, exist_ok=True)
    with open(os.path.join(webroot, "index.html"), "w") as f:
        f.write(PAGE)

    ff = subprocess.Popen(
        f"tail -c +1 -f '{tape}' | "
        f"ffmpeg -hide_banner -loglevel error -y -i - "
        f"-vf fps=4 -update 1 -q:v 3 '{webroot}/latest.jpg'",
        shell=True)

    stop = threading.Event()
    threading.Thread(target=follow_log, args=(log, webroot, test, stop),
                     daemon=True).start()

    os.chdir(webroot)
    httpd = ThreadingHTTPServer(("127.0.0.1", args.port),
                                SimpleHTTPRequestHandler)
    print(f"live: http://127.0.0.1:{args.port}/  (test {test}, tape {tape})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        ff.terminate()


if __name__ == "__main__":
    main()
