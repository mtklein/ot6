#!/usr/bin/env python3
"""live.py -- watch a headless run while it happens.  No video anywhere:
the harness's own stdout stream is the broadcast.

    OT6_LIVE=1 tools/tests/run.sh tools/tests/<x>.lua &    # the run
    python3 tools/stream/live.py                           # the viewer

Follows the newest (or the named) run workspace under build/test-runs/ by
tailing its growing run.log:

  [ot6shot] <f> <b64>   the live screenshot stream (every 128 frames by
                        default; on in every run.sh run unless OT6_LIVE=0)
  [b64:<tag>] <chunk>   milestone screenshot blobs, shown as frames too
  [ot6pad] <f> <pad>    the live frame counter and held buttons
  [ot6note] <f> <text>  the driver's notes
  [ot6] <text>          every other log line, shown as notes too

Serves one page on --port (default 8611).  Latency is Mesen's stdout block
buffering: bursts every second or so.
"""
import argparse
import base64
import glob
import json
import os
import re
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 live</title>
<body style="margin:0;background:#111;color:#cdc;display:grid;place-items:center;min-height:100vh;font:14px ui-monospace,monospace">
<div style="text-align:center;padding:12px">
<img id=f src="latest.png" style="image-rendering:pixelated;display:block;margin:0 auto;width:min(768px,95vw)">
<div style="padding:8px 0;font-size:18px"><span id=frame>-</span> <span id=pad style="color:#8ac"></span></div>
<div id=notes style="text-align:left;max-width:min(768px,95vw);margin:0 auto;color:#9a9;white-space:pre-wrap;word-break:break-all"></div>
<div id=s style="color:#575;padding-top:6px">connecting…</div>
</div>
<script>
const $=id=>document.getElementById(id); let seen=-1;
setInterval(async()=>{ try{
  const r=await fetch('status.json?'+Date.now()); const j=await r.json();
  $('frame').textContent=(j.exact?'frame ':'frame ~')+j.frame.toLocaleString();
  $('pad').textContent=j.pad==='-'?'':('['+j.pad+']');
  $('notes').textContent=j.notes.join('\\n');
  $('s').textContent=j.test+' · live · shot #'+j.shots+' ('+j.shot_tag+') · '+new Date().toLocaleTimeString();
  if(j.shots!==seen){ seen=j.shots; const t=new Image(); const u='latest.png?'+seen;
    t.onload=()=>{ $('f').src=u; }; t.src=u; }
}catch(e){ $('s').textContent='waiting for run…'; } }, 300);
</script>"""

B64 = re.compile(r"^\[b64:([^\]]+)\] (\S+)\s*$")
SHOT = re.compile(r"^\[ot6shot\] (\d+) (\S+)\s*$")
PAD = re.compile(r"\[ot6pad\] (\d+) (\S+)")
NOTE = re.compile(r"\[ot6note\] (\d+) (.*)")
PLAIN = re.compile(r"^\[ot6\] (.*)")
# frame hints inside ordinary notes ("story f31113", "frame=2614",
# "at frame 6623") -- the counter's source when no [ot6pad] taps flow
HINT = re.compile(r"(?:\bframe[= ]|[ (]f)(\d{3,})\b")


def newest_workspace():
    logs = glob.glob(os.path.join(ROOT, "build/test-runs/*/run.log"))
    if not logs:
        sys.exit("no run workspace found (is a run going?)")
    return os.path.dirname(max(logs, key=os.path.getmtime))


def follow(log_path, webroot, test, stop, hop=False):
    state = {"frame": 0, "pad": "-", "notes": [], "test": test,
             "shots": 0, "shot_tag": "-", "exact": False}
    blob_tag, blob = None, []
    pos = 0
    quiet = 0.0

    def finish_blob():
        nonlocal blob_tag, blob
        if blob_tag and blob_tag.endswith(".png"):
            try:
                data = base64.b64decode("".join(blob))
                tmp = os.path.join(webroot, ".f.tmp")
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, os.path.join(webroot, "latest.png"))
                state["shots"] += 1
                state["shot_tag"] = blob_tag
            except Exception:
                pass
        blob_tag, blob = None, []

    while not stop.is_set():
        try:
            with open(log_path, errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
        except OSError:
            chunk = ""
        changed = bool(chunk)
        for line in chunk.splitlines():
            m = SHOT.match(line)
            if m:
                finish_blob()
                try:
                    data = base64.b64decode(m.group(2))
                    tmp = os.path.join(webroot, ".f.tmp")
                    with open(tmp, "wb") as f:
                        f.write(data)
                    os.replace(tmp, os.path.join(webroot, "latest.png"))
                    state["shots"] += 1
                    state["shot_tag"] = "live"
                    state["frame"] = int(m.group(1))
                    state["exact"] = True
                except Exception:
                    pass
                continue
            m = B64.match(line)
            if m:
                if m.group(1) != blob_tag:
                    finish_blob()
                    blob_tag = m.group(1)
                blob.append(m.group(2))
                continue
            finish_blob()
            m = PAD.search(line)
            if m:
                state["frame"], state["pad"] = int(m.group(1)), m.group(2)
                state["exact"] = True
                continue
            m = NOTE.search(line)
            if m:
                state["frame"] = max(state["frame"], int(m.group(1)))
                state["notes"] = (state["notes"] + [m.group(2)])[-8:]
                continue
            m = PLAIN.match(line)
            if m:
                state["notes"] = (state["notes"] + [m.group(1)])[-8:]
                if not state["exact"]:
                    h = None
                    for h in HINT.finditer(line):
                        pass
                    if h:
                        state["frame"] = int(h.group(1))
        if changed:
            quiet = 0.0
            tmp = os.path.join(webroot, ".status.tmp")
            with open(tmp, "w") as f:
                json.dump(state, f)
            os.replace(tmp, os.path.join(webroot, "status.json"))
        else:
            quiet += 0.25
            # channel-hop: this run went quiet; if a newer run is live,
            # follow it instead (started without a named workspace only)
            if hop and quiet > 10.0:
                try:
                    ws = newest_workspace()
                    nl = os.path.join(ws, "run.log")
                    if nl != log_path:
                        log_path, pos, quiet = nl, 0, 0.0
                        state["test"] = os.path.basename(ws).split(".")[0]
                        state["frame"], state["pad"] = 0, "-"
                        state["exact"] = False
                        state["notes"] = [f"— hopped to {state['test']} —"]
                except SystemExit:
                    pass
        time.sleep(0.25)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workspace", nargs="?", help="a build/test-runs/<ws> dir "
                    "(default: the one with the newest run.log)")
    ap.add_argument("--port", type=int, default=8611)
    args = ap.parse_args()

    ws = os.path.abspath(args.workspace) if args.workspace else newest_workspace()
    log = os.path.join(ws, "run.log")
    test = os.path.basename(ws).split(".")[0]

    # The webroot is stable, outside any run workspace: workspaces are
    # deleted when their run succeeds, and a server rooted inside one dies
    # with it.
    webroot = os.path.join(ROOT, "build", "live")
    os.makedirs(webroot, exist_ok=True)
    with open(os.path.join(webroot, "index.html"), "w") as f:
        f.write(PAGE)

    stop = threading.Event()
    threading.Thread(target=follow,
                     args=(log, webroot, test, stop, args.workspace is None),
                     daemon=True).start()

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port),
                                partial(SimpleHTTPRequestHandler,
                                        directory=webroot))
    print(f"live: http://127.0.0.1:{args.port}/  (test {test}, log {log})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()


if __name__ == "__main__":
    main()
