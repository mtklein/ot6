#!/usr/bin/env python3
"""fcalcovelab.py -- the Floating Continent alcove lab (issue #221,
docs/design/fc-alcove.md).

    python3 tools/tests/fcalcovelab.py write [policy ...]
    python3 tools/tests/fcalcovelab.py run   [--seeds 0,10,20,30,40,50] [--jobs N] policy [...]
    python3 tools/tests/fcalcovelab.py aggregate [policy ...]

`write` derives gen_fc_alcove.lua into build/lab/fc-alcove/<policy>.lua:
the generator verbatim, plus three read-only CPU observers and a per-battle
stage line, plus the policy's own field steps at the landing.  Every
substitution asserts it matched exactly once, so a generator edit that moves
an anchor fails the derivation instead of silently measuring something else.

`run` plays each variant once per seed, cold-Continuing the tracked
`fc-landing-v1` battery exactly as the ninja graph does, with retries OFF
(OT6_RETRIES=1) and OT6_SEED_SHIFT idle frames at the boot point -- the
segment runner's own seed knob, the beat a player pauses before walking on.
Logs and artifacts stay under build/lab/fc-alcove/<policy>/; nothing is
published to build/states.  Every attempt is kept, failures included.

`aggregate` prints one row per policy (attempts, verdicts, deaths, Fenix
Downs, descent attempts, mean frames) and every raw [death] line under it,
with the formation the death happened in.

The observers (lab_map269_random.lua's, verbatim in shape):
ExecCmd@battle_code runs with X = the acting entity's offset (party
$00..$06, monsters $08..$12) and $b5/$b6/$b8 the command, attack and target
after spell folding; _writedamage walks $33d0 + entity*2 (the 14-bit damage
word) before ApplyDmg clamps it to HP, so a kill's true roll is read there;
SaveForMimic runs once the command has resolved.  They read, they never
write.

Policies (a person's levers at the landing, where SHADOW joins):

  control    the generator as it ships: SHADOW joins bare (every equipment
             slot $FF) and his kit is applied at the ALCOVE, after the
             crossing is over; the rows step ran before he joined, so his
             row is whatever the join left
  dress      SHADOW's own kit -- the same eleven rungs the generator already
             applies at the alcove, from the same bag -- applied at the
             landing, before the descent
  back       SHADOW moved to the back row at the landing
  dressback  both
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_fc_alcove.lua")
OUT = os.path.join(ROOT, "build", "lab", "fc-alcove")
CHECKPOINT = "tools/tests/checkpoints/fc-landing-v1"

POLICIES = {
    "control":   {},
    "dress":     {"dress": True},
    "back":      {"back": True},
    "dressback": {"dress": True, "back": True},
}

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

OBSERVERS = LIB_LINE + r'''
-- ------------------------------------------------------ fcalcovelab --
-- Read-only measurement (issue #221).  Nothing here presses a button or
-- writes a byte; the generator below plays exactly as it ships except for
-- the policy steps marked `fcalcovelab`.
local FCLAB_SPECIES = {
  [0x003] = "Ninja", [0x00C] = "Apokryphos", [0x020] = "Behemoth",
  [0x04A] = "Brainpan", [0x083] = "Dragon", [0x0A4] = "Misfit",
  [0x0D8] = "WireyDrgn", [0x117] = "AtmaWeapon",
}
local FCLAB_ATTACK = {
  [0x00] = "Fire", [0x01] = "Ice", [0x02] = "Bolt", [0x05] = "Fire2",
  [0x2D] = "Cure", [0x2F] = "Cure2",
  [0x94] = "L5Doom", [0x95] = "L4Flare", [0x96] = "L3Muddle",
  [0xAA] = "AutoCrossbow", [0xEE] = "Battle", [0xEF] = "Special",
  [0xFF] = "Fight",
}
-- the monster's OWN name for its $EF "Special" (monster_special_name_en):
-- Ninja Inviz, Apokryphos Silencer, Behemoth Take Down, Brainpan Smirk,
-- Dragon Tail, Misfit Enmity, Wirey Drgn Wing
local FCLAB_SPECIAL = {
  [0x003] = "Inviz", [0x00C] = "Silencer", [0x020] = "TakeDown",
  [0x04A] = "Smirk", [0x083] = "Tail", [0x0A4] = "Enmity",
  [0x0D8] = "Wing",
}
local function fclabAtk(id, sp)
  if id == 0x1FE then return "Nothing" end
  if id == 0xEF and FCLAB_SPECIAL[sp] then return "Special:" .. FCLAB_SPECIAL[sp] end
  return FCLAB_ATTACK[id] or string.format("$%02X", id)
end
local function fclabMonSpecies(i) return H.readWord(0x57C0 + i * 2) end
local function fclabSpName(w)
  return FCLAB_SPECIES[w] or string.format("$%03X", w or 0xFFF)
end
local function fclabMonHp(i) return H.readWord(0x3BFC + i * 2) end
local function fclabMonShields(i) return H.readByte(0x3E40 + i * 2) end
-- Which slots the formation opened with: the occupied-slot mask $3F45
-- (H.MONSTER_PRESENT), the same byte M.monsterIds decodes from, and the
-- ONLY reliable answer here.  $3AA8 (the per-slot presence bit) and $3BFC
-- (HP) are NOT cleared between battles: reading "in the formation" from them lists
-- the tail of the previous fight for a slot this formation never filled,
-- which is how two earlier cuts of this lab called formation 188 -- Ninja
-- + Wirey Drgn, mask $05 -- "Ninja+Ninja+WireyDrgn" while the driver's own
-- line on the same fight read `monhp=s0:1650/sh2,s2:2802/sh2 monsters=2`.
local function fclabInForm(i) return ((H.readByte(0x3F45) >> i) & 1) == 1 end
-- alive right now, within the formation
local function fclabOnStage(i) return fclabInForm(i) and fclabMonHp(i) > 0 end
local function fclabMonPresent(i) return fclabInForm(i) end
local function fclabSlotChar(s) return H.readByte(0x3ED8 + s * 2) end
local function fclabPartyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(0x3BF4 + e * 2) end
  return p
end
-- the formation as it stands right now, slot by slot
local function fclabStage()
  local m = {}
  for i = 0, 5 do
    if fclabMonPresent(i) then
      m[#m + 1] = string.format("s%d:%s:%d/sh%d", i, fclabSpName(fclabMonSpecies(i)),
        fclabMonHp(i), fclabMonShields(i))
    end
  end
  return table.concat(m, " ")
end
-- the formation's name, for grouping deaths by the fight they happened in
local fclabForm, fclabFight = "none", 0
local function fclabFormName()
  local n = {}
  for i = 0, 5 do
    if fclabMonPresent(i) then
      n[#n + 1] = fclabSpName(fclabMonSpecies(i))
    end
  end
  return #n > 0 and table.concat(n, "+") or "none"
end
-- the field party, levels/rows/gear/HP: the state the crossing goes in with
function fclabParty(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    local base = 0x1600 + 37 * c
    out[#out + 1] = string.format(
      "c%d=L%d %d/%d hp %d/%d mp %s gear=%02X,%02X,%02X,%02X relics=%02X,%02X",
      c, H.readByte(base + 8),
      H.readWord(base + 0x09), H.readWord(base + 0x0B) & 0x3FFF,
      H.readWord(base + 0x0D), H.readWord(base + 0x0F) & 0x3FFF,
      (H.readByte(0x1850 + c) & 0x20) ~= 0 and "back" or "front",
      H.readByte(base + 0x1F), H.readByte(base + 0x20),
      H.readByte(base + 0x21), H.readByte(base + 0x22),
      H.readByte(base + 0x23), H.readByte(base + 0x24))
  end
  H.log(string.format("[fcalcovelab] [party %s] f%d %s", tag, H.frame,
    table.concat(out, " | ")))
end

local fclabPending, fclabEvents, fclabIn = {}, {}, false
local fclabMask, fclabStable = -1, 0
function fclabHook()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x % 2 ~= 0 or x > 0x12 then return end
    fclabPending[x] = { cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      tgt = H.readWord(0xB8), hp = fclabPartyHp() }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local mx = nil
    for x = 8, 0x12, 2 do if fclabPending[x] then mx = x end end
    if not mx then return end
    local raw = {}
    for e = 1, 4 do
      local w = H.readWord(0x33D0 + (e - 1) * 2)
      raw[e] = (w == 0xFFFF) and 0x3FFF or (w & 0x3FFF)
    end
    fclabPending[mx].raw = raw
  end, emu.callbackType.exec, H.sym("_writedamage"), H.sym("_writedamage"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = fclabPending[x]
    if not p then return end
    fclabPending[x] = nil
    if x < 8 then return end                       -- party actions: not the question
    local slot = (x - 8) // 2
    local sp = fclabMonSpecies(slot)
    local after = fclabPartyHp()
    local dmg, raw, kills = {}, {}, 0
    for e = 1, 4 do
      dmg[e] = p.hp[e] - after[e]
      raw[e] = (p.raw and p.raw[e]) or 0x3FFF
      if p.hp[e] > 0 and after[e] == 0 then kills = kills + 1 end
    end
    -- the AI's "attack ... NOTHING" resolves as command $12 with a stale
    -- $b6 (lab_map269_random.lua): label it rather than the leftover
    local atk = (p.cmd == 0x12) and 0x1FE or p.atk
    if dmg[1] + dmg[2] + dmg[3] + dmg[4] ~= 0 or kills > 0 then
      fclabEvents[#fclabEvents + 1] = string.format(
        "[hit] f%d fight%d form=%s %s(s%d) cmd=%02X atk=%s tgt=%04X "
        .. "dmg=%d,%d,%d,%d raw=%d,%d,%d,%d kills=%d party=%d,%d,%d,%d",
        H.frame, fclabFight, fclabForm, fclabSpName(sp), slot, p.cmd,
        fclabAtk(atk, sp), p.tgt, dmg[1], dmg[2], dmg[3], dmg[4],
        raw[1], raw[2], raw[3], raw[4], kills,
        after[1], after[2], after[3], after[4])
    end
    for e = 1, 4 do
      if p.hp[e] > 0 and after[e] == 0 then
        fclabEvents[#fclabEvents + 1] = string.format(
          "[kill] f%d fight%d form=%s entity %d char %d from %d/%d by %s(s%d) %s "
          .. "raw=%d bp=%d party_bp=%d,%d,%d,%d stage=%s",
          H.frame, fclabFight, fclabForm, e - 1, fclabSlotChar(e - 1), p.hp[e],
          H.readWord(0x3C1C + (e - 1) * 2), fclabSpName(sp), slot,
          fclabAtk(atk, sp), raw[e], H.readByte(0x3E9C + (e - 1) * 2),
          H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0),
          H.readByte(0x3EA2), fclabStage())
      end
    end
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
  emu.addEventCallback(function()
    -- one [stage] line per battle, the first frame a body stands on it
    -- The formation is named once its own occupied-slot mask ($3F45, the
    -- lib's M.MONSTER_PRESENT) has held STILL for 120 frames.  None of
    -- $3F45, $3AA8, $57C0 or $3BFC is cleared between battles and all of
    -- them are written during the load, so a read taken while the load is
    -- still running lists the tail of the previous fight: two earlier cuts
    -- of this lab (at the first frame, and 120 frames after
    -- battleLoadStarted) both called formation 188 -- Ninja + Wirey Drgn,
    -- mask $05 -- "Ninja+Ninja+WireyDrgn", against the driver's own
    -- `monhp=s0:1650/sh2,s2:2802/sh2 monsters=2` on the same fight.
    -- battleLoadStarted, not battleActive: the latter takes a screenshot
    -- on every call, and this runs on every frame of the whole segment.
    -- It is the same battle-epoch trigger the lib's own watchdog uses.
    local live = H.battleLoadStarted()
    if live then
      local mask = H.readByte(0x3F45) & 0x3F
      if mask ~= fclabMask then fclabMask, fclabStable = mask, 0
      else fclabStable = fclabStable + 1 end
      local ready = mask ~= 0 and fclabStable >= 120
      for i = 0, 5 do if fclabInForm(i) and fclabMonHp(i) == 0 then ready = false end end
      if not fclabIn and ready then
        fclabIn = true
        fclabFight = fclabFight + 1
        fclabForm = fclabFormName()
        local p = fclabPartyHp()
        H.log(string.format("[fcalcovelab] [stage] f%d fight%d form=%s mask=$%02X %s "
          .. "party=%d,%d,%d,%d", H.frame, fclabFight, fclabForm,
          H.readByte(0x3F45) & 0x3F, fclabStage(), p[1], p[2], p[3], p[4]))
      end
    else
      -- between fights the formation has no name; a kill attributed before
      -- the stage line says "?" rather than inheriting the last fight's
      fclabIn, fclabMask, fclabStable, fclabForm = false, -1, 0, "?"
    end
    if #fclabEvents == 0 then return end
    for _, e in ipairs(fclabEvents) do H.log("[fcalcovelab] " .. e) end
    fclabEvents = {}
  end, emu.eventType.endFrame)
end
'''

# ---- anchors -------------------------------------------------------------
HOOK_OLD = '  H.call(function() H.assertEntryContract("fc-landing-v1") end),\n'
HOOK_NEW = HOOK_OLD + '''  -- fcalcovelab: register the read-only observers before any fight
  H.call(function() fclabHook(); fclabParty("landing (before rows)") end),
'''

# the eleven rungs the generator already applies at the alcove, verbatim
SHADOW_KIT = '''  kitSteps(SHADOW, "SHADOW", { { 4, 0xD1 },
                               { 0, 0x01 }, { 0, 0x04 }, { 0, 0x05 },
                               { 1, 0x01 }, { 1, 0x04 },
                               { 2, 0x69 }, { 2, 0x6B },
                               { 3, 0x84 }, { 3, 0x8A },
                               { 5, 0xB3 } }),
'''

ANCHOR = '  H.fieldCare({ tag = "care after Shadow", threshold = 0.9 }),\n'

DRESS_STEPS = '''  -- fcalcovelab(dress): SHADOW's kit HERE, at the landing where he joins,
  -- instead of at the alcove after the crossing is already over.  Same
  -- eleven rungs, same bag, same H.equipKit ladder -- only the place moves.
''' + SHADOW_KIT + '''  H.fieldCare({ tag = "care after the landing kit", threshold = 0.9 }),
'''

BACK_STEPS = '''  -- fcalcovelab(back): SHADOW to the back row.  The generator's own
  -- setRows ran before he joined, so the shipped run never sets his.
  H.setRows({ [SHADOW] = true }, { tag = "fcalcovelab SHADOW back" }),
'''

PARTY_LINE = '  H.call(function() fclabParty("descent start") end),\n'


def derive(policy, src):
    opts = POLICIES[policy]
    assert src.count(LIB_LINE) == 1, "lib line"
    out = src.replace(LIB_LINE, OBSERVERS)
    assert out.count(HOOK_OLD) == 1, "hook anchor"
    out = out.replace(HOOK_OLD, HOOK_NEW)
    assert out.count(SHADOW_KIT) == 1, "the alcove SHADOW kit"
    assert out.count(ANCHOR) == 1, "the landing care anchor"
    steps = ANCHOR
    if opts.get("back"):
        steps += BACK_STEPS
    if opts.get("dress"):
        steps += DRESS_STEPS
    steps += PARTY_LINE
    out = out.replace(ANCHOR, steps)
    return out


def write(policies):
    src = open(GEN, encoding="utf-8").read()
    os.makedirs(OUT, exist_ok=True)
    for p in policies:
        path = os.path.join(OUT, p + ".lua")
        open(path, "w", encoding="utf-8").write(derive(p, src))
        print("wrote", os.path.relpath(path, ROOT))


def run_one(policy, seed):
    d = os.path.join(OUT, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "seed%02d.log" % seed)
    env = dict(os.environ)
    env.update({
        "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(seed),
        "OT6_NO_PUBLISH": "1", "OT6_KEEP_RUNS": "1",
        "OT6_SRAM_CHECKPOINT": CHECKPOINT,
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "3600"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "seed%02d" % seed),
        "OT6_WORKER": "fcalcove-%s-%02d" % (policy, seed),
    })
    with open(os.path.join(d, "seed%02d.out" % seed), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             os.path.join(OUT, policy + ".lua"), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return policy, seed, rc, summarize(log)


PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
KILL = re.compile(r"^\[ot6\] \[fcalcovelab\] \[kill\] .*")
DEATH = re.compile(r"^\[ot6\] .*\[death\] ")
STAGE = re.compile(r"^\[ot6\] \[fcalcovelab\] \[stage\] f\d+ fight(\d+) form=(\S+) mask=")
PARTY = re.compile(r"^\[ot6\] \[fcalcovelab\] \[party (.*?)\] (.*)")
FENIX = re.compile(r"^\[ot6\] .*(used \$F0 |Fenix Down landed)")
# one line per descent attempt started, and one per attempt LOST (a lost
# attempt also logs "did not reach the alcove", so only LOST is counted --
# counting both double-counted every reload)
ATTEMPT = re.compile(r"^\[ot6\] \[descent\] attempt (\d+) (LOST|reached|did not)")
LOST = re.compile(r"^\[ot6\] \[descent\] attempt (\d+) LOST ")
FIRSTB = re.compile(r"^\[ot6\] \[seed\] first battle:.*key (\S+)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, kills=[], deaths=[], fenix=0, fights=0,
             forms={}, attempts=0, lost=0, fail="", party={}, key="")
    if not os.path.exists(log):
        r["fail"] = "no log"
        return r
    for line in open(log, errors="replace"):
        line = line.rstrip("\n")
        if not line.startswith("[ot6] "):
            continue
        m = PASS.match(line)
        if m:
            r["verdict"], r["frame"] = "PASS", int(m.group(1))
            continue
        m = FAILV.match(line)
        if m:
            r["verdict"], r["fail"] = "FAIL", m.group(1)[:140]
            continue
        m = FIRSTB.match(line)
        if m and not r["key"]:
            r["key"] = m.group(1)
            continue
        m = STAGE.match(line)
        if m:
            r["fights"] = max(r["fights"], int(m.group(1)))
            r["forms"][m.group(2)] = r["forms"].get(m.group(2), 0) + 1
            continue
        m = PARTY.match(line)
        if m:
            r["party"][m.group(1)] = m.group(2)
            continue
        if KILL.match(line):
            r["kills"].append(line[len("[ot6] [fcalcovelab] "):])
            continue
        if DEATH.match(line):
            r["deaths"].append(line[len("[ot6] "):])
            continue
        if FENIX.match(line):
            r["fenix"] += 1
            continue
        m = ATTEMPT.match(line)
        if m:
            r["attempts"] = max(r["attempts"], int(m.group(1)))
            if LOST.match(line):
                r["lost"] += 1
    return r


def aggregate(policies, seeds):
    print("%-10s %4s %-7s %7s %6s %6s %5s %6s %5s  %s" % (
        "policy", "seed", "verdict", "frames", "deaths", "fenix", "wipe",
        "fights", "atts", "first battle"))
    totals = {}
    for p in policies:
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            r = summarize(log)
            t = totals.setdefault(p, dict(n=0, done=0, deaths=0, fenix=0, lost=0,
                                          fights=0, frames=[]))
            t["n"] += 1
            if r["verdict"] == "PASS":
                t["done"] += 1
                t["frames"].append(r["frame"])
            t["deaths"] += len(r["deaths"])
            t["fenix"] += r["fenix"]
            t["lost"] += r["lost"]
            t["fights"] += r["fights"]
            print("%-10s %4d %-7s %7s %6d %6d %5d %6d %5d  %s %s" % (
                p, s, r["verdict"], r["frame"] or "-", len(r["deaths"]), r["fenix"],
                r["lost"], r["fights"], r["attempts"], r["key"], r["fail"]))
    print()
    print("%-10s %3s %5s %7s %6s %6s %7s %8s" % (
        "policy", "n", "pass", "deaths", "fenix", "wipes", "fights", "frames"))
    for p in policies:
        t = totals.get(p)
        if not t:
            continue
        mean = sum(t["frames"]) // len(t["frames"]) if t["frames"] else 0
        print("%-10s %3d %5d %7d %6d %6d %7d %8d" % (
            p, t["n"], t["done"], t["deaths"], t["fenix"], t["lost"],
            t["fights"], mean))
    print()
    for p in policies:
        print("== %s" % p)
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            r = summarize(log)
            print("  seed%02d: %s frame=%s deaths=%d fenix=%d  (%s)"
                  % (s, r["verdict"], r["frame"], len(r["deaths"]), r["fenix"],
                     os.path.relpath(log, ROOT)))
            for k in r["party"].items():
                print("    [party %s] %s" % k)
            for k in r["kills"]:
                print("    " + k)
            for k in r["deaths"]:
                print("    " + k)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["write", "run", "aggregate"])
    ap.add_argument("policies", nargs="*")
    ap.add_argument("--seeds", default="0,10,20,30,40,50")
    ap.add_argument("--jobs", type=int, default=1)
    a = ap.parse_args()
    pols = a.policies or list(POLICIES)
    for p in pols:
        if p not in POLICIES:
            sys.exit("fcalcovelab: unknown policy %r (have %s)"
                     % (p, ", ".join(POLICIES)))
    seeds = [int(s) for s in a.seeds.split(",") if s != ""]
    if a.cmd == "write":
        write(pols)
        return 0
    if a.cmd == "aggregate":
        aggregate(pols, seeds)
        return 0
    write(pols)
    jobs = [(p, s) for p in pols for s in seeds]
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        for policy, seed, rc, r in ex.map(lambda j: run_one(*j), jobs):
            print("  %-10s seed %2d: %-4s rc=%d frames=%s deaths=%d fenix=%d %s"
                  % (policy, seed, r["verdict"], rc, r["frame"], len(r["deaths"]),
                     r["fenix"], r["fail"]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
