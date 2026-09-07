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
import hashlib
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

# The default landing: a control-room census of EVERY active run worker,
# one tile per live workspace, growing/shrinking as workers start and finish.
# Data comes from grid.json (grid_thread); each tile's screenshot is a cached
# PNG under build/live/grid/.  A tile click opens the single-worker detail
# (live1.html) for that worker.
GRID_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 census</title>
<body style="margin:0;background:#111;color:#cdc;font:13px ui-monospace,monospace">
<div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px;padding:10px 14px">
<b style="font-size:16px">live census</b>
<span id=hdr style="color:#8a8"></span>
<a href="progress.html" style="color:#8ac">route map &rarr;</a></div>
<div id=grid style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;padding:0 14px 18px"></div>
<div id=empty style="color:#575;padding:2px 14px">waiting for workers…</div>
<script>
const $=id=>document.getElementById(id);
const nf=n=>(n==null?'\\u2014':Number(n).toLocaleString());
async function tick(){ try{
  const j = await (await fetch('grid.json?'+Date.now())).json();
  const ws = j.workers||[]; const grid=$('grid');
  $('empty').style.display = ws.length ? 'none' : 'block';
  $('hdr').textContent = ws.length ? (ws.length+' active worker'+(ws.length>1?'s':'')
    + ' · '+ws.filter(w=>w.stuck).length+' frozen') : '';
  const seen = new Set();
  ws.forEach(w=>{
    seen.add(w.id);
    let t = document.getElementById('t-'+w.id);
    if(!t){
      t = document.createElement('a');
      t.id = 't-'+w.id;
      t.href = 'live1.html?w='+encodeURIComponent(w.id);
      t.style.cssText = 'position:relative;display:block;text-decoration:none;'
        + 'color:inherit;border:2px solid #2a322c;border-radius:6px;'
        + 'overflow:hidden;background:#181c19';
      t.innerHTML = '<img style="width:100%;display:block;'
        + 'image-rendering:pixelated;aspect-ratio:8/7;background:#000">'
        + '<span class=badge style="position:absolute;top:5px;right:5px;'
        + 'font-size:10px;font-weight:bold;padding:1px 5px;border-radius:3px"></span>'
        + '<div style="padding:5px 7px">'
        + '<div class=nm style="white-space:nowrap;overflow:hidden;'
        + 'text-overflow:ellipsis"></div>'
        + '<div class=fr style="color:#8a8;font-size:11px"></div></div>';
      grid.appendChild(t);
    }
    const img = t.querySelector('img');
    if(w.shot && img.getAttribute('data-s')!==w.shot){
      img.setAttribute('data-s', w.shot); img.src = w.shot; }
    t.querySelector('.nm').textContent = w.name;
    t.querySelector('.fr').textContent = 'frame '+nf(w.frame);
    const badge = t.querySelector('.badge');
    // stuck (red) outranks the live-view flag (cyan); otherwise a plain rim
    if(w.stuck){ t.style.borderColor='#d24b4b';
      badge.textContent='\\u26A0 FROZEN'; badge.style.background='#d24b4b';
      badge.style.color='#fff'; }
    else if(w.live){ t.style.borderColor='#57e9ff';
      badge.textContent='\\u25B6 LIVE'; badge.style.background='#57e9ff';
      badge.style.color='#03242b'; }
    else { t.style.borderColor='#2a322c'; badge.textContent=''; }
  });
  // reflow: drop tiles whose worker vanished
  [...grid.children].forEach(t=>{ if(!seen.has(t.id.slice(2))) t.remove(); });
}catch(e){ $('empty').textContent='waiting for run…';
  $('empty').style.display='block'; } }
tick(); setInterval(tick, 1000);
</script>"""

# The single-worker DETAIL view (was index.html; now live1.html).  With no
# query it follows the server-tailed workspace (the classic big screenshot +
# live notes, sourced from status.json).  With ?w=<id> it "follows by name":
# any census worker's big screenshot + frame + stuck, sourced from grid.json
# (notes stream only for the server-followed worker).
DETAIL_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 live</title>
<body style="margin:0;background:#111;color:#cdc;display:grid;place-items:center;min-height:100vh;font:14px ui-monospace,monospace">
<div style="text-align:center;padding:12px">
<div style="font-size:16px;padding-bottom:6px"><span id=who style="color:#cdc"></span></div>
<img id=f src="latest.png" style="image-rendering:pixelated;display:block;margin:0 auto;width:min(768px,95vw);outline:none">
<div style="padding:8px 0;font-size:18px"><span id=frame>-</span> <span id=pad style="color:#8ac"></span></div>
<div id=notes style="text-align:left;max-width:min(768px,95vw);margin:0 auto;color:#9a9;white-space:pre-wrap;word-break:break-all"></div>
<div id=s style="color:#575;padding-top:6px">connecting…</div>
<div style="padding-top:4px">
<a href="index.html" style="color:#8ac">&larr; census</a> ·
<a href="progress.html" style="color:#8ac">route progress &rarr;</a></div>
</div>
<script>
const $=id=>document.getElementById(id);
const wid = new URLSearchParams(location.search).get('w');
let seen=-1, curShot=null;
async function tick(){
  let st=null, grid=null;
  try{ st = await (await fetch('status.json?'+Date.now())).json(); }catch(e){}
  try{ grid = (await (await fetch('grid.json?'+Date.now())).json()).workers||[]; }catch(e){}
  const followed = st ? st.test : null;
  // resolve the target: explicit ?w means THAT worker (and only it -- no
  // silent fall-back to the followed one when it has finished); no ?w means
  // the server-followed worker
  let tgt = null;
  if(grid){ tgt = wid ? (grid.find(w=>w.id===wid) || null)
                      : (grid.find(w=>w.name===followed) || null); }
  const targetName = wid ? (tgt ? tgt.name : null) : followed;
  const isFollowed = !!st && !!targetName && targetName===st.test;
  $('who').textContent = targetName || (wid ? '('+wid+')' : '(waiting)');
  if(isFollowed && st){
    // rich path: the server streams this worker frame-by-frame + notes
    $('frame').textContent=(st.exact?'frame ':'frame ~')+nf(st.frame);
    $('pad').textContent=st.pad==='-'?'':('['+st.pad+']');
    $('notes').textContent=(st.notes||[]).join('\\n');
    $('s').textContent=st.test+' · live · shot #'+st.shots+' ('+st.shot_tag+') · '
      +new Date().toLocaleTimeString();
    if(st.shots!==seen){ seen=st.shots; const u='latest.png?'+seen;
      const t=new Image(); t.onload=()=>{ $('f').src=u; }; t.src=u; }
  } else if(tgt){
    // census path: a worker the server isn't streaming in detail
    $('frame').textContent='frame '+nf(tgt.frame);
    $('pad').textContent='';
    $('notes').textContent='(full notes stream on the live-view worker)';
    $('s').textContent=tgt.name+(tgt.stuck?' · \\u26A0 frozen':' · live')+' · via census';
    if(tgt.shot && tgt.shot!==curShot){ curShot=tgt.shot; const u=tgt.shot;
      const t=new Image(); t.onload=()=>{ $('f').src=u; }; t.src=u; }
  } else {
    $('s').textContent = wid ? ('worker '+wid+' is no longer active')
                             : 'waiting for run…';
  }
  $('f').style.outline = (tgt && tgt.stuck) ? '3px solid #d24b4b' : 'none';
}
function nf(n){ return n==null ? '\\u2014' : Number(n).toLocaleString(); }
tick(); setInterval(tick, 400);
</script>"""

# __COORDS__ is replaced at page-write time with {name: [x,y]} world-tile
# coordinates (route_coords.py, offsets pre-applied) -- the fallback for a
# progress.json written by an older live.py that carries no x/y per edge.
PROGRESS_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 route</title>
<body style="margin:0;background:#111;color:#cdc;font:13px ui-monospace,monospace">
<div style="max-width:1000px;margin:0 auto;padding:16px">
<div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px">
<b style="font-size:17px">the route</b>
<span id=hdr style="color:#8a8"></span>
<a id=tog href="#" style="color:#8ac">grid view</a></div>
<svg id=map viewBox="0 0 256 256" width="100%" style="display:block;margin:auto;max-height:88vh"></svg>
<div id=cur style="color:#9ac;padding-top:4px"></div>
<div id=pick style="color:#aca;min-height:1.2em"></div>
<div style="color:#575;padding-top:6px"><a href="index.html" style="color:#8ac">&larr; live view</a></div>
</div>
<script>
const C = __COORDS__;   // fallback world coords, keyed by segment name
const COLS = 8, DX = 120, DY = 74, R0 = 6;
let view = 'wob', last = null;
const svg = document.getElementById('map');
document.getElementById('tog').onclick = (ev)=>{ ev.preventDefault();
  view = view==='wob' ? 'grid' : 'wob';
  document.getElementById('tog').textContent = view==='wob' ? 'grid view' : 'map view';
  if(last) render(last); };
svg.addEventListener('click', ev=>{
  const n = ev.target.getAttribute && ev.target.getAttribute('data-name');
  document.getElementById('pick').textContent = n ? n : ''; });
function esc(s){ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
function render(j){
  if(view==='wob') renderWob(j); else renderGrid(j);
  document.getElementById('hdr').textContent =
    `${j.done}/${j.total} segments · ${j.elapsed_min} min elapsed · ~${j.eta_min} min of spine left`;
  document.getElementById('cur').textContent =
    (j.running.length ? ('now playing: ' + j.running.join(', ')) : '')
    + (j.live ? ((j.running.length?'    ':'') + '▶ live view: ' + j.live) : '');
}
function renderWob(j){
  svg.setAttribute('viewBox','0 0 256 256');
  // node placement: server-supplied e.x/e.y (world tiles), else the
  // page-baked table; +.5 centers on the tile
  const P = j.edges.map(e=>{
    const c = (e.x!==undefined) ? [e.x,e.y] : (C[e.name]||[10,10]);
    return [c[0]+.5, c[1]+.5]; });
  let out = `<image href="wob_map.png" x="0" y="0" width="256" height="256"
    style="filter:saturate(.7) brightness(.75)"/>`;
  out += `<polyline fill="none" stroke="#fff" stroke-opacity=".28"
    stroke-width=".6" stroke-linejoin="round"
    points="${P.map(p=>p[0].toFixed(1)+','+p[1].toFixed(1)).join(' ')}"/>`;
  const lastDone = j.edges.reduce((a,e,i)=>e.status==='done'?i:a, -1);
  let labels = '';
  j.edges.forEach((e,i)=>{
    const [x,y] = P[i];
    const rad = 1.5 + Math.min(2.2, Math.sqrt(e.dur||30)/8);
    const col = e.status==='done' ? '#3f9d63' : e.status==='running' ? '#e0a93e' : '#39413b';
    const pulse = e.status==='running' ? `<animate attributeName="r" values="${rad};${rad+1.4};${rad}" dur="1.2s" repeatCount="indefinite"/>` : '';
    // checkpoint-booted segments wear the dotted yellow ring, as in the
    // grid; the rest get a hairline dark rim so they read against the map
    const ring = e.ckpt ? ` stroke="#e8c94a" stroke-width=".55" stroke-dasharray="1 .8"`
                        : ` stroke="#0c100d" stroke-width=".35"`;
    // the ONE segment on index.html's live view: a bright cyan halo, drawn
    // under the node so the node fill stays crisp (server flags e.live)
    if(e.live)
      out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}"
        r="${(rad+2.5).toFixed(1)}" fill="none" stroke="#57e9ff" stroke-width="1"
        style="pointer-events:none">
        <animate attributeName="r" values="${(rad+2).toFixed(1)};${(rad+5).toFixed(1)};${(rad+2).toFixed(1)}" dur="1.3s" repeatCount="indefinite"/>
        <animate attributeName="stroke-opacity" values="1;.2;1" dur="1.3s" repeatCount="indefinite"/></circle>`;
    out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${rad.toFixed(1)}"
      fill="${col}" fill-opacity="${e.status==='pending'?.75:1}"${ring}
      data-name="${esc(e.name)}" style="cursor:pointer">
      <title>${esc(e.name)}</title>${pulse}</circle>`;
    // labels stay sparse at 76 nodes: the live node, running, most recent done
    if(e.live || e.status==='running' || i===lastDone){
      const txt = e.live ? '▶ '+e.name : e.name;   // ▶ pip on the live one
      const lw = 2.8*txt.length;   // ~half the label's width in units
      const lx = Math.min(Math.max(x, lw/2+2), 254-lw/2);
      const ly = y-rad-1.5 < 6 ? y+rad+5.5 : y-rad-1.5;
      labels += `<text x="${lx.toFixed(1)}" y="${ly.toFixed(1)}"
        fill="${e.live?'#8af2ff':e.status==='running'?'#f4d27a':'#bfe3c8'}" font-size="5"
        text-anchor="middle" paint-order="stroke" stroke="#111"
        stroke-width=".9" style="pointer-events:none">${esc(txt)}</text>`;
    }
  });
  svg.innerHTML = out + labels;
}
function renderGrid(j){
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
    // segments that boot from an SRAM save checkpoint rather than the
    // played chain wear a dotted yellow ring
    const ring = e.ckpt ? ` stroke="#e8c94a" stroke-width="2" stroke-dasharray="4 3"` : '';
    // the one live-view segment: bright cyan halo + a "▶ LIVE" tag
    if(e.live)
      out += `<circle cx="${x}" cy="${y}" r="${rad+5}" fill="none" stroke="#57e9ff" stroke-width="2.5">
        <animate attributeName="r" values="${rad+4};${rad+9};${rad+4}" dur="1.3s" repeatCount="indefinite"/>
        <animate attributeName="stroke-opacity" values="1;.2;1" dur="1.3s" repeatCount="indefinite"/></circle>`
        + `<text x="${x}" y="${y-rad-6}" fill="#8af2ff" font-size="10" font-weight="bold" text-anchor="middle" paint-order="stroke" stroke="#111" stroke-width="3">▶ LIVE</text>`;
    out += `<circle cx="${x}" cy="${y}" r="${rad}" fill="${col}"${ring}>${pulse}</circle>`
        + `<text x="${x}" y="${y+rad+12}" fill="${e.status==='pending'?'#565':'#aca'}" font-size="9" text-anchor="middle">${esc(e.name)}</text>`;
  });
  svg.innerHTML = out;
}
let lastS = null;
async function tick(){ try{
  const t = await (await fetch('progress.json?'+Date.now())).text();
  if(t===lastS) return;   // unchanged: keep the DOM (and its animations) still
  lastS = t; last = JSON.parse(t); render(last);
}catch(e){} }
tick(); setInterval(tick, 2000);
</script>"""

def _load_stream_module(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ROOT, f"tools/stream/{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _route_coords(names):
    """{name: (x, y)} WoB world tiles for the map view (route_coords.py,
    stack-spiral offsets applied); {} when the table cannot load, so the
    viewer degrades to its page-baked fallback."""
    try:
        return _load_stream_module("route_coords").coords(names)
    except Exception:
        return {}


def write_pages(webroot):
    # index.html is the census grid (default landing); the classic
    # single-worker detail moves to live1.html
    with open(os.path.join(webroot, "index.html"), "w") as f:
        f.write(GRID_PAGE)
    with open(os.path.join(webroot, "live1.html"), "w") as f:
        f.write(DETAIL_PAGE)
    try:
        states = runpy.run_path(
            os.path.join(ROOT, "tools/tests/savestate_graph.py"))["STATES"]
        coords = _route_coords([e["state"] for e in states])
    except Exception:
        coords = {}
    baked = {n: [round(x, 1), round(y, 1)] for n, (x, y) in coords.items()}
    with open(os.path.join(webroot, "progress.html"), "w") as f:
        f.write(PROGRESS_PAGE.replace("__COORDS__", json.dumps(baked)))


def ensure_map(webroot):
    """Regenerate the World of Balance background (render_worldmap.py, from
    the repo's own game data) if build/live lacks it."""
    out = os.path.join(webroot, "wob_map.png")
    if os.path.exists(out):
        return
    try:
        _load_stream_module("render_worldmap").render(out)
    except Exception as e:
        print(f"wob_map.png not rendered ({e}); map view will show no "
              "background", file=sys.stderr)


# ---- the census grid: one tile per active run worker ----------------------
SHOT_B = re.compile(rb"^\[ot6shot\] (\d+) (\S+)")   # bytes, for tail scans
PAD_B = re.compile(rb"^\[ot6pad\] (\d+)")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def _safe_id(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", s)


def _tail_bytes(path, n):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - n))
        return f.read()


def scan_worker(data, shots_stuck, frames_stuck):
    """Parse a run.log tail once -> (frame, png_bytes|None, hash8|None, stuck).

    frame is the latest [ot6pad] counter (falls back to the last shot's
    frame).  png_bytes is the newest [ot6shot] payload that decodes to a
    valid PNG (a partial trailing line is skipped).  stuck folds in
    stuck_detector's freeze rule: a trailing run of >= shots_stuck identical
    screenshots spanning >= frames_stuck advancing frames.
    """
    shots, last_pad = [], None
    for line in data.splitlines():
        m = SHOT_B.match(line)
        if m:
            shots.append((int(m.group(1)), m.group(2)))
            continue
        p = PAD_B.match(line)
        if p:
            last_pad = int(p.group(1))
    if not shots:
        return (last_pad, None, None, False)
    frame = last_pad if last_pad is not None else shots[-1][0]
    # newest payload that is a whole PNG (guards a truncated tail line)
    png, h = None, None
    for _fr, payload in reversed(shots[-3:]):
        try:
            raw = base64.b64decode(payload)
        except Exception:
            continue
        if raw[:8] == PNG_MAGIC:
            png = raw
            h = hashlib.md5(payload).hexdigest()[:8]
            break
    # freeze verdict: unbroken trailing block of identical shot payloads
    stuck = False
    if len(shots) >= shots_stuck and last_pad is not None:
        last_payload = shots[-1][1]
        trailing = 0
        for _fr, payload in reversed(shots):
            if payload == last_payload:
                trailing += 1
            else:
                break
        if trailing >= shots_stuck:
            stuck = (last_pad - shots[-trailing][0]) >= frames_stuck
    return (frame, png, h, stuck)


def grid_thread(webroot, stop, live_ref=None):
    """Write grid.json + grid/<id>.png every second: one entry per active run
    worker (build/test-runs/*/run.log touched within ACTIVE_SEC -- the same
    live-worker mtime filter stuck_detector uses).  Each entry carries the
    worker's latest decoded screenshot (cached to a PNG, rewritten only when
    it changes), its frame, a stuck flag, and whether it is the one on the
    server's live view.  Vanished workers' tiles are pruned so the grid
    shrinks as runs finish."""
    try:   # reuse stuck_detector's tuning so freeze thresholds stay single-source
        sd = _load_stream_module("stuck_detector")
        active_sec, tail_n = sd.ACTIVE_SEC, sd.TAIL_BYTES
        s_stuck, f_stuck = sd.SHOTS_STUCK, sd.FRAMES_STUCK
    except Exception:
        active_sec, tail_n, s_stuck, f_stuck = 40, 200_000, 8, 2000
    gdir = os.path.join(webroot, "grid")
    os.makedirs(gdir, exist_ok=True)
    written = {}   # id -> hash8 of the PNG currently on disk
    while not stop.is_set():
        live_test = (live_ref or {}).get("test")
        now = time.time()
        workers, active = [], set()
        for log in glob.glob(os.path.join(ROOT, "build/test-runs/*/run.log")):
            try:
                if now - os.path.getmtime(log) > active_sec:
                    continue
                dirname = os.path.basename(os.path.dirname(log))
                data = _tail_bytes(log, tail_n)
            except OSError:
                continue
            wid = _safe_id(dirname)
            name = dirname.split(".")[0]
            frame, png, h, stuck = scan_worker(data, s_stuck, f_stuck)
            active.add(wid)
            if png is not None and h is not None and written.get(wid) != h:
                try:
                    tmp = os.path.join(gdir, "." + wid + ".tmp")
                    with open(tmp, "wb") as f:
                        f.write(png)
                    os.replace(tmp, os.path.join(gdir, wid + ".png"))
                    written[wid] = h
                except OSError:
                    pass
            have = written.get(wid)
            workers.append({
                "id": wid, "name": name, "frame": frame,
                "shot": (f"grid/{wid}.png?{have}") if have else None,
                "stuck": bool(stuck),
                "live": bool(live_test and name == live_test)})
        # prune tiles/PNGs for workers that finished
        for wid in list(written):
            if wid not in active:
                try:
                    os.remove(os.path.join(gdir, wid + ".png"))
                except OSError:
                    pass
                del written[wid]
        workers.sort(key=lambda w: (w["name"], w["id"]))
        out = {"workers": workers, "count": len(workers), "ts": int(now)}
        tmp = os.path.join(webroot, ".grid.tmp")
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, os.path.join(webroot, "grid.json"))
        time.sleep(1.0)


B64 = re.compile(r"^\[b64:([^\]]+)\] (\S+)\s*$")
SHOT = re.compile(r"^\[ot6shot\] (\d+) (\S+)\s*$")
PAD = re.compile(r"\[ot6pad\] (\d+) (\S+)")
NOTE = re.compile(r"\[ot6note\] (\d+) (.*)")
PLAIN = re.compile(r"^\[ot6\] (.*)")
# frame hints inside ordinary notes ("story f31113", "frame=2614",
# "at frame 6623") -- the counter's source when no [ot6pad] taps flow
HINT = re.compile(r"(?:\bframe[= ]|[ (]f)(\d{3,})\b")


def build_progress(states, xy, compose, rootp, t0, live_test):
    """One progress.json payload: every graph edge's status (done when its
    stamp passes compose's freshness check, running when a live workspace
    bears its name, pending otherwise), WoB coords for the map, a
    remaining-spine ETA from the ninja log's durations, and which single
    edge is on the live view.

    live_test is the state name of the workspace follow() is tailing -- the
    ONE segment streaming on index.html.  It is distinct from `running`,
    which can hold several edges at once under -j parallelism; only this one
    is on the live view.  Its name may be an edge's primary state or one of
    its `also` artifacts, so the marked node is the primary edge either way.
    """
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
                running.add(os.path.basename(os.path.dirname(ws)).split(".")[0])
        except OSError:
            pass
    edges, done = [], 0
    for e in states:
        n = e["state"]
        names = [n] + list(e.get("also") or [])
        cost = max((dur.get(x, 0.0) for x in names), default=0.0)
        # a live workspace outranks content freshness: artifacts from a
        # superseded edge can pass the stamp check while their replacement
        # run is mid-flight
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
        ed = {"name": n, "dur": cost, "status": st,
              "ckpt": bool(e.get("checkpoint"))}
        if n in xy:   # WoB world-tile coords for the map view
            ed["x"], ed["y"] = round(xy[n][0], 1), round(xy[n][1], 1)
        if live_test and live_test in names:
            ed["live"] = True   # the one node on index.html's live view
        edges.append(ed)
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
    return {"edges": edges, "done": done, "total": len(edges),
            "running": sorted(running & set(owner)),
            # the live node's PRIMARY edge name (owner maps `also` -> primary),
            # or None when nothing is on the live view
            "live": owner.get(live_test) if live_test else None,
            "elapsed_min": int((time.time() - t0) / 60),
            "eta_min": int(eta / 60)}


def progress_thread(webroot, stop, live_ref=None):
    """Write progress.json every 5s (see build_progress).  live_ref is the
    dict follow() keeps its currently-tailed test name in, shared so the one
    live-view segment can be flagged without either thread blocking."""
    states = runpy.run_path(
        os.path.join(ROOT, "tools/tests/savestate_graph.py"))["STATES"]
    xy = _route_coords([e["state"] for e in states])
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
        live_test = (live_ref or {}).get("test")
        out = build_progress(states, xy, compose, rootp, t0, live_test)
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


def follow(log_path, webroot, test, stop, hop=False, live_ref=None):
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
            if line.startswith("[ot6action] "):
                try:
                    e = json.loads(line[len("[ot6action] "):])
                    note = (f'action #{e["id"]} actor {e["actor"]}: '
                            f'{e["kind"]} {e["event"]} +{e["elapsed_frames"]}f')
                    if "reason" in e:
                        note += " — " + e["reason"]
                    if "hp_net" in e:
                        note += " HP net [" + e["hp_net"] + "]"
                    state["frame"] = max(state["frame"], e["frame"])
                    state["notes"] = (state["notes"] + [note])[-8:]
                except (ValueError, KeyError, TypeError):
                    pass  # a partial/bad trace must not stop the live viewer
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
                        # tell progress.json the live view moved segments
                        if live_ref is not None:
                            live_ref["test"] = state["test"]
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
    write_pages(webroot)
    ensure_map(webroot)

    stop = threading.Event()
    # shared so progress_thread can flag the one edge follow() is tailing
    # (updated on channel-hop); starts on the workspace main() picked
    live_ref = {"test": test}
    threading.Thread(target=follow,
                     args=(log, webroot, test, stop, args.workspace is None,
                           live_ref),
                     daemon=True).start()
    threading.Thread(target=progress_thread, args=(webroot, stop, live_ref),
                     daemon=True).start()
    threading.Thread(target=grid_thread, args=(webroot, stop, live_ref),
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
