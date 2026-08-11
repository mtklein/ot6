-- @suite slow savestate=camp_escaped
-- battle_mpcost.lua -- v0.5 "every ability costs MP": the OT6_MP_COSTS A/B.
--
-- ONE self-detecting instrument, run on BOTH builds (this is the whole A/B the
-- task asks for).  v0.5 flipped the flag ON by default, so the A/B's premise
-- INVERTS: the SHIPPED ROM charges, and the flag-OFF build is the control.
--   * on the shipped, flag-ON ROM (build/ot6.sfc, the suite's default) the
--     cost table is PRESENT in bank F0 with kits.md's numbers, so the test
--     asserts the CHARGE and the insufficient-mp REFUSAL.
--   * on the flag-OFF baseline (ff6/rom/ff6-en-nomp.sfc, handed here via
--     OT6_ROM) the cost table is ABSENT -- so the identical SwdTech tech is
--     FREE.  This is the negative control.
--
-- The mechanism under test: vanilla's GetMPCost prices only magic/lore/
-- summon/x-magic; Blitz/SwdTech/Tools fall through it at 0, so the universal
-- charge at CalcAttackEffect never fires for them.  Ot6AbilityCost (ot6.asm)
-- swaps that 0 for the kit price keyed by the id in $3a7b.
--
-- Issue #75 conversion.  The old apparatus installed a triple-CYAN party by
-- poke ($3ED8, SwdTech-only $202E, the SWDTECH weapon flag written, $2020
-- ceiling pinned), stopped and HP-pinned the guards, and pinned each
-- scenario's MP.  On camp_escaped CYAN IS REAL (battle_bushidogrey's
-- measured kit: katana SWDTECH flag $3BA4 bit 1 reads $82; the real learned
-- window is Dispatch $55 @ 4 MP boost 1 / Retort $56 @ 10 MP boost 2), the
-- fights are real world encounters, and both scenarios' MP states are the
-- fight's own:
--
--   CHARGE  the battle's FIRST Cyan turn -- before any enemy has acted --
--           casts a real Dispatch off the opening 1-bp bank against his
--           real 67-MP pool.  ON: debited to exactly mp0-4 (write watch +
--           direct read inside the clean window).  OFF: the pool does not
--           move.  Both: the tech lands its hit.
--   REFUSAL (ON only) *** LABELED ISOLATION ARM (owner calibration). ***
--           battle_bushidogrey measured the input-driven routes to a broke
--           kit-caster out of reach on this pool's economy: a deferring
--           party is ground down before any real poverty arrives (the
--           'enemy MP drain' first blamed was battle-teardown zeroes read
--           ungated), and a six-battle Dispatch walk never spends the
--           pool down -- the trash dies first.  So this arm keeps ONE
--           write, said loudly: MP := 1 (< Dispatch's 4) with the pip
--           rebanked by a real item turn; the retried Dispatch must
--           fizzle -- no damage, the 1 MP untouched, never negative.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967
local TONIC, POTION = 0xE8, 0xE9
local DISPATCH, DISPATCH_COST = 0x55, 4

local cyan, shadow
local function bp() return H.readByte(0x3E9C + cyan*2) end
local function pend() return H.readByte(0x3E9D + cyan*2) end
local function mp() return H.readWord(0x3C08 + cyan*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function monsterHpSum()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s*2) end
  return t
end
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
local function refindSlots()
  for slot = 0, 3 do
    local id = H.readByte(0x3ED8 + slot*2)
    if id == 0x02 then cyan = slot end
    if id == 0x03 then shadow = slot end
  end
end

-- battle_bushidogrey's drive machine, verbatim shape
local mf = 0
local cyanMode = "defer"                 -- "defer" | "item" | "tech:<row>"
local quietA = false                     -- suppress the menu-idle A-mash: it
                                         -- can land on a JUST-opened window
                                         -- and confirm a bystander's Fight
                                         -- (measured: 104 stray damage inside
                                         -- the refusal window)
local function decide()
  if H.readByte(MENU) == 0 then
    if quietA then return {} end
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act == shadow then
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 60 then hurt = true end
    end
    if st == ST_CMD and not hurt then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(shadow, CMD_ITEM)
      local cur = H.readByte(CMDROW + shadow) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + shadow) + H.readByte(0x894F + shadow)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif act == cyan then
    if cyanMode == "defer" then
      btn = (st == ST_CMD) and "x" or "b"
    elseif cyanMode == "item" then
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_ITEM)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        if want == nil then error("bank ran out of items", 0) end
        local cur = H.readByte(0x8947 + cyan) + H.readByte(0x894F + cyan)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    else
      local row = tonumber(cyanMode:match(":(%d)"))
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_SWDTECH)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_TOOLS then
        local cur = H.readByte(KROW + cyan)
        if cur < row then btn = "down"
        elseif cur > row then btn = "up"
        else btn = "a" end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    end
  else
    btn = (st == ST_CMD) and "x" or "b"
  end
  return btn and { [btn] = true } or {}
end
local function frame()
  if H.battleLoadStarted() then
    H.setPad(decide())
    return
  end
  if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
  H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
end
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(frame),
  }, tag)
end

local mode                               -- "on" (charges) | "off" (free)
local spells, mpWrites = {}, {}
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end
local R = {}

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),

  -- ------------------------------------------------ 1. detect build + table --
  H.call(function()
    local sig = { 0x5d, 0x04, 0x5e, 0x0a, 0x5f, 0x0d }   -- Pummel/AuraBolt/Suplex
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, b in ipairs(sig) do
        if H.readRomByte(a + i - 1) ~= b then ok = false break end
      end
      if ok then base = a break end
    end
    if not base then
      mode = "off"
      H.log("OFF build: Ot6AbilityCostTbl absent from bank F0 (dormant)")
      return
    end
    mode = "on"
    local cost, a = {}, base
    while H.readRomByte(a) ~= 0xFF and a < base + 0x200 do
      cost[H.readRomByte(a)] = H.readRomByte(a + 1)
      a = a + 2
    end
    local want = {                        -- kits.md's authored numbers (#45)
      [0x5d] = 4,  [0x64] = 99,           -- Blitz:   Pummel, Bum Rush (#57 anchor)
      [0x55] = 4,  [0x58] = 16, [0x5c] = 99, -- SwdTech: Dispatch, Quadra Slam, Cleave
      [0xaa] = 4,  [0xa8] = 16, [0xa6] = 18, -- Tools:  AutoCrossbow, Drill, Chain Saw
    }
    for id, c in pairs(want) do
      H.assertEq(cost[id], c, string.format("cost table: id $%02x costs %d", id, c))
    end
    H.log("ON build: cost table verified for Blitz + SwdTech + Tools")
  end),

  H.loadState(STATE),
  H.waitFrames(30),
  driveTo(function() return H.battleLoadStarted() end, 25000, "first encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    refindSlots()
    H.assertEq(cyan ~= nil and shadow ~= nil, true,
      "CYAN and SHADOW really fight this")
    H.assertEq(H.readByte(0x3BA4 + cyan*2) & 0x02, 0x02,
      "his real katana carries the SWDTECH flag (read, not written)")
    H.assertEq(bp(), 1, "the opening 1-bp bank pays Dispatch's boost")
    R.mp0 = mp()
    R.g0 = monsterHpSum()
    -- ON: the real pool must afford the priced tech.  OFF: the nomp
    -- baseline's battle-MP init reads this ON-build save's pool as 0 --
    -- and a FREE Dispatch executing from 0 MP is exactly the control
    -- (battle_stealmp measured the same wallet shape on its OFF half).
    if mode == "on" then
      H.assertEq(R.mp0 >= DISPATCH_COST, true, "his real pool affords the tech")
    end
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
      emu.callbackType.write, 0x7e3C08 + cyan*2, 0x7e3C08 + cyan*2)
    H.log(string.format("cyan slot %d bp=1 mp=%d; monsters %d hp", cyan,
      R.mp0, R.g0))
  end),

  -- ------------------------------------ 2. CHARGE (ON) / FREE (OFF, control) --
  -- The battle's first Cyan turn, before any enemy action can touch the
  -- pool (this species drains MP -- the first drain measured ~2200 frames
  -- in, the first tech resolves well before it).
  H.call(function() cyanMode = "tech:0" end),
  driveTo(function() return sawSpell(DISPATCH) end, 20000,
    "the real Dispatch reaches $3410"),
  H.call(function() cyanMode = "defer" end),
  -- the charge lands at Ot6ActionEnd, past the tech's whole animation
  H.waitUntil(function() return pend() == 0 end, 900,
    "the tech resolves (pending consumed)", 10),
  H.waitFrames(120),
  H.call(function()
    local left, dmg = mp(), R.g0 - monsterHpSum()
    local seen = {}
    for _, v in ipairs(mpWrites) do seen[v & 0xff] = true end
    H.log(string.format("Dispatch: MP %d -> %d, monster damage %d", R.mp0, left, dmg))
    H.assertEq(dmg > 0, true, "the tech landed its hit (both builds)")
    if mode == "on" then
      H.assertEq(seen[(R.mp0 - DISPATCH_COST) & 0xff], true,
        "ON: the pool was debited to exactly mp0-4 (write watch)")
      H.assertEq(left, R.mp0 - DISPATCH_COST,
        "ON: Dispatch charged exactly its table cost (4)")
    else
      H.assertEq(left, R.mp0,
        "OFF: Dispatch is free -- vanilla behavior, the negative control")
    end
    H.screenshot("mpcost_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. REFUSAL (ON only) --
  -- LABELED ISOLATION ARM -- see the header.  The pip is still rebanked by
  -- a real item turn and the attempt is a real menu drive; only the
  -- poverty itself is staged.
  H.cond(function() return mode == "on" end, {
    (function()
      local done = false
      local steps = {}
      for attempt = 1, 4 do
        steps[#steps+1] = H.cond(function() return done end, {}, {
          driveTo(function()
            return H.battleLoadStarted() and H.monstersPresent() > 0
          end, 30000, "refusal battle (attempt " .. attempt .. ")"),
          H.call(function() refindSlots(); cyanMode = "item" end),
          driveTo(function()
            return not H.battleLoadStarted() or bp() >= 1
          end, 40000, "a real item turn rebanks the pip (attempt "
            .. attempt .. ")"),
          H.cond(function()
            return H.battleLoadStarted() and bp() >= 1
          end, {
            H.call(function()
              -- ISOLATION WRITE (waived, labeled): the broke pool
              H.writeWord(0x3C08 + cyan*2, 1)
            end),
            H.cond(function()
              return H.battleLoadStarted() and bp() >= 1
                and mp() < DISPATCH_COST
            end, {
              (function()
                local m0, g1, latched = nil, nil, false
                return H.repeatN(1, {
                  H.call(function()
                    m0 = mp()
                    spells = {}
                    cyanMode = "tech:0"
                  end),
                  -- the fizzled tech has no grant to signal on: drive on
                  -- the latch (pending banks 1 at the submenu confirm) --
                  -- the damage baseline is captured AT the latch, and the
                  -- pad goes quiet for the whole bounded window so nothing
                  -- but the (non-)fizzle can touch the monsters
                  driveTo(function()
                    if not H.battleLoadStarted() then return true end
                    if pend() >= 1 and not latched then
                      latched = true
                      g1 = monsterHpSum()
                    end
                    return latched
                  end, 30000, "the broke Dispatch is latched (attempt "
                    .. attempt .. ")"),
                  H.call(function() cyanMode = "defer"; quietA = true end),
                  H.waitFrames(400),
                  H.call(function() quietA = false end),
                  H.call(function()
                    if not H.battleLoadStarted() or not latched then return end
                    local left = mp()
                    H.log(string.format(
                      "refused Dispatch: MP %d -> %d, damage since %d, $3410 %s",
                      m0, left, g1 - monsterHpSum(),
                      sawSpell(DISPATCH) and "saw $55" or "quiet"))
                    H.assertEq(left, m0,
                      "ON: too little MP is REFUSED -- the 1 MP is untouched, "
                      .. "never negative")
                    H.assertEq(g1 - monsterHpSum() <= 0, true,
                      "ON: and the refused tech dealt no damage (fizzled)")
                    H.screenshot("mpcost_on_refused")
                    done = true
                  end),
                })
              end)(),
            }, {}),
          }, {}),
        })
      end
      steps[#steps+1] = H.call(function()
        H.assertEq(done, true,
          "the refusal completed inside one battle within four encounters")
      end)
      return H.repeatN(1, steps)
    end)(),
  }, {}),

  H.logStep(function() return "mpcost A/B complete in " .. mode .. " mode" end),
})
