#!/usr/bin/env python3
"""Every instrument under tools/tests composes and starts (#309).

docs/TESTING.md "Scripts that stay in the tree": a script stays only if it
is a measuring instrument someone will run again, and qualification proves
it still composes and starts.  An instrument is a tools/tests/*.lua with a
`-- @manual` line (tools/check_test_registration.py makes every non-suite
script declare one or the other).  Per instrument:

  * standalone (`-- @manual standalone: lua <path>`): run with `lua`; exit
    0 is a start.
  * otherwise: every savestate it names ("<name>.mss.lua") must be a state
    the graph makes (tools/tests/savestate_graph.py) or one the script saves
    itself -- a fixture nothing generates any more cannot boot.  The script
    is composed with lib/compose.py, a trailer is appended that stops the
    run SMOKE_FRAMES frames after the body's boot point (M.bootMark: the
    first fixture load, or a checkpoint's entry contract), and the result is
    run through run.sh.  A start is the body's own boot point in the log,
    then either the trailer's `[smoke] started` line or the instrument's
    own PASS verdict (a short one finishes first), and no FAIL verdict.
    The trailer only reads.

Usage:  python3 tools/check_instruments.py [tools/tests/<instrument>.lua ...]
Logs:   build/checks/instruments/<name>.log (composed: <name>.lua beside it)
Exit 0 if every instrument composes and starts, 1 otherwise.
"""

from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "tests", "lib"))
import stamps  # noqa: E402 -- declared_states: the graph's state names

OUT = os.path.join(ROOT, "build", "checks", "instruments")
MANUAL = re.compile(r"^-- @manual(.*)$", re.M)
STATE_REF = re.compile(r'"(?:[^"]*/)?([A-Za-z0-9_]+)\.mss\.lua"')
SAVED = re.compile(r'saveState\(\s*"(?:[^"]*/)?([A-Za-z0-9_]+)\.mss"')
SMOKE_FRAMES = 600
TIMEOUT = "300"      # wall-clock seconds; a healthy start takes a few

TRAILER = """
-- tools/check_instruments.py smoke trailer: the instrument above runs
-- unchanged; this stops it %(frames)d frames after its body's boot point.
do
  local smokeBoot, smokeWhat = nil, nil
  local bootMark = H.bootMark
  H.bootMark = function(what, ...)
    if not smokeBoot then smokeBoot, smokeWhat = H.frame, tostring(what) end
    return bootMark(what, ...)
  end
  emu.addEventCallback(function()
    if smokeBoot and H.frame >= smokeBoot + %(frames)d then
      print(string.format("[ot6] [smoke] started: boot point %%s at f%%d, "
        .. "the body ran to f%%d", smokeWhat, smokeBoot, H.frame))
      emu.stop(0)
    end
  end, emu.eventType.startFrame)
end
""" % {"frames": SMOKE_FRAMES}


def instruments() -> list[str]:
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "tools", "tests", "*.lua"))):
        with open(path, encoding="utf-8", errors="replace") as f:
            if MANUAL.search(f.read()):
                out.append(os.path.relpath(path, ROOT))
    return out


def standalone(rel: str, lua: str | None) -> tuple[bool, str]:
    if lua is None:
        return False, "no `lua` on PATH (standalone instruments need Lua 5.4+)"
    log = os.path.join(OUT, os.path.basename(rel)[:-4] + ".log")
    with open(log, "w") as f:
        rc = subprocess.run([lua, rel], cwd=ROOT, stdout=f,
                            stderr=subprocess.STDOUT).returncode
    said = open(log, errors="replace").read().strip().splitlines() or [""]
    if rc != 0:
        return False, f"lua exit {rc}: {said[0][:160]} ({os.path.relpath(log, ROOT)})"
    return True, f"lua exit 0: {said[-1][:120]}"


def emulated(rel: str, text: str, states: set[str]) -> tuple[bool, str]:
    name = os.path.basename(rel)[:-4]
    own = set(SAVED.findall(text))
    missing = sorted({s for s in STATE_REF.findall(text)
                      if s not in states and s not in own})
    if missing:
        return False, ("loads " + ", ".join(m + ".mss" for m in missing)
                       + ", which no generator in savestate_graph.py makes")
    composed = os.path.join(OUT, name + ".lua")
    log = os.path.join(OUT, name + ".log")
    res = subprocess.run([sys.executable, os.path.join("tools", "tests", "lib", "compose.py"),
                          rel, composed], cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        tail = (res.stdout + res.stderr).strip().splitlines()[-1:] or [""]
        return False, f"compose.py exit {res.returncode}: {tail[0][:160]}"
    with open(composed, "a") as f:
        f.write(TRAILER)
    env = dict(os.environ, OT6_TIMEOUT=TIMEOUT, OT6_TIMEOUT_RETRIES="0",
               OT6_WORKER="instrument_" + name)
    subprocess.run(["sh", os.path.join("tools", "tests", "run.sh"), composed, log],
                   cwd=ROOT, env=env, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    lines = open(log, errors="replace").read().splitlines() if os.path.exists(log) else []
    fail = [l for l in lines if l.startswith("[ot6] FAIL: ")]
    boot = [l for l in lines if l.startswith("[ot6] [retry] boot point: ")]
    start = [l for l in lines if l.startswith("[ot6] [smoke] started: ")]
    done = [l for l in lines if l.startswith("[ot6] PASS (frame ")]
    where = os.path.relpath(log, ROOT)
    if fail:
        return False, f"{fail[0][:200]} ({where})"
    if not boot:
        return False, f"no boot point within {TIMEOUT}s ({where})"
    what = boot[0][len("[ot6] [retry] boot point: "):]
    if not what.startswith(("fixture ", "checkpoint ")):
        return False, f"booted nothing of its own: {what[:160]} ({where})"
    if start:
        return True, start[0][len("[ot6] [smoke] "):]
    if done:
        return True, f"booted {what.split(' (')[0]}, then {done[0][len('[ot6] '):]}"
    return False, f"booted {what[:120]} but neither ran {SMOKE_FRAMES} frames nor passed ({where})"


def main(argv: list[str]) -> int:
    os.makedirs(OUT, exist_ok=True)
    todo = [os.path.relpath(os.path.abspath(a), ROOT) for a in argv] or instruments()
    states = set(stamps.declared_states(ROOT))
    lua = shutil.which("lua")
    bad = 0
    for rel in todo:
        text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
        m = MANUAL.search(text)
        if m and "standalone: lua" in m.group(1):
            ok, why = standalone(rel, lua)
        else:
            ok, why = emulated(rel, text, states)
        print(("  ok    " if ok else "  FAIL  ") + f"{rel}: {why}")
        bad += not ok
    print(f"instruments: {len(todo) - bad} of {len(todo)} compose and start")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
