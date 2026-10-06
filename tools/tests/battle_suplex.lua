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
-- picked with the d-pad and A; the bench is deferred with X.  The battle is
-- then fled (L+R), or won through the menus by the library driver if it
-- cannot be fled.  No state is written.
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
H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/gau_joined.mss.lua"),
  H.waitFrames(20),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the Veldt"),
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      flip = not flip
      H.setPad({ [flip and "left" or "right"] = true })
    end),
  }, "a Veldt encounter fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  H.waitFrames(90),
  H.call(function()
    for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == 0x05 then sabinE = e end end
    H.assertEq(sabinE ~= nil, true, "SABIN is in the battle party")
    for s = 0, 5 do
      H.assertEq(H.readWord(0x57C0 + s * 2) ~= GHOSTTRAIN, true,
        string.format("slot %d is not the Ghost Train", s))
    end
    arm()
  end),
  (function()
    local t, btn = 0, {}
    return H.driveUntil(function()
      return #gateHits > 0 or not H.battleLoadStarted()
    end, 20000, {
      H.call(function()
        t = t + 1
        if t % 12 == 0 then btn = pulse() end
        H.setPad(t % 12 < 4 and btn or {})
      end),
    }, "SABIN's Suplex lands on a Veldt monster")
  end)(),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    disarm()
    H.log(string.format("[suplex] Suplex writes %d, gate hits %d (first on y=$%02X species $%04X), kill hook %d",
      spellWrites, #gateHits, gateHits[1] and gateHits[1].y or 0xFF,
      gateHits[1] and gateHits[1].species or 0xFFFF, kills))
    H.assertEq(spellWrites >= 1, true, "the Suplex executed ($3410 <- $5f)")
    H.assertEq(#gateHits >= 1, true, "Ot6SuplexTrain was consulted on the Suplex's hit")
    H.assertEq(gateHits[1].species ~= GHOSTTRAIN, true, "on a monster that is not the Ghost Train")
    H.assertEq(kills, 0, "Ot6SuplexTrainKill never ran: a Suplex on another monster is untouched")
  end),
  (function()
    local n, refusedN, F = 0, 0, nil
    return H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(function()
        n = n + 1
        refusedN = ((H.readByte(0x00B1) & 0x02) ~= 0) and refusedN + 1 or 0
        if F == nil and n < 1200 and refusedN < 60 then
          H.setPad({ l = true, r = true })
        else
          F = F or H.newFightDriver("suplex-win", { items = true, tactical = true, healer = 2 })
          F.frame()
        end
      end),
    }, "the battle resolved")
  end)(),
  H.call(function() H.setPad({}) end),
})
