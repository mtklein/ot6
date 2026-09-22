-- @manual
-- probe_summon_price.lua -- what does a boosted summon cost?
--
-- mp-economy.md: a summon is outside the command gate, so its boost buys
-- Ot6BoostDmg's x2/x4/x8 and its price escalates, min(99, base * 2.5^n)
-- (Ot6BoostPriceFor; Phoenix's base above 99 stands).  Ot6QueueFold's summon
-- arm re-prices the queued cast at queue time, but it tests `$3a7b < $1b`
-- (an esper index) while FixPlayerAttack has already added $36 to it
-- (CmdAttackOffsetTbl), so that arm may never run.  This measures what is
-- charged, not what the code says.
--
-- From fc_alcove: out onto the continent, pace to an encounter, everyone
-- Defends until the party member wearing the cheapest esper has 3 pips,
-- snapshot.  From it, boost 0, 1 and 3: R presses, Magic, UP into the esper
-- window, A, target select.  Observed, never written: every store to the
-- MP-cost queue $3620,y while $3a7a is $19 (GetMPCost's, then Ot6QueueFold's
-- if it re-prices), Ot6QueueFold's entry ($3a7a/$3a7b, pending), the esper
-- row's list cost byte at the confirm, and the caster's MP before the
-- confirm and after the action.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local BOOSTS = { 0, 1, 3 }
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC, ST_ESPER = 0x05, 0x27, 0x38, 0x0E, 0x16
local BANK, PEND, CURMP, MLISTPTR, STONE = 0x3E9C, 0x3E9D, 0x3C08, 0x302C, 0x3344
local CMD_MAGIC, CMD_SUMMON = 0x02, 0x19

local slot, snap, armed = nil, nil, nil
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function mp() return H.readWord(CURMP + slot * 2) end
local function espRowCost()
  local base = H.readWord(MLISTPTR + slot * 2)
  if base < 0x2000 or base > 0x2600 then return -1 end
  return H.readByte(base + 3)
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  emu.addMemoryCallback(function(addr, v)
    if armed == nil or armed.endF then return end
    if H.readByte(0x3A7A) ~= CMD_SUMMON then return end
    armed.stores[#armed.stores + 1] = string.format("$%04X<-%d (3a7b=$%02X)",
      addr & 0xFFFF, v, H.readByte(0x3A7B))
    armed.queued = v
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  local qf = H.sym("Ot6QueueFold")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    if H.readByte(0x3A7A) ~= CMD_SUMMON then return end
    armed.fold = string.format("Ot6QueueFold: 3a7a=$%02X 3a7b=$%02X pending=%d",
      H.readByte(0x3A7A), H.readByte(0x3A7B), H.readByte(PEND + slot * 2))
  end, emu.callbackType.exec, qf, qf)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) == slot * 2 and armed.queued then
      armed.endF, armed.mpEnd = H.frame, mp()
    end
  end, emu.callbackType.exec, ae, ae)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end
local function defendOthers(except)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

local phase, held = "idle", nil
local function decide(c)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= slot then return nil end
    if H.readByte(PEND + slot * 2) < c.boost then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(slot, CMD_MAGIC)
    local cur = H.readByte(CMDROW + slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "esper"
    return "a"
  end
  if phase == "esper" then
    if st == ST_CMD then return "a" end
    if st == ST_MAGIC then return "up" end        -- the top of the grid opens the esper row
    if st ~= ST_ESPER then return nil end
    c.rowCost, c.mp0, c.pendAtConfirm = espRowCost(), mp(), H.readByte(PEND + slot * 2)
    c.stores, armed = {}, c
    phase = "target"
    return "a"
  end
  if phase == "target" then
    if H.readByte(MENU) == 0 or a ~= slot then phase = "sent" return nil end
    if st == ST_ESPER then return "a" end
    if st ~= ST_TGT then return nil end
    phase = "confirmed"
    return "a"
  end
end

local function runCase(c)
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      tick, phase, held = 0, "boost", nil
    end),
    H.driveUntil(function() return phase == "sent" end, 3000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "summon at boost " .. c.boost),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 30 end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, "the summon resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      H.log(string.format("[summon] boost %d: pending at confirm %d; esper row list cost %d; "
        .. "cost queue %s; %s; MP %d -> %d (charged %d)", c.boost, c.pendAtConfirm, c.rowCost,
        table.concat(c.stores, " "), c.fold or "Ot6QueueFold not reached for $19",
        c.mp0, c.mpEnd or -1, c.mp0 - (c.mpEnd or c.mp0)))
    end),
  }
end

local results = {}
local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function() installObservers() end),
  H.navTo(8, 9, { maxFrames = 3000 }),
  H.driveUntil(function() return (H.mapId() & 0x3FF) == 394 end, 1800, {
    H.call(function()
      if not H.hasControl() then H.setPad({}) return end
      H.setPad({ up = true })
    end),
  }, "alcove -> 394"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, "control on 394", 10),
  (function()
    local lane
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "left", "right", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
          if lane == nil then H.setPad({}) return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
    }, "a random encounter")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    -- the wearer whose esper is cheapest, so a boost-1 price is not already
    -- at the 99 cap and the escalation shows as a number
    local worn, best = {}, nil
    local prop = H.sym("MagicProp") & 0x3FFFFF
    for s = 0, 3 do
      local id, st = H.readByte(0x3ED8 + s * 2), H.readByte(STONE + s * 2)
      worn[#worn + 1] = string.format("slot%d char %d esper $%02X", s, id, st)
      if id ~= 0xFF and st ~= 0xFF and cmdRow(s, CMD_MAGIC) then
        local b = H.readRomByte(prop + (st + 0x36) * 14 + 5)
        if best == nil or b < best then slot, best = s, b end
      end
    end
    assert(slot, "someone wears an esper and has a Magic row")
    local esper = H.readByte(STONE + slot * 2)
    local base = H.readRomByte((H.sym("MagicProp") & 0x3FFFFF) + (esper + 0x36) * 14 + 5)
    H.log(string.format("[summon] %s; caster slot %d, esper $%02X, MagicProp[$%02X]+5 = %d MP, "
      .. "MP %d", table.concat(worn, ", "), slot, esper, esper + 0x36, base, mp()))
  end),
  H.driveUntil(function() return snap ~= nil end, 30000, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == slot
         and H.readByte(BANK + slot * 2) >= 3 and H.readByte(PEND + slot * 2) == 0 then
        H.setPad({})
        snap = H.requestSaveState()
        return
      end
      defendOthers(-1)
    end),
  }, "the caster's window with 3 pips"),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot") end),
}
for _, b in ipairs(BOOSTS) do
  local c = { boost = b }
  results[#results + 1] = c
  for _, s in ipairs(runCase(c)) do steps[#steps + 1] = s end
end
steps[#steps + 1] = H.call(function()
  local base = results[1].queued
  for _, c in ipairs(results) do
    H.log(string.format("[summon] boost %d: queued %s, charged %d; mp-economy.md says %d "
      .. "(min(99, %d x 2.5^%d))", c.boost, tostring(c.queued), c.mp0 - (c.mpEnd or c.mp0),
      H.boostPrice(base, c.boost), base, c.boost))
  end
end)

H.run({ maxFrames = 200000 }, steps)
