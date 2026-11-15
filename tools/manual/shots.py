#!/usr/bin/env python3
"""Regenerate the manual's screenshots (tools/manual/img/*.png).

Every picture is a real frame from the emulator harness, booted from the
graph's own captures (build/states, build/checkpoints), never a tracked
save, and run with OT6_NO_PUBLISH=1 so build/states is left as it was.
Two sources:

  * SUITES: a suite from tools/tests, run unmodified with the env its ninja
    edge gives it; the manual keeps one of the screenshots the suite takes.
  * AREAS: a graph state loaded and shot as it stands (the frame the
    generator saved it on).  One emulator run takes them all.

The PNGs are kept at the emulator's 256x224; build.py scales them up with
nearest-neighbour.  Usage (run from the repository root, after `ninja`
has the states fresh; `python3 tools/tests/lib/compose.py --check-states`):

    python3 tools/manual/shots.py              # everything
    python3 tools/manual/shots.py areas        # just the area shots
    python3 tools/manual/shots.py battle_break # one suite
    python3 tools/manual/shots.py -j 2         # two emulators at once

Take the placement claim first (tools/stream/live.py --place N --claim ...).
Logs land in build/manual/shots/<run>.log.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMG = ROOT / "tools" / "manual" / "img"
WORK = ROOT / "build" / "manual" / "shots"

# image name -> (suite, screenshot tag the suite takes[, crop box x0, y0, x1, y1]).
# A name starting with @ is one of the manual's own capture scripts,
# tools/manual/<name>.lua (no env).
SUITES = {
    "shields": ("battle_class", "class_hud_pierce"),
    "shields_whelk": ("battle_break", "break_gauge"),
    "break": ("battle_break", "break_double"),
    "boost": ("battle_boost", "boost_selected"),
    "aura": ("battle_auraband", "auraband_all_four"),
    "esper_rank": ("menu_esperdetail", "esperdetail_staged_rank4_rung5"),
    "esper_page": ("menu_esperdetail", "esperdetail_e0"),
    "school": ("school", "school_0264_p1"),
    "school_door": ("school", "school_0257_p1"),
    "locke": ("menu_thiefpage", "thiefpage_rows"),
    "edgar": ("battle_toolslist", "tools_cost_display"),
    "sabin": ("menu_blitzpage", "blitz_page_full"),
    "cyan": ("menu_swdtechpage", "swdtech_page_full_pool"),
    "gau": ("menu_ragepage", "rage_page_player_path"),
    "setzer": ("battle_cointoss", "cointoss_table_1"),
    "shadow": ("battle_assassinate", "assassinate_kill"),
    "mastersmark": ("battle_mastersmark", "mastersmark_banner_1"),
    "cover": ("@boss_shots", "boss_rev2_late"),
    "celes": ("@battle_shots", "celes_runic_6"),
    "mog": ("@battle_shots", "mog_dance_1"),
    "strago": ("battle_lorerefuse", "lorerefuse_after"),
    "portrait_umaro": ("@portrait_shots", "menu_tritoch", (12, 15, 63, 62)),
    "portrait_mog": ("@portrait_shots", "menu_tritoch", (12, 63, 63, 110)),
    "portrait_terra": ("@portrait_shots", "menu_tritoch", (12, 111, 63, 158)),
    "portrait_celes": ("@portrait_shots", "menu_tritoch", (12, 159, 63, 206)),
    "portrait_relm": ("@portrait_shots", "menu_opera", (12, 63, 63, 110)),
    "portrait_gogo": ("@portrait_shots", "menu_opera", (12, 111, 63, 158)),
    "portrait_strago": ("@portrait_shots", "menu_opera", (12, 159, 63, 206)),
    "portrait_cyan": ("@portrait_shots", "menu_kt_doom", (12, 15, 63, 62)),
    "portrait_shadow": ("@portrait_shots", "menu_kt_doom", (12, 63, 63, 110)),
    "portrait_sabin": ("@portrait_shots", "menu_kt_doom", (12, 111, 63, 158)),
    "portrait_edgar": ("@portrait_shots", "menu_kt_goddess", (12, 111, 63, 158)),
    "portrait_setzer": ("@portrait_shots", "menu_kt_goddess", (12, 159, 63, 206)),
    "portrait_locke": ("@portrait_shots", "menu_kt_plates", (12, 111, 63, 158)),
    "portrait_gau": ("@portrait_shots", "menu_veldt", (12, 159, 63, 206)),
}

# image name -> graph state (build/states/<state>.mss.lua)
AREAS = {
    "area_narshe": "narshe_streets",
    "area_lete": "lete_river",
    "area_zozo": "zozo_arrival",
    "area_fc": "fc_landing",
    "area_tomb": "wor_tomb",
    "area_wor_narshe": "wor_narshe",
    "area_phoenix": "wor_phoenix",
    "area_owzer": "wor_owzer",
}


def suite_env(suite):
    """The env line of the suite's own ninja edge (build.ninja)."""
    text = (ROOT / "build.ninja").read_text()
    m = re.search(r"^build build/results/suite/%s\.ok: suitetest.*\n((?:  .*\n)*)"
                  % re.escape(suite), text, re.M)
    if not m:
        sys.exit(f"shots.py: no suite edge for {suite} in build.ninja")
    env = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if line.startswith("env = "):
            for kv in line[len("env = "):].split():
                k, _, v = kv.partition("=")
                env[k] = v
    return env


def run(name, script, env, tags):
    """run.sh `script` with OT6_NO_PUBLISH=1, decode its log, return {tag: png path}."""
    log = WORK / f"{name}.log"
    out = WORK / name
    shutil.rmtree(out, ignore_errors=True)
    e = dict(os.environ, OT6_NO_PUBLISH="1", OT6_WORKER=f"manual_{name}", **env)
    print(f"[shots] {name}: run.sh {script} {' '.join(f'{k}={v}' for k, v in env.items())}",
          flush=True)
    rc = subprocess.run(["sh", "tools/tests/run.sh", str(script), str(log)],
                        cwd=ROOT, env=e, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL).returncode
    subprocess.run([sys.executable, "tools/tests/lib/decode_b64.py", str(log), str(out)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    found = {t: out / "shots" / f"{t}.png" for t in tags}
    missing = [t for t, p in found.items() if not p.exists()]
    print(f"[shots] {name}: exit {rc}, log {log.relative_to(ROOT)}"
          + (f", MISSING {missing}" if missing else ""), flush=True)
    return {t: p for t, p in found.items() if p.exists()}


def portrait(png, box):
    """Crop `box` out of a main-menu frame, then trim it to the portrait: the
    pixels that are not the window's blue (a back-row portrait sits 8 pixels
    further right, so the box is wider than any one portrait)."""
    from PIL import Image
    im = Image.open(png).convert("RGB").crop(box)
    xs, ys = [], []
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = im.getpixel((x, y))
            if not (b > r + 30 and b > g + 30):
                xs.append(x)
                ys.append(y)
    if not xs:
        sys.exit(f"shots.py: no portrait in {png} {box}")
    return im.crop((max(0, min(xs) - 1), max(0, min(ys) - 1),
                    min(im.width, max(xs) + 2), min(im.height, max(ys) + 2)))


def area_script():
    """One run: load each area's state and shoot it."""
    lines = ['-- generated by tools/manual/shots.py: load each graph state, take a screenshot',
             'local H = dofile("tools/tests/lib/ot6.lua")',
             'H.run({ maxFrames = %d }, {' % (400 + 120 * len(AREAS)),
             '  H.waitFrames(20),']
    for name, state in AREAS.items():
        lines.append(f'  H.loadState("build/states/{state}.mss.lua"), H.waitFrames(4),')
        lines.append(f'  H.call(function() H.screenshot("{name}") end), H.waitFrames(4),')
    lines.append('})')
    path = WORK / "area_shots.lua"
    path.write_text("\n".join(lines) + "\n")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("only", nargs="*",
                    help="'areas', suite names and/or the manual's own scripts (default: all)")
    ap.add_argument("-j", type=int, default=1, help="emulators at once (default 1)")
    a = ap.parse_args()
    os.chdir(ROOT)
    WORK.mkdir(parents=True, exist_ok=True)
    IMG.mkdir(parents=True, exist_ok=True)

    jobs = []   # (name, script, env, {tag: image})
    by_suite = {}
    for img, (suite, tag, *crop) in SUITES.items():
        by_suite.setdefault(suite, {}).setdefault(tag, []).append((img, crop[0] if crop else None))
    for suite, tags in by_suite.items():
        name = suite.lstrip("@")
        if a.only and name not in a.only:
            continue
        if suite.startswith("@"):
            jobs.append((name, Path("tools/manual") / f"{name}.lua", {}, tags))
        else:
            jobs.append((name, Path("tools/tests") / f"{suite}.lua", suite_env(suite), tags))
    if not a.only or "areas" in a.only:
        jobs.append(("areas", area_script().relative_to(ROOT), {},
                     {name: [(name, None)] for name in AREAS}))

    failed = []

    def one(job):
        name, script, env, tags = job
        got = run(name, script, env, list(tags))
        for tag, png in got.items():
            for img, crop in tags[tag]:
                if crop:
                    portrait(png, crop).save(IMG / f"{img}.png")
                else:
                    shutil.copyfile(png, IMG / f"{img}.png")
        failed.extend(f"{name}:{t}" for t in tags if t not in got)

    with ThreadPoolExecutor(max_workers=max(1, a.j)) as ex:
        list(ex.map(one, jobs))
    if failed:
        print("[shots] not taken: " + ", ".join(failed))
        return 1
    print(f"[shots] all taken into {IMG.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
