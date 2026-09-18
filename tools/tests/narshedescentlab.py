#!/usr/bin/env python3
"""narshedescentlab.py -- the Narshe defense descent lab (docs/design/narshe-descent.md).

    python3 tools/tests/narshedescentlab.py write [policy ...]
    python3 tools/tests/narshedescentlab.py rom          # build the pre-#219 control ROM
    python3 tools/tests/narshedescentlab.py run   [--seeds 0,5,10,...] [--jobs N] policy [...]
    python3 tools/tests/narshedescentlab.py aggregate [policy ...]
    python3 tools/tests/narshedescentlab.py table <log>  # the per-battle resource table

`write` derives gen_narshe_battle.lua into build/lab/narshe-descent/<policy>.lua:
the generator verbatim, plus two read-only CPU exec observers and a settled
per-battle line, plus (for the `priced` policy) the one changed line in the
generator's own fighter.  Every substitution asserts it matched exactly once,
so a generator edit that moves an anchor fails the derivation instead of
silently measuring something else.

`run` plays each variant once per seed from the tracked `reunion_ready`
fixture exactly as the ninja graph does, with the lib's retries OFF
(OT6_RETRIES=1, so every seed reports its first try) and OT6_SEED_SHIFT idle
frames at the boot point -- the beat a player pauses before walking on.  Logs
and artifacts stay under build/lab/narshe-descent/<policy>/; nothing is
published to build/states.  Every attempt is kept, failures included.

The measurement (read-only; nothing here presses a button or writes a byte):

  ExecCmd@battle_code   runs with X = the acting entity's offset and $b5/$b6
                        the command/attack after queue-time folding.  The
                        observer parks the actor's MP ($3c08+x), banked BP
                        ($3e9c+x), revealed boost ($3e9d+x), the party's HP
                        and every monster's HP.
  SaveForMimic          runs once the command has resolved -- including down
                        the insufficient-MP path, which aborts inside ExecCmd
                        and returns to ExecAction's own `jsr SaveForMimic`
                        (battle_main.asm:277-278).  That is what makes a
                        fizzled turn visible: same MP, no damage, turn gone.

A "fizzle" in the table below is therefore measured, not inferred: a costed
verb ($09 Tools, $0a Blitz, $07 SwdTech, a cast) whose MP did not move and
whose monsters lost nothing.

The pre-#219 control ROM is assembled from the same sources with
`-D OT6_BOOST_PRICE=0` (battle_main.asm), which makes Ot6BoostPriceFor return
the base cost at every boost level: every base price still charged, a boost
free again.  `rom` builds it beside its own .dbg, and the run arm points both
OT6_ROM and OT6_DBG at it -- the flag moves every label after the proc, so
the observers must read that ROM's symbols.

Policies:

  control    the fighter as it stood when #219 landed and the segment began
             failing: the bank's whole boost, planned without asking what it
             costs.  On the shipped ROM.
  priced     the fighter asking what the boost costs first (H.affordBoost,
             the lib's copy of Ot6BoostPriceFor) and stepping it down to
             what the pool covers, but spending that pool freely
  ration     the generator as it ships TODAY: priced, and rationed -- one
             turn spends at most a quarter of the caster's MAXIMUM MP, so a
             pool with no refill point between the staging tile and KEFKA is
             not emptied by its first two turns
  preprice   `control`'s fighter on the pre-#219 control ROM -- the "before"
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_narshe_battle.lua")
OUT = os.path.join(ROOT, "build", "lab", "narshe-descent")
ROMDIR = os.path.join(OUT, "roms")
PREPRICE_ROM = os.path.join(ROMDIR, "ff6-en-preprice.sfc")
PREPRICE_DBG = os.path.join(ROMDIR, "ff6-en-preprice.dbg")

POLICIES = {
    "control":  {"body": "unpriced"},
    "priced":   {"body": "priced"},
    "ration":   {},                       # the shipped body, verbatim
    "preprice": {"body": "unpriced", "rom": "preprice"},
}

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

OBSERVERS = LIB_LINE + r'''
-- ------------------------------------------------- narshedescentlab --
-- Read-only measurement.  Nothing here presses a button or writes a byte;
-- the generator below plays exactly as it ships except for the one line
-- marked `narshedescentlab(priced)`, which only the priced policy carries.
local NDCMD = {                    -- BattleCmdProp's order, battle_main.asm
  [0x00] = "Fight", [0x01] = "Item", [0x02] = "Magic", [0x03] = "Morph",
  [0x05] = "Steal", [0x06] = "Capture", [0x07] = "SwdTech", [0x08] = "Throw",
  [0x09] = "Tools", [0x0A] = "Blitz", [0x0B] = "Runic", [0x0C] = "Lore",
  [0x0D] = "Sketch", [0x0E] = "Control", [0x0F] = "Slot", [0x10] = "Rage",
  [0x11] = "Leap", [0x12] = "Mimic", [0x13] = "Dance", [0x14] = "Row",
  [0x15] = "Def", [0x16] = "Jump", [0x17] = "XMagic", [0x19] = "Summon",
}
-- the verbs whose turn OT6 charges MP for (Ot6AbilityCost's three command
-- arms plus Steal, and vanilla's own magic).  A turn under one of these
-- that neither spent MP nor moved a monster is the insufficient-MP fizzle.
local NDCOSTED = { [0x02] = true, [0x05] = true, [0x07] = true,
                   [0x09] = true, [0x0A] = true, [0x0C] = true,
                   [0x13] = true, [0x17] = true, [0x19] = true }
local function ndInForm(i) return ((H.readByte(0x3F45) >> i) & 1) == 1 end
local function ndMonHp()
  local t = 0
  for i = 0, 5 do
    if ndInForm(i) then t = t + H.readWord(0x3BFC + i * 2) end
  end
  return t
end
local function ndPartyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(0x3BF4 + e * 2) end
  return p
end
local function ndPartyMp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(0x3C08 + e * 2) end
  return p
end
-- the driver's own plan for a slot, stamped where the generator builds its
-- button sequence, so the table can say what boost the turn ASKED for
-- beside what the ROM revealed.
NDPLAN = {}
local ndFight, ndMask, ndStable, ndIn, ndLast = 0, -1, 0, false, nil
local ndPending, ndEvents = {}, {}
local function ndPush(s) ndEvents[#ndEvents + 1] = s end

function ndHook()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x >= 8 or x % 2 ~= 0 then return end
    ndPending[x] = {
      cmd = H.readByte(0xB5), atk = H.readByte(0xB6), tgt = H.readWord(0xB8),
      mp = H.readWord(0x3C08 + x), bp = H.readByte(0x3E9C + x),
      rev = H.readByte(0x3E9D + x), mon = ndMonHp(), hp = ndPartyHp(),
      f = H.frame,
    }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"),
     H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = ndPending[x]
    if not p then return end
    ndPending[x] = nil
    -- commands from $1e up are the engine's own (the dot tick of Poison /
    -- Regen, the AI path), not a turn the menu spent (lib/ot6.lua's
    -- EXEC_MENU_CMDS).  They are not turns and do not belong in the table.
    if p.cmd >= 0x1E then return end
    local mp, mon, hp = H.readWord(0x3C08 + x), ndMonHp(), ndPartyHp()
    local slot = x // 2
    local spent, dmg = p.mp - mp, p.mon - mon
    local took = 0
    for e = 1, 4 do took = took + math.max(0, p.hp[e] - hp[e]) end
    local fizzle = (NDCOSTED[p.cmd] and spent == 0 and dmg == 0) and 1 or 0
    ndPush(string.format(
      "[act] f%d b%d slot%d char%d %s($%02X) atk=$%02X bp=%d rev=%d plan=%s "
      .. "mp %d->%d spent=%d dmg=%d took=%d fizzle=%d hp0=%d,%d,%d,%d "
      .. "hp1=%d,%d,%d,%d",
      H.frame, ndFight, slot, H.readByte(0x3ED8 + x),
      NDCMD[p.cmd] or "?", p.cmd, p.atk, p.bp, p.rev,
      tostring(NDPLAN[slot]), p.mp, mp, spent, dmg, took, fizzle,
      p.hp[1], p.hp[2], p.hp[3], p.hp[4], hp[1], hp[2], hp[3], hp[4]))
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))

  emu.addEventCallback(function()
    -- one [fight] line per battle, taken from a SETTLED frame: none of
    -- $3f45, $3aa8, $57c0 or $3bfc is cleared between battles and all are
    -- written during the load, so a read taken while the load still runs
    -- lists the tail of the previous fight (fcalcovelab's own finding).
    local live = H.battleLoadStarted()
    if live then
      local mask = H.readByte(0x3F45) & 0x3F
      if mask ~= ndMask then ndMask, ndStable = mask, 0
      else ndStable = ndStable + 1 end
      local ready = mask ~= 0 and ndStable >= 120
      for i = 0, 5 do
        if ndInForm(i) and H.readWord(0x3BFC + i * 2) == 0 then ready = false end
      end
      if not ndIn and ready then
        ndIn = true
        ndFight = ndFight + 1
        local form, hp, mp = {}, ndPartyHp(), ndPartyMp()
        for i = 0, 5 do
          if ndInForm(i) then
            form[#form + 1] = string.format("$%04X:%d/sh%d",
              H.readWord(0x57C0 + i * 2), H.readWord(0x3BFC + i * 2),
              H.readByte(0x3E40 + i * 2))
          end
        end
        H.log(string.format("[ndlab] [fight] %d f%d form=%s monhp=%d "
          .. "hp=%d,%d,%d,%d mp=%d,%d,%d,%d bp=%d,%d,%d,%d",
          ndFight, H.frame, table.concat(form, "+"), ndMonHp(),
          hp[1], hp[2], hp[3], hp[4], mp[1], mp[2], mp[3], mp[4],
          H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0),
          H.readByte(0x3EA2)))
      end
      if ndIn then ndLast = { f = H.frame, hp = ndPartyHp(),
                              mp = ndPartyMp(), mon = ndMonHp() } end
    elseif ndIn then
      -- the LAST LIVE frame's numbers, not this one's: on the falling edge
      -- $3bf4/$3c08 have already been torn down and read back as $ffff
      -- (an early cut of this lab printed mp=65535 for every fight).
      local L = ndLast or { f = H.frame, hp = ndPartyHp(), mp = ndPartyMp(),
                            mon = ndMonHp() }
      H.log(string.format("[ndlab] [fightend] %d f%d monhp=%d "
        .. "hp=%d,%d,%d,%d mp=%d,%d,%d,%d", ndFight, L.f, L.mon,
        L.hp[1], L.hp[2], L.hp[3], L.hp[4],
        L.mp[1], L.mp[2], L.mp[3], L.mp[4]))
      ndIn, ndMask, ndStable, ndLast = false, -1, 0, nil
    else
      ndIn, ndMask, ndStable, ndLast = false, -1, 0, nil
    end
    if #ndEvents == 0 then return end
    for _, e in ipairs(ndEvents) do H.log("[ndlab] " .. e) end
    ndEvents = {}
  end, emu.eventType.endFrame)
end

-- the field party as the descent starts: levels, rows, HP, MP, gear
function ndParty(tag)
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
  H.log(string.format("[ndlab] [party %s] f%d %s", tag, H.frame,
    table.concat(out, " | ")))
end
'''

# ---- anchors -------------------------------------------------------------
# where the observers come online: the first step of the run, before any
# fight and before the staging assertions.
HOOK_OLD = """  H.loadState(BOOT),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "booted on map 22, the reunion staging")
"""
HOOK_NEW = """  H.loadState(BOOT),
  H.waitFrames(30),
  -- narshedescentlab: register the read-only observers before any fight
  H.call(function() ndHook() end),
  H.call(function()
    H.assertEq(map(), 22, "booted on map 22, the reunion staging")
"""

# the party line, taken at the defense-live checkpoint the descent starts from
PARTY_OLD = """    H.assertPartyStanding("narshe_battle")
    H.screenshot("narshe_battle")
"""
PARTY_NEW = """    H.assertPartyStanding("narshe_battle")
    ndParty("descent start")
    H.screenshot("narshe_battle")
"""

# ---- the fighter, per policy --------------------------------------------
# The shipped generator's own fighter now prices and rations the boost
# (#219).  A policy is that region of seqFor -- from its `function` line to
# the `local seq = {}` that starts building the button sequence -- replaced
# by the cut being measured, plus one read-only stamp so the table can name
# the boost the turn ASKED for.  `ration` replaces nothing: it IS the
# shipped body, and measuring it is measuring what the tree ships.
PLAN_HEAD = "local function seqFor(id, tier, slot)\n"
PLAN_TAIL = "  local seq = {}\n"
STAMP = "  NDPLAN[slot] = boost                       -- narshedescentlab\n"

# `control`: the fighter as it stood BEFORE #219 landed -- the bank's whole
# boost, planned without asking what it costs.
BODY_UNPRICED = """  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
"""

# `priced`: ask what the boost costs and step it down to what the pool can
# pay -- but spend that pool as fast as the bank fills.
BODY_PRICED = """  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  -- narshedescentlab(priced): price the boost before planning it (#219),
  -- with no ration.  The two costed verbs this fighter reaches for are
  -- EDGAR's AutoCrossbow (a $09) and SABIN's Pummel (a $0a); both are
  -- @boosted arms, so the price is the flat 2.5x ladder off their
  -- Ot6AbilityCostTbl base.  Runic and Fight are free.
  local costed = nil
  if id == 4 and tier >= 2 then costed = 0xAA
  elseif id == 5 and tier >= 3 then costed = 0x5D
  end
  if costed then
    local got = H.affordBoost({ base = H.abilityCost(costed) or 0,
                                pool = H.readWord(BCMP + slot * 2),
                                want = boost })
    boost = got or 0
    if got == nil then tier = 0 end
  end
"""

BODIES = { "unpriced": BODY_UNPRICED, "priced": BODY_PRICED }


def derive(policy, src):
    opts = POLICIES[policy]
    assert src.count(LIB_LINE) == 1, "lib line"
    out = src.replace(LIB_LINE, OBSERVERS)
    assert out.count(HOOK_OLD) == 1, "boot anchor"
    out = out.replace(HOOK_OLD, HOOK_NEW)
    assert out.count(PARTY_OLD) == 1, "party anchor"
    out = out.replace(PARTY_OLD, PARTY_NEW)
    # the shipped seqFor body, located by its two ends rather than quoted,
    # so an edit INSIDE it is measured and an edit to either end fails here
    assert out.count(PLAN_HEAD) == 1, "seqFor head"
    h = out.index(PLAN_HEAD) + len(PLAN_HEAD)
    t = out.index(PLAN_TAIL, h)
    body = BODIES.get(opts.get("body"), out[h:t])
    out = out[:h] + body + STAMP + out[t:]
    return out


def write(policies):
    src = open(GEN, encoding="utf-8").read()
    os.makedirs(OUT, exist_ok=True)
    for p in policies:
        path = os.path.join(OUT, p + ".lua")
        open(path, "w", encoding="utf-8").write(derive(p, src))
        print("wrote", os.path.relpath(path, ROOT))


# ---- the pre-#219 control ROM -------------------------------------------
NOMP_OBJS = ["field_en", "btlgfx_en", "battlepreprice_en", "menu_en",
             "sound_en", "cutscene_en", "event_en", "world_en", "gfx_en",
             "text_en"]


def build_rom():
    """Assemble the battle module with -D OT6_BOOST_PRICE=0 and link it.

    The same sources, the same cfg, the same double-link recipe the graph
    uses; only the one flag differs.  link_rom.sh shares the cfg-hardcoded
    temp_lz scratch with the graph's own links, so this must not run beside
    a ninja ROM build.
    """
    os.makedirs(ROMDIR, exist_ok=True)
    ff6 = os.path.join(ROOT, "ff6")
    for m in ["field", "btlgfx", "menu", "sound", "cutscene", "event",
              "world", "gfx", "text"]:
        o = os.path.join(ff6, "obj", m + "_en.o")
        if not os.path.exists(o):
            sys.exit("narshedescentlab: %s is missing -- run `ninja build/ot6.sfc`"
                     " first; the control ROM reuses the graph's own objects" % o)
    subprocess.run(
        ["ca65", "-g", "-I", "include", "-D", "LANG_EN=1", "-D", "ROM_VERSION=0",
         "-D", "OT6_BOOST_PRICE=0", "-l", "obj/battlepreprice_en.lst",
         "src/battle/battle_main.asm", "-o", "obj/battlepreprice_en.o"],
        cwd=ff6, check=True)
    rel = os.path.relpath(PREPRICE_ROM, ff6)
    subprocess.run(["sh", os.path.join(ROOT, "tools/build/link_rom.sh"),
                    "cfg/ff6-en.cfg", rel]
                   + ["obj/%s.o" % o for o in NOMP_OBJS],
                   cwd=ROOT, check=True)
    shipped = open(os.path.join(ROOT, "build/ot6.sfc"), "rb").read()
    control = open(PREPRICE_ROM, "rb").read()
    if shipped == control:
        sys.exit("narshedescentlab: the OT6_BOOST_PRICE=0 control is "
                 "byte-identical to the shipped ROM -- the flag is dead")
    if not os.path.exists(PREPRICE_DBG):
        sys.exit("narshedescentlab: no %s -- H.sym would read the shipped "
                 "ROM's addresses" % PREPRICE_DBG)
    print("built", os.path.relpath(PREPRICE_ROM, ROOT),
          "(%d bytes, differs from the shipped ROM)" % len(control))


def run_one(policy, seed):
    d = os.path.join(OUT, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "seed%02d.log" % seed)
    env = dict(os.environ)
    env.update({
        "OT6_LIVE": "0", "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(seed),
        "OT6_NO_PUBLISH": "1", "OT6_KEEP_RUNS": "1",
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "5400"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "seed%02d" % seed),
        "OT6_WORKER": "ndescent-%s-%02d" % (policy, seed),
    })
    if POLICIES[policy].get("rom") == "preprice":
        if not os.path.exists(PREPRICE_ROM):
            sys.exit("narshedescentlab: run `narshedescentlab.py rom` first")
        # both, always: the flag moves every label after Ot6BoostPriceFor,
        # so the ROM and the symbol file have to be the same build
        env["OT6_ROM"] = PREPRICE_ROM
        env["OT6_DBG"] = PREPRICE_DBG
    with open(os.path.join(d, "seed%02d.out" % seed), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             os.path.join(OUT, policy + ".lua"), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return policy, seed, rc, summarize(log)


# ---- reading a log -------------------------------------------------------
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
FIGHT = re.compile(r"^\[ot6\] \[ndlab\] \[fight\] (\d+) f(\d+) form=(\S+) "
                   r"monhp=(\d+) hp=(\S+) mp=(\S+) bp=(\S+)")
FEND = re.compile(r"^\[ot6\] \[ndlab\] \[fightend\] (\d+) f(\d+) monhp=(\d+) "
                  r"hp=(\S+) mp=(\S+)")
ACT = re.compile(r"^\[ot6\] \[ndlab\] \[act\] f(\d+) b(\d+) slot(\d+) char(\d+) "
                 r"(\S+)\(\$([0-9A-F]{2})\) atk=\$([0-9A-F]{2}) bp=(\d+) "
                 r"rev=(\d+) plan=(\S+) mp (\d+)->(\d+) spent=(-?\d+) "
                 r"dmg=(-?\d+) took=(-?\d+) fizzle=(\d) hp0=(\S+) hp1=(\S+)")
PARTY = re.compile(r"^\[ot6\] \[ndlab\] \[party (.*?)\] f\d+ (.*)")
WIPE = re.compile(r"^\[ot6\] \[descent\] PARTY WIPED in battle #(\d+) at f(\d+)")
ATTEMPT = re.compile(r"^\[ot6\] \[descent\] ATTEMPT (\d+) --")
REACHED = re.compile(r"^\[ot6\] \[descent\] attempt (\d+) reached the entry point")
FIRSTB = re.compile(r"^\[ot6\] \[seed\] first battle:.*key (\S+)")
CARE = re.compile(r"^\[ot6\] \[care before the raider corridor \d+\] (opening|done)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, fights=[], acts=[], wipes=[],
             attempts=1, reached=None, fail="", party="", key="", care=[])
    if not os.path.exists(log):
        r["fail"] = "no log"
        return r
    cur = None
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
            r["verdict"], r["fail"] = "FAIL", m.group(1)[:160]
            continue
        m = FIRSTB.match(line)
        if m and not r["key"]:
            r["key"] = m.group(1)
            continue
        m = PARTY.match(line)
        if m:
            r["party"] = m.group(2)
            continue
        if CARE.match(line):
            r["care"].append(line[len("[ot6] "):])
            continue
        m = FIGHT.match(line)
        if m:
            cur = dict(n=int(m.group(1)), f0=int(m.group(2)), form=m.group(3),
                       monhp=int(m.group(4)),
                       hp0=[int(x) for x in m.group(5).split(",")],
                       mp0=[int(x) for x in m.group(6).split(",")],
                       bp0=[int(x) for x in m.group(7).split(",")],
                       f1=None, hp1=None, mp1=None, acts=[], attempt=r["attempts"])
            r["fights"].append(cur)
            continue
        m = FEND.match(line)
        if m and cur is not None and cur["n"] == int(m.group(1)):
            cur["f1"] = int(m.group(2))
            cur["hp1"] = [int(x) for x in m.group(4).split(",")]
            cur["mp1"] = [int(x) for x in m.group(5).split(",")]
            continue
        m = ACT.match(line)
        if m:
            a = dict(f=int(m.group(1)), b=int(m.group(2)), slot=int(m.group(3)),
                     char=int(m.group(4)), cmd=m.group(5), cmdn=int(m.group(6), 16),
                     atk=int(m.group(7), 16), bp=int(m.group(8)),
                     rev=int(m.group(9)), plan=m.group(10),
                     mp0=int(m.group(11)), mp1=int(m.group(12)),
                     spent=int(m.group(13)), dmg=int(m.group(14)),
                     took=int(m.group(15)), fizzle=int(m.group(16)),
                     hp0=[int(x) for x in m.group(17).split(",")],
                     hp1=[int(x) for x in m.group(18).split(",")])
            r["acts"].append(a)
            if cur is not None and cur["n"] == a["b"]:
                cur["acts"].append(a)
            continue
        m = WIPE.match(line)
        if m:
            r["wipes"].append((int(m.group(1)), int(m.group(2))))
            continue
        m = ATTEMPT.match(line)
        if m:
            r["attempts"] = int(m.group(1))
            continue
        m = REACHED.match(line)
        if m:
            r["reached"] = int(m.group(1))
    return r


CHARNAME = {0: "TERRA", 1: "LOCKE", 2: "CYAN", 4: "EDGAR", 5: "SABIN",
            6: "CELES", 11: "GAU"}


def hp_dropped(f):
    """HP the party lost during one fight.

    Every drop between one sample of the party's HP and the next, seeded
    from the settled fight-start line.  The samples are the two an action
    observer takes (before ExecCmd, after SaveForMimic), so a monster round
    landing between two party turns is billed to the fight it happened in.
    A rise (a Tonic, a level-up's refill, the victory heal) is not counted
    back off, and a body at 0 stops contributing -- what is wanted is the
    damage the fight took, not the net.
    """
    prev, lost = f["hp0"], 0
    for a in f["acts"]:
        for cur in (a["hp0"], a["hp1"]):
            for e in range(4):
                if prev[e] > cur[e]:
                    lost += prev[e] - cur[e]
            prev = cur
    return lost


def table(log):
    """The per-battle resource table for one run."""
    r = summarize(log)
    print("# %s" % os.path.relpath(log, ROOT))
    print("verdict=%s frame=%s attempts=%d reached=%s key=%s"
          % (r["verdict"], r["frame"], r["attempts"], r["reached"], r["key"]))
    if r["party"]:
        print("party: %s" % r["party"])
    print()
    print("%3s %3s %-26s %7s %7s %7s %6s %5s %5s %6s  %s" % (
        "at", "#", "formation", "frames", "mp_sp", "hp_lost", "monhp",
        "turns", "fizz", "dmg", "mp_end (T,E,C)"))
    for f in r["fights"]:
        mp_sp = sum(max(0, a["spent"]) for a in f["acts"])
        fizz = sum(a["fizzle"] for a in f["acts"])
        dmg = sum(a["dmg"] for a in f["acts"])
        hp_lost = hp_dropped(f)
        frames = (f["f1"] - f["f0"]) if f["f1"] else 0
        mpend = f["mp1"] or f["mp0"]
        print("%3d %3d %-26s %7d %7d %7d %6d %5d %5d %6d  %s" % (
            f["attempt"], f["n"], f["form"][:26], frames, mp_sp, hp_lost,
            f["monhp"], len(f["acts"]), fizz, dmg,
            ",".join(str(x) for x in mpend[:3])))
    print()
    # who spent what, and on what
    by = {}
    for a in r["acts"]:
        k = (a["char"], a["cmd"])
        t = by.setdefault(k, dict(n=0, mp=0, dmg=0, fizz=0))
        t["n"] += 1
        t["mp"] += max(0, a["spent"])
        t["dmg"] += a["dmg"]
        t["fizz"] += a["fizzle"]
    print("%-8s %-8s %6s %7s %8s %7s %8s" % (
        "char", "verb", "turns", "mp", "damage", "fizzles", "dmg/turn"))
    for (c, cmd), t in sorted(by.items(), key=lambda kv: (-kv[1]["n"],)):
        print("%-8s %-8s %6d %7d %8d %7d %8.1f" % (
            CHARNAME.get(c, "c%d" % c), cmd, t["n"], t["mp"], t["dmg"],
            t["fizz"], t["dmg"] / max(1, t["n"])))
    print()
    for line in r["care"]:
        print("  " + line)
    for n, f in r["wipes"]:
        print("  WIPE in battle #%d at f%d" % (n, f))
    if r["fail"]:
        print("  FAIL: %s" % r["fail"])


def aggregate(policies, seeds):
    print("%-9s %4s %-7s %8s %6s %6s %6s %6s %7s %7s  %s" % (
        "policy", "seed", "verdict", "frames", "atts", "wipes", "fights",
        "turns", "fizzles", "mp_sp", "first battle / failure"))
    totals = {}
    for p in policies:
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            r = summarize(log)
            fizz = sum(a["fizzle"] for a in r["acts"])
            mp = sum(max(0, a["spent"]) for a in r["acts"])
            t = totals.setdefault(p, dict(n=0, done=0, wipes=0, fights=0,
                                          turns=0, fizz=0, mp=0, frames=[]))
            t["n"] += 1
            if r["verdict"] == "PASS":
                t["done"] += 1
                t["frames"].append(r["frame"])
            t["wipes"] += len(r["wipes"])
            t["fights"] += len(r["fights"])
            t["turns"] += len(r["acts"])
            t["fizz"] += fizz
            t["mp"] += mp
            print("%-9s %4d %-7s %8s %6d %6d %6d %6d %7d %7d  %s %s" % (
                p, s, r["verdict"], r["frame"] or "-", r["attempts"],
                len(r["wipes"]), len(r["fights"]), len(r["acts"]), fizz, mp,
                r["key"], r["fail"]))
    print()
    print("%-9s %3s %5s %6s %7s %6s %8s %8s %9s" % (
        "policy", "n", "pass", "wipes", "fights", "turns", "fizzles",
        "fizz/run", "frames"))
    for p in policies:
        t = totals.get(p)
        if not t:
            continue
        mean = sum(t["frames"]) // len(t["frames"]) if t["frames"] else 0
        print("%-9s %3d %5d %6d %7d %6d %8d %8.1f %9d" % (
            p, t["n"], t["done"], t["wipes"], t["fights"], t["turns"],
            t["fizz"], t["fizz"] / max(1, t["n"]), mean))
    print()
    for p in policies:
        print("== %s" % p)
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            r = summarize(log)
            print("  seed%02d: %s frame=%s wipes=%s  (%s)" % (
                s, r["verdict"], r["frame"],
                ",".join("#%d@f%d" % w for w in r["wipes"]) or "-",
                os.path.relpath(log, ROOT)))
            if r["party"]:
                print("    party: %s" % r["party"])
            if r["fail"]:
                print("    FAIL: %s" % r["fail"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["write", "rom", "run", "aggregate", "table"])
    ap.add_argument("policies", nargs="*")
    ap.add_argument("--seeds", default="0,5,10,15,20,25")
    ap.add_argument("--jobs", type=int, default=1)
    a = ap.parse_args()
    if a.cmd == "rom":
        build_rom()
        return 0
    if a.cmd == "table":
        if not a.policies:
            sys.exit("narshedescentlab: table needs a log path")
        for log in a.policies:
            table(log)
            print()
        return 0
    pols = a.policies or list(POLICIES)
    for p in pols:
        if p not in POLICIES:
            sys.exit("narshedescentlab: unknown policy %r (have %s)"
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
            fizz = sum(x["fizzle"] for x in r["acts"])
            print("  %-9s seed %2d: %-4s rc=%d frames=%s fights=%d turns=%d "
                  "fizzles=%d wipes=%d %s"
                  % (policy, seed, r["verdict"], rc, r["frame"],
                     len(r["fights"]), len(r["acts"]), fizz, len(r["wipes"]),
                     r["fail"]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
