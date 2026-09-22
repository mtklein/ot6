#!/usr/bin/env python3
"""fightvsabilitylab.py -- the boosted-Fight vs boosted-ability lab
(docs/design/fight-vs-ability.md).

    python3 tools/tests/fightvsabilitylab.py reach
    python3 tools/tests/fightvsabilitylab.py write
    python3 tools/tests/fightvsabilitylab.py run [--jitter 0,13,29,47]
                                                 [--jobs N] fixture policy [...]
    python3 tools/tests/fightvsabilitylab.py aggregate [log ...]
    python3 tools/tests/fightvsabilitylab.py mechanic [log ...]

The question (#219 priced every boosted ability but Fight at
min(99, floor(base * 2.5^boost + 0.5)) MP): does a boosted ability still
have a role beside a free boosted Fight, and which one?

Nothing here changes the ROM.  The 2.5x rate, the 99 cap and the Fight
exemption are the owner's locked design; this lab measures against them.

----------------------------------------------------------------------
`reach` -- the static arm, no emulator
----------------------------------------------------------------------
For every World-of-Balance formation the route's own areas cover
(tools/check_break_reach.py's AREAS, whose parsers this reuses), and for
each party member with the weapons that step's FIXTURE really has them
holding, it answers two questions per body:

    does this member's FIGHT chip it?      (weapon class, weapon element,
                                            both hands under a Genji Glove)
    does this member's ABILITY chip it?    (Ot6SkillClassTbl class +
                                            magic_prop element for Blitz /
                                            SwdTech, Ot6WeapClassTbl class +
                                            tool attack element for Tools)

A body no Fight in the party can chip but some ability can is the sharp
case the owner asked about -- "a shield class the character's weapon has
no access to".  The gear is read out of the fixture, not assumed, with
tools/savestate_party.py.

----------------------------------------------------------------------
`write` / `run` / `aggregate` -- the in-play arm
----------------------------------------------------------------------
`write` derives tools/tests/bal_party.lua (the shipped, owner-sanctioned
party balance instrument: seeded $1FA1/$1FA2 draws so battle k is the same
battle in every arm, paired samples, per-character attribution) into
build/lab/fight-vs-ability/lab.lua.  The derivation adds, and changes
nothing else:

  * seven policies -- fight0..fight3 (force Fight, boost N when the bank
    holds N) and ability0 / ability3 / abilitygreedy (the character's own
    kit at boost 0 / 3 / as-it-comes).  fight0 and fight3 are the owner's
    "boost-Fight through randoms" default and its unboosted control;
    ability3 is the same discipline spending the 2.5x price.
  * two fixtures beside bal_party's own -- ifrit_entry (map 264, Flan
    groups: bludgeon-keyed bodies no routed weapon can reach) and
    n024_won (map 273, Rhinox/Gobbler) -- and per-fixture kit rows so
    SABIN reaches Fire Dance and AuraBolt where the element answers.
  * FVA_JITTER, extra settle frames before the battle arms, so a policy
    can be run over a spread of in-battle RNG phases rather than once.
  * five read-only CPU exec observers.  They read; they never write.

        ExecCmd@battle_code   parks the acting character's command, attack,
                              pending boost, MP, both hands' item ids, the
                              shield total and the monster HP total
        Ot6FightBoost         the VANILLA swing count in $3a70, before the
                              boost's own add
        Ot6WeaponClass        one exec per hand per swing (_magicpunch calls
                              it for the swinging hand), gated on the
                              acting entity, so it counts SWINGS ATTEMPTED
        Ot6HitJoin            one exec per LANDED hit per target -- the
                              chip opportunity itself
        SaveForMimic          the action resolved: emit the row

    The swing/hit split is the point.  FightAttack writes $3a70 = 1 (or 7
    with an Offering) and Ot6FightBoost adds 2 per pending BP; the
    multi-attack loop at battle_main.asm:8285/8392 then runs $3a70 + 1
    passes, and `lda $3a70 / inc / lsr` hands _magicpunch the parity that
    picks the hand.  So swings alternate hands, and an empty off hand
    reads battle power 0 and takes the "jump if no damage" exit.  Whether
    the whiffing half really whiffs -- and therefore whether a
    one-weapon character gets +1 or +2 real hits per BP -- is what the
    Ot6WeaponClass / Ot6HitJoin pair measures instead of asserting.

`aggregate` tabulates the head-to-head from the retained logs; `mechanic`
tabulates the swing/hit/chip ladder from the same logs.  Every attempt is
kept, void and wiped runs included; nothing selects a run.
"""
import argparse
import concurrent.futures
import glob
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "tests", "bal_party.lua")
OUT = os.path.join(ROOT, "build", "lab", "fight-vs-ability")
LAB = os.path.join(OUT, "lab.lua")

LIB_LINE = 'local H = dofile("tools/tests/lib/ot6.lua")\n'

# ---------------------------------------------------------------- lua ----
OBSERVERS = LIB_LINE + r'''
-- ------------------------------------------------ fightvsabilitylab --
-- Read-only measurement.  Nothing in this block presses a button or
-- writes a byte; the instrument's own writes (the menu cursor, the
-- command row, the seeded $1FA1/$1FA2 and the cold danger counter) are
-- bal_party.lua's own, unchanged and already registered in
-- tools/state_write_waivers.txt.
local FVA_SHLD, FVA_MHP, FVA_PMP = 0x3e40, 0x3bfc, 0x3c08
local FVA_BP, FVA_PEND, FVA_CHARIX = 0x3e9c, 0x3e9d, 0x3ed9
local FVA_CMDNAME = {
  [0x00] = "Fight", [0x01] = "Item", [0x02] = "Magic", [0x03] = "Morph",
  [0x05] = "Steal", [0x06] = "Capture", [0x07] = "SwdTech", [0x08] = "Throw",
  [0x09] = "Tools", [0x0A] = "Blitz", [0x0B] = "Runic", [0x0C] = "Lore",
  [0x0D] = "Sketch", [0x0E] = "Control", [0x0F] = "Slot", [0x10] = "Rage",
  [0x11] = "Leap", [0x12] = "Mimic", [0x13] = "Dance", [0x14] = "Row",
  [0x15] = "Def", [0x16] = "Jump", [0x17] = "XMagic", [0x19] = "Summon",
}
local FVA = { cur = nil, lines = {}, cells = {}, n = 0,
              killN = -1, killF = -1, armF = -1 }
local fvaRefs, fvaAddr = {}, {}

local function fvaShieldSum()
  local t = 0
  for s = 0, 5 do
    if (H.readByte(0x3aa8 + s * 2) & 0x01) == 1 then
      t = t + H.readByte(FVA_SHLD + s * 2)
    end
  end
  return t
end
-- Monster HP, over the slots that are actually in the formation.  $3BFC is not
-- cleared for an absent slot, so an ungated sum carries the previous
-- formation's tail and never reaches zero.
local function fvaMonSum()
  local t = 0
  for s = 0, 5 do
    if (H.readByte(0x3aa8 + s * 2) & 0x01) == 1 then
      t = t + H.readWord(FVA_MHP + s * 2)
    end
  end
  return t
end
-- bodies still holding HP.  The instrument's own stop rule reads the
-- presence bit and the status byte, not HP, so a formation whose last
-- body is at 0 HP keeps the fight "live" for another few hundred frames
-- while the queued actions swing at nothing.  Recording this per action
-- lets the ladder below count only turns that had something to hit, and
-- lets the report say when the formation actually died.
local function fvaLive()
  local n = 0
  for s = 0, 5 do
    if H.readWord(FVA_MHP + s * 2) > 0
       and (H.readByte(0x3aa8 + s * 2) & 0x01) == 1 then n = n + 1 end
  end
  return n
end
-- both hands as the ENGINE sees them: $1600 + 37*char + $1F/$20 is the
-- record _magicpunch's $3ca8,x is loaded from, and H.isWeapon reads
-- ItemProp's type byte, so a shield in the off hand is not a weapon.
local function fvaArmed(item)
  -- $FF is the empty slot, not an item id: ItemProp has a record there
  -- and H.isWeapon would read it, so the empty hand is excluded here.
  return item ~= 0xFF and H.isWeapon(item)
end
local function fvaHands(slot)
  local c = H.readByte(FVA_CHARIX + slot * 2)
  local r = H.readByte(0x1600 + 37 * c + 0x1f)
  local l = H.readByte(0x1600 + 37 * c + 0x20)
  local n = 0
  if fvaArmed(r) then n = n + 1 end
  if fvaArmed(l) then n = n + 1 end
  return n, r, l
end

local function fvaEmit(c)
  local mp = H.readWord(FVA_PMP + c.slot * 2)
  local sh, mon = fvaShieldSum(), fvaMonSum()
  local name = FVA_CMDNAME[c.cmd] or "?"
  FVA.n = FVA.n + 1
  if mon == 0 and c.mon > 0 and FVA.killN < 0 then
    FVA.killN, FVA.killF = FVA.n, H.frame      -- the formation died here
  end
  FVA.lines[#FVA.lines + 1] = string.format(
    "[fva-act] n=%d f%d slot=%d char=%02X %s($%02X) atk=$%02X bp=%d rev=%d "
    .. "hands=%d live=%d aim=%d monhp=%d tgt=$%04X sh=%d rh=$%02X lh=$%02X "
    .. "pre=%s frev=%s fb1=%s cnt=%s passes=%s swings=%d hits=%d dmg=%d "
    .. "chips=%d mp %d->%d spent=%d",
    FVA.n, H.frame, c.slot, c.cix, name, c.cmd, c.atk, c.bp, c.rev,
    c.hands, c.live, c.aim, c.mon, c.tgt, c.sh, c.rh, c.lh, tostring(c.pre),
    tostring(c.frev), tostring(c.fb1),
    tostring(c.cnt),
    c.cnt and (c.cnt + 1) or "-", c.swings, c.hits,
    math.max(0, c.mon - mon), math.max(0, c.sh - sh), c.mp, mp,
    math.max(0, c.mp - mp))
  if c.live == 0 then return end         -- nothing in the formation: not a turn
  -- the ladder cell: one row per (command, hands, revealed boost)
  local key = string.format("%s/h%d/b%d", name, c.hands, c.rev)
  local e = FVA.cells[key]
  if e == nil then
    e = { n = 0, swings = 0, hits = 0, dmg = 0, chips = 0, mp = 0,
          cnt = 0, cntn = 0 }
    FVA.cells[key] = e
  end
  e.n = e.n + 1
  e.swings = e.swings + c.swings
  e.hits = e.hits + c.hits
  e.dmg = e.dmg + math.max(0, c.mon - mon)
  e.chips = e.chips + math.max(0, c.sh - sh)
  e.mp = e.mp + math.max(0, c.mp - mp)
  if c.cnt then e.cnt = e.cnt + c.cnt + 1 e.cntn = e.cntn + 1 end
end

-- The monster slots a swing can actually land on, in the bit order the
-- battle target windows use ($7B7E's monster-side mask; $7B7D is the
-- character side).  bal_party pressed A on whatever the cursor happened
-- to be lighting, which on a formation that has already lost a body is
-- often a corpse: the command executes, reaches _magicpunch, swings, and
-- lands nothing.  Measured on this lab's first spread of zozo_arrival,
-- 124 of 396 Fights under `fight0` and 167 of 362 under `fight3` landed
-- no hit at all while a live body stood on the other side of the stage
-- -- and the ability policies, whose AutoCrossbow needs no cursor, took
-- almost none of that.  Aiming before pressing A is what a person does
-- and what the comparison needs.
function fvaLiveMask()
  local m = 0
  for s = 0, 5 do
    if H.readWord(FVA_MHP + s * 2) > 0
       and (H.readByte(0x3aa8 + s * 2) & 0x01) == 1 then m = m | (1 << s) end
  end
  return m
end

function fvaHook()
  FVA.cur, FVA.lines, FVA.cells, FVA.n = nil, {}, {}, 0
  FVA.killN, FVA.killF, FVA.armF = -1, -1, H.frame
  fvaAddr.cmd = H.sym("ExecCmd@battle_code")
  fvaAddr.fb = H.sym("Ot6FightBoost")
  fvaAddr.wc = H.sym("Ot6WeaponClass")
  fvaAddr.hj = H.sym("Ot6HitJoin")
  fvaAddr.sf = H.sym("SaveForMimic")
  fvaRefs.cmd = emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    -- monsters (x >= 8) and the odd offsets an off-hand pass carries are
    -- not a party turn; a command from $1E up is the engine's own (the
    -- dot tick, the AI path), not a turn the menu spent.
    if x >= 8 or x % 2 ~= 0 then FVA.cur = nil return end
    local cmd = H.readByte(0xB5)
    if cmd >= 0x1E then FVA.cur = nil return end
    FVA.cur = {
      slot = x // 2, cix = H.readByte(FVA_CHARIX + x), cmd = cmd,
      atk = H.readByte(0xB6), tgt = H.readWord(0xB8),
      bp = H.readByte(FVA_BP + x),
      rev = H.readByte(FVA_PEND + x), mp = H.readWord(FVA_PMP + x),
      sh = fvaShieldSum(), mon = fvaMonSum(), live = fvaLive(),
      swings = 0, hits = 0, pre = nil, cnt = nil, x = x,
    }
    -- did this action, at the moment it RESOLVED, point at a body that
    -- was still standing?  $B8's monster side is bits 8..13, one per
    -- battle slot.  A target picked at the menu can be dead by the time
    -- the ATB gets round to it -- three allies act in between -- and that
    -- swing lands nothing however many times it swings.  It is a real
    -- thing that happens to a person, so it stays in the head-to-head;
    -- the swings-and-hits ladder reads only the aimed turns, because
    -- "how many hits does a boosted Fight land" is a question about
    -- turns that met something.
    FVA.cur.aim = (((FVA.cur.tgt >> 8) & 0x3F) & fvaLiveMask()) ~= 0 and 1 or 0
    FVA.cur.hands, FVA.cur.rh, FVA.cur.lh = fvaHands(FVA.cur.slot)
  end, emu.callbackType.exec, fvaAddr.cmd, fvaAddr.cmd)
  -- The vanilla swing count, read at Ot6FightBoost's entry: FightAttack
  -- has just written it and the boost's own `asl / adc` has not run yet.
  -- Also the two cells the proc's own early-outs read there and then --
  -- the pending boost it is about to deliver, and $B1 bit 0, the global
  -- "a counterattack is executing" flag it refuses on -- so a boost that
  -- was banked at the menu and not delivered at the swing says which of
  -- its own guards stopped it instead of leaving it to be guessed.
  fvaRefs.fb = emu.addMemoryCallback(function()
    local c = FVA.cur
    if not c then return end
    c.pre = H.readByte(0x3A70)
    c.frev = H.readByte(FVA_PEND + c.x)
    c.fb1 = H.readByte(0xB1) & 0x01
  end, emu.callbackType.exec, fvaAddr.fb, fvaAddr.fb)
  -- one exec per hand per swing.  x is the entity offset, +1 for the
  -- left-hand pass, so (x & ~1) identifies whose swing it is: a monster's
  -- counterattack landing inside a character's action cannot inflate it.
  -- The first swing also reads $3A70, which still holds the boosted count
  -- (the loop decrements it at the END of each pass).
  fvaRefs.wc = emu.addMemoryCallback(function()
    local c = FVA.cur
    if not c then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if (x & 0xFFFE) ~= c.x then return end
    if c.swings == 0 then c.cnt = H.readByte(0x3A70) end
    c.swings = c.swings + 1
  end, emu.callbackType.exec, fvaAddr.wc, fvaAddr.wc)
  -- one exec per LANDED hit per target: Ot6HitJoin replaces the broken
  -- double's jsl at the elemental join, so it runs for every damaging hit
  -- and is exactly the chip opportunity Ot6ClassChip/Ot6Chip ride.
  -- Y is the target (Ot6ClassChip's own header), and Ot6HitJoin runs for
  -- every damaging hit on EITHER side, so a monster's counterattack
  -- landing on a character inside this action would be counted as one of
  -- its hits.  Y >= $08 is the monster half of the entity table.
  fvaRefs.hj = emu.addMemoryCallback(function()
    if not FVA.cur then return end
    if (emu.getState()["cpu.y"] & 0xFFFF) < 8 then return end
    FVA.cur.hits = FVA.cur.hits + 1
  end, emu.callbackType.exec, fvaAddr.hj, fvaAddr.hj)
  fvaRefs.sf = emu.addMemoryCallback(function()
    local c = FVA.cur
    if not c then return end
    FVA.cur = nil
    fvaEmit(c)
  end, emu.callbackType.exec, fvaAddr.sf, fvaAddr.sf)
end

function fvaUnhook()
  for k, a in pairs({ cmd = fvaAddr.cmd, fb = fvaAddr.fb, wc = fvaAddr.wc,
                      hj = fvaAddr.hj, sf = fvaAddr.sf }) do
    if fvaRefs[k] then
      emu.removeMemoryCallback(fvaRefs[k], emu.callbackType.exec, a, a)
      fvaRefs[k] = nil
    end
  end
  FVA.cur = nil
end

function fvaReport(mline)
  for _, l in ipairs(FVA.lines) do H.log(l) end
  local keys = {}
  for k in pairs(FVA.cells) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local e = FVA.cells[k]
    mline("fva_cell", string.format(
      "%s n=%d passes=%s swings=%d hits=%d dmg=%d chips=%d mp=%d",
      k, e.n, e.cntn > 0 and string.format("%.2f", e.cnt / e.cntn) or "-",
      e.swings, e.hits, e.dmg, e.chips, e.mp))
  end
  mline("fva_actions", FVA.n)
  -- Turns-to-kill.  The instrument stops the frame the last body's HP
  -- reaches zero, which is BEFORE that action reaches SaveForMimic (the
  -- same one-action skew bal_party's own `bp_action_skew` reports as a
  -- steady -1), so the killing turn is never emitted as a row.  The
  -- honest reading is therefore `fva_actions + 1` whenever the stage is
  -- empty at report time, and that is what fva_end_live says.  A turn
  -- that empties the stage while later turns are still queued does get a
  -- row, and fva_kill_actions carries it when it happens.
  mline("fva_actions_turns", FVA.n)
  mline("fva_end_live", fvaLive())
  mline("fva_kill_actions", FVA.killN)
  mline("fva_kill_frames", FVA.killF < 0 and -1 or (FVA.killF - FVA.armF))
  mline("fva_frames", H.frame - FVA.armF)
end
'''

# -- the generic element gate the added kit rows use ----------------------
WANT_OLD = ('  if entry.want == "weak_fire" then return pol.probe '
            'and anyRevealed(0x01) end\n')
WANT_NEW = ('  -- fightvsabilitylab: a generic revealed-element gate, so an\n'
            '  -- added kit row can name its element instead of needing a\n'
            '  -- `want` branch of its own.  Reads the REVEALED bits only,\n'
            '  -- like every other gate here: what the player has been told.\n'
            '  if entry.welem then return pol.probe and anyRevealed(entry.welem) end\n'
            + WANT_OLD)

# -- the policies --------------------------------------------------------
POL_OLD = """POLICIES.mash     = { boost = function() return 0 end,
                      probe = false, force = "fight" }
"""
POL_NEW = POL_OLD + """
-- fightvsabilitylab (#219).  `fightN` forces the plain swing and spends
-- exactly N pips once the bank holds N -- fight0 is the unboosted
-- control and fight3 the owner's "boost-Fight through randoms" default
-- at its deepest.  `abilityN` leaves the character's own kit ladder in
-- place (probe on, so a revealed weakness is exploited the way a person
-- would) at the same boost discipline, and pays #219's 2.5x price.
local function fvaAt(n)
  return function(slot) return bp(slot) >= n and n or 0 end
end
POLICIES.fight0 = { boost = function() return 0 end, probe = false, force = "fight" }
POLICIES.fight1 = { boost = fvaAt(1), probe = false, force = "fight" }
POLICIES.fight2 = { boost = fvaAt(2), probe = false, force = "fight" }
POLICIES.fight3 = { boost = fvaAt(3), probe = false, force = "fight" }
POLICIES.ability0 = { boost = function() return 0 end, probe = true }
POLICIES.ability3 = { boost = fvaAt(3), probe = true }
POLICIES.abilitygreedy = { boost = function(slot)
  return bp(slot) >= 1 and math.min(bp(slot), 3) or 0 end, probe = true }
"""

# -- extra fixtures ------------------------------------------------------
FX_OLD = ('local FX = assert(FIXTURES[FIXTURE], "unknown FIXTURE: " '
          '.. tostring(FIXTURE))\n')
FX_NEW = """-- fightvsabilitylab fixtures.
--
-- ifrit_entry stands on map 264 (group 104): Flan $047 x1 / x4, whose
-- Ot6ShieldTbl row is BLUDGEON-keyed with a FIRE weakness.  The routed
-- party there is LOCKE (Guardian + MithrilKnife, a pierce Genji pair),
-- EDGAR (MithrilBlade, slash), SABIN (MetalKnuckle, slash) and CELES
-- (MithrilBlade, slash) -- not one bludgeoning weapon and not one fire
-- weapon between them, so every key on that body is an ability.
FIXTURES.ifrit_entry = {
  state = "build/states/ifrit_entry.mss.lua",
  mode = "field", map = 264,
  seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
            {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
}
-- n024_won stands on map 273 (group 106): Rhinox $075 (bludgeon, no
-- element) and Gobbler $088 (slash|pierce, no element).  The same party
-- one stretch later, LOCKE now carrying ThunderBlade (slash, BOLT) over
-- Guardian (pierce) -- a Genji pair covering two classes and an element.
FIXTURES.n024_won = {
  state = "build/states/n024_won.mss.lua",
  mode = "field", map = 273,
  seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
            {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
}
-- esper_mtn_save is the CASTER's stretch: TERRA L24 with 216 MP and the
-- natural Fire ladder, LOCKE's two-class Genji pair, STRAGO with an Ice
-- Rod (a bludgeoning staff -- the one routed weapon in the WoB that is).
-- Map 375 (group 90) rolls Slurm $0B8 (bludgeon, FIRE-weak, 4 shields)
-- and Adamanchyt $0D6 (bludgeon, no element, 5 shields), so it carries
-- the two cases a caster arm needs: a group with an exploitable element
-- and a body with none.  A boosted family-head cast does not take the
-- 2.5x ladder at all -- it FOLDS to its own tier and pays that tier's
-- vanilla MP (Fire 4 -> Fire 2 20 -> Fire 3 51) -- so this is also the
-- arm where #219's price is not the price being paid.
-- ultros_won rather than esper_mtn_save, which stands ON the save point
-- and never hands the pacer field control (its whole spread FAILed with
-- "timeout after 1800 frames waiting for field control (b=1)"; the logs
-- are kept under esper_mtn_save/).  Same map, same stretch, one more
-- party member: TERRA, LOCKE, STRAGO and RELM just past Ultros.
FIXTURES.ultros_won = {
  state = "build/states/ultros_won.mss.lua",
  mode = "field", map = 375,
  seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
            {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
}
FIXTURES.esper_mtn_save = {
  state = "build/states/esper_mtn_save.mss.lua",
  mode = "field", map = 375,
  seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
            {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
}
""" + FX_OLD

# -- per-fixture kit rows -------------------------------------------------
KIT_OLD = 'local FALLBACK_KIT = { name = "?", { tag = "fight", cmd = CMD.fight } }\n'
KIT_NEW = KIT_OLD + """
-- fightvsabilitylab: the kit rows the added fixtures need.  SABIN's Blitz
-- list is his own (BlitzLevelTbl: Pummel L1, AuraBolt L6, Suplex L10,
-- Fire Dance L15) and he is L20+ at both fixtures, so these are rows he
-- really owns; each is gated on the element having been REVEALED, so the
-- lab exploits what the screen has said, never a hidden byte.  Bio
-- Blaster stays EDGAR's poison row; AutoCrossbow is his group line.
local FVA_BLITZ = { firedance = 0x60, aurabolt = 0x5e }
if FIXTURE == "ifrit_entry" or FIXTURE == "n024_won" then
  KITS[0x05] = { name = "SABIN",
    { tag = "firedance", cmd = CMD.blitz, welem = 0x01,
      pick = function(slot) return toolsCursor(slot, FVA_BLITZ.firedance) end },
    { tag = "aurabolt", cmd = CMD.blitz, welem = 0x20,
      pick = function(slot) return toolsCursor(slot, FVA_BLITZ.aurabolt) end },
    { tag = "blitz", cmd = CMD.blitz,
      pick = function(slot) return toolsCursor(slot, BLITZ.pummel) end },
    { tag = "fight", cmd = CMD.fight },
  }
end
"""

# -- observers on and off -------------------------------------------------
ARM_OLD = "local function arm()\n  S.t0 = H.frame\n"
ARM_NEW = "local function arm()\n  S.t0 = H.frame\n  fvaHook()   -- fightvsabilitylab\n"
DISARM_OLD = "local function disarm()\n"
DISARM_NEW = "local function disarm()\n  fvaUnhook()   -- fightvsabilitylab\n"
# Aim before confirming.  bal_party's own line is a bare A at the target
# state; this taps the d-pad until the lit mask covers a body that is
# still standing, then confirms -- d-pad and A, nothing else.  A budget of
# twelve taps, then it confirms anyway and the row records what happened,
# so a cursor this cannot reach is measured rather than hidden.
TGT_OLD = "  if st == ST.target then return { \"a\" } end\n"
TGT_NEW = """  if st == ST.target then
    -- fightvsabilitylab: aim before pressing A (see fvaLiveMask)
    local lit = H.readByte(0x7B7E)
    if lit ~= 0 and (fvaLiveMask() & lit) ~= 0 then return { "a" } end
    ep.aim = (ep.aim or 0) + 1
    if ep.aim > 12 then return { "a" } end
    return { (ep.aim % 2 == 1) and "right" or "down" }
  end
"""
AIM_OLD = "  ep.pulses = 0\nend\n"
AIM_NEW = "  ep.pulses, ep.aim = 0, 0\nend\n"

REPORT_OLD = "  -- identity checks\n"
REPORT_NEW = "  fvaReport(mline)   -- fightvsabilitylab\n" + REPORT_OLD

# -- the jitter knob ------------------------------------------------------
JIT_OLD = "      H.waitFrames(240 + 7 * (k - 1)),   -- settle + rng phase jitter\n"
JIT_NEW = ("      -- fightvsabilitylab: FVA_JITTER shifts the in-battle RNG\n"
           "      -- phase, so a policy is run over a spread rather than once.\n"
           "      -- Paired: the same jitter is the same phase in every arm.\n"
           "      H.waitFrames(240 + 7 * (k - 1) + FVA_JITTER),\n")
# Mesen's Lua sandbox blocks os.getenv (lib/compose.py:2016), so
# bal_party.lua's own `envcfg` reads are dead and the instrument is
# configured by editing the file.  The derivation therefore substitutes
# literals, the way m269lab_batch.sh does: @POLICY@ / @FIXTURE@ /
# @JITTER@ are filled in per run, and a token left unfilled fails loudly
# rather than silently measuring the default fixture.
POLDEF_OLD = 'local POLICY = envcfg("BAL_POLICY") or "baseline"\n'
POLDEF_NEW = ('local POLICY = "@POLICY@"\n'
              'local FVA_JITTER = tonumber("@JITTER@") or 0\n'
              'assert(not POLICY:find("@"), "fightvsabilitylab: @POLICY@ '
              'unsubstituted")\n')
FIXDEF_OLD = 'local FIXTURE = envcfg("BAL_FIXTURE") or "worldmap_narshe"\n'
FIXDEF_NEW = ('local FIXTURE = "@FIXTURE@"\n'
              'assert(not FIXTURE:find("@"), "fightvsabilitylab: @FIXTURE@ '
              'unsubstituted")\n')


def derive(src):
    def sub(text, old, new, what):
        assert text.count(old) == 1, "anchor: " + what
        return text.replace(old, new)
    out = sub(src, LIB_LINE, OBSERVERS, "lib line")
    out = sub(out, POLDEF_OLD, POLDEF_NEW, "policy/jitter knob")
    out = sub(out, FIXDEF_OLD, FIXDEF_NEW, "fixture knob")
    out = sub(out, FX_OLD, FX_NEW, "fixtures")
    out = sub(out, WANT_OLD, WANT_NEW, "welem gate")
    out = sub(out, KIT_OLD, KIT_NEW, "kit rows")
    out = sub(out, POL_OLD, POL_NEW, "policies")
    out = sub(out, TGT_OLD, TGT_NEW, "target aim")
    out = sub(out, AIM_OLD, AIM_NEW, "episode reset")
    out = sub(out, ARM_OLD, ARM_NEW, "arm")
    out = sub(out, DISARM_OLD, DISARM_NEW, "disarm")
    out = sub(out, REPORT_OLD, REPORT_NEW, "report")
    out = sub(out, JIT_OLD, JIT_NEW, "settle")
    return out


def write():
    os.makedirs(OUT, exist_ok=True)
    src = open(SRC, encoding="utf-8").read()
    open(LAB, "w", encoding="utf-8").write(derive(src))
    print("wrote", os.path.relpath(LAB, ROOT))


# ---------------------------------------------------------------- run ----
def run_one(fixture, policy, jitter, timeout, subdir=None):
    d = os.path.join(OUT, subdir or fixture)
    os.makedirs(d, exist_ok=True)
    tag = "%s_j%02d" % (policy, jitter)
    log = os.path.join(d, tag + ".log")
    lua = os.path.join(d, tag + ".lua")
    src = open(LAB, encoding="utf-8").read()
    src = (src.replace("@POLICY@", policy).replace("@FIXTURE@", fixture)
              .replace("@JITTER@", str(jitter)))
    for tok in ("@POLICY@", "@FIXTURE@", "@JITTER@"):
        assert tok not in src, "token %s left unsubstituted" % tok
    open(lua, "w", encoding="utf-8").write(src)
    env = dict(os.environ)
    env.update({
        "OT6_TIMEOUT": str(timeout),
        "OT6_WORKER": "fvalab-%s-%s" % (fixture, tag),
        "OT6_ARTIFACT_DIR": os.path.join(d, tag),
        "OT6_NO_PUBLISH": "1",
    })
    with open(os.path.join(d, tag + ".out"), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             lua, log], cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return fixture, policy, jitter, rc, log


# ------------------------------------------------------------- reading ---
MET = re.compile(r"^\[ot6\] \[metrics\] b=(\d+) (\w+)=(.*)$")
ACT = re.compile(r"^\[ot6\] \[fva-act\] (.*)$")


def read_log(path):
    """{battle index: {key: value}} plus the raw [fva-act] rows."""
    battles, acts = defaultdict(dict), []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return battles, acts
    with fh:
        for line in fh:
            m = MET.match(line.rstrip("\n"))
            if m:
                b, k, v = int(m.group(1)), m.group(2), m.group(3)
                if k in ("fva_cell", "mon_detail", "member"):
                    battles[b].setdefault(k, []).append(v)
                else:
                    battles[b][k] = v
                continue
            m = ACT.match(line.rstrip("\n"))
            if m:
                acts.append(kv(m.group(1)))
    return battles, acts


def kv(line):
    out = {}
    for m in re.finditer(r"(\w+)=(\S+)", line):
        out[m.group(1)] = m.group(2)
    m = re.search(r"(\w+)\(\$([0-9A-F]{2})\)", line)
    if m:
        out["cmdname"], out["cmd"] = m.group(1), m.group(2)
    return out


def num(s, default=0):
    m = re.match(r"-?\d+", str(s or ""))
    return int(m.group(0)) if m else default


def kill_turns(m):
    """Party turns spent killing the formation, or -1 if it survived.

    The instrument stops the frame the last body's HP reaches zero, which
    is one action before that action reaches SaveForMimic -- the same
    one-action skew bal_party's own `bp_action_skew` reports as a steady
    -1 -- so the killing turn is never emitted as a row.  When the stage
    is empty at report time the honest count is the rows seen plus that
    one turn.  A turn that empties the stage with others still queued
    does get a row, and fva_kill_actions carries it; prefer it."""
    k = num(m.get("fva_kill_actions"), -1)
    if k > 0:
        return k
    if num(m.get("fva_end_live"), -1) == 0:
        return num(m.get("fva_actions"), 0) + 1
    return -1


def logs_for(paths):
    if paths:
        return sorted(paths)
    return sorted(glob.glob(os.path.join(OUT, "*", "*.log")))


CHARNAME = {0x00: "TERRA", 0x01: "LOCKE", 0x04: "EDGAR", 0x05: "SABIN",
            0x06: "CELES"}


# --------------------------------------------------------- aggregate -----
def aggregate(paths):
    paths = logs_for(paths)
    if not paths:
        sys.exit("fightvsabilitylab: no logs under %s -- run first"
                 % os.path.relpath(OUT, ROOT))
    rows = []
    for p in paths:
        fixture = os.path.basename(os.path.dirname(p))
        battles, acts = read_log(p)
        for b, m in sorted(battles.items()):
            if "result" not in m:
                rows.append({"fixture": fixture, "log": p, "b": b,
                             "policy": m.get("policy", "?"),
                             "result": "void:" + m.get("void", "no-report")})
                continue
            rows.append({
                "fixture": fixture, "log": p, "b": b,
                "policy": m.get("policy", "?"),
                "formation": m.get("formation", "?"),
                "result": m.get("result", "?"),
                "frames": num(m.get("frames")),
                "actions": num(m.get("player_actions")),
                "kacts": kill_turns(m),
                "kframes": num(m.get("fva_frames"), -1),
                "dmg": num(m.get("player_dmg")),
                "taken": num(m.get("enemy_dmg")),
                "chips": num(m.get("shield_chips")),
                "breaks": num(m.get("breaks")),
                "mp": sum(num(x.split(":")[1])
                          for x in (m.get("char_mp_spent") or "").split(",")
                          if ":" in x),
                "plans": m.get("char_plan", "-"),
                "monhp": m.get("monster_hp_start", "-"),
            })
    print("== per battle (every retained attempt; nothing selected) ==")
    print("kill_acts / kill_fr: the turn and the frame after which no body")
    print("still held HP -- turns-to-kill.  -1 means the formation outlived")
    print("the attempt.  acts / frames are the instrument's own and run past")
    print("the kill, because its stop rule reads the presence bit not HP.")
    hdr = ("%-14s %-14s %-14s %2s %-8s %7s %5s %6s %6s %7s %6s %5s %6s %5s"
           % ("fixture", "policy", "formation", "b", "result", "frames",
              "acts", "kacts", "kfr", "dmg", "taken", "chip", "breaks", "mp"))
    print(hdr)
    for r in rows:
        if r["result"].startswith("void"):
            print("%-14s %-14s %-14s %2d %-8s" % (r["fixture"], r["policy"],
                                                  "-", r["b"], r["result"]))
            continue
        print("%-14s %-14s %-14s %2d %-8s %7d %5d %6d %6d %7d %6d %5d %6d %5d"
              % (r["fixture"], r["policy"], r["formation"], r["b"],
                 r["result"], r["frames"], r["actions"], r["kacts"],
                 r["kframes"], r["dmg"], r["taken"], r["chips"], r["breaks"],
                 r["mp"]))
    # one summary row per (fixture, policy)
    agg = defaultdict(list)
    for r in rows:
        if r["result"].startswith("void"):
            continue
        agg[(r["fixture"], r["policy"])].append(r)
    print()
    print("== per fixture x policy (mean over kept battles) ==")
    print("kacts / kfr are means over the battles that actually killed the")
    print("formation; `killed` is how many of the n did.")
    print("%-14s %-14s %3s %4s %4s %6s %6s %6s %7s %7s %6s %6s %6s"
          % ("fixture", "policy", "n", "won", "kild", "kacts", "kfr",
             "acts", "dmg", "dmg/act", "taken", "chips", "mp"))
    for key in sorted(agg):
        rs = agg[key]
        n = len(rs)
        won = sum(1 for r in rs if r["result"] == "won")
        killed = [r for r in rs if r["kacts"] > 0]
        mean = lambda f: sum(r[f] for r in rs) / n
        kmean = lambda f: (sum(r[f] for r in killed) / len(killed)
                           if killed else 0)
        acts = mean("actions")
        print("%-14s %-14s %3d %4d %4d %6.1f %6.0f %6.1f %7.0f %7.1f %6.0f "
              "%6.2f %6.1f"
              % (key[0], key[1], n, won, len(killed), kmean("kacts"),
                 kmean("kframes"), acts, mean("dmg"),
                 mean("dmg") / acts if acts else 0,
                 mean("taken"), mean("chips"), mean("mp")))
    print()
    print("(%d logs read: %s)" % (len(paths),
                                  ", ".join(os.path.relpath(p, ROOT)
                                            for p in paths)))


# ---------------------------------------------------------- mechanic -----
def mechanic(paths):
    """The swing/hit/chip ladder, from every [fva-act] row in every log."""
    paths = logs_for(paths)
    cells = defaultdict(lambda: defaultdict(int))
    skipped = 0
    for p in paths:
        _, acts = read_log(p)
        for a in acts:
            # a turn taken when no body still held HP swung at nothing: the
            # instrument's stop rule reads the presence bit, not HP, so a
            # formation's last few queued actions land after it is dead.
            # They are not turns and are counted out, here and nowhere else.
            # and a turn whose target was already dead when the ATB got
            # round to it swung at a corpse: its swing count is real, its
            # hit count is a fact about the corpse.
            # and an action that reached FightAttack with $B1 bit 0 set is
            # a counterattack, which Ot6FightBoost refuses by design
            # ("counterattacks never boost"); it is not a turn the menu
            # spent, and its swing count is the unboosted one whatever the
            # actor's pending boost reads.
            if (num(a.get("live"), 0) == 0 or num(a.get("aim"), 1) == 0
                    or num(a.get("fb1"), 0) == 1):
                skipped += 1
                continue
            cmd = a.get("cmdname", "?")
            if cmd != "Fight":
                cmd = "%s %s" % (cmd, a.get("atk", "?"))
            hands = num(a.get("hands"))
            rev = num(a.get("rev"))
            c = cells[(cmd, hands, rev, CHARNAME.get(int(a.get("char", "-1"), 16)
                                                     if a.get("char") else -1,
                                                     a.get("char", "?")))]
            c["n"] += 1
            h = num(a.get("hits"))
            c["max"] = max(c["max"], h)
            c["h%d" % h] = c.get("h%d" % h, 0) + 1
            c["swings"] += num(a.get("swings"))
            c["hits"] += num(a.get("hits"))
            c["dmg"] += num(a.get("dmg"))
            c["chips"] += num(a.get("chips"))
            c["mp"] += num(a.get("spent"))
            if a.get("passes", "-") != "-":
                c["passes"] += num(a.get("passes"))
                c["pn"] += 1
            if a.get("pre", "-") != "-":
                c["pre"] += num(a.get("pre"))
                c["pren"] += 1
    print("== the mechanic, per action, measured (every retained action) ==")
    print("`max` is the most landed hits any one action of that shape made;")
    print("`hits` is the mean over all of them, which a miss or a target")
    print("under Vanish pulls below `max`.  `hist` is hits:count.")
    print("%-14s %-7s %5s %3s %5s %6s %6s %6s %3s %6s %8s %6s  %s"
          % ("cmd", "who", "hands", "bp", "n", "$3a70", "passes", "swings",
             "max", "hits", "dmg", "chips", "hist"))
    for key in sorted(cells, key=lambda k: (k[0], k[3], k[1], k[2])):
        cmd, hands, rev, who = key
        c = cells[key]
        n = c["n"]
        hist = ",".join("%s:%d" % (k[1:], c[k]) for k in
                        sorted((k for k in c if k.startswith("h")
                                and k[1:].isdigit()), key=lambda k: int(k[1:])))
        print("%-14s %-7s %5d %3d %5d %6s %6s %6.2f %3d %6.2f %8.1f %6.2f  %s"
              % (cmd, who, hands, rev, n,
                 "%.2f" % (c["pre"] / c["pren"]) if c["pren"] else "-",
                 "%.2f" % (c["passes"] / c["pn"]) if c["pn"] else "-",
                 c["swings"] / n, c["max"], c["hits"] / n, c["dmg"] / n,
                 c["chips"] / n, hist))
    print()
    print("(%d logs read; %d rows dropped as turns taken with no body left "
          "holding HP)" % (len(paths), skipped))


# ------------------------------------------------------------- reach -----
# Which kit verbs a character has actually LEARNED at a given level:
# BlitzLevelTbl / BushidoLevelTbl (ff6/src/field/event.asm:1235-1240), the
# tables the field's own learn loop walks.
BLITZ_LEVELS = [1, 6, 10, 15, 23, 30, 42, 70]
BUSHIDO_LEVELS = [1, 6, 12, 15, 24, 34, 44, 70]
INV_IDS, INV_CNT = 0x1869, 0x1969        # 256 item ids, then 256 counts

# Ot6AbilityCostTbl, the base (unboosted) MP a kit verb costs, re-read from
# ff6/src/battle/ot6_boost.asm rather than copied, so a table edit shows up
# here instead of being remembered.
def _ability_mp():
    src = open(os.path.join(ROOT, "ff6/src/battle/ot6_boost.asm"),
               encoding="utf-8").read().splitlines()
    i = next(k for k, l in enumerate(src)
             if l.strip().startswith("Ot6AbilityCostTbl:"))
    out = {}
    for line in src[i + 1:]:
        code = line.split(";", 1)[0].strip()
        if not code:
            continue
        m = re.match(r"\.byte\s+\$([0-9a-fA-F]{2}),\s*(\d+)\s*$", code)
        if m:
            out[int(m.group(1), 16)] = int(m.group(2))
            continue
        if code.startswith(".byte"):
            break                      # the $ff terminator
    if len(out) < 20:
        raise SystemExit("fightvsabilitylab: Ot6AbilityCostTbl parsed %d rows,"
                         " want >= 20 -- parser drift" % len(out))
    return out


ABILITY_MP = _ability_mp()


def boost_price(base, boost):
    """Ot6BoostPriceFor, in the integers the proc itself uses."""
    if base is None:
        return None
    if boost <= 0:
        return base
    boost = min(boost, 3)
    p = base
    for _ in range(boost):
        p *= 5
    p = ((p >> (boost - 1)) + 1) >> 1
    return max(base, min(99, p))


def bodies_of(data, step):
    """(label, species) for every distinct body in the step's random pools
    and its forced event battles, through check_break_reach's own walkers."""
    import check_break_reach as CBR            # already imported by reach()
    out, seen = [], set()

    def add(f):
        for sp, _cnt in data.formation_bodies(f & 0x1FF):
            if sp in seen:
                continue
            seen.add(sp)
            out.append(("%s ($%03X)" % (data.names[sp].strip(), sp), sp))

    for m in step["maps"]:
        if not data.map_random_enabled(m):
            continue
        for f in data.group_formations(data.map_group(m)):
            add(f)
    for ev, slots, _label in step.get("events", []):
        for s in slots:
            f = data.event_formation(ev, s)
            if f != 0x01FF:
                add(f)
    return out


# Which fixture's gear and bag stand for each declared step of
# check_break_reach's AREAS: the tracked savestate the route really passes
# through on the way into that stretch.
STEP_FIXTURE = {
    ("sealed-gate", 0): "gate_cave_save",
    ("vector-factory", 0): "ifrit_entry",
    ("vector-factory", 1): "n128_won",
    ("zozo", 0): "zozo_arrival",
}


def reach():
    """The static arm: the route's own gear against the WoB's own bodies."""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import check_break_reach as CBR
    import savestate_party as SP

    data = CBR.Data(ROOT)

    def fixture_state(fx):
        raw = SP.biggest_stream(os.path.join(ROOT, "build/states", fx + ".mss"))
        if raw is None:
            return None, None, "no zlib stream"
        cb = SP.find_char_block(raw)
        if cb is None:
            return None, None, "character table not located"
        base = cb - SP.CHAR_BLOCK
        bag = set()
        for i in range(256):
            it = raw[base + INV_IDS + i]
            if it != 0xFF and raw[base + INV_CNT + i] > 0:
                bag.add(it)
        return SP.party_at(raw, cb), bag, None

    def is_weapon(item):
        if item == 0xFF:
            return False
        t = data.items[item * CBR.ITEM_REC]
        return (t & 0x80) == 0 and (t & 0x07) == 1

    def axes_of_weapon(item):
        """(class, element) a Fight with this item chips on.  An empty hand
        is $FF, a bludgeoning fist; a NULLBRK weapon chips nothing."""
        cls = data.weap_class[item]
        if cls & CBR.NULLBRK:
            return 0, 0
        return cls & 0x0F, (0 if item == 0xFF else data.weapon_elem(item))

    def fight_axes(rh, lh):
        c, e = axes_of_weapon(rh if is_weapon(rh) else 0xFF)
        if is_weapon(lh):                      # the Genji Glove pair
            c2, e2 = axes_of_weapon(lh)
            c, e = c | c2, e | e2
        return c, e

    def ability_axes(who, level, bag):
        """(label, class, element, base MP) per verb this character owns AT
        THIS LEVEL, with a Tool credited only when the bag really holds it."""
        out = []
        cmds = data.commands[who]
        if "BLITZ" in cmds:
            for i, sid in enumerate(CBR.COMMAND_ABILITIES["BLITZ"]):
                if level < BLITZ_LEVELS[i]:
                    continue
                cls = data.skill_class.get(sid, 0)
                out.append(("Blitz $%02X" % sid,
                            0 if cls & CBR.NULLBRK else cls & 0x0F,
                            data.attack_elem(sid), ABILITY_MP.get(sid)))
        if "BUSHIDO" in cmds:
            for i, sid in enumerate(CBR.COMMAND_ABILITIES["BUSHIDO"]):
                if level < BUSHIDO_LEVELS[i]:
                    continue
                cls = data.skill_class.get(sid, 0)
                out.append(("SwdTech $%02X" % sid,
                            0 if cls & CBR.NULLBRK else cls & 0x0F,
                            data.attack_elem(sid), ABILITY_MP.get(sid)))
        if "TOOLS" in cmds:
            for it in CBR.TOOLS_RANGE:
                if it not in bag:
                    continue
                cls = data.weap_class[it]
                out.append(("Tool $%02X" % it,
                            0 if cls & CBR.NULLBRK else cls & 0x0F,
                            data.attack_elem(it - CBR.TOOL_ATK_DELTA),
                            ABILITY_MP.get(it)))
        return out

    print("== the routed party's Fight against the WoB's own bodies ==")
    print()
    print("Gear and bag are read out of each stretch's own tracked fixture")
    print("(tools/savestate_party.py), never assumed.  Class rows come from")
    print("Ot6ShieldTbl or the generated break floor, and weak elements from")
    print("monster_prop +25 merged with Ot6ElemAddTbl minus absorb and null,")
    print("both through tools/check_break_reach.py's own parsers -- so this")
    print("arm and the shipped linter cannot read the tables differently.")
    print("A kit verb counts only at the level that learns it (BlitzLevelTbl")
    print("/ BushidoLevelTbl) and, for a Tool, only when the bag holds it.")
    print()
    totals = defaultdict(int)
    for area_name in sorted(CBR.AREAS):
        area = CBR.AREAS[area_name]
        for si, step in enumerate(area["steps"]):
            fx = STEP_FIXTURE.get((area_name, si))
            if fx is None:
                continue
            recs, bag, err = fixture_state(fx)
            if recs is None:
                print("  %s step %d: %s" % (area_name, si, err))
                continue
            info = {r["name"]: r for r in recs}
            print("-- %s / %s" % (area_name, step["name"]))
            print("   gear + bag: build/states/%s.mss" % fx)
            party = []
            for who in step["party"]:
                r = info.get(who)
                if r is None:
                    print("     %-7s not in this fixture's party" % who)
                    continue
                rh, lh = r["gear"][0], r["gear"][1]
                fc, fe = fight_axes(rh, lh)
                abl = ability_axes(who, r["level"], bag)
                ac = ae = 0
                for _lab, c, e, _mp in abl:
                    ac |= c
                    ae |= e
                party.append((who, fc, fe, abl))
                print("     %-7s L%-3d hands $%02X/$%02X%s  Fight chips "
                      "%-20s %-20s | the kit ADDS %-14s %s"
                      % (who, r["level"], rh, lh,
                         " (pair)" if is_weapon(lh) else "       ",
                         CBR.class_str(fc), CBR.elem_str(fe),
                         CBR.class_str(ac & ~fc), CBR.elem_str(ae & ~fe)))
            print()
            print("     %-26s %-11s %-20s %-20s %s"
                  % ("body", "shields", "class key", "element key", "verdict"))
            for label, sp in bodies_of(data, step):
                cls, _src, gaugeless = data.species_class(sp)
                sh, shsrc = data.boss.effective_shields(sp)
                el = data.species_break_elems(sp)
                fighters = [w for (w, fc, fe, _a) in party
                            if (cls & fc) or (el & fe)]
                keys = []
                for (w, fc, fe, abl) in party:
                    for (lab, c, e, mp) in abl:
                        if (cls & c) or (e & el):
                            keys.append("%s %s%s" % (
                                w, lab, "" if mp is None else "/%dMP" % mp))
                if gaugeless or sh == 0:
                    verdict = "no gauge"
                    totals["nogauge"] += 1
                elif fighters:
                    verdict = "Fight reaches it: " + ",".join(fighters)
                    totals["fight"] += 1
                elif keys:
                    verdict = "ABILITY ONLY: " + ", ".join(keys[:4])
                    totals["ability"] += 1
                else:
                    verdict = "NO KEY AT ALL"
                    totals["none"] += 1
                totals["all"] += 1
                print("     %-26s %-11s %-20s %-20s %s"
                      % (label, "%d (%s)" % (sh, shsrc.split()[0]),
                         CBR.class_str(cls), CBR.elem_str(el), verdict))
            print()
    print("== totals, one row per distinct BODY in the stretches examined ==")
    print("  bodies examined                      %d" % totals["all"])
    print("  a routed Fight chips it              %d" % totals["fight"])
    print("  ONLY a costed ability chips it       %d" % totals["ability"])
    print("  nothing in the party chips it        %d" % totals["none"])
    print("  no gauge to chip                     %d" % totals["nogauge"])
    print()
    print("== what the ability-only keys cost at each boost (Ot6BoostPriceFor) ==")
    print("  %-14s %4s %4s %4s %4s" % ("verb", "b0", "b1", "b2", "b3"))
    for sid in sorted(ABILITY_MP):
        base = ABILITY_MP[sid]
        print("  $%02X %-10s %4d %4d %4d %4d"
              % (sid, "", base, boost_price(base, 1), boost_price(base, 2),
                 boost_price(base, 3)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cmd", choices=["reach", "write", "run", "aggregate",
                                    "mechanic"])
    ap.add_argument("rest", nargs="*")
    ap.add_argument("--jitter", default="0")
    ap.add_argument("--tag", default=None,
                    help="put this run's logs under <fixture>-<tag>/ instead "
                         "of <fixture>/, so a re-measurement with sharper "
                         "observers does not overwrite the spread it "
                         "supersedes")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=3600)
    a = ap.parse_args()
    if a.cmd == "reach":
        return reach()
    if a.cmd == "write":
        return write()
    if a.cmd == "aggregate":
        return aggregate(a.rest)
    if a.cmd == "mechanic":
        return mechanic(a.rest)
    # run <fixture> <policy> [policy ...]
    if len(a.rest) < 2:
        sys.exit("usage: run <fixture> <policy> [policy ...] "
                 "[--jitter 0,13,29]")
    fixture, policies = a.rest[0], a.rest[1:]
    jitters = [int(x) for x in a.jitter.split(",") if x != ""]
    write()
    jobs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        sub = (fixture + "-" + a.tag) if a.tag else None
        for p in policies:
            for j in jitters:
                jobs.append(ex.submit(run_one, fixture, p, j, a.timeout, sub))
        for f in concurrent.futures.as_completed(jobs):
            fx, pol, j, rc, log = f.result()
            print("%-14s %-14s j%-3d rc=%d  %s"
                  % (fx, pol, j, rc, os.path.relpath(log, ROOT)))


if __name__ == "__main__":
    main()
