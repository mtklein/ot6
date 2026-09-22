-- @suite savestate=tunnelarmr_entry slow
-- battle_retaliate_umaro.lua -- #237: a provoked UMARO dumps his bank on
-- whichever of his four arms the roll picks, not only on the plain swing.
--
-- THIS IS A SYNTHETIC MECHANISM TEST (docs/TESTING.md, "Synthetic mechanism
-- tests"), and it says so: Umaro is World of Ruin content, no route state
-- reaches him, and nothing here is a route claim, a balance claim, or a
-- claim about ordinary play.  One party member of a legitimately reached
-- battle (battle 67, TunnelArmr, from tunnelarmr_entry) is STAGED as Umaro
-- with four byte writes, all declared in tools/state_write_waivers.txt:
--   * his character id ($3ed8,x) becomes UMARO, which is what CheckPlayerAction
--     refuses a command window by name and what Cmd_06 sends to Umaro's own
--     chooser (_163b) instead of FightAttack.  This one lands on the
--     battle's FIRST CheckPlayerAction pass, inside InitBattle, ahead of
--     that proc's by-name test -- see the callback for why the timing is
--     load-bearing;
--   * his two relic cells ($3cd0/$3cd1,x) become BLIZZARD_ORB and RAGE_RING,
--     the items _163b tests for, so all four arms are on the roll
--     (RandBitRateTbl row 3, about a quarter each);
--   * STATUS2's Berserk bit, so RandCharAction's berserk arm queues Fight
--     for him every turn -- Umaro's own command row -- rather than a random
--     row of the staged character's.  These three land once the battle is
--     up, the moment battle_retaliate.lua stages its Berserk.
-- Everything else is the engine's: the roll, the targets, the passes, the
-- damage, the charge.
--
-- WHY THIS FIGHT.  TunnelArmr's every line is single-target (`attack
-- BATTLE, BOLT, FIRE / wait / attack POISON, SPECIAL, FIRE`, and a
-- one-in-three Battle counter at whoever hit him), and the party is TWO,
-- so about every other action of his lands on the subject and the
-- subject's own Fights draw the counter: he is provoked on most of his
-- turns.  The first staging, DADALUMA with four seats
-- (build/lab/umaro/red-umaro.log and
-- build/states/suite_battle_retaliate_umaro.log before this move), was hit
-- 3 times in 15 actions across three attempts (`hp 567 vs line 567` on
-- arm after arm) and his knife throws one-shot the subject at ~500
-- damage, so every attempt wiped before a second provoked arm.  The other
-- seat here hands every turn straight back; when he falls, Throw has no
-- ally to throw and falls back to Charge (UmaroAttack_00's own `beq`),
-- which the ledger records as the arm that EXECUTED.
--
-- THE GAP, measured before it was closed (build/lab/umaro/red-umaro.log,
-- retained as build/attempts/<branch>/lab/umaro/red-umaro.log): the dump
-- hooked into Ot6FightBoost, which hooks into FightAttack, and FightAttack is
-- only the LAST of UmaroAttackTbl's four slots.  A provoked Throw reached
-- its roll with pending 0 -- `f1806 Throw PROVOKED: bank 3, hp 489 vs
-- line 546; pending at roll 0` -- ran one pass at plain damage, and
-- Ot6ActionEnd took the gain arm: the retaliation tally was spent on nothing, and
-- the bank climbed 1 2 3 4 5.
--
-- WHAT EACH ARM BUYS WITH THE DUMP, and why it is not one thing:
--   * Fight ($1658): swings, through Ot6FightBoost -- unchanged.
--   * Charge ($16BF) and Storm ($174E): the damage multiplier, through
--     Ot6BoostDmg.  Charge executes as command $23 and Storm as command $02,
--     neither of which is on Ot6BoostDmg's exempt list, so an armed pending
--     byte already multiplies them; the only missing piece was arming it
--     before the roll.
--   * Throw ($16D3): extra throws, through the multi-attack loop.  Throw
--     runs ExecAttack with x = the THROWN ALLY (UmaroAttack_00's `tyx` after
--     BitToTargetID), so Ot6BoostDmg reads the ally's pending byte, not
--     Umaro's, and can never deliver here; Ot6ThrowBoost adds one throw per
--     pip to $3a70 instead, the same landed-hit ladder as a one-weapon Fight.
--
-- WHEN THE MEASUREMENT IS COMPLETE: two provoked non-Fight actions of his
-- have resolved (one, if the fight ends first).  "Provoked" is the
-- machine's own reading -- he stood below the hp line his own last turn
-- drew, with a pip in the bank, and it is not a counterattack -- decided
-- without reference to the dump, so a ROM without the hook reaches the
-- verdict and fails AT the assertion.  A seed on which the fight ends
-- before he is provoked on a non-Fight arm runs out the budget instead,
-- which the segment runner retries at the next shift.  Which arms a run
-- covers is the roll's; the run logs them, and the 8-shift sweep's union
-- is where all three non-Fight arms are seen.
local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/tunnelarmr_entry.mss.lua"
local TUNNELARMR = 0x0104                -- formation species word (const.inc)

local CHAR_UMARO = 0x0D                 -- CHAR::UMARO (const.inc)
local BLIZZARD_ORB, RAGE_RING = 0xC5, 0xC6   -- ITEM:: (const.inc); _163b's own tests
local BERSERK = 0x10                    -- STATUS2 bit 4
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD = 0x01, 0x05
local CMDTBL = 0x202E
local BANK_CAP = 5
local ARM = { [0] = "Throw", [1] = "Storm", [2] = "Charge", [3] = "Fight" }

local function hp(e)     return H.readWord(0x3BF4 + e * 2) end
local function bp(e)     return H.readByte(0x3E9C + e * 2) end
local function pend(e)   return H.readByte(0x3E9D + e * 2) end
local function charOf(e) return H.readByte(0x3ED8 + e * 2) end
local function st2(e)    return H.readByte(0x3EE5 + e * 2) end
local function batPwr(e) return H.readByte(0x3B68 + e * 2) + H.readByte(0x3B69 + e * 2) end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("e%d c$%02X %d/%d bp%d pwr%d", e, charOf(e),
      hp(e), H.readWord(0x3C1C + e * 2), bp(e), batPwr(e))
  end
  return table.concat(p, " | ")
end
local function romBytes(base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = H.readRomByte(base + i) end
  return t
end

local D = {}                            -- base, perBp, cap, unctl, mark, jmp, sites
local SUBJ = nil

local L = { windows = {}, dumps = {}, ends = {}, hurts = 0, markAtStart = 0,
            provokedSpecial = 0, staged = false }
local W = nil                           -- the open window

-- A window opens at his chooser, RESOLVES at SaveForMimic (no more passes
-- or damage rolls belong to it), takes its charge record at Ot6ActionEnd's
-- entry (which runs after SaveForMimic on the action-end path,
-- battle_main.asm:324/344), reads the bank Ot6ActionEnd LEFT on the next
-- frame start, and only then is finalized into the ledger.
local function newWindow()
  return { f = H.frame, bankBefore = bp(SUBJ), pendBefore = pend(SUBJ),
    hp = hp(SUBJ), mark = L.markAtStart, arm = nil, pendAtRoll = nil,
    a70AtRoll = nil, a70 = 0, passes = 0, dumpBeforeRoll = false, rolled = false,
    dmg = {}, entered = {}, charge = nil, bankAfter = nil, resolved = false }
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local sChooser, sTbl = H.sym("_163b"), H.sym("UmaroAttackTbl")
  local sExec, sSF, sAE = H.sym("ExecAttack"), H.sym("SaveForMimic"), H.sym("Ot6ActionEnd")
  local sBD = H.sym("Ot6BoostDmg")
  local arms = { [0] = H.sym("UmaroAttack_00"), [1] = H.sym("UmaroAttack_01"),
                 [2] = H.sym("UmaroAttack_02"), [3] = H.sym("FightAttack") }

  local function yIsSubj()
    return SUBJ ~= nil and (emu.getState()["cpu.y"] & 0xFFFF) == SUBJ * 2
  end
  local function xIsSubj()
    return SUBJ ~= nil and (emu.getState()["cpu.x"] & 0xFFFF) == SUBJ * 2
  end

  -- his chooser: the window opens here, before the roll and before any hook
  emu.addMemoryCallback(function()
    if not yIsSubj() then return end
    W = newWindow()
    W.counter = (H.readByte(0xB1) & 0x01) ~= 0
    W.provoked = (not W.counter) and W.mark > W.hp and W.bankBefore > 0
  end, emu.callbackType.exec, sChooser, sChooser)

  -- the roll's end: `jmp (UmaroAttackTbl,x)`, x = arm * 2
  emu.addMemoryCallback(function()
    if W == nil or W.rolled or not yIsSubj() then return end
    W.rolled = true
    W.arm = (emu.getState()["cpu.x"] & 0xFFFF) // 2
    W.pendAtRoll = pend(SUBJ)
    W.a70AtRoll = H.readByte(0x3A70)
  end, emu.callbackType.exec, D.jmp, D.jmp)

  for a = 0, 3 do
    emu.addMemoryCallback(function()
      if W == nil or W.resolved or not yIsSubj() then return end
      W.entered[#W.entered + 1] = a
    end, emu.callbackType.exec, arms[a], arms[a])
  end

  -- every pass of the multi-attack loop is an entry into ExecAttack
  emu.addMemoryCallback(function()
    if W == nil or W.resolved then return end
    if (H.readByte(0xB1) & 0x01) ~= 0 then return end
    W.passes = W.passes + 1
  end, emu.callbackType.exec, sExec, sExec)

  emu.addMemoryCallback(function(_, v)
    if v == 0 or v == 0xFF or W == nil or W.resolved then return end
    if v > W.a70 then W.a70 = v end
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)

  -- the dump: his pending byte written nonzero, and whether it happened
  -- before the roll (the chooser's hook) or after (FightAttack's)
  emu.addMemoryCallback(function(addr, v)
    if v == 0 or v == 0xFF or SUBJ == nil or addr ~= 0x7E3E9D + SUBJ * 2
       or not H.battleLoadStarted() then return end    -- $ff = the end-of-battle clear
    L.dumps[#L.dumps + 1] = { f = H.frame, v = v, bank = bp(SUBJ) }
    if W ~= nil and not W.resolved and not W.rolled then W.dumpBeforeRoll = true end
    H.log(string.format("[dump] f%d e%d pending <- %d off a bank of %d, %s "
      .. "the roll", H.frame, SUBJ, v, bp(SUBJ),
      (W ~= nil and not W.rolled) and "BEFORE" or "after"))
  end, emu.callbackType.write, 0x7E3E9D, 0x7E3E9D + 6)

  -- the multiplier: damage as Ot6BoostDmg finds it and as it leaves it
  emu.addMemoryCallback(function()
    if W == nil or W.resolved then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    W.dmg[#W.dmg + 1] = { x = x, pendX = H.readByte(0x3E9D + x),
      before = H.readWord(0x11B0), after = nil,
      b5 = H.readByte(0xB5), b6 = H.readByte(0xB6),
      a7c = H.readByte(0x3A7C), a7d = H.readByte(0x3A7D),
      b1 = H.readByte(0xB1) }
  end, emu.callbackType.exec, sBD, sBD)
  for _, ret in ipairs(D.sites) do
    emu.addMemoryCallback(function()
      if W == nil or W.resolved or #W.dmg == 0 then return end
      local d = W.dmg[#W.dmg]
      if d.after == nil then d.after = H.readWord(0x11B0) end
    end, emu.callbackType.exec, ret, ret)
  end

  emu.addMemoryCallback(function()
    if W == nil or W.resolved or not W.rolled then return end
    W.resolved = true
  end, emu.callbackType.exec, sSF, sSF)

  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    local b, p = bp(SUBJ), pend(SUBJ)
    L.ends[#L.ends + 1] = { f = H.frame, bank = b, pending = p }
    if W ~= nil and W.resolved and W.charge == nil then
      W.charge = { f = H.frame, bank = b, p = p }
    end
    H.log(string.format("[bank] f%d e%d Ot6ActionEnd bank=%d pending=%d -> %s "
      .. "(hp %d)", H.frame, SUBJ, b, p, p > 0 and "CHARGE" or "gain", hp(SUBJ)))
  end, emu.callbackType.exec, sAE, sAE)

  local function finalizeWindow()
    L.windows[#L.windows + 1] = W
    if W.provoked and W.arm ~= 3 then
      L.provokedSpecial = L.provokedSpecial + 1
    end
    local dm = {}
    for _, d in ipairs(W.dmg) do
      dm[#dm + 1] = string.format("x%d/p%d:%d->%s[b5=%02X b6=%02X "
        .. "$3a7c=%02X%02X b1=%02X]", d.x, d.pendX, d.before,
        tostring(d.after), d.b5, d.b6, d.a7d, d.a7c, d.b1)
    end
    H.log(string.format("[arm] f%d %s %s: bank %d, hp %d vs line %d; pending "
      .. "at roll %d (%s); $3a70 at roll %d, max %d; %d pass(es); dmg %s; "
      .. "entered %s; end found bank %d pending %d, left %d", W.f,
      ARM[W.arm] or "?", W.provoked and "PROVOKED"
      or (W.counter and "counter" or "unprovoked"), W.bankBefore, W.hp,
      W.mark, W.pendAtRoll, W.dumpBeforeRoll and "armed before the roll"
      or "not armed before the roll", W.a70AtRoll, W.a70, W.passes,
      table.concat(dm, " "), table.concat(W.entered, ","), W.charge.bank,
      W.charge.p, W.bankAfter))
    W = nil
  end

  -- who decides his turns: CheckPlayerAction's by-name refusal, the menu
  -- opener, and QueueAction, each with x = the subject.
  --
  -- THE RENAME HAPPENS HERE, at the battle's FIRST CheckPlayerAction for a
  -- character, because of what that proc does for everyone it does not
  -- refuse: it sets $3aa0.1, and a full gauge with that bit set opens the
  -- battle menu instead of taking the auto-command path (_c211bb).  The
  -- real Umaro is refused by name before the bit is ever set, so his
  -- gauge always auto-commands.  A stand-in renamed after InitBattle's
  -- pass (:6280) keeps the bit, and his full gauge opened a window for a
  -- berserked "Umaro" nobody could drive: build/lab/umaro/red-umaro.log,
  -- three attempts, every seat's bank still 1 at the wipe, not one action
  -- of his.  InitParty has seated $3ed8 and InitChars has loaded battle
  -- power and the command rows by this point, so the subject is chosen
  -- from the loaded table and renamed before the by-name test reads it.
  local sCPA, sMenu, sQA = H.sym("CheckPlayerAction"), H.sym("_c211ef"), H.sym("QueueAction")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x >= 8 then return end
    if not L.staged and H.battleLoadStarted() then
      local best = nil
      for e = 0, 3 do
        local fights = false
        for r = 0, 3 do
          if H.readByte(CMDTBL + e * 12 + r * 3) == 0x00 then fights = true end
        end
        if hp(e) > 0 and fights and (best == nil or batPwr(e) < batPwr(best)) then
          best = e
        end
      end
      SUBJ = best
      D.mark = D.markBase + SUBJ * 2
      -- nothing has happened to him yet: this is InitBattle
      H.assertEq(bp(SUBJ), 1, "the subject opens with Ot6InitBP's one pip")
      H.assertEq(H.readWord(D.mark), 0, "and no hurt line yet")
      H.assertEq(H.readByte(D.unctl), 0, "OT6_UNCTL starts the battle clear")
      -- ---- STATE WRITE 1 of 4 (waiver file): the rename -------------- --
      H.writeByte(0x3ED8 + SUBJ * 2, CHAR_UMARO)
      L.staged = true
      H.log(string.format("[stage] f%d first CheckPlayerAction pass (x=%d): "
        .. "e%d (battle power %d, the lowest) renamed to character $%02X "
        .. "before its by-name test; $3aa0=$%02X", H.frame, x, SUBJ,
        batPwr(SUBJ), charOf(SUBJ), H.readByte(0x3AA0 + SUBJ * 2)))
    end
    if not xIsSubj() then return end
    H.log(string.format("[turn] f%d e%d CheckPlayerAction: char $%02X $3aa0=$%02X "
      .. "$3aa1=$%02X gauge=%d", H.frame, SUBJ, charOf(SUBJ),
      H.readByte(0x3AA0 + SUBJ * 2), H.readByte(0x3AA1 + SUBJ * 2),
      H.readByte(0x3219 + SUBJ * 2)))
  end, emu.callbackType.exec, sCPA, sCPA)
  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    H.log(string.format("[turn] f%d e%d the battle MENU opens for him: $3aa0=$%02X",
      H.frame, SUBJ, H.readByte(0x3AA0 + SUBJ * 2)))
  end, emu.callbackType.exec, sMenu, sMenu)
  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    H.log(string.format("[turn] f%d e%d QueueAction: pending list $%02X st2=$%02X",
      H.frame, SUBJ, H.readByte(0x32CC + SUBJ * 2), st2(SUBJ)))
  end, emu.callbackType.exec, sQA, sQA)

  local lastHp, hb = nil, -1000
  emu.addEventCallback(function()
    if SUBJ == nil or not H.battleLoadStarted() then lastHp = nil; return end
    local h = hp(SUBJ)
    if lastHp ~= nil and h < lastHp then L.hurts = L.hurts + 1 end
    lastHp = h
    L.markAtStart = H.readWord(D.mark)
    if W ~= nil and W.charge ~= nil and W.bankAfter == nil
       and H.frame ~= W.charge.f then
      W.bankAfter = bp(SUBJ)
      finalizeWindow()
    end
    if H.frame - hb >= 300 then
      hb = H.frame
      local seats = {}
      for e = 0, 3 do
        seats[#seats + 1] = string.format("e%d $3aa0=%02X/%02X g=%d hp=%d bp=%d",
          e, H.readByte(0x3AA0 + e * 2), H.readByte(0x3AA1 + e * 2),
          H.readByte(0x3219 + e * 2), hp(e), bp(e))
      end
      H.log(string.format("[hb] f%d menu=%d st=%02X actor=%d | %s", H.frame,
        H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR),
        table.concat(seats, " | ")))
    end
  end, emu.eventType.startFrame)
end

local phase = 0
local function measured()
  if L.provokedSpecial >= 2 then return true end
  if L.provokedSpecial >= 1 and (not H.battleLoadStarted() or hp(SUBJ) == 0) then
    return true
  end
  return false
end

H.run({ maxFrames = 60000, retries = 3 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),

  H.call(function()
    -- the ROM's own arithmetic
    local fb = romBytes(H.sym("Ot6FightBoost") & 0x3FFFFF, 40)
    local tail = nil
    for i = 1, #fb - 6 do
      if fb[i] == 0x18 and fb[i + 1] == 0x6D and fb[i + 2] == 0x70
         and fb[i + 3] == 0x3A and fb[i + 4] == 0x8D and fb[i + 5] == 0x70
         and fb[i + 6] == 0x3A then tail = i; break end
    end
    H.assertEq(tail ~= nil, true,
      "Ot6FightBoost still ends in clc / adc $3a70 / sta $3a70")
    local asls = 0
    while tail - 1 - asls >= 1 and fb[tail - 1 - asls] == 0x0A do
      asls = asls + 1
    end
    D.perBp = 1 << asls
    local fa = romBytes(H.sym("FightAttack") & 0x3FFFFF, 24)
    for i = 1, #fa - 4 do
      if fa[i] == 0xA9 and fa[i + 1] == 0x01 and fa[i + 2] == 0x90 then
        D.base = fa[i + 1]; break
      end
    end
    H.assertEq(D.base, 1, "FightAttack seeds $3a70 = 1 without an Offering")
    local rt = romBytes(H.sym("Ot6Retaliate") & 0x3FFFFF, 64)
    for i = 1, #rt - 4 do
      if rt[i] == 0xC9 and rt[i + 2] == 0x90 and rt[i + 4] == 0xA9 then
        D.cap = rt[i + 5]; break
      end
    end
    H.assertEq(D.cap, 3, "the spend caps at 3, read out of Ot6Retaliate")
    D.unctl = 0x7E0000 + (H.sym("OT6_UNCTL") & 0xFFFF)
    D.markBase = 0x7E0000 + (H.sym("OT6_HPMARK") & 0xFFFF)

    -- Umaro's table and the roll that indexes it
    local TBL = H.sym("UmaroAttackTbl")
    local tblOff = TBL & 0x3FFFFF
    local FAW = H.sym("FightAttack") & 0xFFFF
    local arms = {}
    for i = 0, 3 do
      arms[i] = H.readRomByte(tblOff + i * 2) | (H.readRomByte(tblOff + i * 2 + 1) << 8)
    end
    H.assertEq(arms[3], FAW, string.format("UmaroAttackTbl's last slot is "
      .. "FightAttack ($%04X %04X %04X %04X)", arms[0], arms[1], arms[2], arms[3]))
    H.assertEq(arms[0], H.sym("UmaroAttack_00") & 0xFFFF, "slot 0 is Throw")
    H.assertEq(arms[1], H.sym("UmaroAttack_01") & 0xFFFF, "slot 1 is Storm")
    H.assertEq(arms[2], H.sym("UmaroAttack_02") & 0xFFFF, "slot 2 is Charge")
    D.jmp = TBL - 3
    H.assertEq(H.readRomByte((D.jmp & 0x3FFFFF)), 0x7C,
      "the table is indexed by the `jmp (abs,x)` three bytes before it")
    H.assertEq(H.readRomByte((D.jmp & 0x3FFFFF) + 1)
      | (H.readRomByte((D.jmp & 0x3FFFFF) + 2) << 8), TBL & 0xFFFF,
      "...and that jmp's operand is the table")

    -- Ot6BoostDmg's two call sites (physical and magic base damage), found
    -- by their jsl bytes in bank $C2; the observer hooks each return address
    local bd = H.sym("Ot6BoostDmg")
    local b0, b1, b2 = bd & 0xFF, (bd >> 8) & 0xFF, (bd >> 16) & 0xFF
    D.sites = {}
    for off = 0x020000, 0x02FFFC do
      if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == b0
         and H.readRomByte(off + 2) == b1 and H.readRomByte(off + 3) == b2 then
        D.sites[#D.sites + 1] = 0xC00000 + off + 4
      end
    end
    H.assertEq(#D.sites, 2, string.format(
      "Ot6BoostDmg has exactly two call sites in bank $C2 (found %d)", #D.sites))
    H.log(string.format("[rom] $3a70 = %d + %d*bp; spend cap %d; roll jmp "
      .. "$%06X; Ot6BoostDmg returns to $%06X and $%06X", D.base, D.perBp,
      D.cap, D.jmp, D.sites[1], D.sites[2]))
  end),

  -- the observers go in BEFORE the fight loads: the rename rides the
  -- battle's first CheckPlayerAction pass, inside InitBattle
  H.call(installObservers),

  -- one step from the fight: gen_tunnelarmr's own entry -- (47,37) is one
  -- tile above the (47,38) trigger, so step DOWN onto it and ride the
  -- event into battle 67
  H.call(function()
    H.assertEq(H.mapId() & 0x1FF, 70, "tunnelarmr_entry boots on map 70")
    H.assertEq(H.fieldX() == 47 and H.fieldY() == 37, true,
      "one tile above the TunnelArmr trigger")
  end),
  H.hold({ "down" }), H.waitFrames(12), H.release(), H.waitFrames(4),
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function() H.setPad((H.frame % 8 < 4) and { a = true } or {}) end),
  }, "battle 67 loads"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),

  H.call(function()
    H.log("[seed] " .. partyLine())
    H.assertEq(H.formationHas({ [TUNNELARMR] = true }), true, "battle 67: TunnelArmr")
    H.assertEq(L.staged and SUBJ ~= nil, true,
      "the rename landed on the battle's first CheckPlayerAction pass")
    H.assertEq(charOf(SUBJ), CHAR_UMARO, "and it stuck")
    H.assertEq(H.readByte(0x3AA0 + SUBJ * 2) & 0x02, 0,
      "$3aa0.1 never set for him: his full gauge auto-commands, as the "
      .. "real Umaro's does")
    -- A name-refused character's full gauge already auto-commands through
    -- RandCharAction, Berserk or not, so at some seeds the engine has
    -- chosen a turn for him (a random command row of the staged
    -- character's, and the latch) before this point; logged, not asserted.
    H.log(string.format("[stage] f%d before the relics and Berserk: bank %d, "
      .. "hurt line %d, OT6_UNCTL $%02X, %d action end(s) of his so far",
      H.frame, bp(SUBJ), H.readWord(D.mark), H.readByte(D.unctl), #L.ends))
    -- ---- STATE WRITES 2-4 of 4 (waiver file): relics and Berserk ------ --
    H.writeByte(0x3CD0 + SUBJ * 2, BLIZZARD_ORB)
    H.writeByte(0x3CD1 + SUBJ * 2, RAGE_RING)
    H.writeByte(0x3EE5 + SUBJ * 2, st2(SUBJ) | BERSERK)
    H.log(string.format("[stage] f%d e%d is character $%02X with relics "
      .. "$%02X/$%02X and STATUS2 $%02X; hp %d, bank %d, battle power %d",
      H.frame, SUBJ, charOf(SUBJ), H.readByte(0x3CD0 + SUBJ * 2),
      H.readByte(0x3CD1 + SUBJ * 2), st2(SUBJ), hp(SUBJ), bp(SUBJ), batPwr(SUBJ)))
  end),

  H.driveUntil(measured, 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      if not H.battleLoadStarted() then H.setPad({}); return end
      if H.readByte(MENU) == 0 then
        H.setPad(phase < 4 and { a = true } or {})
        return
      end
      if phase >= 4 then H.setPad({}); return end
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      H.setPad(st == ST_CMD and { x = true } or { b = true })
    end),
  }, "two provoked non-Fight actions of the staged Umaro resolve"),

  -- ================================================================== --
  -- the verdict
  -- ================================================================== --
  H.call(function()
    H.setPad({})
    local seen, prov = {}, {}
    for _, w in ipairs(L.windows) do
      local n = ARM[w.arm] or "?"
      seen[n] = (seen[n] or 0) + 1
      if w.provoked then prov[n] = (prov[n] or 0) + 1 end
    end
    local function hist(t)
      local o = {}
      for a = 0, 3 do o[#o + 1] = string.format("%s %d", ARM[a], t[ARM[a]] or 0) end
      return table.concat(o, ", ")
    end
    H.log(string.format("[ledger] %d action(s): %s; provoked: %s; %d hp "
      .. "drop(s), %d dump(s)", #L.windows, hist(seen), hist(prov), L.hurts,
      #L.dumps))

    H.assertEq(L.provokedSpecial >= 1, true, string.format(
      "at least one provoked Throw/Storm/Charge resolved (%d)", L.provokedSpecial))

    -- THE CLAIM, FIRST: every provoked non-Fight arm carried the dump,
    -- armed at the chooser before the roll -- a ROM whose dump hooks into
    -- FightAttack alone arrives here with pending 0 on every one of them
    for _, w in ipairs(L.windows) do
      if w.provoked and w.arm ~= 3 then
        local want = math.min(w.bankBefore, D.cap)
        H.assertEq(w.pendAtRoll, want, string.format(
          "f%d provoked %s (hp %d below a line of %d, bank %d) reached its "
          .. "roll with pending %d = min(bank, cap %d), and NOT the 0 the "
          .. "FightAttack-only dump left it", w.f, ARM[w.arm], w.hp, w.mark,
          w.bankBefore, want, D.cap))
        H.assertEq(w.dumpBeforeRoll, true, string.format(
          "f%d %s: the dump was armed BEFORE the roll, at the chooser",
          w.f, ARM[w.arm]))
      end
    end

    -- then what each arm bought with it.  The roll's pick is the first arm
    -- entered; the arm that EXECUTED is the last, which differs only when
    -- Throw found no ally to throw and fell back to Charge.
    for _, w in ipairs(L.windows) do
      H.assertEq(w.entered[1], w.arm, string.format(
        "f%d: the arm the roll picked (%s) is the one entered first", w.f,
        ARM[w.arm] or "?"))
      local ran = w.entered[#w.entered]
      H.assertEq(ran == w.arm or (w.arm == 0 and ran == 2), true, string.format(
        "f%d: %s executed as itself, or Throw fell back to Charge (entered %s)",
        w.f, ARM[w.arm] or "?", table.concat(w.entered, ",")))
      local name = ARM[ran] or "?"
      if w.provoked then
        local p = w.pendAtRoll
        if ran == 3 then
          H.assertEq(w.a70, D.base + D.perBp * p, string.format(
            "f%d provoked Fight: $3a70 = %d + %d*%d, the swings ladder",
            w.f, D.base, D.perBp, p))
          H.assertEq(w.passes, H.fightPasses(p), string.format(
            "f%d provoked Fight: %d passes", w.f, H.fightPasses(p)))
        elseif ran == 0 then
          H.assertEq(w.a70, p, string.format(
            "f%d provoked Throw: $3a70 = %d, one extra throw per pip", w.f, p))
          H.assertEq(w.passes, 1 + p, string.format(
            "f%d provoked Throw: %d throws, and NOT the 1 an unboosted Throw "
            .. "runs", w.f, 1 + p))
          for _, d in ipairs(w.dmg) do
            H.assertEq(d.x ~= SUBJ * 2, true, string.format(
              "f%d Throw: the damage roll's attacker record is the thrown "
              .. "ally (x = %d), not Umaro", w.f, d.x))
            H.assertEq(d.after, d.before, string.format(
              "f%d Throw: no multiplier rode the ally's empty pending byte "
              .. "(%d -> %d)", w.f, d.before, d.after or -1))
          end
        else
          H.assertEq(w.passes, 1, string.format(
            "f%d provoked %s: one pass -- the multiplier, not the loop", w.f, name))
          H.assertEq(#w.dmg >= 1, true, string.format(
            "f%d provoked %s reached Ot6BoostDmg", w.f, name))
          for _, d in ipairs(w.dmg) do
            H.assertEq(d.x, SUBJ * 2, string.format(
              "f%d %s: Ot6BoostDmg ran for Umaro himself (x = %d)", w.f, name, d.x))
            H.assertEq(d.pendX, p, string.format(
              "f%d %s: with his pending %d", w.f, name, p))
            local want = d.before << p
            if want > 0xFFFF then want = 0x7FFF end
            H.assertEq(d.after, want, string.format(
              "f%d %s: damage %d -> %d (x%d, $7fff on overflow), and NOT "
              .. "the unmultiplied %d", w.f, name, d.before, want, 1 << p,
              d.before))
          end
        end
        H.assertEq(w.charge.p, p, string.format(
          "f%d %s: Ot6ActionEnd found exactly the %d pip(s) armed and took "
          .. "its CHARGE arm", w.f, name, p))
        H.assertEq(w.bankAfter, w.charge.bank - p, string.format(
          "f%d %s: the bank fell from %d to %d: the pips LEFT it, and NOT "
          .. "the %d the gain arm would have left", w.f, name, w.charge.bank,
          w.bankAfter, math.min(w.charge.bank + 1, BANK_CAP)))
      elseif not w.counter then
        H.assertEq(w.pendAtRoll, 0, string.format(
          "f%d unprovoked %s: nothing armed", w.f, name))
        H.assertEq(w.passes, ran == 3 and H.fightPasses(0) or 1, string.format(
          "f%d unprovoked %s: the plain pass count", w.f, name))
        H.assertEq(w.charge.p, 0, string.format(
          "f%d unprovoked %s: Ot6ActionEnd found nothing armed", w.f, name))
        H.assertEq(w.bankAfter, math.min(w.charge.bank + 1, BANK_CAP),
          string.format("f%d unprovoked %s: and took its gain arm, %d -> %d "
          .. "(capped at %d)", w.f, name, w.charge.bank, w.bankAfter, BANK_CAP))
      end
    end
    H.assertEq(#L.dumps <= L.hurts, true, string.format(
      "%d dump(s) over %d hp drop(s): never conjured out of a turn nothing "
      .. "hurt", #L.dumps, L.hurts))
    H.log(string.format("[result] e%d as Umaro: %d action(s), %d provoked "
      .. "non-Fight; arms seen: %s; provoked arms: %s", SUBJ, #L.windows,
      L.provokedSpecial, hist(seen), hist(prov)))
    H.screenshot("retaliate_umaro")
  end),
})
