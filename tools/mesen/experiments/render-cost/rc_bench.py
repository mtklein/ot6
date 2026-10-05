#!/usr/bin/env python3
"""rc_bench.py <workload> <variant> <rep> -- one timed run for wt/render-cost.

Runs tools/tests/run_rc.sh (run.sh with Mesen wrapped in /usr/bin/time -l and
a 0.2 s poll) on the experiment build (or the deployed one for variant
'deployed'), with the variant's env knobs, into build/rc/runs/<w>/<v>/r<rep>/,
and appends one line to build/rc/results.tsv:
  workload variant rep verdict frame real user sys maxrss_MB Ginstr Gcycles shots load1 wall_total when
"""
import os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RC = os.path.join(ROOT, "build", "rc")
WORKLOADS = {
    "whelk": "tools/tests/gen_whelk_poweron.lua",   # cold boot -> intro -> Narshe -> Whelk
    "rage": "tools/tests/battle_rage.lua",          # battle suite
    "zozo": "tools/tests/gen_zozo2_arrival.lua",    # long field walk
    "banner": "tools/tests/battle_banner.lua",      # short smoke
    # replays (mk_replay.py): a harness run's recorded pads/loads, no pixel reads
    "rwhelk": "build/rc/replay_whelk.lua",
    "rrage": "build/rc/replay_rage.lua",
    "rzozo": "build/rc/replay_zozo.lua",
    # the same replays with a memory-hash checkpoint every 512 frames (identity, not timing)
    "cwhelk": "build/rc/replaychk_whelk.lua",
    "crage": "build/rc/replaychk_rage.lua",
    "czozo": "build/rc/replaychk_zozo.lua",
}
VARIANTS = {
    "deployed": ("/Users/mtklein/ot6/tools/Mesen.app", {}),
    "base": (f"{RC}/apps/Mesen.app", {}),
    "skip128": (f"{RC}/apps/Mesen.app", {"OT6X_RENDER_EVERY": "128", "OT6X_SKIP_SEND": "1"}),
    "skipall": (f"{RC}/apps/Mesen.app", {"OT6X_RENDER_EVERY": "1000000000", "OT6X_SKIP_SEND": "1"}),
    "skipnosend": (f"{RC}/apps/Mesen.app", {"OT6X_RENDER_EVERY": "1000000000"}),
    "nomixer": (f"{RC}/apps/Mesen.app", {"OT6X_NO_MIXER": "1"}),
    "skip128_nomixer": (f"{RC}/apps/Mesen.app", {"OT6X_RENDER_EVERY": "128", "OT6X_SKIP_SEND": "1", "OT6X_NO_MIXER": "1"}),
    "norewind": (f"{RC}/apps/Mesen.app", {"OT6X_NO_REWIND": "1"}),
    "all_safe": (f"{RC}/apps/Mesen.app", {"OT6X_RENDER_EVERY": "128", "OT6X_SKIP_SEND": "1", "OT6X_NO_MIXER": "1", "OT6X_NO_REWIND": "1"}),
    "nodsp_probe": (f"{RC}/apps/Mesen.app", {"OT6X_NO_DSP": "1", "OT6X_NO_MIXER": "1"}),
}

def main():
    w, v, rep = sys.argv[1], sys.argv[2], sys.argv[3]
    app, knobs = VARIANTS[v]
    out = os.path.join(RC, "runs", w, v, f"r{rep}")
    subprocess.run(["rm", "-rf", out])
    os.makedirs(out)
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("OT6X_"):
            del env[k]
    env.update(knobs)
    env.update({
        "OT6_MESEN_APP": app,
        "OT6_MESEN_CACHE": os.path.join(RC, "cache-" + ("deployed" if v == "deployed" else "exp")),
        "OT6_ARTIFACT_DIR": out,
        "OT6_WORKER": f"rc_{w}_{v}_{rep}",
        "OT6_TIMEOUT": "1500",
    })
    load1 = os.getloadavg()[0]
    log = os.path.join(out, "run.log")
    t0 = time.time()
    p = subprocess.run(["sh", "tools/tests/run_rc.sh", WORKLOADS[w], log], cwd=ROOT, env=env,
                       stdout=open(os.path.join(out, "run.out"), "w"), stderr=subprocess.STDOUT)
    wall = time.time() - t0
    txt = open(log, errors="replace").read()
    m = re.search(r"^\s*([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys", txt, re.M)
    real, user, sys_ = (m.groups() if m else ("?", "?", "?"))
    m = re.search(r"^\s*(\d+)\s+maximum resident set size", txt, re.M)
    rss = f"{int(m.group(1))/1048576:.0f}" if m else "?"
    verdict = "PASS" if re.search(r"^\[ot6\] PASS \(frame ", txt, re.M) else (
        "FAIL" if re.search(r"^\[ot6\] FAIL: ", txt, re.M) else "NONE")
    fr = re.findall(r"^\[ot6\] PASS \(frame (\d+)", txt, re.M)
    if not fr:
        fr = re.findall(r"^\[ot6note\] (\d+) ", txt, re.M)
    frame = fr[-1] if fr else "?"
    mi = re.search(r"^\s*(\d+)\s+instructions retired", txt, re.M)
    mc = re.search(r"^\s*(\d+)\s+cycles elapsed", txt, re.M)
    ginst = f"{int(mi.group(1))/1e9:.1f}" if mi else "?"
    gcyc = f"{int(mc.group(1))/1e9:.1f}" if mc else "?"
    shots = len(re.findall(r"^\[ot6shot\] ", txt, re.M))
    line = "\t".join(map(str, [w, v, rep, verdict, frame, real, user, sys_, rss, ginst, gcyc, shots,
                               f"{load1:.2f}", f"{wall:.1f}", time.strftime("%Y-%m-%dT%H:%M:%S")]))
    with open(os.path.join(RC, "results.tsv"), "a") as f:
        f.write(line + "\n")
    print(line, flush=True)

main()
