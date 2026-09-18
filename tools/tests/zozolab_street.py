#!/usr/bin/env python3
"""zozolab_street.py -- the whole-street half of the Zozo lab (issue #155).

    python3 tools/tests/zozolab_street.py write   [policy ...]
    python3 tools/tests/zozolab_street.py run     [policy ...]

`write` derives one variant of tools/tests/gen_zozo4_dadaluma.lua per policy
into build/zozolab/street_<policy>.lua: the generator's own route from
zozo_arrival to Dadaluma's door with the policy applied to its encounter
driver, stopping right after dadaluma_entry.mss is emitted (the fight with
Dadaluma is outside the street).  `run` plays each under run.sh with the
artifacts redirected to build/zozolab/street/<policy>/ so the tree's own
dadaluma_entry fixture is never touched, three at a time, and prints the
per-run audit (deaths, Fenix, frames; tools/audit_fenix.py on the log).

Policies (lab_zozo_street.lua has the definitions):
  control     the generator as it ships
  allback     LOCKE joins the other three in the back row
  allfront    everyone in the front row
  breakfirst  encounters() with bank = 0 (spend BP as it comes)
  runic       CELES answers every command menu with Runic; LOCKE is the
              item medic (a Cure would be absorbed too).  Only the
              generator's own encounters() driver is wrapped: the crane
              maze's navTo legs keep the lib driver, and are the same in
              every variant.

Every substitution asserts it matched exactly once, so a generator edit
that moves a patch site fails loudly here instead of silently measuring
the wrong policy.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_zozo4_dadaluma.lua")
OUT = os.path.join(ROOT, "build", "zozolab")
POLICIES = ["control", "allback", "allfront", "breakfirst", "runic"]

STOP = '''  H.saveState("dadaluma_entry.mss"),
'''
STOP_NEW = STOP + '''  -- zozolab street: the street ends at Dadaluma's door; stop here so the
  -- variant never plays (or re-emits) the boss half.
  H.call(function() H.log("[zozolab] street done -- dadaluma_entry emitted"); emu.stop(0) end),
'''

ROWS = '''  H.setRows({ [5] = true, [6] = true }, { tag = "CELES and SABIN back row" }),
  H.call(function()
    for _, c in ipairs({ 5, 6 }) do
      H.assertEq((H.readByte(0x1850 + c) & 0x20) ~= 0, true,
        string.format("char %d is in the back row for the climb", c))
    end
    H.assertEq((H.readByte(0x1850 + 1) & 0x20) == 0, true,
      "LOCKE stays in front -- his swing chips DADALUMA's pierce row")
'''
ROWS_ALLBACK = '''  H.setRows({ [1] = true, [5] = true, [6] = true }, { tag = "zozolab allback" }),
  H.call(function()
    for _, c in ipairs({ 1, 5, 6 }) do
      H.assertEq((H.readByte(0x1850 + c) & 0x20) ~= 0, true,
        string.format("char %d is in the back row for the climb", c))
    end
'''
ROWS_ALLFRONT = '''  H.setRows({ [1] = false, [4] = false, [5] = false, [6] = false }, { tag = "zozolab allfront" }),
  H.call(function()
    for _, c in ipairs({ 1, 4, 5, 6 }) do
      H.assertEq((H.readByte(0x1850 + c) & 0x20) == 0, true,
        string.format("char %d is in the front row for the climb", c))
    end
'''

DRIVER = '''  local F = H.newFightDriver(what, { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, healer = CELES, cadence = 12,
    tool = BIO_BLASTER, focus = ZOZO_FOCUS })
'''
DRIVER_BREAKFIRST = DRIVER.replace("bank = 3", "bank = 0")
DRIVER_RUNIC = '''  local F = H.newFightDriver(what, { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, healer = 1, cure = false, cadence = 12,
    tool = BIO_BLASTER, focus = ZOZO_FOCUS })
  local frameF = zozolabRunic(F)
'''
FRAME = '''    if H.battleLoadStarted() then
      F.frame()
      return true
    end
    F.idle()
    return false
'''
FRAME_RUNIC = '''    if H.battleLoadStarted() then
      frameF()
      return true
    end
    F.idle()
    return false
'''
RUNIC_PRELUDE_AT = '''local BIO_BLASTER = H.BIO_BLASTER
'''
RUNIC_PRELUDE = RUNIC_PRELUDE_AT + '''-- zozolab runic policy (lab_zozo_street.lua): on CELES's command window
-- steer to RUNIC and confirm its target window; every other frame is the
-- control driver's.  Measured in the lab: Runic opens a target window
-- (state $38) in this ROM.
local function zozolabRunic(F)
  local MENU_, ACTOR_, MSTATE_ = 0x7BCA, 0x62CA, 0x7BC2
  local CMDTBL_, CMDROW_, BCHID_ = 0x202E, 0x890F, 0x3ED8
  local tick, said = 0, false
  return function()
    if H.readByte(MENU_) ~= 0 then
      local actor = H.readByte(ACTOR_) & 3
      if H.readByte(BCHID_ + actor * 2) == 6 then
        tick = tick + 1
        local st, ph = H.readByte(MSTATE_), tick % 12
        if st == 0x05 then
          local row = nil
          for r = 0, 3 do
            if H.readByte(CMDTBL_ + actor * 12 + r * 3) == 0x0B then row = r end
          end
          if row ~= nil then
            local cur = H.readByte(CMDROW_ + actor) & 3
            local btn = cur == row and "a" or (cur < row and "down" or "up")
            if not said and btn == "a" then
              said = true
              H.log(string.format("[zozolab] CELES (slot %d) -> RUNIC on row %d", actor, row))
            end
            H.setPad(ph < 4 and { [btn] = true } or {})
            return
          end
        elseif st == 0x38 then
          H.setPad(ph < 4 and { a = true } or {})
          return
        elseif st ~= 0x01 then
          H.setPad(ph < 4 and { b = true } or {})
          return
        end
      else
        said = false
      end
    end
    F.frame()
  end
end
'''


def sub(src, old, new, what):
    n = src.count(old)
    if n != 1:
        raise SystemExit("zozolab_street: patch site %r matched %d times, want 1" % (what, n))
    return src.replace(old, new)


def variant(policy):
    src = open(GEN, encoding="utf-8").read()
    src = sub(src, STOP, STOP_NEW, "stop after dadaluma_entry")
    if policy == "allback":
        src = sub(src, ROWS, ROWS_ALLBACK, "rows")
    elif policy == "allfront":
        src = sub(src, ROWS, ROWS_ALLFRONT, "rows")
    elif policy == "breakfirst":
        src = sub(src, DRIVER, DRIVER_BREAKFIRST, "encounters driver")
    elif policy == "runic":
        src = sub(src, RUNIC_PRELUDE_AT, RUNIC_PRELUDE, "runic prelude")
        src = sub(src, DRIVER, DRIVER_RUNIC, "encounters driver")
        src = sub(src, FRAME, FRAME_RUNIC, "encounters frame")
    elif policy != "control":
        raise SystemExit("unknown policy " + policy)
    header = ("-- zozolab street variant: policy=%s, derived from gen_zozo4_dadaluma.lua by\n"
              "-- tools/tests/zozolab_street.py (issue #155).  Not a fixture generator: its\n"
              "-- artifacts are redirected to build/zozolab/street/%s/.\n" % (policy, policy))
    return header + src


def write(policies):
    os.makedirs(OUT, exist_ok=True)
    for p in policies:
        path = os.path.join(OUT, "street_%s.lua" % p)
        with open(path, "w", encoding="utf-8") as f:
            f.write(variant(p))
        print("wrote", os.path.relpath(path, ROOT))


def audit(policy):
    log = os.path.join(OUT, "street_%s.log" % policy)
    if not os.path.exists(log):
        return "%-10s no log" % policy
    txt = open(log, encoding="utf-8", errors="replace").read()
    lines = [l for l in txt.splitlines() if l.startswith("[ot6] ")]
    verdict = "PASS" if any("[zozolab] street done" in l for l in lines) else "FAIL/incomplete"
    fails = [l for l in lines if "FAIL" in l or "WIPED" in l]
    revives = [l for l in lines if "plan: revive" in l]
    fenix_battle = [l for l in lines if re.search(r"actor=\d+ char=\d+ plan=item", l)]
    care_lines = [l for l in lines if re.search(r"\[care [^\]]*\] (done|nothing to do)", l)]
    last_care = care_lines[-1] if care_lines else ""
    m = re.search(r"fenix=(\d+)", last_care)
    fenix_left = m.group(1) if m else "?"
    frames = None
    for l in lines:
        m2 = re.search(r"\[dadaluma_entry\] f(\d+)", l)
        if m2:
            frames = m2.group(1)
    battles = len([l for l in lines if re.search(r"battle f\+1 menu=", l)])
    zeros = [l for l in lines if "partyhp=" in l and re.search(r"partyhp=[0-9,]*\b0\b", l)]
    return ("%-10s %s frames=%s battles~%d revives(care)=%d fenix_left=%s "
            "wipe/fail lines=%d" % (policy, verdict, frames, battles, len(revives),
                                    fenix_left, len(fails)))


def run(policies):
    write(policies)
    procs = []
    for p in policies:
        d = os.path.join(OUT, "street", p)
        os.makedirs(d, exist_ok=True)
        env = dict(os.environ, OT6_TIMEOUT="1800",
                   OT6_WORKER="zozolab-street-%s" % p, OT6_ARTIFACT_DIR=d)
        cmd = [os.path.join(ROOT, "tools", "tests", "run.sh"),
               os.path.join(OUT, "street_%s.lua" % p),
               os.path.join(OUT, "street_%s.log" % p)]
        procs.append((p, subprocess.Popen(cmd, env=env, cwd=ROOT,
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))
        while len([q for _, q in procs if q.poll() is None]) >= 3:
            os.wait()
    for p, q in procs:
        q.wait()
        print(audit(p))


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("write", "run", "audit"):
        raise SystemExit(__doc__)
    pols = sys.argv[2:] or POLICIES
    if sys.argv[1] == "write":
        write(pols)
    elif sys.argv[1] == "run":
        run(pols)
    else:
        for p in pols:
            print(audit(p))
