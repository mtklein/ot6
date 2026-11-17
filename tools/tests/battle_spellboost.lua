-- @suite slow
-- battle_spellboost.lua -- a spell's boost is the one its list showed when it was picked (#555).
--
-- The owner, playing v0.47 after Vargas: "i just tried to boost terra up to fire 3 with two BP but she cast
-- fire 2 and used one".  Her list said Fire 3, 51 MP, at two points.  At the target select, L and R are FF6's
-- keys for spreading a spell over a group (a spell whose targeting has MANUAL and MULTI_TARGET: Fire, Ice,
-- Bolt, Cure...), and OT6's boost took the same keys: spreading Fire 3 with L also took a point back, so Fire 2
-- was cast for one point while the list, still on screen, said Fire 3 and 51 (lab, v0.47's ROM:
-- build/attempts/wt/v048-spellboost/v047b_H.log).  Spread with R, it raised the boost a point the same way,
-- with the list still showing the lower tier and price.  Now the boost of an action picked from a list does not
-- move at its target select (Ot6Boost): L and R there spread the spell and nothing else, and on a target select
-- that has no spread they buzz, as a refused boost does.  An action picked straight off the command window
-- (Fight) has no list, and R at its target select still raises its boost.
--
-- Played: Continue ultros-won-v1 (TERRA with Fire and Cure and a pool that pays Fire 3, at Esper Mountain),
-- pace into random battles beside it, and play these through the real menu (H.kitBattle), each in a battle
-- of its own turn, banking points by Defending first:
--   1. the owner's turn: Fire picked at 2 points (the list shows Fire 3 and its price, white), then one L at
--      the target select, which spreads it over the monsters: the boost stays 2, Fire 3 is cast, the MP charged
--      is the price the list showed, the bank pays 2;
--   2. Fire picked at 1 point (Fire 2), then one R at the target select (a spread again): the boost stays 1,
--      Fire 2 is cast for the list's price and 1 point;
--   3. Cure picked at 1 point (Cure 2) on an ally, then R at the target select: stays 1, Cure 2 cast, the
--      list's price, 1 point;
--   4. Fight at 1 point, R at its target select: the boost rises to 2 (the command window's pick keeps L/R).
-- What the list showed is read at the pick (the row's price byte, the one cell the drawn number, the grey,
-- the confirm and the charge read; Ot6FoldPrices) and what was cast and charged at the action (the queued
-- command and attack at Ot6ActionEnd, the MP pool and the bank around it).  Nothing is written.
-- @checkpoint ultros-won-v1
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local TERRA = 0
local CMD_FIGHT, CMD_MAGIC = 0x00, 0x02
local FIRE, FIRE2, FIRE3, CURE, CURE2 = 0x00, 0x05, 0x09, 0x2D, 0x2E
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function seat()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then return s end end
end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function rowCell(s, id)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[s] + i * 4
    if H.readByte(a) == id then return a end
  end
end

local CASES = {
  { name = "owner: Fire 3 picked, L spreads it", entry = { who = TERRA, cmd = CMD_MAGIC, spell = FIRE, boost = 2,
      lowerTo = 1, tgtPresses = 1 }, list = FIRE, pend = 2, cast = FIRE3, spent = 2 },
  { name = "Fire 2 picked, R spreads it", entry = { who = TERRA, cmd = CMD_MAGIC, spell = FIRE, boost = 1,
      bank = 2, raiseTo = 2, tgtPresses = 1 }, list = FIRE, pend = 1, cast = FIRE2, spent = 1 },
  { name = "Cure 2 picked on an ally, R at the target", entry = { who = TERRA, cmd = CMD_MAGIC, spell = CURE,
      boost = 1, bank = 2, raiseTo = 2, tgtPresses = 1, ally = true }, list = CURE, pend = 1, cast = CURE2,
      spent = 1 },
  { name = "Fight at 1 point, R at its target", entry = { who = TERRA, cmd = CMD_FIGHT, boost = 1, bank = 2,
      raiseTo = 2, tgtPresses = 1 }, pend = 2, fight = true, spent = 2 },
}

local case, ci, rec = nil, 1, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local watching = false

local function arm()
  -- the action begins: ExecCmd, x = the actor's entity offset (a counter is not hers)
  emu.addMemoryCallback(function()
    local s = seat()
    -- (only once the case's own pick reached its target select: the Defends that bank its points run first)
    if not watching or rec == nil or rec.tgtPend == nil or rec.mp0 ~= nil or s == nil then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= s * 2 or (H.readByte(0xB1) & 1) == 1 or H.readByte(0xB5) == 0x12 then return end
    rec.mp0, rec.bank0, rec.pend0, rec.f0 = mp(s), bank(s), pend(s), H.frame
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"))
  -- and ends: what was queued, before the charge
  emu.addMemoryCallback(function()
    local s = seat()
    if not watching or rec == nil or rec.mp0 == nil or rec.ended ~= nil or s == nil then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= s * 2 then return end
    rec.ended, rec.cmd, rec.atk, rec.pendEnd = H.frame, H.readByte(0x3A7C), H.readByte(0x3A7D), pend(s)
  end, emu.callbackType.exec, H.sym("Ot6ActionEnd"))
end

local function resolved()
  if rec == nil or rec.ended == nil or H.frame <= rec.ended + 30 then return false end
  if rec.mp1 == nil then
    local s = seat()
    rec.mp1, rec.bank1 = mp(s), bank(s)
  end
  return true
end

local function start()
  case = CASES[ci]
  rec = { name = case.name }
  plan = { case.entry }
  H.freshKitEntries(plan)
  local s = seat()
  H.log(string.format("[spellboost] case %d (%s): TERRA seat %s, MP %d, bank %d", ci, case.name, tostring(s),
    s and mp(s) or -1, s and bank(s) or -1))
end

local function onList(p, a)
  if p ~= case.entry then return end
  local c = rowCell(a, case.list)
  rec.listPend, rec.listCost, rec.listGrey = pend(a), H.readByte(c + 3), (H.readByte(c + 1) & 0x80) ~= 0
  H.log(string.format("[spellboost] f%d at the list: pending %d, the row's price %d (%s), MP %d", H.frame,
    rec.listPend, rec.listCost, rec.listGrey and "grey" or "white", mp(a)))
  if not rec.shotList then rec.shotList = true; H.screenshot(string.format("spellboost_%d_list", ci)) end
end
local function onTarget(p, a)
  if p ~= case.entry then return end
  rec.tgtPend, rec.spread = pend(a), H.readByte(0x7B7F)
  local c = case.list and rowCell(a, case.list)
  rec.tgtCost = c and H.readByte(c + 3)
  H.log(string.format("[spellboost] f%d at the target select after %d %s press(es): pending %d, spread %d, "
    .. "the row's price %s", H.frame, p.rPresses or 0, p.raiseTo and "R" or "L", rec.tgtPend, rec.spread,
    tostring(rec.tgtCost)))
  H.screenshot(string.format("spellboost_%d_target", ci))
end

local function judge()
  local r = rec
  H.log(string.format("[spellboost] case %d: began at f%s pending %d bank %d MP %d; ended cmd $%02X attack $%02X; "
    .. "MP %d -> %d, bank %d -> %d", ci, tostring(r.f0), r.pend0, r.bank0, r.mp0, r.cmd, r.atk, r.mp0, r.mp1,
    r.bank0, r.bank1))
  H.assertEq(r.tgtPend, case.pend, string.format("case %d (%s): the pending boost at the target select", ci,
    case.name))
  H.assertEq(r.pend0, case.pend, string.format("case %d: the action began at the boost it was confirmed with", ci))
  H.assertEq(r.bank0 - r.bank1, case.spent, string.format("case %d: the bank paid %d point(s)", ci, case.spent))
  if case.fight then
    H.assertEq(r.cmd, CMD_FIGHT, "case 4: a Fight ran")
    return
  end
  H.assertEq(r.listPend, case.pend, string.format("case %d: the list was read at the boost cast", ci))
  H.assertEq(r.listGrey, false, string.format("case %d: the row was white (payable) at the pick", ci))
  H.assertEq(r.tgtCost, r.listCost, string.format("case %d: the target select left the row's price as the "
    .. "list showed it", ci))
  H.assertEq(r.cmd, CMD_MAGIC, string.format("case %d: a Magic ran", ci))
  H.assertEq(r.atk, case.cast, string.format("case %d: the tier the list showed was cast ($%02X)", ci, case.cast))
  H.assertEq(r.mp0 - r.mp1, r.listCost, string.format("case %d: the MP charged is the price the list showed", ci))
  if ci == 1 then
    H.assertEq(r.spread, 1, "case 1: the L spread Fire 3 over the monsters (the spread is the key's use there)")
  end
end

local tries = 0
H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("ultros-won-v1"),
  H.call(function() arm(); start() end),
  H.driveUntil(function() return ci > #CASES end, 880000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.paceToEncounter("spellboost", 0) }, {}),
    H.call(function() watching = true end),
    H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
      onTarget = onTarget, planDone = resolved }),
    H.call(function()
      if resolved() then
        judge()
        H.log(string.format("[spellboost] case %d PASSED", ci))
        ci = ci + 1
        tries = 0
        if ci <= #CASES then start() end
      else
        tries = tries + 1
        H.log(string.format("[spellboost] case %d: the battle ended before the action resolved (try %d): again",
          ci, tries))
        H.assertEq(tries <= 6, true, "each case resolves within six battles")
        start()
      end
    end),
    H.cond(function() return H.battleLoadStarted() and ci > #CASES end, { H.kitBattle({}, {}) }, {}),
  }, "the four cases"),
})
