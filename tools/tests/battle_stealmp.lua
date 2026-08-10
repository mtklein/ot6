-- @suite slow frontier=figaro_cleared
-- battle_stealmp.lua -- v0.5 "every ability costs MP": Steal (cmd $05) joins the
-- cost gate. The SAME self-detecting A/B as battle_mpcost.lua, aimed at the one
-- costed verb that test does NOT drive -- Locke's Steal -- proving the flat-cost
-- path added to Ot6AbilityCost (cmd $05 -> 4 MP, keyed on the command, NOT an
-- id-table row) charges and refuses through the universal machinery, and stays
-- free on the OFF baseline.
--
-- REPRICED BY #52 (2026-07-29): 2 -> 4. The flat path now reads the Ot6StealCost
-- leaf (the Ot6DanceCost shape) instead of an inline immediate, so this test,
-- battle_costtable.lua and #55's future row decorator all price one number.
--
--   * ON  (build/ot6.sfc, the suite default): a Steal is QUEUED at cost 4
--     (Ot6AbilityCost's flat path), DEDUCTS 4 MP when it executes, and a caster
--     below 4 MP is REFUSED -- the universal insufficient-mp fizzle
--     (CalcAttackEffect) skips the steal effect, so no item is taken and MP is
--     not driven negative.
--   * OFF (ff6/rom/ff6-en-nomp.sfc, handed in via OT6_ROM): Ot6AbilityCost is
--     not assembled, so cmd $05 keeps vanilla's 0 -- the identical Steal is
--     FREE (0 MP deducted). The refusal half has nothing to refuse and is
--     skipped. This is the negative control.
--
-- Issue #75 conversion.  battle_steal.lua's fixture move, drive and
-- observation rig, minus the RNG decode: on figaro_cleared LOCKE's real
-- Steal runs against real desert species, and the MP LEDGER IS THE REAL
-- POOL.  The old writes -- party/enemy installs, slot sentinels, HP pins,
-- STOP bits, bp/pending hands, and above all the per-drive MP :=
-- 50 / := 1 writes -- are all gone.  The affordable arm charges his real
-- 31-MP pool; the refusal arm EARNS its poverty: real steal attempts
-- drain 4 MP each until the pool reads < 4, then a FRESH battle (fresh
-- species loot) hosts the refused attempt.  The refused steal is 3-bp
-- guaranteed (bank earned by zero-MP item turns), so "no item granted on
-- a populated, would-always-succeed steal" is an unambiguous refusal
-- signal -- a 0-bp attempt could just have missed its roll.
--
-- THE COST IS READ AT THE SOURCE, unchanged: a write watch on the mp-cost
-- queue ($3620,y, stored in CreateAction) filtered to command $05
-- captures EXACTLY what Ot6AbilityCost returned -- 4 on ON, 0 on OFF --
-- and the MP delta then confirms the charge landed.  That store fires for
-- both the affordable and the refused steal (the refusal is downstream,
-- at execution), so it is also the uniform "the action was created"
-- signal both scenarios wait on.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_THIEF, ST_ITEM, ST_TGT, ST_TRANS = 0x05, 0x30, 0x0A, 0x38, 0x01
local CMD_STEAL, CMD_ITEM = 0x05, 0x01
local NONE = 0xFF
local TONIC, POTION = 0xE8, 0xE9
local STEAL_COST = 4                     -- #52: Ot6StealCost's immediate

local mode                               -- "on" (charges) | "off" (free)
local locke
local function bp() return H.readByte(0x3E9C + locke*2) end
local function pend() return H.readByte(0x3E9D + locke*2) end
local function mp() return H.readWord(0x3C08 + locke*2) end
local function stealRare(s)   return H.readByte(0x3308 + 8 + s*2) end
local function stealCommon(s) return H.readByte(0x3309 + 8 + s*2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- ------------------------------------------------- the observation rig --
local rec = nil
local function newRec() rec = { code = 0 } end
local function armWatches()
  -- steal message trail ($3401): gates the grant watch, exactly as
  -- battle_steal measured (the bank turns' item id lands in $32F4 too)
  emu.addMemoryCallback(function(_, v)
    if not rec then return end
    if v >= 1 and v <= 3 then rec.code = math.max(rec.code, v)
    elseif v == NONE and rec.code >= 1 and not rec.msgDone then
      rec.msgDone = true
    end
  end, emu.callbackType.write, 0x7E3401, 0x7E3401)
  -- mp-cost queue store (CreateAction), filtered to command $05: the
  -- exact cost Ot6AbilityCost handed back for this Steal.  First $05
  -- store per record (queued latches).
  emu.addMemoryCallback(function(_, v)
    if rec and not rec.queued and H.readByte(0x3A7A) == 0x05 then
      rec.qcost = v; rec.queued = true
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  emu.addMemoryCallback(function(_, v)
    if rec and rec.code >= 1 and v ~= NONE and not rec.msgDone then
      rec.grant = v
    end
  end, emu.callbackType.write, 0x7E32F4, 0x7E32F4 + 18)
end

-- ------------------------------------------------------ the menu drive --
-- battle_steal.lua's measured machine: latched blink-proof target mask,
-- per-cycle direction rotation, slow item-window cadence.
local mf = 0
local drive = { wantBp = 0, wantPend = 0, target = nil }
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  if H.readByte(MSTATE) == ST_TGT then
    local m = H.readByte(0x7B7E)
    if m ~= 0 then
      if m == drive.curMask then drive.maskAge = (drive.maskAge or 0) + 1
      else drive.curMask, drive.maskAge = m, 1 end
    end
  else
    drive.curMask, drive.maskAge, drive.tgtPress = nil, 0, 0
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (act == locke and st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act ~= locke then
    btn = (st == ST_CMD) and "x" or "b"
  elseif bp() < drive.wantBp then
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_ITEM)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then error("bank ran out of items", 0) end
      local cur = H.readByte(0x8947 + locke) + H.readByte(0x894F + locke)
      if cur < want then btn = "down"
      elseif cur > want then btn = "up"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif pend() < drive.wantPend then
    btn = (st == ST_CMD) and "r" or "b"
  else
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_STEAL)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_THIEF then btn = "a"
    elseif st == ST_TGT then
      if drive.target == nil then
        btn = "a"                                -- any monster will do
      elseif drive.curMask == (1 << drive.target)
          and (drive.maskAge or 0) >= 4 then
        btn = "a"
      else
        local dirs = { "left", "down", "right", "up" }
        if (mf - 1) % 8 == 0 then drive.tgtPress = (drive.tgtPress or 0) + 1 end
        btn = dirs[(((drive.tgtPress or 1) - 1) // 2) % 4 + 1]
      end
    else btn = "b" end
  end
  return btn and { [btn] = true } or {}
end

-- drive one steal until its action is QUEUED, then hold while it executes
-- (grant) or fizzles (bounded wait -- a refused steal grants nothing to
-- signal on).  The original's own completion shape.
local function oneSteal(tag, wantBp, wantPend, execWait)
  local execFrames = 0
  return H.repeatN(1, {
    H.call(function()
      drive.wantBp, drive.wantPend = wantBp, wantPend
      newRec(); execFrames = 0
    end),
    H.driveUntil(function()
      if rec.queued then execFrames = execFrames + 1 end
      return rec.queued and (rec.grant ~= nil or execFrames >= (execWait or 300))
    end, 30000, {
      H.call(function() H.setPad(decide()) end),
    }, tag),
    H.call(function()
      H.setPad({})
      H.log(string.format("[%s] qcost=%s grant=%s code=%d bp=%d pend=%d mp=%d",
        tag, tostring(rec.qcost), rec.grant and string.format("%02X", rec.grant)
        or "nil", rec.code, bp(), pend(), mp()))
    end),
    H.waitFrames(60),
  })
end

-- classify + suitable-formation battle entry (battle_steal's shape): the
-- executed-signal arms need a BOTH-populated species so a granted item is
-- exactly "the steal executed"
local rareT
local function classify()
  rareT = nil
  for s = 0, 5 do
    if H.readWord(0x3BFC + s*2) > 0 and stealRare(s) ~= NONE then
      rareT = rareT or s
    end
  end
end
local plan
local function enterDesertBattle(n)
  local steps = {}
  for try = 1, 6 do
    steps[#steps+1] = H.cond(function()
      return H.battleLoadStarted() and rareT ~= nil
    end, {}, {
      H.cond(function() return H.battleLoadStarted() end, {
        H.logStep("formation unsuitable -- fleeing for a fresh draw"),
        H.fleeBattle(12000),
        H.waitFrames(240),
      }, {}),
      H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
        H.call(function()
          if not H.worldMode() or not H.worldHasControl() then
            H.setPad({}); return
          end
          H.setPad(((H.frame // 120) % 2 == 0) and { left = true }
            or { right = true })
        end),
      }, "desert encounter " .. n .. " try " .. try),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900,
        "battle " .. n .. " active", 30),
      H.waitFrames(90),
      H.call(function()
        locke = nil
        for slot = 0, 3 do
          if H.readByte(0x3ED8 + slot*2) == 0x01 then locke = slot end
        end
        H.assertEq(locke ~= nil, true, "LOCKE is really in this party")
        classify()
        H.log(string.format("battle %d: rareT=%s mp=%d", n,
          tostring(rareT), mp()))
      end),
    })
  end
  steps[#steps+1] = H.call(function()
    H.assertEq(rareT ~= nil, true,
      "a both-populated species drawn within six encounters")
  end)
  return H.repeatN(1, steps)
end

local mp0

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),

  -- ------------------------------------------------ 1. detect the build --
  H.call(function()
    -- Ot6AbilityCostTbl is present in bank F0 IFF OT6_MP_COSTS was on, and a
    -- byte scan is the only way to ask: OT6_SYMS is scraped from the ON build's
    -- ff6-en.dbg, so H.sym would hand back an address that means nothing in the
    -- nomp ROM this test also runs against.
    --
    -- THE SIGNATURE IS KEYS ONLY, WITH THE COSTS WILDCARDED (see #45): the
    -- KEYS ($5d..$64, the Blitz attack ids) are structural -- they are
    -- FixPlayerAttack's +$5d run and cannot move without the verb moving.
    local keys = { 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64 }
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, k in ipairs(keys) do
        if H.readRomByte(a + (i - 1) * 2) ~= k then ok = false break end
      end
      if ok and H.readRomByte(a + 16) ~= 0x55 then ok = false end
      if ok then base = a break end
    end
    mode = base and "on" or "off"
    if mode == "on" then
      H.log(string.format("ON build: cost table at $%06x -- Steal must charge %d MP",
        base, STEAL_COST))
    else
      H.log("OFF build: cost table absent -- Steal must be FREE (the control)")
    end
  end),

  H.hold({ "b" }),                    -- real chocobo dismount (gen_kolts)
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),

  -- ---------------------------------- 2. CHARGE (ON) / FREE (OFF, control) --
  enterDesertBattle(1),
  H.call(function()
    armWatches()
    mp0 = mp()
    -- ON: the real pool must afford the priced steal (measured 31).
    -- OFF: vanilla gives spell-less LOCKE a 0-MP pool -- and a FREE steal
    -- executing from 0 MP is exactly the control this half asserts.
    if mode == "on" then
      H.assertEq(mp0 >= STEAL_COST, true,
        "his real pool affords the priced steal")
    end
    drive.target = rareT
  end),
  oneSteal("affordable steal (real pool)", 3, 3),
  H.call(function()
    local left = mp()
    H.log(string.format("affordable steal: queued cost %s, MP %d -> %d, granted %s",
      tostring(rec.qcost), mp0, left, tostring(rec.grant)))
    H.assertEq(rec.grant ~= nil, true,
      "the steal executed and took an item (both builds)")
    if mode == "on" then
      H.assertEq(rec.qcost, STEAL_COST,
        "ON: Ot6AbilityCost priced cmd $05 at 4 (flat path)")
      H.assertEq(left, mp0 - STEAL_COST, "ON: the steal deducted exactly 4 MP")
    else
      -- If this trips with a NONZERO qcost, suspect the build probe above
      -- before you suspect Steal.
      H.assertEq(rec.qcost, 0, "OFF: cmd $05 keeps vanilla's 0 (Ot6AbilityCost absent)")
      H.assertEq(left, mp0, "OFF: the steal is FREE -- vanilla behavior, the control")
    end
    H.screenshot("stealmp_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. REFUSAL (ON only) --
  -- Poverty is EARNED: real unboosted attempts drain 4 MP each (target
  -- irrelevant -- the universal charge lands before the steal effect looks
  -- at the loot) until the pool cannot pay one more.  Then a FRESH battle
  -- re-seeds real loot, and a 3-bp GUARANTEED steal -- which can never
  -- miss -- is refused by the universal insufficient-mp fizzle: nothing
  -- taken, MP untouched.  The OFF build charges 0, so there is nothing to
  -- refuse -- run this half only under the flag (battle_mpcost.lua ditto).
  H.cond(function() return mode == "on" end, {
    H.call(function()
      drive.target = nil                         -- any monster will do
      drive.wantBp, drive.wantPend = 0, 0        -- pure unboosted attempts
    end),
    (function()
      local guard = 0
      return H.driveUntil(function()
        return mp() < STEAL_COST
      end, 60000, {
        H.call(function()
          guard = guard + 1
          if guard % 600 == 0 then
            H.log(string.format("draining: mp=%d", mp()))
          end
          H.setPad(decide())
        end),
      }, "the pool drained below one steal by real attempts")
    end)(),
    H.call(function()
      H.setPad({})
      H.log(string.format("drained: mp=%d (< %d)", mp(), STEAL_COST))
    end),
    H.fleeBattle(12000),
    H.waitFrames(240),
    enterDesertBattle(2),
    H.call(function() drive.target = rareT end),
    oneSteal("unaffordable steal (earned poverty)", 3, 3, 400),
    H.call(function()
      local left = mp()
      H.log(string.format("unaffordable steal: queued cost %s, MP stayed %d, granted %s",
        tostring(rec.qcost), left, tostring(rec.grant)))
      H.assertEq(rec.qcost, STEAL_COST, "ON: the gate still priced cmd $05 at 4")
      H.assertEq(rec.grant, nil,
        "ON: too little MP is REFUSED -- no item taken (fizzled), though the "
        .. "3-bp guarantee means it could not have missed")
      H.assertEq(left < STEAL_COST, true,
        "ON: MP not driven negative -- the leftover pool is untouched")
      H.screenshot("stealmp_on_refused")
    end),
  }, {}),

  H.logStep(function() return "steal mpcost A/B complete in " .. mode .. " mode" end),
})
