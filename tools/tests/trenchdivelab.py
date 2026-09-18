#!/usr/bin/env python3
"""trenchdivelab.py -- the Serpent Trench dive lab (docs/design/trench-dive.md).

    python3 tools/tests/trenchdivelab.py write
    python3 tools/tests/trenchdivelab.py libs          # cut the lib revisions
    python3 tools/tests/trenchdivelab.py rom           # the OT6_BOOST_PRICE=0 ROM
    python3 tools/tests/trenchdivelab.py run [--seeds 0,5,...] [--jobs N] policy [...]
    python3 tools/tests/trenchdivelab.py aggregate [policy ...]
    python3 tools/tests/trenchdivelab.py table <log>   # the per-battle table
    python3 tools/tests/trenchdivelab.py restore       # put the shipped lib back

`write` derives `gen_sabin_trench.lua` into build/lab/trench-dive/trench.lua:
the generator verbatim, plus two read-only CPU exec observers, one settled
per-battle line naming the formation by species, and one party line.  Every
substitution asserts it matched exactly once, so a generator edit that moves
an anchor fails the derivation instead of silently measuring something else.

There is only ONE derived script.  `gen_sabin_trench` has no private fighter
-- it plays every trench battle with the library's own `H.newFightDriver`
(`tag = "trench ..."`, `bank = 3`, `cadence = 12`) -- so the policy under test
is not a region of the generator but the DRIVER, and the axes are:

  * `tools/tests/lib/ot6.lua` at a named commit.  compose.py inlines that
    file by path with no override, so `run` swaps the file in, plays every
    seed of the policy, and puts the shipped copy back.  Policies therefore
    run one at a time; seeds inside a policy run in parallel.
  * the ROM: the same sources assembled with `-D OT6_BOOST_PRICE=0`, which
    makes `Ot6BoostPriceFor` return the base cost at every level -- the
    pre-#219 boost economy.

`run` plays the generator exactly as the ninja graph does -- from the tracked
`gau_joined` fixture, with the generator's OWN three-attempt dive ladder
intact -- with the segment runner's retries OFF (OT6_RETRIES=1, so every seed
reports the ladder's own verdict and not a re-boot), and OT6_SEED_SHIFT idle
frames at the boot point.  Nothing is published to build/states.  Every
attempt is kept, failures included.

The measurement (read-only; nothing here presses a button or writes a byte),
narshedescentlab's observers verbatim in shape:

  ExecCmd@battle_code   X = the acting entity's offset, $b5/$b6 the command
                        and attack after queue-time folding.  Park the
                        actor's MP, banked BP, revealed boost, the party's
                        HP and every stage slot's HP.
  SaveForMimic          runs once the command has resolved.  The deltas are
                        the action's damage, the party's loss, and the MP it
                        spent.

Entities 0-3 are the party; 4-9 are the monster stage slots, and their
actions are recorded too -- which is what this lab needs and the descent's
did not.  The trench's killer is a COUNTER, so an enemy action has to be
readable next to the party action that provoked it.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_sabin_trench.lua")
LIB = os.path.join(ROOT, "tools", "tests", "lib", "ot6.lua")
OUT = os.path.join(ROOT, "build", "lab", "trench-dive")
LIBDIR = os.path.join(OUT, "libs")
ROMDIR = os.path.join(OUT, "roms")
PREPRICE_ROM = os.path.join(ROMDIR, "ff6-en-preprice.sfc")
PREPRICE_DBG = os.path.join(ROMDIR, "ff6-en-preprice.dbg")
SCRIPT = os.path.join(OUT, "trench.lua")

# A policy is (which lib/ot6.lua, which ROM).  `head` is the tree as it
# ships.  The three `pre*` cuts walk back the three commits this cycle put
# into the driver, newest first, so a policy pair brackets exactly one of
# them.  `v018` is the driver v0.18 shipped with.
# The BEFORE arms all carry variant "prefocus": the generator's fight-driver
# config as it stood before this lab's change, i.e. with no kill order.
# `focus` is the generator VERBATIM as it ships now, which is why it
# substitutes nothing.
POLICIES = {
    "head":     {"lib": None, "variant": "prefocus",
                 "why": "the driver that shipped into this cycle, no kill order"},
    "pre235":   {"lib": "cc25e69b", "variant": "prefocus",
                 "why": "before #235 (a swing is not a landed hit)"},
    "pre230":   {"lib": "b18ce557", "variant": "prefocus",
                 "why": "before #230 (boostPlan)"},
    "v018":     {"lib": "v0.18", "variant": "prefocus",
                 "why": "the driver v0.18 shipped (before #219's driver half)"},
    "preprice": {"lib": None, "rom": "preprice", "variant": "prefocus",
                 "why": "today's driver on the pre-#219 boost economy"},
    "focus":    {"lib": None,
                 "why": "the generator as it ships NOW: kill order, the Aspiks first"},
    "noblitz":  {"lib": "patch:noblitz", "variant": "noblitz",
                 "why": "the alternative not taken: SABIN's Blitz line off"},
}

# `noblitz` is the candidate change, cut as a lab arm before it is offered
# as one: `opts.blitz = false` turns SABIN's Blitz line off and leaves the
# rest of the tactical kit alone, exactly as `opts.tools = false` already
# does for EDGAR's AutoCrossbow ("against a formation where a multi-target
# attack heals the enemy, Edgar's single-target pierce Fight removes the
# same class-weak shields without triggering that heal" -- lib/ot6.lua).
# Two sites offer the Blitz; both are gated, and both substitutions assert
# they matched exactly once.
LIB_PATCHES = {
    "noblitz": [
        ("      if opts.tactical and id == 5 and (opts.blitz or PUMMEL) == PUMMEL\n"
         "         and cmdRow(actor, CMD_BLITZ) and not skillDead[CMD_BLITZ] then\n",
         "      if opts.tactical and opts.blitz ~= false                  -- trenchdivelab\n"
         "         and id == 5 and (opts.blitz or PUMMEL) == PUMMEL\n"
         "         and cmdRow(actor, CMD_BLITZ) and not skillDead[CMD_BLITZ] then\n"),
        ("    if opts.tactical and id == 5\n"
         "       and cmdRow(actor, CMD_BLITZ) and not skillDead[CMD_BLITZ] then\n",
         "    if opts.tactical and opts.blitz ~= false and id == 5        -- trenchdivelab\n"
         "       and cmdRow(actor, CMD_BLITZ) and not skillDead[CMD_BLITZ] then\n"),
    ],
}

# A variant is the generator's own fight-driver CONFIG, substituted in the
# derived copy -- the only thing `gen_sabin_trench` owns about how these
# battles are played (it has no private fighter).
DRIVER_OLD = """  local ASPIK = 0x0059
  local F = H.newFightDriver("trench " .. what, { tactical = true,
    boost = true, bank = 3, items = true, healPercent = 60, cadence = 12,
    focus = { { species = ASPIK } } })
"""
VARIANTS = {
    # The config as it stood BEFORE this lab's change: no kill order at
    # all.  Aspik is the only monster in these formations whose
    # retaliation script answers a non-Fight hit with Giga Volt; it is
    # also the flimsiest (220 HP against Actaneon's 230, and 2 battle
    # power against 13), so the shipped `focus` steers the party's Fights
    # at it first and shortens the window in which SABIN's auto-targeted
    # Pummel can land on one.
    "prefocus": """  local F = H.newFightDriver("trench " .. what, { tactical = true,
    boost = true, bank = 3, items = true, healPercent = 60, cadence = 12 })
""",
    # SABIN Fights the dive.  Aspik's retaliation answers a Fight with its
    # own plain Battle (2 battle power) and anything else with Giga Volt.
    "noblitz": """  local F = H.newFightDriver("trench " .. what, { tactical = true,
    boost = true, bank = 3, items = true, healPercent = 60, cadence = 12,
    blitz = false })                            -- trenchdivelab(noblitz)
""",
}

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

OBSERVERS = LIB_LINE + r'''
-- --------------------------------------------------- trenchdivelab --
-- Read-only measurement.  Nothing below presses a button or writes a
-- byte; the generator plays exactly as it ships.
local TDCMD = {
  [0x00] = "Fight", [0x01] = "Item", [0x02] = "Magic", [0x03] = "Morph",
  [0x05] = "Steal", [0x06] = "Capture", [0x07] = "SwdTech", [0x08] = "Throw",
  [0x09] = "Tools", [0x0A] = "Blitz", [0x0B] = "Runic", [0x0C] = "Lore",
  [0x0D] = "Sketch", [0x0E] = "Control", [0x0F] = "Slot", [0x10] = "Rage",
  [0x11] = "Leap", [0x12] = "Mimic", [0x13] = "Dance", [0x14] = "Row",
  [0x15] = "Def", [0x16] = "Jump", [0x17] = "XMagic", [0x19] = "Summon",
}
local function tdInForm(i) return ((H.readByte(0x3F45) >> i) & 1) == 1 end
local function tdMonHp()
  local t = {}
  for i = 0, 5 do t[i + 1] = tdInForm(i) and H.readWord(0x3BFC + i * 2) or 0 end
  return t
end
local function tdPartyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(0x3BF4 + e * 2) end
  return p
end
local tdFight, tdMask, tdStable, tdIn, tdAtt = 0, -1, 0, false, 0
local tdPending, tdEvents = {}, {}
local function tdPush(s) tdEvents[#tdEvents + 1] = s end

-- The generator's dive ladder reloads a snapshot on a lost ride.  Its
-- attempt number is not in RAM, so the lab takes it from the generator's
-- own log line through this global (one assignment, in the derived copy).
TDATTEMPT = 0

function tdHook()
  emu.addMemoryCallback(function()
    -- entities 0-3 are the party, 4-9 the monster stage slots: both are
    -- wanted here, because the trench's killer is a counter and an enemy
    -- action has to be readable beside the party action that provoked it
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x >= 20 or x % 2 ~= 0 then return end
    tdPending[x] = {
      cmd = H.readByte(0xB5), atk = H.readByte(0xB6), tgt = H.readWord(0xB8),
      mp = H.readWord(0x3C08 + x), bp = H.readByte(0x3E9C + x),
      rev = H.readByte(0x3E9D + x), mon = tdMonHp(), hp = tdPartyHp(),
      f = H.frame,
    }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"),
     H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = tdPending[x]
    if not p then return end
    tdPending[x] = nil
    if p.cmd >= 0x1E then return end
    local mon, hp = tdMonHp(), tdPartyHp()
    local slot, dmg, took = x // 2, 0, 0
    for i = 1, 6 do dmg = dmg + math.max(0, p.mon[i] - mon[i]) end
    for e = 1, 4 do took = took + math.max(0, p.hp[e] - hp[e]) end
    local hurt = {}
    for e = 1, 4 do
      if p.hp[e] > hp[e] then
        hurt[#hurt + 1] = string.format("e%d-%d", e - 1, p.hp[e] - hp[e])
      end
    end
    local mp = (slot < 4) and H.readWord(0x3C08 + x) or 0
    tdPush(string.format(
      "[act] f%d a%d b%d %s%d char%d %s($%02X) atk=$%02X bp=%d rev=%d "
      .. "mp %d->%d dmg=%d took=%d hurt=%s",
      H.frame, TDATTEMPT, tdFight, slot < 4 and "slot" or "mon",
      slot < 4 and slot or slot - 4,
      slot < 4 and H.readByte(0x3ED8 + x) or 99,
      TDCMD[p.cmd] or "?", p.cmd, p.atk, p.bp, p.rev,
      p.mp, mp, dmg, took, #hurt > 0 and table.concat(hurt, ",") or "-"))
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))

  emu.addEventCallback(function()
    -- one [fight] line per battle from a SETTLED frame (the descent lab's
    -- rule: $3f45/$57c0/$3bfc are written during the load and never
    -- cleared, so an early read lists the tail of the previous fight)
    local live = H.battleLoadStarted()
    if live then
      local mask = H.readByte(0x3F45) & 0x3F
      if mask ~= tdMask then tdMask, tdStable = mask, 0
      else tdStable = tdStable + 1 end
      local ready = mask ~= 0 and tdStable >= 120
      for i = 0, 5 do
        if tdInForm(i) and H.readWord(0x3BFC + i * 2) == 0 then ready = false end
      end
      if not tdIn and ready then
        tdIn = true
        tdFight = tdFight + 1
        local form, hp = {}, tdPartyHp()
        for i = 0, 5 do
          if tdInForm(i) then
            form[#form + 1] = string.format("s%d=$%04X:%d", i,
              H.readWord(0x57C0 + i * 2), H.readWord(0x3BFC + i * 2))
          end
        end
        H.log(string.format("[tdlab] [fight] %d a%d f%d form=%s "
          .. "hp=%d,%d,%d,%d bp=%d,%d,%d,%d", tdFight, TDATTEMPT, H.frame,
          table.concat(form, "+"), hp[1], hp[2], hp[3], hp[4],
          H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0),
          H.readByte(0x3EA2)))
      end
    else
      tdIn, tdMask, tdStable = false, -1, 0
    end
    if #tdEvents == 0 then return end
    for _, e in ipairs(tdEvents) do H.log("[tdlab] " .. e) end
    tdEvents = {}
  end, emu.eventType.endFrame)
end

-- the field party at the dive: levels, rows, HP, MP, gear
function tdParty(tag)
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
  H.log(string.format("[tdlab] [party %s] f%d %s", tag, H.frame,
    table.concat(out, " | ")))
end
'''

# ---- anchors -------------------------------------------------------------
HOOK_OLD = """  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the world at Crescent's door")
"""
HOOK_NEW = """  H.loadState(DOOR),
  H.waitFrames(30),
  -- trenchdivelab: the read-only observers, before any fight
  H.call(function() tdHook() end),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the world at Crescent's door")
"""

# the party line, taken at the pre-dive care stop -- the state the dive
# is actually entered in
PARTY_OLD = """  H.fieldCare({ tag = "pre-dive care", threshold = 0.95 }),
"""
PARTY_NEW = """  H.fieldCare({ tag = "pre-dive care", threshold = 0.95 }),
  H.call(function() tdParty("dive start") end),
"""

# the ladder's attempt number, so every action line carries it
ATT_OLD = """    H.call(function()
      rideLost, rideWipeN = nil, 0
      H.gameOverFired = 0
    end),
"""
ATT_NEW = """    H.call(function()
      rideLost, rideWipeN = nil, 0
      H.gameOverFired = 0
      TDATTEMPT = n                          -- trenchdivelab
    end),
"""


def derive(src, variant=None):
    assert src.count(LIB_LINE) == 1, "lib line"
    out = src.replace(LIB_LINE, OBSERVERS)
    assert out.count(HOOK_OLD) == 1, "boot anchor"
    out = out.replace(HOOK_OLD, HOOK_NEW)
    assert out.count(PARTY_OLD) == 1, "care anchor"
    out = out.replace(PARTY_OLD, PARTY_NEW)
    assert out.count(ATT_OLD) == 1, "dive-attempt anchor"
    out = out.replace(ATT_OLD, ATT_NEW)
    assert out.count(DRIVER_OLD) == 1, "fight-driver anchor"
    if variant is not None:
        out = out.replace(DRIVER_OLD, VARIANTS[variant])
    return out


def script_for(policy):
    v = POLICIES[policy].get("variant")
    return SCRIPT if v is None else os.path.join(OUT, "trench-%s.lua" % v)


def write(variants=(None,)):
    os.makedirs(OUT, exist_ok=True)
    src = open(GEN, encoding="utf-8").read()
    for v in variants:
        path = SCRIPT if v is None else os.path.join(OUT, "trench-%s.lua" % v)
        open(path, "w", encoding="utf-8").write(derive(src, v))
        print("wrote", os.path.relpath(path, ROOT))


# ---- the lib revisions ---------------------------------------------------
def cut_libs():
    os.makedirs(LIBDIR, exist_ok=True)
    shutil.copyfile(LIB, os.path.join(LIBDIR, "head.lua"))
    print("cut head.lua (the working tree's own copy)")
    head = open(os.path.join(LIBDIR, "head.lua"), encoding="utf-8").read()
    for name, p in POLICIES.items():
        rev = p.get("lib")
        if rev is None:
            continue
        path = os.path.join(LIBDIR, name + ".lua")
        if rev.startswith("patch:"):
            out = head
            for old, new in LIB_PATCHES[rev[len("patch:"):]]:
                assert out.count(old) == 1, "patch anchor %r" % old[:48]
                out = out.replace(old, new)
            open(path, "w", encoding="utf-8").write(out)
            print("cut %s.lua from head + %s (%d bytes)" % (name, rev, len(out)))
            continue
        blob = subprocess.run(
            ["git", "show", "%s:tools/tests/lib/ot6.lua" % rev],
            cwd=ROOT, check=True, capture_output=True).stdout
        open(path, "wb").write(blob)
        print("cut %s.lua from %s (%d bytes)" % (name, rev, len(blob)))


def lib_for(policy):
    rev = POLICIES[policy].get("lib")
    return os.path.join(LIBDIR, ("head" if rev is None else policy) + ".lua")


def install_lib(policy):
    """Swap tools/tests/lib/ot6.lua for this policy's cut.

    compose.py resolves the lib by path with no override, so this is how a
    driver revision is put under the generator.  `restore` (and the
    finally in `run`) puts the shipped copy back; libs/head.lua is that
    copy, cut before anything is swapped.
    """
    src = lib_for(policy)
    if not os.path.exists(src):
        sys.exit("trenchdivelab: %s is missing -- run `trenchdivelab.py libs`"
                 % os.path.relpath(src, ROOT))
    shutil.copyfile(src, LIB)


def restore():
    head = os.path.join(LIBDIR, "head.lua")
    if not os.path.exists(head):
        sys.exit("trenchdivelab: no %s to restore from"
                 % os.path.relpath(head, ROOT))
    shutil.copyfile(head, LIB)
    print("restored tools/tests/lib/ot6.lua from", os.path.relpath(head, ROOT))


# ---- the pre-#219 control ROM -------------------------------------------
NOMP_OBJS = ["field_en", "btlgfx_en", "battlepreprice_en", "menu_en",
             "sound_en", "cutscene_en", "event_en", "world_en", "gfx_en",
             "text_en"]


def build_rom():
    """narshedescentlab's control ROM, verbatim: the battle module
    reassembled with -D OT6_BOOST_PRICE=0 and linked through the graph's
    own recipe against the graph's own objects."""
    os.makedirs(ROMDIR, exist_ok=True)
    ff6 = os.path.join(ROOT, "ff6")
    for m in ["field", "btlgfx", "menu", "sound", "cutscene", "event",
              "world", "gfx", "text"]:
        o = os.path.join(ff6, "obj", m + "_en.o")
        if not os.path.exists(o):
            sys.exit("trenchdivelab: %s is missing -- run `ninja build/ot6.sfc`"
                     " first" % o)
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
        sys.exit("trenchdivelab: the OT6_BOOST_PRICE=0 control is "
                 "byte-identical to the shipped ROM -- the flag is dead")
    if not os.path.exists(PREPRICE_DBG):
        sys.exit("trenchdivelab: no %s" % PREPRICE_DBG)
    print("built", os.path.relpath(PREPRICE_ROM, ROOT),
          "(%d bytes, differs from the shipped ROM)" % len(control))


# ---- running -------------------------------------------------------------
def run_one(policy, seed):
    d = os.path.join(OUT, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "seed%02d.log" % seed)
    env = dict(os.environ)
    env.update({
        "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(seed),
        "OT6_NO_PUBLISH": "1", "OT6_KEEP_RUNS": "1",
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "3600"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "seed%02d" % seed),
        "OT6_WORKER": "trench-%s-%02d" % (policy, seed),
    })
    if POLICIES[policy].get("rom") == "preprice":
        if not os.path.exists(PREPRICE_ROM):
            sys.exit("trenchdivelab: run `trenchdivelab.py rom` first")
        env["OT6_ROM"] = PREPRICE_ROM
        env["OT6_DBG"] = PREPRICE_DBG
    with open(os.path.join(d, "seed%02d.out" % seed), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             script_for(policy), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return policy, seed, rc, summarize(log)


def run(policies, seeds, jobs):
    write(sorted({POLICIES[p].get("variant") for p in policies},
                 key=lambda v: (v is not None, v)))
    for policy in policies:
        install_lib(policy)
        print("== %s (%s): lib <- %s" % (policy, POLICIES[policy]["why"],
                                         os.path.relpath(lib_for(policy), ROOT)))
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
                futs = [ex.submit(run_one, policy, s) for s in seeds]
                for f in concurrent.futures.as_completed(futs):
                    p, s, rc, r = f.result()
                    print("  %-9s seed %2d rc=%d %s frame=%s deaths=%d wipes=%d "
                          "fights=%d attempts=%d fenix=%d"
                          % (p, s, rc, r["verdict"], r["frame"], len(r["deaths"]),
                             len(r["wipes"]), len(r["fights"]), r["attempts"],
                             r["fenix"]))
                    sys.stdout.flush()
        finally:
            restore()


# ---- reading a log -------------------------------------------------------
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
FIGHT = re.compile(r"^\[ot6\] \[tdlab\] \[fight\] (\d+) a(\d+) f(\d+) form=(\S+) "
                   r"hp=(\S+) bp=(\S+)")
ACT = re.compile(r"^\[ot6\] \[tdlab\] \[act\] f(\d+) a(\d+) b(\d+) (slot|mon)(\d+) "
                 r"char(\d+) (\S+)\(\$([0-9A-F]{2})\) atk=\$([0-9A-F]{2}) "
                 r"bp=(\d+) rev=(\d+) mp (\d+)->(\d+) dmg=(-?\d+) took=(-?\d+) "
                 r"hurt=(\S+)")
PARTY = re.compile(r"^\[ot6\] \[tdlab\] \[party (.*?)\] f\d+ (.*)")
DEATH = re.compile(r"^\[ot6\] \[trench .*?\] \[death\] f\+(\d+) entity (\d) "
                   r"char (\d+) from (\d+)/(\d+) by (.*?)(?: \(ONE ACTION[^)]*\))? "
                   r"bp=(\d+) party_bp=([\d,]+)")
WIPE = re.compile(r"^\[ot6\] \[trench .*?\] \[wipe\] f\+(\d+) party_bp=(\S+) "
                  r"deaths=(\S+) class=(.*)$")
ATTEMPT = re.compile(r"^\[ot6\] \[trench\] dive ATTEMPT (\d+) --")
LANDED = re.compile(r"^\[ot6\] \[trench\] dive attempt (\d+) LANDED at Nikeah f(\d+)")
FENIX = re.compile(r"Fenix Down landed")
SPEND = re.compile(r"^\[ot6\] \[trench .*?\] actor=(\d+) (SPEND|no spend) \((\w+)\): (.*)$")
FIRSTB = re.compile(r"^\[ot6\] \[seed\] first battle:.*key (\S+)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, fights=[], acts=[], deaths=[],
             wipes=[], attempts=1, landed=None, fail="", party="", key="",
             fenix=0, spend=[])
    if not os.path.exists(log):
        r["fail"] = "no log"
        return r
    cur = None
    for line in open(log, errors="replace"):
        line = line.rstrip("\n")
        if not line.startswith("[ot6] "):
            continue
        if FENIX.search(line):
            r["fenix"] += 1
        m = PASS.match(line)
        if m:
            r["verdict"], r["frame"] = "PASS", int(m.group(1))
            continue
        m = FAILV.match(line)
        if m:
            r["verdict"], r["fail"] = "FAIL", m.group(1)[:200]
            continue
        m = FIRSTB.match(line)
        if m and not r["key"]:
            r["key"] = m.group(1)
            continue
        m = PARTY.match(line)
        if m:
            r["party"] = m.group(2)
            continue
        m = FIGHT.match(line)
        if m:
            cur = dict(n=int(m.group(1)), att=int(m.group(2)), f0=int(m.group(3)),
                       form=m.group(4),
                       hp0=[int(x) for x in m.group(5).split(",")],
                       bp0=[int(x) for x in m.group(6).split(",")],
                       acts=[], deaths=[])
            r["fights"].append(cur)
            continue
        m = ACT.match(line)
        if m:
            a = dict(f=int(m.group(1)), att=int(m.group(2)), b=int(m.group(3)),
                     side=m.group(4), slot=int(m.group(5)), char=int(m.group(6)),
                     cmd=m.group(7), cmdn=int(m.group(8), 16),
                     atk=int(m.group(9), 16), bp=int(m.group(10)),
                     rev=int(m.group(11)), mp0=int(m.group(12)),
                     mp1=int(m.group(13)), dmg=int(m.group(14)),
                     took=int(m.group(15)), hurt=m.group(16))
            r["acts"].append(a)
            if cur is not None and cur["n"] == a["b"]:
                cur["acts"].append(a)
            continue
        m = DEATH.match(line)
        if m:
            d = dict(tick=int(m.group(1)), e=int(m.group(2)), char=int(m.group(3)),
                     frm=int(m.group(4)), maxhp=int(m.group(5)), by=m.group(6),
                     bp=int(m.group(7)), pbp=m.group(8),
                     one="ONE ACTION" in line,
                     fight=cur["n"] if cur else 0,
                     att=cur["att"] if cur else 0)
            r["deaths"].append(d)
            if cur is not None:
                cur["deaths"].append(d)
            continue
        m = WIPE.match(line)
        if m:
            r["wipes"].append(dict(tick=int(m.group(1)), pbp=m.group(2),
                                   cls=m.group(4),
                                   fight=cur["n"] if cur else 0))
            continue
        m = SPEND.match(line)
        if m:
            r["spend"].append(dict(actor=int(m.group(1)), verdict=m.group(2),
                                   where=m.group(3), why=m.group(4)))
            continue
        m = ATTEMPT.match(line)
        if m:
            r["attempts"] = int(m.group(1))
            continue
        m = LANDED.match(line)
        if m:
            r["landed"] = (int(m.group(1)), int(m.group(2)))
    return r


# ---- species -------------------------------------------------------------
def monster_names():
    p = os.path.join(ROOT, "ff6/src/text/monster_name_en.json")
    return json.load(open(p))["text"]


def attack_names():
    # AttackName's cell 0 is attack id $51 (ot6_thief.asm:56, and
    # ListTextCmd_0f renders any id >= $51 from AttackName[id-$51])
    p = os.path.join(ROOT, "ff6/src/text/attack_name_en.json")
    return json.load(open(p))["text"]


def atkname(i):
    a = attack_names()
    j = i - 0x51
    return a[j] if 0 <= j < len(a) else "$%02X" % i


def formname(form):
    names = monster_names()
    out = []
    for cell in form.split("+"):
        m = re.match(r"s(\d)=\$([0-9A-F]{4}):(\d+)", cell)
        if not m:
            out.append(cell)
            continue
        # $57C0 carries the species in the low bits; the high bit is the
        # bit-slot flag (lib/ot6.lua monsterIds, #177)
        sp = int(m.group(2), 16) & 0x7FFF
        out.append("%s(s%s)" % (names[sp] if sp < len(names) else "?%d" % sp,
                                m.group(1)))
    return "+".join(out)


# ---- tables --------------------------------------------------------------
CHARNAME = {0: "TERRA", 1: "LOCKE", 2: "CYAN", 4: "EDGAR", 5: "SABIN",
            6: "CELES", 11: "GAU", 99: "-"}


def table(log):
    r = summarize(log)
    print("%s: %s frame=%s attempts=%d landed=%s"
          % (os.path.relpath(log, ROOT), r["verdict"], r["frame"],
             r["attempts"], r["landed"]))
    if r["party"]:
        print("party:", r["party"])
    print()
    print("%-3s %-2s %-46s %5s %5s %6s %6s %s"
          % ("#", "a", "formation", "turns", "mon", "party", "giga", "deaths"))
    for f in r["fights"]:
        turns = sum(1 for a in f["acts"] if a["side"] == "slot")
        montn = sum(1 for a in f["acts"] if a["side"] == "mon")
        took = sum(a["took"] for a in f["acts"] if a["side"] == "mon")
        giga = sum(a["took"] for a in f["acts"]
                   if a["side"] == "mon" and a["atk"] == 0xB9)
        ds = ";".join("%s@%d:%d/%d:bp%d%s"
                      % (CHARNAME.get(d["char"], d["char"]), d["tick"],
                         d["frm"], d["maxhp"], d["bp"],
                         ":one" if d["one"] else "")
                      for d in f["deaths"])
        print("%-3d %-2d %-46s %5d %5d %6d %6d %s"
              % (f["n"], f["att"], formname(f["form"]), turns, montn, took,
                 giga, ds))
    print()
    counters = [a for a in r["acts"] if a["side"] == "mon" and a["cmdn"] == 0x0C]
    print("enemy casts: %d (%s)"
          % (len(counters),
             ", ".join(sorted(set(atkname(a["atk"]) for a in counters))) or "-"))
    for a in counters:
        prev = None
        for b in r["acts"]:
            if b["f"] < a["f"] and b["side"] == "slot":
                prev = b
        print("  f%-7d a%d b%-2d mon%d %s took=%d hurt=%s  <- after %s %s bp=%d"
              % (a["f"], a["att"], a["b"], a["slot"], atkname(a["atk"]),
                 a["took"], a["hurt"],
                 CHARNAME.get(prev["char"], "?") if prev else "-",
                 prev["cmd"] if prev else "-", prev["bp"] if prev else 0))
    print()
    for s in r["spend"]:
        print("  spend rule: actor=%d %s (%s): %s"
              % (s["actor"], s["verdict"], s["where"], s["why"]))


ASPIK, ACTANEON, ANGUIFORM = 0x0059, 0x005E, 0x003A


def counters(policies, seeds):
    """Who provokes Giga Volt.

    Aspik's retaliation script is `if_cmd FIGHT -> attack BATTLE / end_if /
    if_hit -> attack GIGA_VOLT` (ai_script.asm, `; aspik`).  This walks
    every retained log and reports, per party verb, how many times that
    verb landed on a formation carrying an Aspik and how many Giga Volts
    came back -- the claim measured rather than read off the script.
    """
    byverb, gv, rows = {}, [], []
    for p in policies:
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            r = summarize(log)
            for f in r["fights"]:
                aspik = ("$%04X" % ASPIK) in f["form"]
                if not aspik:
                    continue
                last = None
                for a in f["acts"]:
                    if a["side"] == "slot":
                        if a["cmdn"] != 0x01:      # an Item is not a hit
                            byverb[a["cmd"]] = byverb.get(a["cmd"], 0) + 1
                        last = a
                    elif a["atk"] == 0xB9:
                        gv.append((p, s, f["n"], a, last))
            rows.append((p, s, r))
    print("party actions into an Aspik formation, by verb "
          "(%d log(s)):" % len(rows))
    for k in sorted(byverb, key=lambda k: -byverb[k]):
        print("  %-8s %4d" % (k, byverb[k]))
    print()
    print("Giga Volts: %d" % len(gv))
    print("  %-9s %4s %3s %9s %6s  %s" % ("policy", "seed", "b", "frame",
                                          "took", "the party action before it"))
    for p, s, n, a, last in gv:
        print("  %-9s %4d %3d %9d %6d  %s %s at %d BP"
              % (p, s, n, a["f"], a["took"],
                 CHARNAME.get(last["char"], "?") if last else "-",
                 last["cmd"] if last else "(none)", last["bp"] if last else 0))
    verbs = {}
    for _, _, _, _, last in gv:
        k = last["cmd"] if last else "(none)"
        verbs[k] = verbs.get(k, 0) + 1
    print()
    print("the verb immediately before each Giga Volt:",
          ", ".join("%s x%d" % (k, v) for k, v in sorted(verbs.items())) or "-")


def aggregate(policies, seeds):
    rows = []
    for p in policies:
        for s in seeds:
            log = os.path.join(OUT, p, "seed%02d.log" % s)
            rows.append((p, s, summarize(log)))
    print("%-9s %4s %-6s %8s %4s %6s %6s %6s %6s %6s %6s"
          % ("policy", "seed", "verd", "frame", "att", "fights", "turns",
             "deaths", "banked", "wipes", "fenix"))
    for p, s, r in rows:
        turns = sum(1 for a in r["acts"] if a["side"] == "slot")
        banked = sum(1 for d in r["deaths"] if d["bp"] >= 3)
        print("%-9s %4d %-6s %8s %4d %6d %6d %6d %6d %6d %6d"
              % (p, s, r["verdict"], r["frame"], r["attempts"],
                 len(r["fights"]), turns, len(r["deaths"]), banked,
                 len(r["wipes"]), r["fenix"]))
    print()
    print("%-9s %5s %6s %6s %6s %6s %6s %9s  %s"
          % ("policy", "pass", "deaths", "banked", "wipes", "fenix", "1shot",
             "meanframe", "attempts(1/2/3)"))
    for p in policies:
        rs = [r for pp, _, r in rows if pp == p]
        ok = [r for r in rs if r["verdict"] == "PASS"]
        deaths = sum(len(r["deaths"]) for r in rs)
        banked = sum(1 for r in rs for d in r["deaths"] if d["bp"] >= 3)
        one = sum(1 for r in rs for d in r["deaths"] if d["one"])
        wipes = sum(len(r["wipes"]) for r in rs)
        fenix = sum(r["fenix"] for r in rs)
        mf = sum(r["frame"] for r in ok) // len(ok) if ok else 0
        att = [sum(1 for r in rs if r["attempts"] == n) for n in (1, 2, 3)]
        print("%-9s %2d/%-2d %6d %6d %6d %6d %6d %9d  %d/%d/%d"
              % (p, len(ok), len(rs), deaths, banked, wipes, fenix, one, mf,
                 att[0], att[1], att[2]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["write", "libs", "rom", "run", "aggregate",
                                    "table", "counters", "restore"])
    ap.add_argument("rest", nargs="*")
    ap.add_argument("--seeds", default="0,5,10,15,20,25")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    seeds = [int(x) for x in a.seeds.split(",") if x != ""]
    if a.cmd == "write":
        return write(sorted({p.get("variant") for p in POLICIES.values()},
                            key=lambda v: (v is not None, v)))
    if a.cmd == "libs":
        return cut_libs()
    if a.cmd == "rom":
        return build_rom()
    if a.cmd == "restore":
        return restore()
    if a.cmd == "table":
        return table(a.rest[0])
    pols = a.rest or list(POLICIES)
    for p in pols:
        if p not in POLICIES:
            sys.exit("unknown policy %r (have %s)" % (p, ", ".join(POLICIES)))
    if a.cmd == "run":
        return run(pols, seeds, a.jobs)
    if a.cmd == "counters":
        return counters(pols, seeds)
    return aggregate(pols, seeds)


if __name__ == "__main__":
    sys.exit(main() or 0)
