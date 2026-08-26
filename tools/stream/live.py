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
import importlib.util
import runpy
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
<div style="padding-top:4px"><a href="progress.html" style="color:#8ac">route progress &rarr;</a></div>
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

PROGRESS_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 route</title>
<body style="margin:0;background:#111;color:#cdc;font:13px ui-monospace,monospace">
<div style="max-width:1000px;margin:0 auto;padding:16px">
<div style="display:flex;justify-content:space-between;align-items:baseline">
<b style="font-size:17px">the route</b>
<span id=hdr style="color:#8a8"></span></div>
<svg id=map viewBox="0 0 1000 offset" width="100%"></svg>
<div id=cur style="color:#9ac;padding-top:4px"></div>
<div style="color:#575;padding-top:6px"><a href="index.html" style="color:#8ac">&larr; live view</a></div>
</div>
<script>
const COLS = 8, DX = 120, DY = 74, R0 = 6;
async function tick(){ try{
  const j = await (await fetch('progress.json?'+Date.now())).json();
  const svg = document.getElementById('map');
  const rows = Math.ceil(j.edges.length / COLS);
  svg.setAttribute('viewBox', `0 0 1000 ${rows*DY+40}`);
  let out = '', px=null, py=null;
  j.edges.forEach((e,i)=>{
    const r = Math.floor(i/COLS), c = i%COLS;
    const x = 60 + (r%2 ? (COLS-1-c) : c)*DX, y = 30 + r*DY;
    if(px!==null) out += `<path d="M${px} ${py} L${x} ${y}" stroke="#333" stroke-width="3" fill="none"/>`;
    px=x; py=y;
  });
  px=null;
  j.edges.forEach((e,i)=>{
    const r = Math.floor(i/COLS), c = i%COLS;
    const x = 60 + (r%2 ? (COLS-1-c) : c)*DX, y = 30 + r*DY;
    const rad = R0 + Math.min(14, Math.sqrt(e.dur||30));
    const col = e.status==='done' ? '#3f9d63' : e.status==='running' ? '#e0a93e' : '#3a423c';
    const pulse = e.status==='running' ? `<animate attributeName="r" values="${rad};${rad+4};${rad}" dur="1.2s" repeatCount="indefinite"/>` : '';
    out += `<circle cx="${x}" cy="${y}" r="${rad}" fill="${col}">${pulse}</circle>`
        + `<text x="${x}" y="${y+rad+12}" fill="${e.status==='pending'?'#565':'#aca'}" font-size="9" text-anchor="middle">${e.name}</text>`;
  });
  svg.innerHTML = out;
  document.getElementById('hdr').textContent =
    `${j.done}/${j.total} segments · ${j.elapsed_min} min elapsed · ~${j.eta_min} min of spine left`;
  document.getElementById('cur').textContent =
    j.running.length ? ('now playing: ' + j.running.join(', ')) : '';
}catch(e){} }
tick(); setInterval(tick, 2000);
</script>"""

B64 = re.compile(r"^\[b64:([^\]]+)\] (\S+)\s*$")
SHOT = re.compile(r"^\[ot6shot\] (\d+) (\S+)\s*$")
PAD = re.compile(r"\[ot6pad\] (\d+) (\S+)")
NOTE = re.compile(r"\[ot6note\] (\d+) (.*)")
PLAIN = re.compile(r"^\[ot6\] (.*)")
# frame hints inside ordinary notes ("story f31113", "frame=2614",
# "at frame 6623") -- the counter's source when no [ot6pad] taps flow
HINT = re.compile(r"(?:\bframe[= ]|[ (]f)(\d{3,})\b")


def progress_thread(webroot, stop):
    """Write progress.json every 2s: each graph edge's status (done when its
    primary stamp postdates the newest build.ninja, running when a live
    workspace bears its name, pending otherwise), plus a remaining-spine ETA
    from the ninja log's measured durations."""
    states = runpy.run_path(
        os.path.join(ROOT, "tools/tests/savestate_graph.py"))["STATES"]
    # freshness authority: compose.py's own stamp verification (sig over
    # generator+libs+extras, artifact hash, ancestor chain).  A fresh stamp
    # is what ninja will not re-run -- modulo a ROM-content change, which
    # the graph's latch owns and a mid-gate page can ignore honestly.
    spec = importlib.util.spec_from_file_location(
        "compose", os.path.join(ROOT, "tools/tests/lib/compose.py"))
    compose = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compose)
    from pathlib import Path
    rootp = Path(ROOT)
    t0 = time.time()
    while not stop.is_set():
        dur = {}
        try:
            with open(os.path.join(ROOT, "build/ninja/.ninja_log")) as f:
                for line in f:
                    q = line.rstrip("\n").split("\t")
                    if len(q) >= 5 and q[3].startswith("build/states/") \
                       and q[3].endswith(".mss"):
                        dur[q[3][13:-4]] = (int(q[1]) - int(q[0])) / 1000
        except OSError:
            pass
        running = set()
        for ws in glob.glob(os.path.join(ROOT, "build/test-runs/*/run.log")):
            try:
                if time.time() - os.path.getmtime(ws) < 45:
                    running.add(os.path.basename(os.path.dirname(ws))
                                .split(".")[0])
            except OSError:
                pass
        edges, done = [], 0
        for e in states:
            n = e["state"]
            names = [n] + list(e.get("also") or [])
            cost = max((dur.get(x, 0.0) for x in names), default=0.0)
            # a live workspace outranks content freshness: artifacts from a
            # superseded edge can pass the stamp check while their
            # replacement run is mid-flight
            st = "pending"
            if running & set(names):
                st = "running"
            else:
                try:
                    if all(os.path.exists(
                               os.path.join(ROOT, f"build/states/{x}.stamp"))
                           and compose.stamp_check(x, rootp) is None
                           for x in names):
                        st = "done"
                except Exception:
                    pass
            if st == "done":
                done += 1
            edges.append({"name": n, "dur": cost, "status": st})
        # remaining spine: longest chain of not-done edges (file order is
        # play order; prev links carry the real topology)
        owner = {}
        for e in states:
            for x in [e["state"]] + list(e.get("also") or []):
                owner[x] = e["state"]
        fin = {}
        idx = {e["state"]: d for e, d in zip(states, edges)}
        def finish(e):
            n = e["state"]
            if n in fin:
                return fin[n]
            b = 0.0
            for dep in (e.get("prev"), e.get("seed"), e.get("after")):
                if dep:
                    b = max(b, finish(next(x for x in states
                                           if x["state"] == owner[dep])))
            mine = 0.0 if idx[n]["status"] == "done" else (idx[n]["dur"] or 60)
            fin[n] = b + mine
            return fin[n]
        eta = max((finish(e) for e in states), default=0.0)
        out = {"edges": edges, "done": done, "total": len(edges),
               "running": sorted(running & set(owner)),
               "elapsed_min": int((time.time() - t0) / 60),
               "eta_min": int(eta / 60)}
        tmp = os.path.join(webroot, ".p.tmp")
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, os.path.join(webroot, "progress.json"))
        time.sleep(5)


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
    with open(os.path.join(webroot, "progress.html"), "w") as f:
        f.write(PROGRESS_PAGE)

    stop = threading.Event()
    threading.Thread(target=follow,
                     args=(log, webroot, test, stop, args.workspace is None),
                     daemon=True).start()
    threading.Thread(target=progress_thread, args=(webroot, stop),
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
