-- @suite savestate=train_b68_entry
-- battle_suplextrain.lua -- SABIN's Suplex on the Ghost Train wins (#410).
--
-- FF6's best-known gag, made true in OT6: a landed Suplex (attack $5f) on
-- the Ghost Train (species $0106) deals the train's whole current HP
-- (Ot6SuplexTrain / Ot6SuplexTrainKill, ot6_break.asm, from Ot6HitJoin).
-- battle_suplex.lua is the control: a Suplex on any other monster is
-- untouched.
--
-- The fixture is train_b68_entry, the corridor before the smokestack switch
-- (gen_sabin_train's capture).  The suite walks to the switch, pulls it, and
-- in battle 68 opens SABIN's real Blitz menu and picks Suplex with the d-pad
-- and A; CYAN's and SHADOW's menus are deferred with X.  No state is written.
--
-- Asserted:
--   1. the Suplex executed: InitTarget_02 wrote $5f to $3410 ("last spell
--      used") for the action;
--   2. Ot6SuplexTrainKill ran exactly once, on the train's entity, with the
--      train's HP above 0 going in;
--   3. the train is at 0 HP within the same action (the killing hit is the
--      Suplex: $3410 still reads $5f when the HP word reaches 0), and the
--      battle ends won, the party standing.
local H = dofile("tools/tests/lib/ot6.lua")

local GHOSTTRAIN, SUPLEX = 0x0106, 0x5F
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, CMDROW = 0x202E, 0x4005, 0x890F
local BLCOL, BLROW = 0x8963, 0x8967
local function MHP(s) return 0x3BFC + s * 2 end

local gSlot, sabinE = nil, nil
local spellWrites, kills, cast = 0, {}, false
local killHP, deadSkill, suplexAt = nil, nil, nil
local refs = {}

local function arm()
  refs.spell = emu.addMemoryCallback(function(_, v)
    if v == SUPLEX then
      spellWrites = spellWrites + 1
      suplexAt = suplexAt or H.frame
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  refs.kill = emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    kills[#kills + 1] = { y = y, hp = H.readWord(0x3BF4 + y), frame = H.frame }
  end, emu.callbackType.exec, H.sym("Ot6SuplexTrainKill"), H.sym("Ot6SuplexTrainKill"))
end
local function disarm()
  emu.removeMemoryCallback(refs.spell, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.removeMemoryCallback(refs.kill, emu.callbackType.exec,
    H.sym("Ot6SuplexTrainKill"), H.sym("Ot6SuplexTrainKill"))
end

local function rowOf(actor, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmd then return i end
  end
  return nil
end

-- one pulse of the menu hand: SABIN picks Suplex, everyone else is deferred
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

local function trainHP() return H.readWord(MHP(gSlot)) end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/train_b68_entry.mss.lua"),
  H.waitFrames(30),
  H.navTo(32, 7, { maxFrames = 8000, playBattles = "tactical" }),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "the smokestack switch -> battle 68")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    for s = 0, 5 do if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then return true end end
    return false
  end, 1200, "the Ghost Train in the formation", 5),
  H.call(function()
    for s = 0, 5 do if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then gSlot = s end end
  end),
  -- the battle table fills the HP words late in setup: wait for the train's
  H.waitUntil(function() return trainHP() > 0 end, 1200, "the train's HP word is live", 5),
  H.call(function()
    for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == 0x05 then sabinE = e end end
    H.assertEq(sabinE ~= nil, true, "SABIN is in the battle party")
    H.log(string.format("[suplextrain] train in slot %d at %d HP; SABIN e%d mp %d",
      gSlot, trainHP(), sabinE, H.readWord(0x3C08 + sabinE * 2)))
    arm()
  end),
  (function()
    local t, btn = 0, {}
    return H.driveUntil(function()
      if #kills > 0 and trainHP() == 0 and deadSkill == nil then deadSkill = H.readByte(0x3410) end
      -- done when the train falls, or 900 frames after the Suplex began
      -- (its action has long resolved by then) with the train standing
      return (#kills > 0 and trainHP() == 0)
          or (suplexAt ~= nil and H.frame - suplexAt > 900)
    end, 20000, {
      H.call(function()
        t = t + 1
        if t % 12 == 0 then btn = pulse() end
        H.setPad(t % 12 < 4 and btn or {})
      end),
    }, "battle 68: SABIN's Suplex lands")
  end)(),
  H.call(function()
    H.setPad({})
    disarm()
    H.log(string.format("[suplextrain] Suplex writes %d, kill hook %d (y=%s, train HP in %s), " ..
      "train HP now %d, $3410 at 0 HP $%02X", spellWrites, #kills,
      kills[1] and string.format("$%02X", kills[1].y) or "-",
      kills[1] and tostring(kills[1].hp) or "-", trainHP(), deadSkill or 0xFF))
    H.assertEq(spellWrites >= 1, true, "the Suplex executed ($3410 <- $5f)")
    H.assertEq(#kills, 1, "Ot6SuplexTrainKill ran once")
    H.assertEq(kills[1].y, 8 + gSlot * 2, "on the train's entity")
    H.assertEq(kills[1].hp > 0, true, "with the train standing going in")
    H.assertEq(deadSkill, SUPLEX, "the hit that took the train to 0 HP was the Suplex")
  end),
  (function()
    local t = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.battleLoadStarted()
    end, 30000, {
      H.call(function()
        t = t + 1
        H.setPad((H.dialogWaiting() or H.battleLoadStarted()) and t % 16 < 4 and { "a" } or {})
      end),
    }, "battle 68 won: control back")
  end)(),
  H.call(function()
    H.assertPartyStanding("after the Suplex")
    H.log("[suplextrain] PASS-path: the Ghost Train fell to one Suplex")
  end),
})
