-- @suite savestate=gau_joined
-- battle_suplex.lua -- the control for #410: a Suplex on any monster but
-- the Ghost Train is untouched.
--
-- Ot6SuplexTrain (ot6_break.asm) runs on every landed hit and hands the hit
-- to Ot6SuplexTrainKill only for attack $5f on species $0106.  Here SABIN
-- Suplexes a Veldt monster: the gate is consulted on the Suplex's hit (the
-- entry fires with $3410 = $5f) and the kill never runs.
--
-- The fixture is gau_joined (SABIN, CYAN, GAU on the Veldt).  A natural
-- encounter is walked into; SABIN's real Blitz menu is opened and Suplex
-- picked with the d-pad and A; every other window is the library fight
-- driver's, and encounters are fought until one Suplex has landed (a
-- body too heavy to throw takes none).  No state is written.
--
-- Asserted:
--   1. the Suplex executed ($3410 <- $5f);
--   2. Ot6SuplexTrain ran on a Suplex hit against a monster that is not the
--      Ghost Train (the gate was consulted, so its silence means something);
--   3. Ot6SuplexTrainKill never ran.
local H = dofile("tools/tests/lib/ot6.lua")

local GHOSTTRAIN, SUPLEX = 0x0106, 0x5F
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, CMDROW = 0x202E, 0x4005, 0x890F
local BLCOL, BLROW = 0x8963, 0x8967

local sabinE = nil
local inCmd = false
local throwable, fleeN = false, 0
local SUPLEX_MP = H.abilityCost(SUPLEX) or 13
local spellWrites, gateHits, kills, cast = 0, {}, 0, false
local refs = {}

local function arm()
  refs.spell = emu.addMemoryCallback(function(_, v)
    if v == SUPLEX then spellWrites = spellWrites + 1 end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  refs.gate = emu.addMemoryCallback(function()
    local s = emu.getState()
    local y = s["cpu.y"] & 0xFF
    if H.readByte(0x3410) == SUPLEX and y >= 8 then
      gateHits[#gateHits + 1] = { y = y, species = H.readWord(0x57C0 + (y - 8)) }
    end
  end, emu.callbackType.exec, H.sym("Ot6SuplexTrain"), H.sym("Ot6SuplexTrain"))
  refs.kill = emu.addMemoryCallback(function() kills = kills + 1 end,
    emu.callbackType.exec, H.sym("Ot6SuplexTrainKill"), H.sym("Ot6SuplexTrainKill"))
end
local function disarm()
  emu.removeMemoryCallback(refs.spell, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.removeMemoryCallback(refs.gate, emu.callbackType.exec,
    H.sym("Ot6SuplexTrain"), H.sym("Ot6SuplexTrain"))
  emu.removeMemoryCallback(refs.kill, emu.callbackType.exec,
    H.sym("Ot6SuplexTrainKill"), H.sym("Ot6SuplexTrainKill"))
end

local function rowOf(actor, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local function pulse()
  if H.readByte(MENU) == 0 then return {} end
  local actor, st = H.readByte(ACTOR), H.readByte(MSTATE)
  if actor ~= sabinE or cast then
    if st == ST_CMD then return { "x" } end
    return { "b" }
  end
  if st == ST_CMD then
    local want = rowOf(actor, CMD_BLITZ)
    assert(want, "SABIN has a Blitz row")
    local cur = H.readByte(CMDROW + actor) & 3
    if cur == want then return { "a" } end
    return { cur < want and "down" or "up" }
  end
  if st == ST_TOOLS then
    local row = nil
    for i = 0, 7 do if H.readByte(ITEMLIST + i * 3) == SUPLEX then row = i end end
    assert(row, "Suplex is in SABIN's Blitz list (learned at this fixture)")
    local wc, wr = row % 2, row // 2
    local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
    if cc ~= wc then return { wc > cc and "right" or "left" } end
    if cr ~= wr then return { wr > cr and "down" or "up" } end
    cast = true
    return { "a" }
  end
  return {}
end

local flip = false
-- One encounter: walk into it, SABIN Suplexes at his first window, the
-- library driver fights every other window to the end.  A Suplex that does
-- not land (a body too heavy to throw, or the pack dead first) consults
-- nothing, so encounters are taken until one Suplex hit has been seen.
local function encounter(k)
  local t, btn, F = 0, {}, nil
  return H.cond(function() return #gateHits == 0 end, {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 6000, "world control on the Veldt (encounter " .. k .. ")"),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}); return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, "a Veldt encounter fires (" .. k .. ")"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
    H.waitFrames(90),
    H.call(function()
      sabinE, cast, t, F, throwable, fleeN = nil, false, 0, nil, false, 0
      for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == 0x05 then sabinE = e end end
      H.assertEq(sabinE ~= nil, true, "SABIN is in the battle party")
      -- a body Suplex can throw: present, standing, and without the
      -- throw-immune bit ($3C80 bit 2, TargetEffect_30) -- many Veldt
      -- species carry it, and a Suplex at only those misses
      for s = 0, 5 do
        H.assertEq(H.readWord(0x57C0 + s * 2) ~= GHOSTTRAIN, true,
          string.format("slot %d is not the Ghost Train", s))
        if (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0
           and (H.readByte(0x3C80 + 8 + s * 2) & 0x04) == 0 then throwable = true end
      end
      H.log(string.format("[suplex] encounter %d: %s", k, throwable
        and "a throwable body stands -- SABIN Suplexes" or "every body is throw-immune -- fleeing"))
    end),
    H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
      H.call(function()
        t = t + 1
        F = F or H.newFightDriver("suplex-bench", { items = true, tactical = true, healer = 2 })
        -- SABIN Suplexes at every window until a Suplex has landed (one that
        -- picks only throw-immune bodies misses, TargetEffect_30), MP permitting
        if not throwable then
          -- nothing to throw here: run (L+R), the driver if it cannot
          fleeN = fleeN + 1
          if fleeN < 1200 and (H.readByte(0x00B1) & 0x02) == 0 then H.setPad({ l = true, r = true }); return end
        end
        local mine = throwable and H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == sabinE
          and #gateHits == 0 and H.readWord(0x3C08 + sabinE * 2) >= SUPLEX_MP
        if mine and H.readByte(MSTATE) == ST_CMD and not inCmd then cast, inCmd = false, true end
        if H.readByte(MSTATE) ~= ST_CMD then inCmd = false end
        if not mine then F.frame(); return end
        if t % 12 == 0 then btn = pulse() end
        H.setPad(t % 12 < 4 and btn or {})
      end),
    }, "encounter " .. k .. " fought out"),
    H.call(function()
      H.setPad({})
      H.log(string.format("[suplex] encounter %d: Suplex writes so far %d, gate hits %d", k,
        spellWrites, #gateHits))
    end),
  }, {})
end

local steps = {
  H.loadState("build/states/gau_joined.mss.lua"),
  H.waitFrames(20),
  H.call(function() arm() end),
}
for k = 1, 10 do steps[#steps + 1] = encounter(k) end
steps[#steps + 1] = H.call(function()
  disarm()
  H.log(string.format("[suplex] Suplex writes %d, gate hits %d (first on y=$%02X species $%04X), kill hook %d",
    spellWrites, #gateHits, gateHits[1] and gateHits[1].y or 0xFF,
    gateHits[1] and gateHits[1].species or 0xFFFF, kills))
  H.assertEq(spellWrites >= 1, true, "the Suplex executed ($3410 <- $5f)")
  H.assertEq(#gateHits >= 1, true, "Ot6SuplexTrain was consulted on a Suplex's hit (within 10 encounters)")
  H.assertEq(gateHits[1].species ~= GHOSTTRAIN, true, "on a monster that is not the Ghost Train")
  H.assertEq(kills, 0, "Ot6SuplexTrainKill never ran: a Suplex on another monster is untouched")
end)
H.run({ maxFrames = 300000 }, steps)
