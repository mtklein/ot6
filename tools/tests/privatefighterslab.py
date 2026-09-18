#!/usr/bin/env python3
"""privatefighterslab.py -- the private-fighter boost-pricing lab (#230).

    python3 tools/tests/privatefighterslab.py write   [segment ...]
    python3 tools/tests/privatefighterslab.py run     [--seeds 0,5,...] [--jobs N] [segment ...]
    python3 tools/tests/privatefighterslab.py aggregate [--seeds ...] [segment ...]
    python3 tools/tests/privatefighterslab.py table <log>

The class #230 names: a generator with its own private fighter presses R,
names a costed ability, and never checks the caster can pay for the boost.
Since #219 a boosted Blitz/Tool/cast costs escalating MP, so a row the pool
covers unboosted prices out the moment pips go on it.  When #228 found this,
such a row was GREYED BUT STILL COMMITTABLE -- it reached ExecCmd and
CalcAttackEffect's universal insufficient-MP gate ate it, after the turn and
the banked pips were spent; gen_narshe_battle did that sixteen times in one
descent and lost the segment (docs/design/narshe-descent.md).

v0.19's Ot6KitConfirmMP refuses the row at the CONFIRM instead: it buzzes,
the list stays open, and the turn, the pips and the MP are all kept
(battle_kitrefuse).  That makes the class WORSE for a blind fighter, not
better -- an A press that never commits is a stall, and a stall is a timeout
that says nothing about why -- which is what the `refused` column below
counts.  This lab measures the six other fighters that made the same claim.

Shape, and the reason for it, are narshedescentlab.py's: derive the shipped
generator into policy variants by substituting ONE region, assert every
substitution matched exactly once (so a generator edit that moves an anchor
fails the derivation instead of silently measuring something else), play each
variant once per seed from the tracked fixtures with the lib's retries OFF,
and keep every attempt including the failures.

Policies:

  control   the fighter as it stood before #230: the bank's whole boost,
            pressed without asking what it costs.  This is HEAD's code for
            these six, which is why they are a class and not a bug.
  priced    the generator as it ships TODAY -- verbatim, no substitution.
            Its seqFor routes the claim through H.boostPlan, the library's
            one door (M.affordBoost + M.abilityCost + M.spellPrice).

The measurement is read-only and comes from two independent counters that
must agree:

  [fizzle]  the LIBRARY's own, always on since #230 (lib/ot6.lua).  Its
            predicate is the ROM's own arithmetic on the ROM's own operands:
            InitPlayerAction parks the queued cost in $3A4C, CalcAttackEffect
            refuses when $3c08,x - $3a4c borrows, and SaveForMimic confirms
            the pool did not move.
  [pflab]   this lab's, derived from the outcome instead of the price: a
            costed command whose MP did not move AND whose monsters lost
            nothing.  That is narshedescentlab's predicate, and the two
            agreed exactly (16 = 16) on the descent control.
  [refused] the library's confirm-side counter, also always on: a buzz
            ($95) raised inside a kit or magic list window.  On the v0.19
            ROM this is where an unpriced claim lands FIRST, and a fighter
            that keeps asking accumulates them until a watchdog fires.

Nothing here presses a button or writes a byte beyond the one substituted
policy line.
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TESTS = os.path.join(ROOT, "tools", "tests")
OUT = os.path.join(ROOT, "build", "lab", "private-fighters")

# segment -> the generator it drives, and how long to let one attempt run.
# `marker` is the #230 comment the shipped seqFor carries: the `control`
# policy is the region of seqFor BEFORE it, i.e. the bank with no pricing.
SEQFOR = "local function seqFor(id, tier, slot)\n"
SEQTAIL = "  local seq = {}\n"
MARKER = "  -- #230: pressing R is a CLAIM"

SEGMENTS = {
    "kefka_won":   {"gen": "gen_kefka_won.lua",        "timeout": 1800},
    "blackjack":   {"gen": "gen_opera7_blackjack.lua", "timeout": 2400},
    "rapids":      {"gen": "gen_rapids.lua",           "timeout": 1800},
    "scenario":    {"gen": "gen_scenario.lua",         "timeout": 3000},
    "dadaluma":    {"gen": "gen_zozo4_dadaluma.lua",   "timeout": 3600},
    # boots by a cold Continue off a tracked SRAM checkpoint rather than a
    # savestate, so it needs the generate edge's own OT6_SRAM_CHECKPOINT
    "thamasa_fire": {"gen": "gen_thamasa_fire.lua",    "timeout": 4200,
                     "kind": "cast",
                     "env": {"OT6_SRAM_CHECKPOINT":
                             "tools/tests/checkpoints/thamasa-night-v1"}},
}

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

# ---- the read-only observer ---------------------------------------------
# One [act] line per party menu command, taken at ExecCmd and settled at
# SaveForMimic -- the pair narshedescentlab measures the descent with, and
# the pair that makes a fizzled turn visible at all: same MP, no damage,
# turn gone.  Armed from the top of the segment body, so it is inside the
# region compose.py wraps (M.segmentBody) and a replay re-registers it.
OBSERVERS = LIB_LINE + r'''
-- ----------------------------------------------- privatefighterslab --
-- Read-only measurement.  Nothing here presses a button or writes a byte.
local PFCMD = {                    -- BattleCmdProp's order, battle_main.asm
  [0x00] = "Fight", [0x01] = "Item", [0x02] = "Magic", [0x03] = "Morph",
  [0x05] = "Steal", [0x06] = "Capture", [0x07] = "SwdTech", [0x08] = "Throw",
  [0x09] = "Tools", [0x0A] = "Blitz", [0x0B] = "Runic", [0x0C] = "Lore",
  [0x0D] = "Sketch", [0x0E] = "Control", [0x0F] = "Slot", [0x10] = "Rage",
  [0x11] = "Leap", [0x12] = "Mimic", [0x13] = "Dance", [0x14] = "Row",
  [0x15] = "Def", [0x16] = "Jump", [0x17] = "XMagic", [0x19] = "Summon",
  [0x1A] = "Health",
}
-- the verbs OT6 charges MP for (Ot6AbilityCost's three command arms plus
-- Steal, and vanilla's own magic).  A turn under one of these that neither
-- spent MP nor moved a monster is the insufficient-MP fizzle.
local PFCOSTED = { [0x02] = true, [0x05] = true, [0x07] = true,
                   [0x09] = true, [0x0A] = true, [0x0C] = true,
                   [0x13] = true, [0x17] = true, [0x19] = true }
local function pfInForm(i) return ((H.readByte(0x3F45) >> i) & 1) == 1 end
local function pfMonHp()
  local t = 0
  for i = 0, 5 do
    if pfInForm(i) then t = t + H.readWord(0x3BFC + i * 2) end
  end
  return t
end
local pfPending, pfEvents, pfArmed = {}, {}, false
function pfHook()
  if pfArmed then return end
  pfArmed = true
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x >= 8 or x % 2 ~= 0 then return end
    pfPending[x] = {
      cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      mp = H.readWord(0x3C08 + x), bp = H.readByte(0x3E9C + x),
      rev = H.readByte(0x3E9D + x), cost = H.readWord(0x3A4C),
      mon = pfMonHp(), f = H.frame,
    }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"),
     H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = pfPending[x]
    if not p then return end
    pfPending[x] = nil
    -- commands from $1e up are the engine's own (a Poison/Regen dot tick,
    -- the AI path), not a turn the menu spent
    if p.cmd >= 0x1E then return end
    local mp, mon = H.readWord(0x3C08 + x), pfMonHp()
    local spent, dmg = p.mp - mp, p.mon - mon
    local fizzle = (PFCOSTED[p.cmd] and spent == 0 and dmg == 0) and 1 or 0
    pfEvents[#pfEvents + 1] = string.format(
      "[act] f%d slot%d char%d %s($%02X) atk=$%02X bp=%d rev=%d cost=%d "
      .. "mp %d->%d spent=%d dmg=%d fizzle=%d",
      H.frame, x // 2, H.readByte(0x3ED8 + x), PFCMD[p.cmd] or "?", p.cmd,
      p.atk, p.bp, p.rev, p.cost, p.mp, mp, spent, dmg, fizzle)
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
  emu.addEventCallback(function()
    if #pfEvents == 0 then return end
    for _, e in ipairs(pfEvents) do H.log("[pflab] " .. e) end
    pfEvents = {}
  end, emu.eventType.endFrame)
end
pfHook()
'''

# ---- the control fighter -------------------------------------------------
# `control` for a seqFor generator is the region of seqFor BEFORE the #230
# comment: the bank, and nothing that prices it.  Derived from the shipped
# file rather than quoted, so the two policies can only differ by the
# pricing and a change to the bank rule is measured, not silently dropped.
#
# thamasa_fire's fighter is not a seqFor: its boost rides a plan, and its
# control is the one line the pricing replaced.
CAST_NEW = """          if plan.boostLeft == nil then
            local cell, base = spellCellA(actor, plan.spell, false)
            plan.boostLeft = cell == nil and 0
              or (H.boostPlan({ slot = actor, id = plan.spell, spell = true,
                                base = base, want = want, tag = "fire" }))
          end
"""
CAST_OLD = """          plan.boostLeft = plan.boostLeft or want
"""


def derive(seg, policy, src):
    out = src.replace(LIB_LINE, OBSERVERS, 1)
    assert out != src, "%s: no lib line" % seg
    if policy == "priced":
        return out
    if SEGMENTS[seg].get("kind") == "cast":
        assert out.count(CAST_NEW) == 1, "%s: cast anchor" % seg
        return out.replace(CAST_NEW, CAST_OLD)
    assert out.count(SEQFOR) == 1, "%s: seqFor head" % seg
    h = out.index(SEQFOR) + len(SEQFOR)
    t = out.index(SEQTAIL, h)
    body = out[h:t]
    assert body.count(MARKER) == 1, "%s: #230 marker" % seg
    return out[:h] + body[:body.index(MARKER)] + out[t:]


def write(segs, policies):
    for seg in segs:
        src = open(os.path.join(TESTS, SEGMENTS[seg]["gen"]), encoding="utf-8").read()
        d = os.path.join(OUT, seg)
        os.makedirs(d, exist_ok=True)
        for p in policies:
            path = os.path.join(d, p + ".lua")
            open(path, "w", encoding="utf-8").write(derive(seg, p, src))
            print("wrote", os.path.relpath(path, ROOT))


def run_one(seg, policy, seed):
    d = os.path.join(OUT, seg, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "seed%02d.log" % seed)
    env = dict(os.environ)
    env.update({
        "OT6_LIVE": "0", "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(seed),
        "OT6_NO_PUBLISH": "1", "OT6_KEEP_RUNS": "1",
        "OT6_TIMEOUT": str(SEGMENTS[seg]["timeout"]),
        "OT6_ARTIFACT_DIR": os.path.join(d, "seed%02d" % seed),
        "OT6_WORKER": "pf-%s-%s-%02d" % (seg, policy, seed),
    })
    env.update(SEGMENTS[seg].get("env", {}))
    with open(os.path.join(d, "seed%02d.out" % seed), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             os.path.join(OUT, seg, policy + ".lua"), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return seg, policy, seed, rc, summarize(log)


# ---- reading a log -------------------------------------------------------
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
ACT = re.compile(r"^\[ot6\] \[pflab\] \[act\] f(\d+) slot(\d+) char(\d+) "
                 r"(\S+)\(\$([0-9A-F]{2})\) atk=\$([0-9A-F]{2}) bp=(\d+) "
                 r"rev=(\d+) cost=(\d+) mp (\d+)->(\d+) spent=(-?\d+) "
                 r"dmg=(-?\d+) fizzle=(\d)")
LIBFIZZ = re.compile(r"^\[ot6\] \[fizzle\] f(\d+) slot(\d+) char(\d+) "
                     r"(\S+)\(\$([0-9A-F]{2})\) atk=\$([0-9A-F]{2}) "
                     r"boost=(\d+) cost=(\d+) pool=(\d+)")
FIZZSUM = re.compile(r"^\[ot6\] \[watch\] fizzles: (\d+) costed action\(s\) "
                     r"refused for MP, (\d+) boost point")
# v0.19's confirm-side refusal, the same claim caught one step earlier: the
# kit/magic list buzzed and stayed open.  For a fighter that keeps asking,
# this is the stall that reads as a timeout.
REFUSED = re.compile(r"^\[ot6\] \[watch\] kit/magic confirm refusals: (\d+) "
                     r"confirm")
WIPE = re.compile(r"PARTY WIPED|\[wipe\] f\+")
FIRSTB = re.compile(r"^\[ot6\] \[seed\] first battle:.*key (\S+)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, acts=[], libfizz=[], fizz_bp=0,
             refused=0, fail="", key="", wipes=0)
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
            r["verdict"], r["fail"] = "FAIL", m.group(1)[:150]
            continue
        m = FIRSTB.match(line)
        if m and not r["key"]:
            r["key"] = m.group(1)
            continue
        m = ACT.match(line)
        if m:
            r["acts"].append(dict(
                f=int(m.group(1)), slot=int(m.group(2)), char=int(m.group(3)),
                cmd=m.group(4), cmdn=int(m.group(5), 16),
                atk=int(m.group(6), 16), bp=int(m.group(7)),
                rev=int(m.group(8)), cost=int(m.group(9)),
                mp0=int(m.group(10)), mp1=int(m.group(11)),
                spent=int(m.group(12)), dmg=int(m.group(13)),
                fizzle=int(m.group(14))))
            continue
        m = LIBFIZZ.match(line)
        if m:
            r["libfizz"].append(dict(
                f=int(m.group(1)), slot=int(m.group(2)), char=int(m.group(3)),
                cmd=m.group(4), atk=int(m.group(6), 16),
                boost=int(m.group(7)), cost=int(m.group(8)),
                pool=int(m.group(9))))
            continue
        m = FIZZSUM.match(line)
        if m:
            r["fizz_bp"] = int(m.group(2))
            continue
        m = REFUSED.match(line)
        if m:
            r["refused"] = int(m.group(1))
            continue
        if WIPE.search(line):
            r["wipes"] += 1
    return r


CHARNAME = {0: "TERRA", 1: "LOCKE", 2: "CYAN", 3: "SHADOW", 4: "EDGAR",
            5: "SABIN", 6: "CELES", 7: "STRAGO", 8: "RELM", 11: "GAU",
            14: "BANON"}


def table(log):
    """Who spent what, and on what, for one run."""
    r = summarize(log)
    print("# %s" % os.path.relpath(log, ROOT))
    print("verdict=%s frame=%s turns=%d lab_fizzles=%d lib_fizzles=%d "
          "boost_burned=%d key=%s"
          % (r["verdict"], r["frame"], len(r["acts"]),
             sum(a["fizzle"] for a in r["acts"]), len(r["libfizz"]),
             r["fizz_bp"], r["key"]))
    if r["fail"]:
        print("FAIL: %s" % r["fail"])
    print()
    by = {}
    for a in r["acts"]:
        t = by.setdefault((a["char"], a["cmd"]), dict(n=0, mp=0, dmg=0, fz=0))
        t["n"] += 1
        t["mp"] += max(0, a["spent"])
        t["dmg"] += a["dmg"]
        t["fz"] += a["fizzle"]
    print("%-8s %-8s %6s %7s %9s %8s %9s" % (
        "char", "verb", "turns", "mp", "damage", "fizzles", "dmg/turn"))
    for (c, cmd), t in sorted(by.items(), key=lambda kv: -kv[1]["n"]):
        print("%-8s %-8s %6d %7d %9d %8d %9.1f" % (
            CHARNAME.get(c, "c%d" % c), cmd, t["n"], t["mp"], t["dmg"],
            t["fz"], t["dmg"] / max(1, t["n"])))
    if r["libfizz"]:
        print()
        print("fizzles (the library's own line):")
        for z in r["libfizz"]:
            print("  f%-7d %-7s %-8s atk=$%02X boost=%d cost=%d pool=%d"
                  % (z["f"], CHARNAME.get(z["char"], "c%d" % z["char"]),
                     z["cmd"], z["atk"], z["boost"], z["cost"], z["pool"]))


def aggregate(segs, policies, seeds):
    print("%-13s %-8s %4s %-7s %8s %6s %7s %7s %7s %8s  %s" % (
        "segment", "policy", "seed", "verdict", "frames", "turns", "fizz",
        "libfizz", "bp_lost", "refused", "first battle / failure"))
    totals = {}
    for seg in segs:
        for p in policies:
            for s in seeds:
                log = os.path.join(OUT, seg, p, "seed%02d.log" % s)
                r = summarize(log)
                fz = sum(a["fizzle"] for a in r["acts"])
                t = totals.setdefault((seg, p), dict(
                    n=0, done=0, turns=0, fz=0, lfz=0, bp=0, ref=0,
                    frames=[]))
                t["n"] += 1
                if r["verdict"] == "PASS":
                    t["done"] += 1
                    t["frames"].append(r["frame"])
                t["turns"] += len(r["acts"])
                t["fz"] += fz
                t["lfz"] += len(r["libfizz"])
                t["bp"] += r["fizz_bp"]
                t["ref"] += r["refused"]
                print("%-13s %-8s %4d %-7s %8s %6d %7d %7d %7d %8d  %s %s" % (
                    seg, p, s, r["verdict"], r["frame"] or "-", len(r["acts"]),
                    fz, len(r["libfizz"]), r["fizz_bp"], r["refused"],
                    r["key"], r["fail"]))
    print()
    print("%-13s %-8s %3s %5s %7s %8s %9s %9s %9s %9s" % (
        "segment", "policy", "n", "pass", "turns", "fizzles", "lib_fizz",
        "bp_lost", "refused", "frames"))
    for seg in segs:
        for p in policies:
            t = totals.get((seg, p))
            if not t:
                continue
            mean = sum(t["frames"]) // len(t["frames"]) if t["frames"] else 0
            print("%-13s %-8s %3d %5d %7d %8d %9d %9d %9d %9d" % (
                seg, p, t["n"], t["done"], t["turns"], t["fz"], t["lfz"],
                t["bp"], t["ref"], mean))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["write", "run", "aggregate", "table"])
    ap.add_argument("segments", nargs="*")
    ap.add_argument("--seeds", default="0,5,10,15,20,25")
    ap.add_argument("--policies", default="control,priced")
    ap.add_argument("--jobs", type=int, default=1)
    a = ap.parse_args()
    if a.cmd == "table":
        if not a.segments:
            sys.exit("privatefighterslab: table needs a log path")
        for log in a.segments:
            table(log)
            print()
        return 0
    segs = a.segments or list(SEGMENTS)
    for s in segs:
        if s not in SEGMENTS:
            sys.exit("privatefighterslab: unknown segment %r (have %s)"
                     % (s, ", ".join(SEGMENTS)))
    policies = [p for p in a.policies.split(",") if p]
    seeds = [int(s) for s in a.seeds.split(",") if s != ""]
    if a.cmd == "write":
        write(segs, policies)
        return 0
    if a.cmd == "aggregate":
        aggregate(segs, policies, seeds)
        return 0
    write(segs, policies)
    jobs = [(g, p, s) for g in segs for p in policies for s in seeds]
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        for seg, policy, seed, rc, r in ex.map(lambda j: run_one(*j), jobs):
            print("  %-13s %-8s seed %2d: %-4s rc=%d frames=%s turns=%d "
                  "fizzles=%d libfizz=%d refused=%d %s"
                  % (seg, policy, seed, r["verdict"], rc, r["frame"],
                     len(r["acts"]), sum(x["fizzle"] for x in r["acts"]),
                     len(r["libfizz"]), r["refused"], r["fail"]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
