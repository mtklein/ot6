-- @suite savestate=camp_cleared slow
-- battle_retaliate_script.lua -- #238: a character an AI SCRIPT drives is
-- one the player is not driving, so the retaliation rule holds for it: it
-- banks BP normally and, once something has hurt it, dumps the bank on its
-- next Fight.  battle_retaliate.lua proves the rule for Berserk; this file
-- proves it for the script-driven case, on the route, with nothing staged.
--
-- THE GAP, measured before it was closed (build/lab/scripted/red-script.log,
-- retained as build/attempts/<branch>/lab/scripted/red-script.log): every
-- writer of OT6_UNCTL was RandCharAction's, and a scripted character never
-- passes RandCharAction -- QueueAction sends it to ExecMonsterAction first
-- -- so CYAN in the Doma courtyard defence logged `flag=$00` at all five
-- of his scripted actions over two waves, his bank read 1 2 1 2 3 at his
-- action ends with every one of them the gain arm, the soldiers cut him
-- 358 -> 324 and 358 -> 322, and his provoked Fight (`f5093 e2 bank=3
-- pending=0 hp=322 line=358 -> PROVOKED`) resolved with pending 0:
--     got 0 ($0), want 3 ($3)
--
-- WHAT IS PLAYED, AND NOTHING IS STAGED.  camp_cleared is SABIN at (8,29) on
-- map 119 with CYAN (the warrior NPC, object 18) fighting off Imperial
-- troops.  Facing CYAN and pressing A runs the courtyard defence: three
-- fights (battle 13, 13, 14), in each of which CYAN stands in the party as
-- an AI-scripted character (CharAI $05/$06 cyan_imp_camp, script
-- AIScript::_368: `attack DISPATCH, BATTLE, BATTLE`, and a one-in-three
-- Fight counter when hit).  The player-driven pair, SABIN and SHADOW, hand
-- every turn straight back, so the fight is CYAN's to carry and the
-- soldiers' to hurt him in.  The script's choice, the soldiers' targets,
-- the swing count, the hit count and the charge are all read out of the
-- machine.  The talk-to-CYAN driver is gen_sabin_escape.lua's: hold
-- bfsPath's first step toward him through the courtyard's floor-trigger
-- flap, then face-and-A until a battle loads.
--
-- WHEN THE MEASUREMENT IS COMPLETE: a PROVOKED Fight of CYAN's has resolved
-- -- his plain Fight (command $00, not the scripted counter, which executes
-- through ExecRetal and is guarded out by design) queued while he stood
-- below the hp line his own last turn drew, with a pip in the bank.  That
-- condition is decided by the machine's own cells and not by the dump, so a
-- ROM without the flag reaches the verdict and fails AT the assertion
-- rather than timing out.  A seed on which the soldiers never provoke him
-- across the three waves runs out the budget instead, which the segment
-- runner classifies as seed-dependent and retries at the next shift.
--
-- EVERY EXPECTED NUMBER IS DERIVED from the built ROM, never pinned, the
-- same way battle_retaliate.lua derives them.
local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/camp_cleared.mss.lua"

local CHAR_CYAN = 0x02
local CYAN_OBJ = 18                     -- map 119's warrior NPC (gen_sabin_escape)
local WAVES = { 0x0034, 0x0035, 0x0036 } -- the three fight switches, in order
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD = 0x01, 0x05
local BANK_CAP = 5                      -- Ot6ActionEnd's ceiling
local FACE = { up = 0, right = 1, down = 2, left = 3 }

local function hp(e)     return H.readWord(0x3BF4 + e * 2) end
local function bp(e)     return H.readByte(0x3E9C + e * 2) end
local function pend(e)   return H.readByte(0x3E9D + e * 2) end
local function charOf(e) return H.readByte(0x3ED8 + e * 2) end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086A + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086D + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087F + H.readWord(0x0803)) end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("e%d c$%02X %d/%d bp%d", e, charOf(e), hp(e),
      H.readWord(0x3C1C + e * 2), bp(e))
  end
  return table.concat(p, " | ")
end

-- ---------------------------------------------------------- the machine --
local D = {}                            -- base, perBp, cap, unctl, mark, hands
local SUBJ = nil                        -- CYAN's entity index, read at battle up

-- the run's ledger
local L = {
  scriptActs = 0,                       -- ExecMonsterAction with x = CYAN
  randActs = 0,                         -- RandCharAction with x = CYAN
  flagAtFirstAct = nil,                -- OT6_UNCTL's CYAN bit, one frame after his first scripted act
  fights = {},                          -- every plain Fight of his: {f, pending, bank, hp, mark, provoked}
  counters = 0,                         -- Ot6FightBoost reached under $b1.0
  ends = {},                            -- every Ot6ActionEnd for him: {f, bank, pending}
  dumps = {},                           -- every nonzero pending write for him
  hurts = 0,
  markWrites = {},
  charges = {},
  waves = 0,                            -- battles seen
  markAtStart = 0,
}
-- the ONE action under the microscope: the first provoked plain Fight.
-- Opened at Ot6FightBoost (before the dump is or is not armed), closed by
-- SaveForMimic.
local W = { open = false, closed = false, ended = false, swings = 0, hits = 0,
            hand = { [0] = 0, [1] = 0 }, a70 = 0, pendAfter = 0 }

local function romBytes(base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = H.readRomByte(base + i) end
  return t
end

-- ------------------------------------------------------- the observers --
-- Installed once, at the first battle up; SUBJ is re-read at every battle up.
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local sEMA, sRCA = H.sym("ExecMonsterAction"), H.sym("RandCharAction")
  local sFB, sAE = H.sym("Ot6FightBoost"), H.sym("Ot6ActionEnd")
  local sWC, sHJ = H.sym("Ot6WeaponClass"), H.sym("Ot6HitJoin")
  local sSF = H.sym("SaveForMimic")

  local function xIsSubj()
    return SUBJ ~= nil and (emu.getState()["cpu.x"] & 0xFFFF) == SUBJ * 2
  end
  local function xIsSubjHand()
    return SUBJ ~= nil and ((emu.getState()["cpu.x"] & 0xFFFE) == SUBJ * 2)
  end

  -- who chose his action: the script, or vanilla's random chooser
  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    L.scriptActs = L.scriptActs + 1
    H.log(string.format("[script] f%d ExecMonsterAction for e%d (act %d) "
      .. "bank=%d pending=%d hp=%d flag=$%02X", H.frame, SUBJ,
      L.scriptActs, bp(SUBJ), pend(SUBJ), hp(SUBJ), H.readByte(D.unctl)))
  end, emu.callbackType.exec, sEMA, sEMA)
  emu.addMemoryCallback(function()
    if xIsSubj() then L.randActs = L.randActs + 1 end
  end, emu.callbackType.exec, sRCA, sRCA)

  -- every plain Fight of his, with the machine's own "provoked" reading
  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    if (H.readByte(0xB1) & 0x01) ~= 0 then
      L.counters = L.counters + 1
      return                              -- the scripted counter: guarded out
    end
    local rec = { f = H.frame, pending = pend(SUBJ), bank = bp(SUBJ),
      hp = hp(SUBJ), mark = L.markAtStart }
    rec.provoked = rec.mark > rec.hp and rec.bank > 0
    L.fights[#L.fights + 1] = rec
    H.log(string.format("[fight] f%d e%d bank=%d pending=%d hp=%d line=%d "
      .. "-> %s", H.frame, SUBJ, rec.bank, rec.pending, rec.hp, rec.mark,
      rec.provoked and "PROVOKED" or "unprovoked"))
    if rec.provoked and not W.open and not W.closed then
      W.open, W.rec = true, rec
    end
  end, emu.callbackType.exec, sFB, sFB)

  -- every write to the swing count: the arming value is the frame's
  -- MAXIMUM (the loop decrements it; battle_retaliate.lua's finding)
  emu.addMemoryCallback(function(_, v)
    if v == 0 or v == 0xFF then return end
    if W.open and not W.closed and v > W.a70 then W.a70 = v end
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)

  -- the dump itself: a nonzero pending byte for an actor nobody boosted.
  -- The range spans all four pending bytes, and the bank bytes between
  -- them, so the address is filtered to HIS pending byte.
  emu.addMemoryCallback(function(addr, v)
    if v == 0 or v == 0xFF or SUBJ == nil or addr ~= 0x7E3E9D + SUBJ * 2
       or not H.battleLoadStarted() then return end    -- $ff = the end-of-battle clear
    L.dumps[#L.dumps + 1] = { f = H.frame, v = v, bank = bp(SUBJ),
      hp = hp(SUBJ), mark = L.markAtStart }
    if W.open and not W.closed then W.pendAfter = v end
    H.log(string.format("[dump] f%d e%d pending <- %d off a bank of %d "
      .. "(hp %d against a line of %d)", H.frame, SUBJ, v, bp(SUBJ),
      hp(SUBJ), L.markAtStart))
  end, emu.callbackType.write, 0x7E3E9D, 0x7E3E9D + 6)

  -- Ot6ActionEnd, at its entry: the bank and pending it FINDS.  What it
  -- leaves is read on the next frame start (SaveForMimic runs before it on
  -- the action-end path, battle_main.asm:324/344, so the window's close
  -- cannot be where the after-bank is read).
  emu.addMemoryCallback(function()
    if not xIsSubj() then return end
    local b, p = bp(SUBJ), pend(SUBJ)
    L.ends[#L.ends + 1] = { f = H.frame, bank = b, pending = p }
    if p > 0 then
      L.charges[#L.charges + 1] = { f = H.frame, p = p, bank = b }
    end
    if W.open and W.closed and not W.ended then
      W.ended, W.endF, W.bankAtEnd, W.chargeP = true, H.frame, b, p
    end
    H.log(string.format("[bank] f%d e%d Ot6ActionEnd bank=%d pending=%d -> %s "
      .. "(hp %d)", H.frame, SUBJ, b, p, p > 0 and "CHARGE" or "gain", hp(SUBJ)))
  end, emu.callbackType.exec, sAE, sAE)

  emu.addMemoryCallback(function()
    if not W.open or W.closed or not xIsSubjHand() then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    W.swings = W.swings + 1
    W.hand[x & 1] = W.hand[x & 1] + 1
  end, emu.callbackType.exec, sWC, sWC)
  emu.addMemoryCallback(function()
    if not W.open or W.closed then return end
    if (emu.getState()["cpu.y"] & 0xFFFF) < 8 then return end
    W.hits = W.hits + 1
  end, emu.callbackType.exec, sHJ, sHJ)
  emu.addMemoryCallback(function()
    if W.open and not W.closed then W.closed = true end
  end, emu.callbackType.exec, sSF, sSF)

  -- his hurt line, from its writes; and hp drops, flag, and the line as
  -- it stood at the start of the frame
  local lastHp, lastFlag = nil, nil
  emu.addEventCallback(function()
    if SUBJ == nil or not H.battleLoadStarted() then lastHp = nil; return end
    local h = hp(SUBJ)
    if lastHp ~= nil and h < lastHp then L.hurts = L.hurts + 1 end
    lastHp = h
    L.markAtStart = H.readWord(D.mark)
    local flag = H.readByte(D.unctl)
    if flag ~= lastFlag then
      H.log(string.format("[flag] f%d OT6_UNCTL $%02X -> $%02X (e%d's bit $%02X)",
        H.frame, lastFlag or 0, flag, SUBJ, H.readByte(0x3018 + SUBJ * 2)))
      lastFlag = flag
    end
    if L.scriptActs >= 1 and L.flagAtFirstAct == nil then
      L.flagAtFirstAct = (flag & H.readByte(0x3018 + SUBJ * 2)) ~= 0
    end
    if W.ended and W.bankAfter == nil and H.frame ~= W.endF then
      W.bankAfter = bp(SUBJ)
      H.log(string.format("[bank] f%d e%d after the action: bank=%d (found %d, "
        .. "charged %d)", H.frame, SUBJ, W.bankAfter, W.bankAtEnd, W.chargeP))
    end
  end, emu.eventType.startFrame)
  emu.addMemoryCallback(function(addr)
    if SUBJ == nil or D.mark == nil or addr < D.mark or addr > D.mark + 1 then
      return
    end
    L.markWrites[#L.markWrites + 1] = { f = H.frame, v = H.readWord(D.mark) }
  end, emu.callbackType.write, 0x7E0000 + (H.sym("OT6_HPMARK") & 0xFFFF),
    0x7E0000 + (H.sym("OT6_HPMARK") & 0xFFFF) + 7)
end

-- ------------------------------------------------------------ the drive --
local function measured()
  return W.closed and W.bankAfter ~= nil
end

local battleUp, wavesDone = false, false
local phase = 0
local function fieldFrame()
  if H.dialogWaiting() then H.setPad(phase < 4 and { a = true } or {}); return end
  local nextWave = nil
  for i, s in ipairs(WAVES) do
    if sw(s) == 0 then nextWave = i; break end
  end
  if nextWave == nil then
    if not wavesDone then
      wavesDone = true
      H.log(string.format("[scripted] f%d all three waves fought and nothing "
        .. "provoked him: idling out the budget (seed-dependent)", H.frame))
    end
    H.setPad({})
    return
  end
  local cx, cy = objX(CYAN_OBJ), objY(CYAN_OBJ)
  local adjacent = math.abs(cx - H.fieldX()) + math.abs(cy - H.fieldY()) == 1
  if not adjacent then
    local best, bd = nil, nil
    for _, d in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
      local p = H.bfsPath(cx + d[1], cy + d[2])
      if p and (not bd or #p < bd) then best, bd = p, #p end
    end
    local mv = best and best[1] or nil
    H.setPad(mv and { [H.movePress(mv)] = true } or {})
    return
  end
  local dx, dy = cx - H.fieldX(), cy - H.fieldY()
  local dir = dx == 1 and "right" or dx == -1 and "left"
           or dy == 1 and "down" or "up"
  if facing() ~= FACE[dir] then H.setPad({ [dir] = true })
  else H.setPad(phase < 4 and { a = true } or {}) end
end

local function battleFrame()
  if not battleUp then
    battleUp = true
    L.waves = L.waves + 1
    SUBJ = nil
    for e = 0, 3 do
      if charOf(e) == CHAR_CYAN then SUBJ = e end
    end
    installObservers()
    H.log(string.format("[wave %d] f%d battle up: %s; CYAN is e%s",
      L.waves, H.frame, partyLine(), tostring(SUBJ)))
    W.open, W.closed, W.ended = false, false, false
  end
  -- everyone the player still drives hands the turn straight back
  if H.readByte(MENU) == 0 then
    H.setPad(phase < 4 and { a = true } or {})
    return
  end
  if phase >= 4 then H.setPad({}); return end
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}); return end
  H.setPad(st == ST_CMD and { x = true } or { b = true })
end

H.run({ maxFrames = 60000, retries = 3 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),

  -- the ROM's own arithmetic, before a single button is pressed
  H.call(function()
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
    H.log(string.format("[rom] $3a70 = %d + %d*bp; spend cap %d; OT6_UNCTL "
      .. "$%06X; hurt lines at $%06X", D.base, D.perBp, D.cap, D.unctl,
      D.markBase))
    H.assertEq(H.mapId() & 0x1FF, 119, "camp_cleared boots on map 119")
    H.assertEq(sw(WAVES[1]), 0, "and the courtyard defence has not begun")
    H.log(string.format("[seed] SABIN at (%d,%d), CYAN (obj %d) at (%d,%d)",
      H.fieldX(), H.fieldY(), CYAN_OBJ, objX(CYAN_OBJ), objY(CYAN_OBJ)))
  end),

  -- the courtyard defence, wave by wave, until a provoked Fight resolves
  H.driveUntil(measured, 45000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.battleLoadStarted() then
        if SUBJ ~= nil then D.mark = D.markBase + SUBJ * 2 end
        battleFrame()
      else
        if battleUp then
          battleUp = false
          H.log(string.format("[wave %d] f%d battle over: %s", L.waves,
            H.frame, partyLine()))
        end
        fieldFrame()
      end
    end),
  }, "a provoked scripted Fight of CYAN's resolves"),

  -- ================================================================== --
  -- the verdict
  -- ================================================================== --
  H.call(function()
    H.setPad({})
    H.log(string.format("[ledger] waves %d; script acts %d; RandCharAction "
      .. "%d; plain Fights %d; counters %d; hp drops %d; dumps %d; charges %d",
      L.waves, L.scriptActs, L.randActs, #L.fights, L.counters, L.hurts,
      #L.dumps, #L.charges))
    local banks = {}
    for _, e in ipairs(L.ends) do
      banks[#banks + 1] = string.format("%d%s", e.bank, e.pending > 0 and "*" or "")
    end
    H.log("[ledger] bank at each of his action ends (* = charged): "
      .. table.concat(banks, " "))

    -- who drove him: the script, every time, and vanilla's random chooser never
    H.assertEq(L.scriptActs >= 1, true, string.format(
      "the SCRIPT chose CYAN's actions (ExecMonsterAction with x = e%d, %d "
      .. "time(s))", SUBJ or -1, L.scriptActs))
    H.assertEq(L.randActs, 0,
      "and RandCharAction never did: this is the path #236 could not see")

    -- the claim, FIRST: his provoked Fight dumped
    local r = W.rec
    H.assertEq(r ~= nil and W.closed, true, "a provoked plain Fight resolved")
    local want = math.min(r.bank, D.cap)
    H.assertEq(W.pendAfter, want, string.format(
      "his provoked Fight (f%d: hp %d below a line of %d, bank %d) carried "
      .. "the dump: pending %d = min(bank, cap %d), and NOT the 0 a "
      .. "scripted character was left with before #238", r.f, r.hp, r.mark,
      r.bank, want, D.cap))
    H.assertEq(L.flagAtFirstAct, true,
      "OT6_UNCTL carried his bit from his first scripted action on: the "
      .. "flag is set where the script chooses for him")

    -- the swings the dump bought, and the pips it cost
    local wantA70 = D.base + D.perBp * want
    H.assertEq(W.a70, wantA70, string.format(
      "the provoked swing queued $3a70 = %d (ROM: %d + %d*%d), and NOT the "
      .. "%d an unboosted Fight queues", wantA70, D.base, D.perBp, want,
      D.base))
    local wantPasses = H.fightPasses(want)
    H.assertEq(W.swings, wantPasses, string.format(
      "the multi-attack loop ran %d passes for the %d-pip dump, and NOT the "
      .. "%d an unboosted Fight runs", wantPasses, want, H.fightPasses(0)))
    H.assertEq(W.hand[0] == W.hand[1], true, string.format(
      "the passes alternate hands: %d main, %d off", W.hand[0], W.hand[1]))
    local c = H.readByte(0x3ED8 + SUBJ * 2)
    local rh = H.readByte(0x1600 + 37 * c + 0x1F)
    local lh = H.readByte(0x1600 + 37 * c + 0x20)
    D.hands = (H.isWeapon(rh) and 1 or 0) + (H.isWeapon(lh) and 1 or 0)
    if D.hands == 0 then D.hands = 1 end
    local main, off = H.fightHits(D.hands, want)
    H.assertEq(W.hits == 0 or W.hits == main + off, true, string.format(
      "the volley landed 0 or %d hits and nothing between (measured %d)",
      main + off, W.hits))
    H.assertEq(W.chargeP, want, string.format(
      "Ot6ActionEnd found exactly the %d pip(s) armed and took its CHARGE arm",
      want))
    H.assertEq(W.bankAfter, W.bankAtEnd - want, string.format(
      "the bank fell from %d to %d: the pips LEFT it, and NOT the %d the "
      .. "gain arm would have left", W.bankAtEnd, W.bankAfter,
      math.min(W.bankAtEnd + 1, BANK_CAP)))
    H.assertEq(#L.dumps <= L.hurts, true, string.format(
      "%d dump(s) over %d hp drop(s): a dump is never conjured out of a turn "
      .. "nothing hurt", #L.dumps, L.hurts))
    H.log(string.format("[result] CYAN e%d: bank %d -> %d; pending %d; $3a70 "
      .. "%d; %d passes (%d main, %d off); %d landed of a possible %d; %d hp "
      .. "drop(s), %d dump(s), %d scripted act(s) over %d wave(s)",
      SUBJ, W.bankAtEnd, W.bankAfter, want, W.a70, W.swings, W.hand[0],
      W.hand[1], W.hits, main + off, L.hurts, #L.dumps, L.scriptActs, L.waves))
    H.screenshot("retaliate_script_dump")
  end),
})
