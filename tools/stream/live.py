#!/usr/bin/env python3
"""live.py -- watch a headless run while it happens.  No video anywhere:
the harness's own stdout stream is the broadcast.

    tools/tests/run.sh tools/tests/<x>.lua &               # the run
    python3 tools/stream/live.py                           # the viewer

Follows the newest (or the named) run workspace under build/test-runs/ by
tailing its growing run.log:

  [ot6shot] <f> <b64>   the live screenshot stream (every 128 frames by
                        default; on in EVERY run.sh run -- no off switch)
  [b64:<tag>] <chunk>   milestone screenshot blobs, shown as frames too
  [ot6pad] <f> <pad>    the live frame counter and held buttons
  [ot6note] <f> <text>  the driver's notes
  [ot6] <text>          every other log line, shown as notes too

Serves one page on --port (default 8611).  Latency is Mesen's stdout block
buffering: bursts every second or so.

More machines: `--peer air.local` (repeatable; `host:path` when the repo is
not at ~/ot6 there) adds that machine's workers, load and route progress to
the same pages.  The viewer runs `ssh <host> python3 - --emit` with this very
file on stdin: the far side scans its own run logs with the code below and
prints one JSON snapshot a second, and exits when the connection drops.
Nothing is installed or left running there and no port is opened.  The local
machine goes through the same snapshot path, minus the ssh.

Throughput and placement.  Each machine's line shows its emulated frames per
second, summed over its active emulators across the last 30 s.  Every run
watched from its start on any machine appends one line to the main tree's
build/throughput.jsonl when it finishes: machine, test, frames, wall seconds,
and the concurrency it ran at (emulators, and the load average).  From that
log each machine gets a curve of frames/s per emulator against emulators
running, recent runs weighing more (6 h half-life), so it follows other load,
heat and power as they change; and from
the curve and what the machine runs right now, how many more emulators it
can take before its total stops growing.  That is placement.json, one line on
the page, and:

    python3 tools/stream/live.py --place 8     # where the next 8 should go
"""
import argparse
import base64
import collections
import glob
import hashlib
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import importlib.util
import runpy
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# OT6_ROOT is set by the --emit transport, where this file arrives on stdin
# and has no path of its own.
ROOT = os.path.abspath(os.environ.get("OT6_ROOT") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HOST = socket.gethostname().split(".")[0].lower()   # this machine's label

# Runs happen in every git worktree of this repo (agents and the release
# qualification each get their own), not only under ROOT, and in plain clones
# parked where agent worktrees live (.claude/worktrees/ of the main tree) or
# anywhere a running worker's command line points (<clone>/build/test-runs/).
# The worker grid, the progress view and the newest-workspace picker all look
# through the same list, refreshed every 5s, so the owner sees what is
# actually running.  "main" is the main tree: its workers carry no tag.
_TREES = {"ts": 0.0, "roots": [ROOT], "branch": {}, "main": ROOT}


RUNNING_TREE = re.compile(r"(/\S+?)/build/test-runs/[^/\s]+/")


def _refresh_trees():
    roots, branch, main = [], {}, None
    try:
        out = subprocess.run(["git", "-C", ROOT, "worktree", "list",
                              "--porcelain"], capture_output=True,
                             text=True, timeout=5).stdout
        cur = None
        for line in out.splitlines():
            if line.startswith("worktree "):
                cur = line[len("worktree "):].strip()
                main = main or cur
                if cur and cur not in roots and os.path.isdir(cur):
                    roots.append(cur)
            elif line.startswith("branch ") and cur:
                branch[cur] = line[len("branch "):].replace("refs/heads/", "", 1)
            elif line == "detached" and cur:
                branch[cur] = "(detached)"
    except Exception:
        pass
    main = main or ROOT
    if ROOT not in roots:
        roots.insert(0, ROOT)
    extra = set(glob.glob(os.path.join(main, ".claude/worktrees/*")))
    try:   # clones anywhere else, found through their running workers' argv
        ps = subprocess.run(["ps", "-Ao", "command"], capture_output=True,
                            text=True, timeout=5).stdout
        extra |= set(RUNNING_TREE.findall(ps))
    except Exception:
        pass
    for d in sorted(extra):
        if d in roots or not os.path.exists(os.path.join(d, ".git")):
            continue
        roots.append(d)   # a plain clone: not in the worktree list
        try:
            branch[d] = subprocess.run(
                ["git", "-C", d, "branch", "--show-current"],
                capture_output=True, text=True, timeout=5).stdout.strip() or "?"
        except Exception:
            branch[d] = "?"
    _TREES.update(roots=roots, branch=branch, main=main, ts=time.time())


def worktree_roots():
    if time.time() - _TREES["ts"] > 5:
        _refresh_trees()
    return _TREES["roots"]


def run_logs():
    """Every build/test-runs/<ws>/run.log across the worktrees."""
    logs = []
    for r in worktree_roots():
        logs += glob.glob(os.path.join(r, "build/test-runs/*/run.log"))
    return logs


def log_tree(log):
    """(tag, branch) of the tree a run log lives in; tag is a short label
    for the worktree ("" for the main tree)."""
    best = ""
    for r in worktree_roots():
        if log.startswith(r + os.sep) and len(r) > len(best):
            best = r      # the longest match: agent trees live under the main one
    tag = "" if best in ("", _TREES["main"]) else os.path.basename(best)
    return tag, _TREES["branch"].get(best, "?")



# The default landing: a worker grid of EVERY active run worker,
# one tile per live workspace, growing/shrinking as workers start and finish.
# Data comes from grid.json (Board.write); each tile's screenshot is a cached
# PNG under build/live/grid/.  Above the tiles, one line per machine: up or
# unreachable, load, active and frozen counts, and which branch/worktree each
# of its workers belongs to.  A tile click opens the single-worker detail
# (live1.html) for that worker.
GRID_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 workers</title>
<body style="margin:0;background:#111;color:#cdc;font:13px ui-monospace,monospace">
<div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px;padding:10px 14px">
<b style="font-size:16px">live workers</b>
<span id=hdr style="color:#8a8"></span>
<a href="progress.html" style="color:#8ac">route map &rarr;</a></div>
<div id=machines style="padding:0 14px 10px;line-height:1.6"></div>
<div id=grid style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;padding:0 14px 18px"></div>
<div id=starting style="color:#575;padding:0 14px 14px;font-size:11px;line-height:1.7"></div>
<div id=empty style="color:#575;padding:2px 14px">waiting for workers…</div>
<script>
const $=id=>document.getElementById(id);
const nf=n=>(n==null?'\\u2014':Number(n).toLocaleString());
const esc=t=>String(t==null?'':t).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
async function tick(){ try{
  const j = await (await fetch('grid.json?'+Date.now())).json();
  const all = j.workers||[]; const grid=$('grid');
  // A worker that has not emitted a screenshot yet has nothing to show, and a
  // black tile reading "frame —" is worse than nothing: at 32 workers the
  // handful that ARE playing get lost in a wall of them.  Those are listed by
  // name underneath instead, and promote themselves into the grid the moment
  // they have a frame.
  const ws = all.filter(w=>w.shot);
  const starting = all.filter(w=>!w.shot);
  $('empty').style.display = all.length ? 'none' : 'block';
  $('hdr').textContent = all.length ? (all.length+' active worker'+(all.length>1?'s':'')
    + ' · '+all.filter(w=>w.stuck).length+' frozen'
    + (starting.length ? ' · '+starting.length+' booting' : '')) : '';
  // Live processes whose first screenshot has not landed yet.  There is no
  // second case any more: OT6_LIVE is gone and every run broadcasts, so a
  // worker without a picture is booting rather than mute, and it promotes
  // itself into the grid as soon as it has a frame.  Its latest log line is
  // shown meanwhile, since that is all it has.
  let html = '';
  if(starting.length) html += '<div>' + starting.length
    + ' booting, no frame yet</div>';
  starting.forEach(w=>{ html += '<div style="margin-top:3px">'
    + '<span style="color:#7a7">' + esc(w.machine) + ' \u00b7 ' + esc(w.name) + '</span>'
    + (w.frame!=null ? ' · frame '+nf(w.frame) : '')
    + (w.last ? '<div style="color:#687;padding-left:14px;white-space:nowrap;'
      + 'overflow:hidden;text-overflow:ellipsis">' + esc(w.last) + '</div>' : '')
    + '</div>'; });
  $('starting').innerHTML = html;
  const hm=t=>new Date(t*1000).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
  $('machines').innerHTML = (j.machines||[]).map(m=>{
    if(!m.up) return '<div><b style="color:#d9a24b">'+esc(m.name)+'</b> <span style="color:#d9a24b">'
      + (m.err==='connecting' ? 'connecting\u2026' : 'unreachable since '+hm(m.down_since))
      + '</span>' + (m.err && m.err!=='connecting' ? ' <span style="color:#687">('+esc(m.err)+')</span>' : '') + '</div>';
    let h = '<div><b>'+esc(m.name)+'</b> <span style="color:#8a8">'
      + m.active+' active \u00b7 '
      + '<span style="color:'+(m.frozen?'#e06060':'#8a8')+'">'+m.frozen+' frozen</span>'
      + (m.load ? ' \u00b7 load '+m.load[0].toFixed(1)+' / '+m.ncpu+' cores' : '')
      + (m.fps!=null ? ' \u00b7 '+nf(Math.round(m.fps))+' frames/s' : '')
      + (m.room!=null ? ' \u00b7 room '+m.room+' (peak '+m.peak+')' : '') + '</span></div>';
    m.trees.forEach(t=>{ h += '<div style="color:#8a9;padding-left:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'
      + '<span style="color:#9bc">'+esc(t.branch)+'</span>'+(t.tree?' <span style="color:#687">@'+esc(t.tree)+'</span>':'')
      + ' \u00b7 '+t.tests.length+': '+esc(t.tests.join(', '))+'</div>'; });
    return h; }).join('')
    + (j.place ? '<div style="color:#687">' + esc(j.place) + '</div>' : '');
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
        + '<span class=mc style="position:absolute;top:5px;left:5px;'
        + 'font-size:10px;padding:1px 5px;border-radius:3px;'
        + 'background:#000a;color:#cdc"></span>'
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
    t.querySelector('.mc').textContent = w.machine;
    t.querySelector('.fr').textContent = 'frame '+nf(w.frame);
    const badge = t.querySelector('.badge');
    // a frozen worker gets a red rim and badge; every other a plain rim
    if(w.stuck){ t.style.borderColor='#d24b4b';
      badge.textContent='\\u26A0 FROZEN'; badge.style.background='#d24b4b';
      badge.style.color='#fff'; }
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
# any grid worker's big screenshot, frame, stuck flag and latest notes,
# sourced from grid.json.
DETAIL_PAGE = """<!doctype html><meta charset="utf-8"><title>OT6 live</title>
<body style="margin:0;background:#111;color:#cdc;display:grid;place-items:center;min-height:100vh;font:14px ui-monospace,monospace">
<div style="text-align:center;padding:12px">
<div style="font-size:16px;padding-bottom:6px"><span id=who style="color:#cdc"></span></div>
<img id=f src="latest.png" style="image-rendering:pixelated;display:block;margin:0 auto;width:min(768px,95vw);outline:none">
<div style="padding:8px 0;font-size:18px"><span id=frame>-</span> <span id=pad style="color:#8ac"></span></div>
<div id=notes style="text-align:left;max-width:min(768px,95vw);margin:0 auto;color:#9a9;white-space:pre-wrap;word-break:break-all"></div>
<div id=s style="color:#575;padding-top:6px">connecting…</div>
<div style="padding-top:4px">
<a href="index.html" style="color:#8ac">&larr; workers</a> ·
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
  // (status.json streams a worker on THIS machine: a same-named worker on
  // another machine is not it)
  if(grid){ tgt = wid ? (grid.find(w=>w.id===wid) || null)
                      : (grid.find(w=>w.local && w.name===followed) || null); }
  const targetName = wid ? (tgt ? tgt.name : null) : followed;
  const isFollowed = !!st && !!targetName && targetName===st.test
    && (!tgt || tgt.local);
  $('who').textContent = (targetName || (wid ? '('+wid+')' : '(waiting)'))
    + (tgt ? ' \u00b7 ' + tgt.machine
       + (tgt.branch ? ' \u00b7 ' + tgt.branch : '') : '');
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
    // grid path: a worker the server isn't streaming in detail
    $('frame').textContent='frame '+nf(tgt.frame);
    $('pad').textContent='';
    $('notes').textContent=(tgt.notes||[]).join('\\n');
    $('s').textContent=tgt.name+' on '+tgt.machine+(tgt.stuck?' · \\u26A0 frozen':'');
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
<div id=legend style="color:#687;font-size:11px"></div>
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
  const e = n && last ? last.edges.find(x=>x.name===n) : null;
  document.getElementById('pick').textContent = e ? tip(e) : (n || ''); });
function esc(s){ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
// done here: green; done only on another machine (merged from a --peer):
// teal; running anywhere: amber.  e.on lists the machines.
function doneCol(e, j){ return (e.on && j.local && e.on.length
  && !e.on.includes(j.local)) ? '#3a8f9d' : '#3f9d63'; }
function tip(e){ return e.name + (e.on && e.on.length
  ? ' \u2014 ' + e.status + ' on ' + e.on.join(', ') : ''); }
function render(j){
  if(view==='wob') renderWob(j); else renderGrid(j);
  document.getElementById('hdr').textContent =
    `${j.done}/${j.total} segments · ${j.elapsed_min} min elapsed · ~${j.eta_min} min left`;
  document.getElementById('cur').textContent =
    j.running.length ? ('now playing: ' + j.running.join(', ')) : '';
  document.getElementById('legend').innerHTML = j.local ?
    `<span style="color:#3f9d63">\u25cf</span> done on ${esc(j.local)} \u00b7 `
    + `<span style="color:#3a8f9d">\u25cf</span> done only on another machine \u00b7 `
    + `<span style="color:#e0a93e">\u25cf</span> running (machine named above)` : '';
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
    const col = e.status==='done' ? doneCol(e,j) : e.status==='running' ? '#e0a93e' : '#39413b';
    const pulse = e.status==='running' ? `<animate attributeName="r" values="${rad};${rad+1.4};${rad}" dur="1.2s" repeatCount="indefinite"/>` : '';
    // checkpoint-booted segments wear the dotted yellow ring, as in the
    // grid; the rest get a hairline dark rim so they read against the map
    const ring = e.ckpt ? ` stroke="#e8c94a" stroke-width=".55" stroke-dasharray="1 .8"`
                        : ` stroke="#0c100d" stroke-width=".35"`;
    out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${rad.toFixed(1)}"
      fill="${col}" fill-opacity="${e.status==='pending'?.75:1}"${ring}
      data-name="${esc(e.name)}" style="cursor:pointer">
      <title>${esc(tip(e))}</title>${pulse}</circle>`;
    // labels stay sparse at 76 nodes: running, most recent done
    if(e.status==='running' || i===lastDone){
      const txt = e.name;
      const lw = 2.8*txt.length;   // ~half the label's width in units
      const lx = Math.min(Math.max(x, lw/2+2), 254-lw/2);
      const ly = y-rad-1.5 < 6 ? y+rad+5.5 : y-rad-1.5;
      labels += `<text x="${lx.toFixed(1)}" y="${ly.toFixed(1)}"
        fill="${e.status==='running'?'#f4d27a':'#bfe3c8'}" font-size="5"
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
    const col = e.status==='done' ? doneCol(e,j) : e.status==='running' ? '#e0a93e' : '#3a423c';
    const pulse = e.status==='running' ? `<animate attributeName="r" values="${rad};${rad+4};${rad}" dur="1.2s" repeatCount="indefinite"/>` : '';
    // segments that boot from an SRAM save checkpoint rather than the
    // played chain wear a dotted yellow ring
    const ring = e.ckpt ? ` stroke="#e8c94a" stroke-width="2" stroke-dasharray="4 3"` : '';
    out += `<circle cx="${x}" cy="${y}" r="${rad}" fill="${col}"${ring}><title>${esc(tip(e))}</title>${pulse}</circle>`
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
    # index.html is the worker grid (default landing); the classic
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


# ---- the worker grid: one tile per active run worker ----------------------
SHOT_B = re.compile(rb"^\[ot6shot\] (\d+) (\S+)")   # bytes, for tail scans
PAD_B = re.compile(rb"^\[ot6pad\] (\d+)")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def _safe_id(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", s)


def _last_note(data):
    """The newest ordinary [ot6] line in a log tail, for a worker that has no
    picture to show.  A non-streaming run is not silent, it just is not
    drawing, and its last line is the most useful thing it has."""
    for line in reversed(data.splitlines()):
        if line.startswith(b"[ot6] ") and not line.startswith(b"[ot6] [watch]"):
            try:
                return line[6:].decode("utf-8", "replace")[:150]
            except Exception:
                return None
    return None


def _last_notes(data, n):
    """The newest n ordinary [ot6] lines in a log tail, oldest first: the
    notes any worker's detail page shows."""
    out = []
    for line in reversed(data.splitlines()):
        if line.startswith(b"[ot6] ") and not line.startswith(b"[ot6] [watch]"):
            out.append(line[6:].decode("utf-8", "replace")[:300])
            if len(out) >= n:
                break
    return out[::-1]


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


# ---- throughput: frames emulated per second, and one record per run -------
FRAME_B = re.compile(rb"^\[ot6(?:shot|pad|note)\] (\d+) ")
FPS_WINDOW = 30.0      # seconds the per-machine frames/s figure averages over


def run_progress(data):
    """(latest frame, verdict) from a run.log tail.  The frame is M.frame on
    the newest complete [ot6shot]/[ot6pad]/[ot6note] line: the harness's own
    count of frames it has advanced, reset to 0 when an attempt restarts.  A
    partial trailing line is skipped, since a half-written number would read
    as a reset.  verdict is "pass", "fail" or None."""
    lines = data.split(b"\n")[:-1]
    frame = None
    for line in reversed(lines):
        m = FRAME_B.match(line)
        if m:
            frame = int(m.group(1))
            break
    verdict = None
    p, f = data.rfind(b"\n[ot6] PASS (frame "), data.rfind(b"\n[ot6] FAIL: ")
    if max(p, f) >= 0:
        verdict = "pass" if p > f else "fail"
    return frame, verdict


def _run_start(ws):
    """(start time, script name) of a run workspace: run.sh writes
    composed_live.lua once, just before it launches the emulator, and its
    third line names the script (compose.py's OT6_SCRIPT)."""
    try:
        path = os.path.join(ws, "composed_live.lua")
        with open(path, "rb") as f:
            head = f.read(400)
        m = re.search(rb'^OT6_SCRIPT = "([^"]+)"', head, re.M)
        return os.path.getmtime(path), (m.group(1).decode() if m else None)
    except OSError:
        return None, None


class Scanner:
    """This machine's view, one JSON-able snapshot per call: every active run
    worker (build/test-runs/*/run.log touched within ACTIVE_SEC -- the same
    live-worker mtime filter stuck_detector uses) with its frame, stuck flag,
    latest notes and tree/branch; the load average; and, whenever a new one
    is ready (about every 5s), the route progress (build_progress).  A worker's decoded screenshot rides along in
    "pngs" only when it changed since the previous snapshot.

    The local grid ingests snapshots directly; another machine's viewer gets
    them over ssh from --emit.  Both go through Board.ingest."""

    def __init__(self, live_ref=None):
        try:   # stuck_detector's tuning, so freeze thresholds stay single-source
            sd = _load_stream_module("stuck_detector")
            self.tuning = (sd.ACTIVE_SEC, sd.TAIL_BYTES,
                           sd.SHOTS_STUCK, sd.FRAMES_STUCK)
        except Exception:
            self.tuning = (40, 200_000, 8, 2000)
        self.sent = {}         # worker id -> hash8 of the PNG last handed out
        self.live_ref = live_ref
        self.prog = None       # progress inputs, loaded on first use
        self.fresh = None      # a progress payload not yet handed out
        self.t0 = time.time()
        self.runs = {}         # worker id -> what one run has done so far
        self.recorded = set()  # worker ids already finished and reported
        self.incs = collections.deque()   # (ts, frames) advanced, all workers
        # the stamp checks take seconds, so the route has its own thread and
        # never holds up the 1s worker scan
        threading.Thread(target=self._progress_loop, daemon=True).start()

    def _progress_loop(self):
        while True:
            self.fresh = self.progress()
            time.sleep(5)

    def progress(self):
        try:
            if self.prog is None:
                states = runpy.run_path(os.path.join(
                    ROOT, "tools/tests/savestate_graph.py"))["STATES"]
                xy = _route_coords([e["state"] for e in states])
                # freshness check: compose.py's own stamp verification
                # (signature over generator+libs+extras, artifact hash,
                # ancestor chain).  A fresh stamp is what ninja will not
                # re-run -- except for a ROM-content change, which the graph
                # tracks separately and a mid-gate page can ignore honestly.
                spec = importlib.util.spec_from_file_location(
                    "compose", os.path.join(ROOT, "tools/tests/lib/compose.py"))
                compose = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(compose)
                from pathlib import Path
                self.prog = (states, xy, compose, Path(ROOT))
            live_test = (self.live_ref or {}).get("test")
            return build_progress(*self.prog, self.t0, live_test)
        except Exception as e:
            return {"error": f"{type(e).__name__}: {e}"[:200]}

    def snapshot(self):
        active_sec, tail_n, s_stuck, f_stuck = self.tuning
        now = time.time()
        workers, pngs, active = [], {}, set()
        for log in run_logs():
            try:
                mtime = os.path.getmtime(log)
                if now - mtime > active_sec:
                    continue
                dirname = os.path.basename(os.path.dirname(log))
                data = _tail_bytes(log, tail_n)
            except OSError:
                continue
            tag, branch = log_tree(log)
            wid = _safe_id((tag + "_" if tag else "") + dirname)
            frame, png, h, stuck = scan_worker(data, s_stuck, f_stuck)
            self._track(wid, log, tag, branch, data, mtime, now)
            active.add(wid)
            if png is not None and h is not None and self.sent.get(wid) != h:
                pngs[wid] = png
                self.sent[wid] = h
            rec = {"id": wid, "test": dirname.split(".")[0], "tree": tag,
                   "branch": branch, "frame": frame, "h": self.sent.get(wid),
                   "stuck": bool(stuck), "notes": _last_notes(data, 8)}
            if not rec["h"]:
                # nothing to draw YET -- the broadcast is unconditional, so
                # this worker is booting and will fill in.  Offer its latest
                # log line meanwhile, which is all it has.
                rec["last"] = _last_note(data)
            workers.append(rec)
        for wid in list(self.sent):
            if wid not in active:
                del self.sent[wid]
        try:
            load = [round(x, 2) for x in os.getloadavg()]
        except OSError:
            load = None
        done = self._settle(active, len(workers), load, now)
        snap = {"host": HOST, "ts": now, "load": load, "ncpu": os.cpu_count(),
                "workers": workers, "pngs": pngs, "fps": self._fps(now)}
        if done:
            snap["done"] = done
        fresh, self.fresh = self.fresh, None
        if fresh is not None:
            snap["progress"] = fresh
        return snap

    def _track(self, wid, log, tag, branch, data, mtime, now):
        """Fold one scan of one worker into its run: frames advanced since
        the last scan (a drop in M.frame is a restarted attempt, counted from
        0) and the newest log mtime, which is where the run ends."""
        r = self.runs.get(wid)
        if r is None:
            if wid in self.recorded:   # a retained failed workspace, touched
                return
            ws = os.path.dirname(log)
            start, script = _run_start(ws)
            label = os.path.basename(ws).split(".")[0]
            # a run is whole when it began after this scanner did, so every
            # frame it advanced was seen; only whole runs are recorded
            whole = start is not None and start >= self.t0 - 2
            r = self.runs[wid] = {
                "test": script or label, "label": label, "tree": tag,
                "branch": branch, "start": start, "end": mtime, "whole": whole,
                "last": None if not whole else 0, "frames": 0, "verdict": None,
                "n": 0, "conc": 0.0, "load": 0.0, "busy": 0.0}
        frame, verdict = run_progress(data)
        if frame is not None:
            if r["last"] is not None:
                inc = frame - r["last"] if frame >= r["last"] else frame
                r["frames"] += inc
                self.incs.append((now, inc))
            r["last"] = frame
        r["end"] = max(r["end"], mtime)
        r["verdict"] = verdict or r["verdict"]

    def _settle(self, active, n_active, load, now):
        """Sample the concurrency every live run is seeing, and turn the runs
        that stopped (workspace deleted on a pass, or gone quiet) into
        records."""
        load1 = load[0] if load else 0.0
        busy = max(n_active, load1)
        done = []
        for wid in list(self.runs):
            r = self.runs[wid]
            if wid in active:
                r["n"] += 1
                r["conc"] += n_active
                r["load"] += load1
                r["busy"] += busy
                continue
            del self.runs[wid]
            self.recorded.add(wid)
            wall = r["end"] - (r["start"] or r["end"])
            if not r["whole"] or not r["n"] or r["frames"] <= 0 or wall <= 0:
                continue
            n = r["n"]
            done.append({
                "ts": int(r["end"]), "id": wid, "test": r["test"],
                "label": r["label"], "tree": r["tree"], "branch": r["branch"],
                "frames": r["frames"], "wall": round(wall, 1),
                "fps": round(r["frames"] / wall, 1),
                "conc": round(r["conc"] / n, 2), "busy": round(r["busy"] / n, 2),
                "load": round(r["load"] / n, 2), "ncpu": os.cpu_count(),
                "verdict": r["verdict"]})
        return done

    def _fps(self, now):
        """Frames per second advanced by all of this machine's emulators over
        the last FPS_WINDOW seconds (less while the scanner is younger)."""
        while self.incs and self.incs[0][0] < now - FPS_WINDOW:
            self.incs.popleft()
        span = min(FPS_WINDOW, now - self.t0)
        if span < 5:
            return None
        return round(sum(i for _t, i in self.incs) / span, 1)


PEER_STALE_SEC = 20   # a peer silent this long is shown unreachable

# ---- placement: where the next emulators should go ------------------------
HALF_LIFE_H = 6.0   # a run this old weighs half as much as one finishing now
PEAK_FRAC = 0.95    # the knee: the fewest emulators within 5% of the best total


def curve(records, now):
    """{emulators: [frames/s per emulator, runs]} for one machine: each
    finished run's frames/wall, bucketed by how many emulators ran beside it
    (itself included, averaged over its life), averaged with weights halving
    every HALF_LIFE_H.  So recent runs outweigh old ones, and the curve
    follows whatever else slows the machine now (other load, heat, the
    charger); a bucket nothing recent has reached keeps what it last
    measured."""
    acc = {}
    for r in records:
        k = max(1, int(round(r["conc"])))
        w = 0.5 ** (max(0.0, now - r["ts"]) / (HALF_LIFE_H * 3600))
        a = acc.setdefault(k, [0.0, 0.0, 0])
        a[0] += w * r["fps"]
        a[1] += w
        a[2] += 1
    return {k: [a[0] / a[1], a[2]] for k, a in acc.items() if a[1] > 0}


def per_emulator(cv, x):
    """Frames/s one emulator gets beside x-1 others: linear between measured
    buckets; below the lowest, the lowest's; above the highest, the total
    stays flat (nothing measured says it grows)."""
    ks = sorted(cv)
    if x <= ks[0]:
        return cv[ks[0]][0]
    if x >= ks[-1]:
        return cv[ks[-1]][0] * ks[-1] / x
    for a, b in zip(ks, ks[1:]):
        if a <= x <= b:
            return cv[a][0] + (cv[b][0] - cv[a][0]) * (x - a) / (b - a)


def total(cv, x):
    return x * per_emulator(cv, x) if x > 0 else 0.0


def placement(machines, records, now):
    """placement.json: per machine its curve, its knee (the fewest emulators
    whose total is within 5% of the best measured total, one more when
    that is the most ever measured, so the curve keeps learning), room =
    knee - its active emulators now; and "order", the machines for the next
    emulators, greedily by how much each one adds to its machine's total."""
    out, gains = [], []
    for m in machines:
        mine = [r for r in records if r.get("machine") == m["name"]]
        cv = curve(mine, now)
        rec = {"name": m["name"], "up": m["up"], "active": m["active"],
               "load1": (m["load"] or [None])[0], "ncpu": m["ncpu"],
               "fps": m.get("fps"), "runs": len(mine),
               "curve": {str(k): [round(v[0], 1), v[1]]
                         for k, v in sorted(cv.items())}}
        out.append(rec)
        if not cv or not m["up"]:
            continue
        top = max(cv)
        best = max(total(cv, k) for k in range(1, top + 1))
        knee = min(k for k in range(1, top + 1)
                   if total(cv, k) >= PEAK_FRAC * best)
        if knee == top:
            knee += 1
        busy = m["active"]
        room = max(0, knee - busy)
        rec.update(peak=knee, room=room)
        for j in range(1, room + 1):
            gains.append((total(cv, busy + j) - total(cv, busy + j - 1),
                          m["name"]))
    gains.sort(key=lambda g: -g[0])
    return {"ts": int(now), "half_life_h": HALF_LIFE_H, "machines": out,
            "order": [n for _g, n in gains], "room": len(gains)}


def place_line(p):
    """The page's one line: each machine's room now."""
    parts = []
    for m in p["machines"]:
        parts.append(f"{m['name']} {m['room']}" if "room" in m else
                     f"{m['name']} (down)" if not m["up"] else
                     f"{m['name']} (no runs logged yet)")
    return ("room now: " + ", ".join(parts)
            + " · python3 tools/stream/live.py --place N")


class Board:
    """Every machine's latest snapshot, merged into grid.json (tiles plus a
    per-machine summary) and progress.json (the route, from all machines).
    Machine 0 is this one; the rest are --peer hosts, in flag order."""

    def __init__(self, webroot, names):
        self.webroot, self.names = webroot, list(names)
        self.gdir = os.path.join(webroot, "grid")
        os.makedirs(self.gdir, exist_ok=True)
        self.lock = threading.Lock()
        t = time.time()
        # name -> {"snap", "progress", "ok_ts", "down_since", "err"}
        self.m = {n: {"snap": None, "progress": None, "ok_ts": None,
                      "down_since": t, "err": "connecting"} for n in names}
        self.pngs = {n: set() for n in names}   # PNG files on disk per machine
        self.procs = {}   # name -> its live ssh child (peer_thread)
        # The run log lives in the main tree, like build/attempts, so every
        # viewer (whichever tree it runs from) adds to and reads one history.
        worktree_roots()
        self.log = os.path.join(_TREES["main"], "build", "throughput.jsonl")
        self.records, self.seen = [], set()
        try:
            with open(self.log) as f:
                for line in f:
                    try:
                        self._remember(json.loads(line))
                    except (ValueError, KeyError, TypeError):
                        pass
        except OSError:
            pass

    def _remember(self, rec):
        """Keep one finished-run record; False if it is already known (two
        viewers watching the same machine both report its runs)."""
        key = (rec["machine"], rec["id"])
        if key in self.seen:
            return False
        self.seen.add(key)
        self.records.append(rec)
        return True

    def _log_runs(self, name, done):
        lines = []
        with self.lock:
            for d in done:
                rec = dict(d, machine=name)
                if self._remember(rec):
                    lines.append(json.dumps(rec) + "\n")
        if lines:
            try:
                os.makedirs(os.path.dirname(self.log), exist_ok=True)
                with open(self.log, "a") as f:
                    f.write("".join(lines))
            except OSError as e:
                print(f"live: {self.log}: {e}", file=sys.stderr)

    def _png(self, name, wid):
        return os.path.join(self.gdir, _safe_id(f"{name}_{wid}") + ".png")

    def ingest(self, name, snap):
        for wid, png in (snap.get("pngs") or {}).items():
            if isinstance(png, str):
                png = base64.b64decode(png)
            try:
                tmp = os.path.join(self.gdir, "." + _safe_id(name + wid) + ".tmp")
                with open(tmp, "wb") as f:
                    f.write(png)
                os.replace(tmp, self._png(name, wid))
                self.pngs[name].add(wid)
            except OSError:
                pass
        live = {w["id"] for w in snap.get("workers", [])}
        for wid in list(self.pngs[name] - live):   # finished workers
            self._drop_png(name, wid)
        if snap.get("done"):
            self._log_runs(name, snap["done"])
        with self.lock:
            st = self.m[name]
            st["snap"] = dict(snap, pngs=None)
            if snap.get("progress") is not None:
                st["progress"] = snap["progress"]
            st.update(ok_ts=time.time(), down_since=None, err=None)

    def _drop_png(self, name, wid):
        try:
            os.remove(self._png(name, wid))
        except OSError:
            pass
        self.pngs[name].discard(wid)

    def down(self, name, err):
        with self.lock:
            st = self.m[name]
            if st["down_since"] is None:
                st["down_since"] = st["ok_ts"] or time.time()
            st.update(snap=None, progress=None, err=err)
        for wid in list(self.pngs[name]):
            self._drop_png(name, wid)

    def write(self):
        now = time.time()
        with self.lock:
            for n, st in self.m.items():   # a wedged stream reads as down
                if st["snap"] and now - st["ok_ts"] > PEER_STALE_SEC:
                    st.update(down_since=st["ok_ts"], snap=None, progress=None,
                              err=f"no data for {int(now - st['ok_ts'])}s")
                    p = self.procs.get(n)
                    if p is not None:
                        p.kill()     # and peer_thread reconnects
            m = {n: dict(st) for n, st in self.m.items()}
        workers, machines = [], []
        for n in self.names:
            st, snap = m[n], m[n]["snap"]
            mine = []
            for w in (snap or {}).get("workers", []):
                rec = {k: v for k, v in w.items() if k != "h"}
                rec.update(
                    id=_safe_id(f"{n}_{w['id']}"), machine=n, local=(n == HOST),
                    name=w["test"] + (f" @{w['tree']}" if w["tree"] else ""),
                    shot=(f"grid/{_safe_id(n + '_' + w['id'])}.png?{w['h']}"
                          if w.get("h") else None))
                mine.append(rec)
            mine.sort(key=lambda w: (w["name"], w["id"]))
            workers += mine
            trees = {}
            for w in mine:
                trees.setdefault((w["branch"], w["tree"]), []).append(w["test"])
            machines.append({
                "name": n, "local": n == HOST, "up": snap is not None,
                "down_since": st["down_since"], "err": st["err"],
                "load": (snap or {}).get("load"), "ncpu": (snap or {}).get("ncpu"),
                "fps": (snap or {}).get("fps"),
                "active": len(mine), "frozen": sum(w["stuck"] for w in mine),
                "trees": [{"branch": b, "tree": t, "tests": sorted(ts)}
                          for (b, t), ts in sorted(trees.items())]})
        with self.lock:
            records = list(self.records)
        place = placement(machines, records, now)
        for mc, pm in zip(machines, place["machines"]):
            mc.update({k: pm[k] for k in ("room", "peak") if k in pm})
        out = {"workers": workers, "count": len(workers), "ts": int(now),
               "machines": machines, "local": HOST, "place": place_line(place)}
        self._dump("grid.json", out)
        self._dump("placement.json", place)
        prog = self.merge_progress(m)
        if prog is not None:
            self._dump("progress.json", prog)

    def merge_progress(self, m):
        """The local route (its coords, ETA and done/running) with every other
        machine's running and done folded in by edge name.  Each edge's "on"
        lists the machines it is running or done on, so the map can tell a
        segment done here from one done only elsewhere."""
        base = m[self.names[0]]["progress"]
        if not base or "edges" not in base:
            return None
        out = dict(base, edges=[dict(e) for e in base["edges"]], local=HOST)
        per = {n: {e["name"]: e["status"] for e in m[n]["progress"]["edges"]}
               for n in self.names
               if m[n]["progress"] and "edges" in m[n]["progress"]}
        running = []
        for e in out["edges"]:
            run = [n for n in self.names if per.get(n, {}).get(e["name"]) == "running"]
            done = [n for n in self.names if per.get(n, {}).get(e["name"]) == "done"]
            e["status"] = "running" if run else "done" if done else "pending"
            e["on"] = run or done
            if run:
                running.append(f"{e['name']} ({', '.join(run)})")
        out["running"] = running
        out["done"] = sum(e["status"] == "done" for e in out["edges"])
        return out

    def _dump(self, fname, obj):
        tmp = os.path.join(self.webroot, "." + fname + ".tmp")
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, os.path.join(self.webroot, fname))


def local_thread(board, stop, live_ref=None):
    """This machine: a Scanner snapshot into the Board every second, then
    rewrite grid.json/progress.json from every machine's latest."""
    sc = Scanner(live_ref)
    while not stop.is_set():
        try:
            board.ingest(HOST, sc.snapshot())
        except Exception as e:   # a bad scan must not stop the viewer
            print(f"live: local scan failed: {e}", file=sys.stderr)
        board.write()
        stop.wait(1.0)


# The peer's keep-awake wrapper, chosen on the peer.  macOS: caffeinate -is
# (idle sleep, and system sleep on AC).  Linux: systemd-inhibit --what=idle,
# which logind grants an ssh session without authentication; sleep and
# lid-switch locks need interactive polkit auth, so a closed lid still
# suspends there.  Neither available: run unwrapped rather than not at all.
def awake(cmd):
    """A remote shell line running cmd under the peer's keep-awake wrapper."""
    return ("if command -v caffeinate >/dev/null 2>&1; then exec caffeinate -is "
            f"{cmd}; elif systemd-inhibit --what=idle --who=ot6 --why=probe true"
            " >/dev/null 2>&1; then exec systemd-inhibit --what=idle --who=ot6"
            f" --why='live.py is watching' {cmd}; else exec {cmd}; fi")


def peer_thread(board, peer, stop):
    """Another machine: ssh there, feed it this file on stdin as --emit, and
    ingest its snapshot lines.  The emitter runs under awake(), so
    the peer stays awake for as long as
    this viewer watches it, and may sleep again once it stops.  Any failure (asleep, off the network, no
    repo) marks it down with the last diagnostic line and retries in 10s;
    ssh keepalives notice a peer that vanished mid-stream."""
    host, _, path = peer.partition(":")
    name = host.split(".")[0].lower()
    path = path or "ot6"
    if path.startswith("~/"):
        path = path[2:]      # ssh starts in $HOME; a quoted ~ would not expand
    cmd = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
           "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", host,
           f"cd {shlex.quote(path)} && export OT6_ROOT=\"$PWD\" && "
           + awake("python3 - --emit 2>&1")]
    with open(os.path.abspath(__file__), "rb") as f:
        src = f.read()
    while not stop.is_set():
        err = "connection closed"
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT)
            board.procs[name] = p
            try:
                p.stdin.write(src)
                p.stdin.close()
                for line in p.stdout:
                    if line.startswith(b"{"):
                        try:
                            board.ingest(name, json.loads(line))
                            continue
                        except ValueError:
                            pass
                    line = line.decode("utf-8", "replace").strip()
                    err = line[:200] if line else err
            finally:
                if p.poll() is None:
                    p.kill()
                p.wait()
                board.procs.pop(name, None)
        except Exception as e:
            err = f"{type(e).__name__}: {e}"[:200]
        board.down(name, err)
        stop.wait(10)


def peer_name(peer):
    return peer.partition(":")[0].split(".")[0].lower()


def emit():
    """--emit: one Scanner snapshot a second on stdout, PNGs base64'd, until
    the reader goes away (the ssh connection dropped: BrokenPipe)."""
    sc = Scanner()
    try:
        while True:
            snap = sc.snapshot()
            snap["pngs"] = {k: base64.b64encode(v).decode("ascii")
                            for k, v in snap["pngs"].items()}
            sys.stdout.write(json.dumps(snap) + "\n")
            sys.stdout.flush()
            time.sleep(1.0)
    except (BrokenPipeError, KeyboardInterrupt):
        os._exit(0)


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
    whole-build time-left ETA (the savestate critical path plus the parallel
    suite phase) from the ninja log's durations, and which single
    edge is on the live view.

    live_test is the state name of the workspace follow() is tailing -- the
    ONE segment streaming on index.html.  It is distinct from `running`,
    which can hold several edges at once under -j parallelism; only this one
    is on the live view.  Its name may be an edge's primary state or one of
    its `also` artifacts, so the marked node is the primary edge either way.
    """
    dur, qdur = {}, {}
    try:
        with open(os.path.join(ROOT, "build/ninja/.ninja_log")) as f:
            for line in f:
                q = line.rstrip("\n").split("\t")
                if len(q) < 5:
                    continue
                o, secs = q[3], (int(q[1]) - int(q[0])) / 1000
                if o.startswith("build/states/") and o.endswith(".mss"):
                    dur[o[13:-4]] = secs          # savestate generate edge
                elif o.startswith("build/results/suite/") and o.endswith(".ok"):
                    qdur[o[20:-3]] = secs          # a parallel suite test edge
    except OSError:
        pass
    running = set()
    for ws in run_logs():
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
        # a live workspace takes priority over content freshness: artifacts
        # from a superseded edge can pass the stamp check while their
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
        ed = {"name": n, "dur": cost, "status": st,
              "ckpt": bool(e.get("checkpoint"))}
        if n in xy:   # WoB world-tile coords for the map view
            ed["x"], ed["y"] = round(xy[n][0], 1), round(xy[n][1], 1)
        if live_test and live_test in names:
            ed["live"] = True   # the one node on index.html's live view
        edges.append(ed)
    # remaining critical path: longest chain of not-done edges (file order is
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
    # `eta` so far is the savestate critical path -- the serial savestate
    # chain.  A full build has a phase the chain does not see: the suite
    # tests, many of which run in parallel once the ROM is built and their
    # state deps are done.  Count it so the figure reads as whole-build
    # time-left, not just savestate-generation time.  A suite is still-to-run
    # when its .ok is missing or older than the ROM; these run in parallel, so
    # divide by an effective worker count (heavy emulator workers -> about
    # half the logical cores).
    # During a plain run nothing rebuilds the ROM, every .ok stays fresh, and
    # this term is zero, so the run ETA is unchanged.
    try:
        rom_m = os.path.getmtime(os.path.join(ROOT, "build/ot6.sfc"))
    except OSError:
        rom_m = 0.0
    rem_state = sum((idx[e["state"]]["dur"] or 60)
                    for e in states if idx[e["state"]]["status"] != "done")
    rem_suite = 0.0
    for name, secs in qdur.items():
        ok = os.path.join(ROOT, f"build/results/suite/{name}.ok")
        try:
            fresh = os.path.exists(ok) and os.path.getmtime(ok) >= rom_m
        except OSError:
            fresh = False
        if not fresh:
            rem_suite += secs
    par = max((os.cpu_count() or 4) // 2, 1)
    eta = max(eta, (rem_state + rem_suite) / par)
    return {"edges": edges, "done": done, "total": len(edges),
            "running": sorted(running & set(owner)),
            # the live node's PRIMARY edge name (owner maps `also` -> primary),
            # or None when nothing is on the live view
            "live": owner.get(live_test) if live_test else None,
            "elapsed_min": int((time.time() - t0) / 60),
            "eta_min": int(eta / 60)}


def newest_workspace():
    """The workspace with the newest run.log, or None when there is none."""
    logs = run_logs()
    if not logs:
        return None
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
            if not log_path:
                raise OSError("no run yet")
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
                ws = newest_workspace()
                nl = ws and os.path.join(ws, "run.log")
                if nl and nl != log_path:
                    log_path, pos, quiet = nl, 0, 0.0
                    state["test"] = os.path.basename(ws).split(".")[0]
                    # tell progress.json the live view moved segments
                    if live_ref is not None:
                        live_ref["test"] = state["test"]
                    state["frame"], state["pad"] = 0, "-"
                    state["exact"] = False
                    state["notes"] = [f"— hopped to {state['test']} —"]
        time.sleep(0.25)


def place(n, port):
    """--place N: the running viewer's placement.json, read for N emulators."""
    import urllib.request
    try:
        with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/placement.json", timeout=5) as r:
            p = json.load(r)
    except Exception as e:
        sys.exit(f"no placement: is live.py running on port {port}? ({e})")
    counts = collections.Counter(p["order"][:n])
    got = ", ".join(f"{m} {c}" for m, c in counts.most_common()) or "nowhere"
    print(f"place {n}: {got}")
    if n > p["room"]:
        print(f"  only {p['room']} have room now; the other {n - p['room']} "
              "would slow every emulator where they land: queue them")
    for m in p["machines"]:
        if "room" not in m:
            why = "down" if not m["up"] else "no runs logged yet"
            print(f"  {m['name']}: {why}")
            continue
        cv = " ".join(f"{k}:{v[0]:.0f}" for k, v in m["curve"].items())
        print(f"  {m['name']}: room {m['room']} = knee {m['peak']} - "
              f"{m['active']} running (load {m['load1']}, {m['ncpu']} cores)"
              f" · frames/s per emulator by emulators running: {cv} "
              f"({m['runs']} runs)")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workspace", nargs="?", help="a build/test-runs/<ws> dir "
                    "(default: the one with the newest run.log)")
    ap.add_argument("--port", type=int, default=8611)
    ap.add_argument("--peer", action="append", default=[], metavar="HOST[:PATH]",
                    help="also show this machine's workers, over ssh (repo at "
                    "~/ot6 there unless :PATH); repeatable")
    ap.add_argument("--place", type=int, metavar="N",
                    help="ask the running viewer (on --port) where the next N "
                    "emulators should go, and exit")
    ap.add_argument("--emit", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.emit:     # the far end of a --peer connection
        return emit()
    if args.place is not None:
        return place(args.place, args.port)

    ws = os.path.abspath(args.workspace) if args.workspace else newest_workspace()
    log = os.path.join(ws, "run.log") if ws else None
    test = os.path.basename(ws).split(".")[0] if ws else None

    # The webroot is stable, outside any run workspace: workspaces are
    # deleted when their run succeeds, and a server rooted inside one dies
    # with it.
    webroot = os.path.join(ROOT, "build", "live")
    os.makedirs(webroot, exist_ok=True)
    write_pages(webroot)
    ensure_map(webroot)

    stop = threading.Event()
    # shared so the progress scan can flag the one edge follow() is tailing
    # (updated on channel-hop); starts on the workspace main() picked
    live_ref = {"test": test}
    threading.Thread(target=follow,
                     args=(log, webroot, test, stop, args.workspace is None,
                           live_ref),
                     daemon=True).start()
    board = Board(webroot, [HOST] + [peer_name(p) for p in args.peer])
    threading.Thread(target=local_thread, args=(board, stop, live_ref),
                     daemon=True).start()
    for p in args.peer:
        threading.Thread(target=peer_thread, args=(board, p, stop),
                         daemon=True).start()

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port),
                                partial(SimpleHTTPRequestHandler,
                                        directory=webroot))
    # a plain kill runs the cleanup below too (the ssh children)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print(f"live: http://127.0.0.1:{args.port}/  (test {test}, log {log}, "
          f"machines {', '.join(board.names)})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        for p in list(board.procs.values()):   # the ssh children
            p.kill()


if __name__ == "__main__":
    main()
