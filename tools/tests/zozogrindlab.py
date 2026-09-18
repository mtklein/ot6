#!/usr/bin/env python3
"""zozogrindlab.py -- the Zozo grind lab (issue #195, docs/design/zozo-grind.md).

    python3 tools/tests/zozogrindlab.py bake
    python3 tools/tests/zozogrindlab.py write   [policy ...]
    python3 tools/tests/zozogrindlab.py run     [--seeds 0,12,24,36,48] [--jobs N] policy [policy ...]
    python3 tools/tests/zozogrindlab.py aggregate [policy ...]

`bake` derives gen_zozo2_arrival.lua with a saveState at the west landing
(the party's first world tile off the west castle, the generator's own play
from figaro_submerged) and runs it: build/states/zozogrind_landing.mss is
the fixture every lab attempt branches from; its ancestry is
build/lab/zozo-grind/bake/bake.log.

`write` derives one variant of the generator per policy into
build/lab/zozo-grind/<policy>.lua: the landing fixture in place of the
castle exit, the policy written into the generator's GRIND table, three
read-only CPU observers ([hit] lines carry the engine's damage word at
_writedamage and the caster's and every target's level, which is what
Stone's x8 keys on), and a [result] line + stop after "grind done" (the
Jidoor stop and the walk to Zozo are the same in every variant).  Every
substitution asserts it matched exactly once.

`run` plays each variant once per seed under run.sh, retries off, with
OT6_SEED_SHIFT idle frames at the fixture load (the segment runner's own
seed knob: what a player who paused a beat before walking on would have
done), logs to build/lab/zozo-grind/<policy>/seed<NN>.log, artifacts under
the same directory, nothing published to build/states.

`aggregate` prints one row per policy (attempts, deaths, Fenix Downs
resolved, laps, mean frames, wipes, Stone casts / kills / level-parity
kills) and every raw [death] line under it.

Policies (GRIND fields; the generator documents each):
  control     the generator as it ships
  heal75      healPercent 75 (the in-battle top-up: Potions under the hit)
  care80      lapCare 0.8 and careThreshold 0.8 (the field care stops)
  breakfirst  bank 0 (every pip spent as it exists)
  boostfight  keyed false (the plain boost-Fight default line)
  allback     everyone in the back row
  focus       kill order: Iron Fists first (their solo branch is Stone)
  gentle      group-9 laps by the castle to L16, then the crossing
  focusnotool focus + no Tools line (the AutoCrossbow hits both bodies and can kill the Vulture first)
  focusb0     focus + breakfirst
  focusheal75 focus + heal75
  gentlefocus gentle + focus
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_zozo2_arrival.lua")
OUT = os.path.join(ROOT, "build", "lab", "zozo-grind")
FIXTURE = "zozogrind_landing"

POLICIES = {
    "control":     {},
    "heal75":      {"healPercent": "75"},
    "care80":      {"lapCare": "0.8", "careThreshold": "0.8"},
    "breakfirst":  {"bank": "0"},
    "boostfight":  {"keyed": "false"},
    "allback":     {"rows": "{ [1] = true, [4] = true, [5] = true, [6] = true }"},
    "focus":       {"focus": '"ironfist"'},
    "gentle":      {"gentle": "{ untilLevel = 16 }"},
    "focusnotool": {"focus": '"ironfist"', "tools": "false"},
    "focusb0":     {"focus": '"ironfist"', "bank": "0"},
    "focusheal75": {"focus": '"ironfist"', "healPercent": "75"},
    "gentlefocus": {"gentle": "{ untilLevel = 16 }", "focus": '"ironfist"'},
}

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

OBSERVERS = LIB_LINE + r'''
-- ---------------------------------------------------- zozogrindlab observers --
-- Read-only CPU exec callbacks (lab_zozo_street.lua's, with levels).
-- ExecCmd@battle_code runs with X = the acting entity's offset (party
-- $00..$06, monsters $08..$12), $b5/$b6 the command/attack after spell
-- folding, $b8 the target word.  _writedamage walks $33d0 + entity*2 (the
-- 14-bit damage word) before ApplyDmg clamps it to HP, so a kill's true
-- roll is read there.  SaveForMimic runs right after the command resolves.
-- $3b18 + entity offset is the battle level byte TargetEffect_22 (Stone)
-- compares between caster and target.
local LAB_SPECIES = { [0x02A] = "Vulture", [0x06C] = "IronFist", [0x08C] = "MindCandy",
  [0x078] = "RedFang", [0x090] = "OverGrunk", [0x05C] = "SandRay", [0x05D] = "Areneid",
  [0x023] = "FossilFang" }
local LAB_ATTACK = { [0x9F] = "Stone", [0xE7] = "Shimsham", [0xEE] = "Battle",
  [0xEF] = "Special", [0xFF] = "Fight" }
local labPending, labEvents = {}, {}
local function labPartyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(0x3BF4 + e * 2) end
  return p
end
local function labMonSpecies(slot)   -- the full-width formation word ($57C0)
  return H.readWord(H.FORMATION + slot * 2)
end
local function labHook()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x % 2 ~= 0 or x > 0x12 then return end
    labPending[x] = { frame = H.frame, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      tgt = H.readWord(0xB8), hp = labPartyHp(), lvl = H.readByte(0x3B18 + x) }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local mx = nil
    for x = 8, 0x12, 2 do if labPending[x] then mx = x end end
    if not mx then return end
    local raw = {}
    for e = 1, 4 do
      local w = H.readWord(0x33D0 + (e - 1) * 2)
      raw[e] = (w == 0xFFFF) and 0x3FFF or (w & 0x3FFF)
    end
    labPending[mx].raw = raw
  end, emu.callbackType.exec, H.sym("_writedamage"), H.sym("_writedamage"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = labPending[x]
    if not p then return end
    labPending[x] = nil
    if x < 8 then return end
    local slot = (x - 8) // 2
    local after = labPartyHp()
    local dmg, raw, lvl, kills = {}, {}, {}, 0
    for e = 1, 4 do
      dmg[e] = p.hp[e] - after[e]
      raw[e] = (p.raw and p.raw[e]) or 0x3FFF
      lvl[e] = H.readByte(0x3B18 + (e - 1) * 2)
      if p.hp[e] > 0 and after[e] == 0 then kills = kills + 1 end
    end
    local sp = labMonSpecies(slot)
    labEvents[#labEvents + 1] = string.format(
      "[hit] f%d %s(s%d) L%d cmd=%02X atk=%s tgt=%04X dmg=%d,%d,%d,%d raw=%d,%d,%d,%d "
      .. "lvl=%d,%d,%d,%d kills=%d party=%s",
      H.frame, LAB_SPECIES[sp] or string.format("$%03X", sp or 0xFFF), slot, p.lvl, p.cmd,
      LAB_ATTACK[p.atk] or string.format("$%02X", p.atk), p.tgt,
      dmg[1], dmg[2], dmg[3], dmg[4], raw[1], raw[2], raw[3], raw[4],
      lvl[1], lvl[2], lvl[3], lvl[4], kills,
      table.concat({ tostring(after[1]), tostring(after[2]), tostring(after[3]),
                     tostring(after[4]) }, ","))
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
  emu.addEventCallback(function()
    if #labEvents == 0 then return end
    for _, e in ipairs(labEvents) do H.log("[zozogrindlab] " .. e) end
    labEvents = {}
  end, emu.eventType.endFrame)
end
'''

BOOT_OLD_START = '  H.loadState("build/states/figaro_submerged.mss.lua"),\n'
BOOT_OLD_END = '''    where("west landing")
  end),
'''
BOOT_NEW = '''  -- zozogrindlab: the west landing, baked by the generator's own play
  -- (build/lab/zozo-grind/bake/bake.log)
  H.loadState("build/states/%s.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    labHook()
    H.assertEq(H.worldMode(), true, "the landing fixture is on the world map")
  end),
  -- the rows lever: the fixture was baked after the generator's own
  -- setRows (LOCKE front, the rest back), so a rows policy re-applies here
  H.cond(function() return GRIND.rows[1] == true end, {
    H.setRows(GRIND.rows, { tag = "zozogrindlab rows" }),
  }, {}),
  H.call(function() where("west landing") end),
''' % FIXTURE

STOP_OLD = '''    where("grind done")
    H.screenshot("zozo_grind_done")
  end),
'''
STOP_NEW = STOP_OLD + '''  -- zozogrindlab: the grind is the measurement; stop before Jidoor
  H.call(function()
    H.log(string.format("[result] policy=%s seed=%d frame=%d laps=%d gentle=%d %s",
      "@POLICY@", OT6_SEED_SHIFT or 0, H.frame, grindLaps, gentleLaps, rosterLine()))
    emu.stop(0)
  end),
'''


def derive(policy, src):
    assert src.count(LIB_LINE) == 1, "lib line"
    out = src.replace(LIB_LINE, OBSERVERS)
    i = out.index(BOOT_OLD_START)
    j = out.index(BOOT_OLD_END, i) + len(BOOT_OLD_END)
    assert out.count(BOOT_OLD_START) == 1 and out.count(BOOT_OLD_END) == 1, "boot block"
    out = out[:i] + BOOT_NEW + out[j:]
    assert out.count(STOP_OLD) == 1, "stop block"
    out = out.replace(STOP_OLD, STOP_NEW.replace("@POLICY@", policy))
    for field, value in POLICIES[policy].items():
        pat = re.compile(r"^(  %s = )(.*?),(\s*--.*)?$" % re.escape(field), re.M)
        n = len(pat.findall(out))
        assert n == 1, "GRIND.%s: %d matches" % (field, n)
        out = pat.sub(lambda m: "%s%s,%s" % (m.group(1), value, m.group(3) or ""), out)
    return out


def write(policies, gen=GEN):
    src = open(gen, encoding="utf-8").read()
    os.makedirs(OUT, exist_ok=True)
    for p in policies:
        path = os.path.join(OUT, p + ".lua")
        open(path, "w", encoding="utf-8").write(derive(p, src))
        print("wrote", os.path.relpath(path, ROOT))


def bake(gen=GEN):
    src = open(gen, encoding="utf-8").read()
    anchor = BOOT_OLD_END
    assert src.count(anchor) == 1
    new = anchor + '''  -- zozogrindlab bake: the west landing, the generator's own play from
  -- figaro_submerged; every lab attempt branches from this snapshot.
  H.saveState("%s.mss"),
  H.call(function() H.log("[zozogrindlab] landing baked -- stopping"); emu.stop(0) end),
''' % FIXTURE
    d = os.path.join(OUT, "bake")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "gen_bake.lua")
    open(path, "w", encoding="utf-8").write(src.replace(anchor, new))
    env = dict(os.environ, OT6_RETRIES="1", OT6_ARTIFACT_DIR=d,
               OT6_WORKER="zozogrind-bake")
    rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"), path,
                         os.path.join(d, "bake.log")], cwd=ROOT, env=env).returncode
    if rc != 0:
        return rc
    for ext in (".mss", ".mss.lua"):
        srcf = os.path.join(d, FIXTURE + ext)
        dst = os.path.join(ROOT, "build", "states", FIXTURE + ext)
        open(dst, "wb").write(open(srcf, "rb").read())
        print("fixture", os.path.relpath(dst, ROOT))
    return 0


def run_one(policy, seed, jobs_env):
    d = os.path.join(OUT, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "seed%02d.log" % seed)
    env = dict(os.environ)
    env.update({
        "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(seed),
        "OT6_NO_PUBLISH": "1", "OT6_KEEP_RUNS": "1",
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "3600"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "seed%02d" % seed),
        "OT6_WORKER": "zozogrind-%s-%02d" % (policy, seed),
    })
    with open(os.path.join(d, "seed%02d.out" % seed), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             os.path.join(OUT, policy + ".lua"), log],
                            cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT).returncode
    return policy, seed, rc, summarize(log)


RESULT = re.compile(r"^\[ot6\] \[result\] policy=(\S+) seed=(\d+) frame=(\d+) laps=(\d+) gentle=(\d+)")
DEATH = re.compile(r"^\[ot6\] .*\[death\] ")
HIT = re.compile(r"^\[ot6\] \[zozogrindlab\] \[hit\] f(\d+) (\S+)\(s(\d)\) L(\d+) cmd=(..) atk=(\S+) "
                 r"tgt=(....) dmg=(\S+) raw=(\S+) lvl=(\S+) kills=(\d+)")
FENIX_CARE = re.compile(r"^\[ot6\] \[care .*used \$F0 ")
FENIX_BATTLE = re.compile(r"^\[ot6\] .*Fenix Down landed")
WIPE = re.compile(r"^\[ot6\] .*canary: BATTLE WIPE")
FAIL = re.compile(r"^\[ot6\] (FAIL: .*|\[retry\] attempt \d+/\d+ FAILED .*)")
ROSTER = re.compile(r"^\[ot6\] (grind lap \d+:|gentle lap \d+:|crossing hop \d+ ->|\[grind start\] c)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, laps=None, gentle=None, deaths=[], hits=[],
             fenix_care=0, fenix_battle=0, wipes=0, fail="", stone=0, stone_kills=0,
             parity_kills=0, stone_raw=[], roster="")
    if not os.path.exists(log):
        r["fail"] = "no log"
        return r
    last_roster = ""
    for line in open(log, errors="replace"):
        line = line.rstrip("\n")
        if not line.startswith("[ot6] "):
            continue
        m = RESULT.match(line)
        if m:
            r["verdict"], r["frame"], r["laps"], r["gentle"] = "DONE", int(m.group(3)), int(m.group(4)), int(m.group(5))
            r["roster"] = line
            continue
        if ROSTER.match(line):
            last_roster = line
        if DEATH.match(line):
            r["deaths"].append((line, last_roster))
            continue
        m = HIT.match(line)
        if m:
            r["hits"].append(line)
            if m.group(6) == "Stone":
                r["stone"] += 1
                kills = int(m.group(11))
                r["stone_kills"] += kills
                dmg = [int(v) for v in m.group(8).split(",")]
                raw = [int(v) for v in m.group(9).split(",")]
                lvl = [int(v) for v in m.group(10).split(",")]
                for e in range(4):
                    if dmg[e] > 0:
                        r["stone_raw"].append((raw[e], lvl[e], int(m.group(4)), dmg[e]))
                        if lvl[e] == int(m.group(4)) and raw[e] > 0 and dmg[e] > 0:
                            # a kill at parity: the HP it found them at is the
                            # damage, the raw word is the x8 roll
                            pass
                if kills:
                    for e in range(4):
                        if dmg[e] > 0 and lvl[e] == int(m.group(4)):
                            r["parity_kills"] += 1
            continue
        if FENIX_CARE.match(line):
            r["fenix_care"] += 1
        elif FENIX_BATTLE.match(line):
            r["fenix_battle"] += 1
        elif WIPE.match(line):
            r["wipes"] += 1
        m = FAIL.match(line)
        if m and not r["fail"]:
            r["fail"] = m.group(1)[:160]
    if r["verdict"] != "DONE":
        r["verdict"] = "FAIL"
    return r


def aggregate(policies, seeds=None):
    rows = []
    print("%-12s %2s %4s %6s %5s %4s %7s %5s %5s %6s %6s  %s" % (
        "policy", "n", "done", "deaths", "fenix", "wipe", "frames", "laps",
        "stone", "kills", "parity", "stone raw (min..max, non-parity / parity)"))
    for p in policies:
        d = os.path.join(OUT, p)
        if not os.path.isdir(d):
            continue
        logs = sorted(f for f in os.listdir(d) if re.fullmatch(r"seed\d\d\.log", f))
        if seeds is not None:
            logs = [f for f in logs if int(f[4:6]) in seeds]
        rs = [(f, summarize(os.path.join(d, f))) for f in logs]
        if not rs:
            continue
        n = len(rs)
        done = sum(1 for _, r in rs if r["verdict"] == "DONE")
        deaths = sum(len(r["deaths"]) for _, r in rs)
        fenix = sum(r["fenix_care"] + r["fenix_battle"] for _, r in rs)
        wipes = sum(r["wipes"] for _, r in rs)
        frames = [r["frame"] for _, r in rs if r["frame"]]
        laps = [r["laps"] + (r["gentle"] or 0) for _, r in rs if r["laps"] is not None]
        stone = sum(r["stone"] for _, r in rs)
        kills = sum(r["stone_kills"] for _, r in rs)
        parity = sum(r["parity_kills"] for _, r in rs)
        non = [raw for _, r in rs for raw, lt, lc, dmg in r["stone_raw"] if lt != lc and raw < 0x3FFF]
        par = [raw for _, r in rs for raw, lt, lc, dmg in r["stone_raw"] if lt == lc and raw < 0x3FFF]
        rng = lambda v: ("%d..%d" % (min(v), max(v))) if v else "-"
        print("%-12s %2d %4d %6d %5d %4d %7s %5s %5d %5d %6d  %s / %s" % (
            p, n, done, deaths, fenix, wipes,
            ("%d" % (sum(frames) / len(frames))) if frames else "-",
            ("%.1f" % (sum(laps) / len(laps))) if laps else "-",
            stone, kills, parity, rng(non), rng(par)))
        rows.append((p, rs))
    for p, rs in rows:
        print()
        print("== %s" % p)
        for f, r in rs:
            print("  %s: %s frame=%s laps=%s gentle=%s deaths=%d fenix=%d+%d wipes=%d %s" % (
                f, r["verdict"], r["frame"], r["laps"], r["gentle"], len(r["deaths"]),
                r["fenix_care"], r["fenix_battle"], r["wipes"], r["fail"]))
            for line, roster in r["deaths"]:
                print("    " + line[:230])
                if roster:
                    print("      " + roster[:200])
            for h in r["hits"]:
                if " atk=Stone " in h:
                    print("    " + h[6:])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["bake", "write", "run", "aggregate"])
    ap.add_argument("policies", nargs="*")
    ap.add_argument("--seeds", default="0,12,24,36,48")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--gen", default=GEN, help="the generator to derive from")
    a = ap.parse_args()
    policies = a.policies or list(POLICIES)
    for p in policies:
        if p not in POLICIES:
            sys.exit("unknown policy %r; one of %s" % (p, ", ".join(POLICIES)))
    if a.cmd == "bake":
        return bake(a.gen)
    if a.cmd == "write":
        write(policies, a.gen)
        return 0
    if a.cmd == "aggregate":
        aggregate(policies)
        return 0
    seeds = [int(s) for s in a.seeds.split(",")]
    write(policies, a.gen)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        futs = [ex.submit(run_one, p, s, None) for p in policies for s in seeds]
        for f in concurrent.futures.as_completed(futs):
            p, s, rc, r = f.result()
            print("  %s seed %2d: rc=%d %s frame=%s laps=%s deaths=%d fenix=%d+%d %s" % (
                p, s, rc, r["verdict"], r["frame"], r["laps"], len(r["deaths"]),
                r["fenix_care"], r["fenix_battle"], r["fail"]), flush=True)
    print()
    aggregate(policies, set(seeds))
    return 0


if __name__ == "__main__":
    sys.exit(main())
