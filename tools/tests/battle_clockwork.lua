-- @suite
-- battle_clockwork.lua -- issue #33: the HUD's boost pips and weakness
-- reveals land on the MECHANICAL frame, not near it.
--
-- MEASURED DESYNC THIS GUARDS AGAINST (probe_clockwork on the pre-change
-- ROM, battle_doorstep, boosted Quadra Slam):
--   - pips: the staged party-row cell showed bp-minus-pending at the menu
--     restage (~f605), ~900 frames BEFORE Ot6ActionEnd's charge (f1504).
--   - reveals: the class chip wrote the revealed byte at damage CALC
--     (f704), ~300 frames BEFORE the first damage numeral (f1006), and
--     only on the slot the hit landed on.
-- POST-CHANGE (same probe): the pip cell holds the FULL bank ($79) all
-- through the flight and drops to the charged value 3 frames after the bp
-- write; the reveal commits on GfxCmd_0b's numeral frame and writes BOTH
-- same-species guards in the same frame.
--
-- Staged exactly as battle_mpcost.lua's proven drive: all-Bushido CYAN,
-- boost banked by the swdtech submenu row, guards stopped + HP/shield
-- pinned, MP pinned once (guests carry 0 MP and the universal fizzle eats
-- the tech otherwise).  Phase 3 re-stages SETZER for the Slot input gate:
-- an R/L edge during a LATCHED spin (first reel pressed) must be fully
-- inert -- no pending change, no ching/click (the latch already decides
-- the charge; the sound acknowledged input the reels ignore).
--
-- The boosted verb here is Bushido ($59 Dragon: single target, so the
-- same-species propagation is a real assertion, not a multi-hit accident).
-- Fight/Blitz/spell pip timing rides the same Ot6ActionEnd/Ot6PipStage
-- pair (one charge site, one painter), and battle_boost keeps the Fight
-- path's arrow/consume coverage.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN = 0x2020
local GUARD_HP = 0x3000
local PIP = { [0]=0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

local actor, msPresent = nil, {}
local pinActor = true
local phase3 = false

local function inWindow() return H.readByte(MSTATE) == 0x30 end
local function bp() return H.readByte(0x3E9C + actor * 2) end
local function pend() return H.readByte(0x3E9D + actor * 2) end

local function pinField()
  H.writeWord(KNOWN, 4)                               -- ceiling 4: window {1..4}
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
      if phase3 then
        H.writeByte(0x3ED8 + s * 2, 0x09)             -- CHAR::SETZER
        H.writeByte(0x202E + s * 12, 0x0F)            -- Slot, alone
      else
        H.writeByte(0x3ED8 + s * 2, 0x02)             -- CHAR::CYAN
        H.writeByte(0x202E + s * 12, 0x07)            -- Bushido, alone
        H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
        H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
      end
      H.writeByte(0x2031 + s * 12, 0xFF)
      H.writeByte(0x2034 + s * 12, 0xFF)
      H.writeByte(0x2037 + s * 12, 0xFF)
      H.writeWord(0x3BF4 + s * 2, 999)                -- nobody dies
      H.writeWord(0x3C30 + s * 2, 99)                 -- real max MP
      H.writeWord(0x3C08 + s * 2, 50)                 -- affordable techs
    end
  end
  if actor and pinActor then
    H.writeByte(0x3E9C + actor * 2, 5)                -- full bp bank
    H.writeByte(0x3E9D + actor * 2, 3)                -- pending 3 -> Dragon
  end
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3BE8 + m * 2, 0)      -- no element weak (class path only)
    H.writeByte(0x3EA4 + m * 2, 0x0F)   -- weak to EVERY weapon class
    H.writeByte(0x3E88 + e, 0)          -- never broken
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)   -- stopped
    if H.readWord(0x3BFC + m * 2) ~= GUARD_HP then
      H.writeWord(0x3BFC + m * 2, GUARD_HP)
    end
    H.writeByte(0x3E40 + m * 2, 8)      -- shields pinned high: chip, no break
  end
end

-- actor's pip cell, both bands
local function pipCells()
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  local row
  for r = 0, 3 do if H.readByte(0x64d6 + r) == actor then row = r end end
  if not row then return nil end
  return emu.readWord(base + (1 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam),
         emu.readWord(base + (9 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam)
end

-- per-frame observations across the in-flight window
local watch = false
local chargeF, spentGlyphBeforeCharge, spentGlyphAfterF = nil, nil, nil
local hpFrames, rclsF = {}, { [2] = nil, [3] = nil }
local numeralF, lastCtr = {}, nil
local function sample()
  if not watch then return end
  pinField()
  if not chargeF and bp() ~= 5 then chargeF = H.frame end
  local lo, hi = pipCells()
  if lo then
    local spent = PIP[2]        -- bp 5 - pend 3 = 2 -> the charged glyph
    if (lo & 0xFF) == spent or (hi & 0xFF) == spent then
      if not chargeF then
        spentGlyphBeforeCharge = spentGlyphBeforeCharge or H.frame
      elseif not spentGlyphAfterF then
        spentGlyphAfterF = H.frame
      end
    end
  end
  for _, m in ipairs(msPresent) do
    if not rclsF[m] and H.readByte(0x3EA5 + m * 2) ~= 0 then rclsF[m] = H.frame end
  end
  local ctr = H.readByte(0x632E)
  if lastCtr ~= nil and ctr ~= lastCtr then numeralF[#numeralF + 1] = H.frame end
  lastCtr = ctr
end

-- sfx counters for phase 3 (battle_boost's instrument)
local sfx = { ching = 0, click = 0, error = 0 }
local function sfxWatch()
  emu.addMemoryCallback(function(_, v)
    if v ~= 0 then sfx.ching = sfx.ching + 1 end
  end, emu.callbackType.write, 0x7E6281, 0x7E6281)
  emu.addMemoryCallback(function(a, v)
    if v == 0 then return end
    if a == 0x000094 then sfx.click = sfx.click + 1 end
    if a == 0x000095 then sfx.error = sfx.error + 1 end
  end, emu.callbackType.write, 0x000094, 0x000095)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    H.assertEq(#msPresent, 2, "two guards (same species) on the doorstep")
    H.assertEq(H.readWord(0x57C0 + msPresent[1] * 2),
               H.readWord(0x57C0 + msPresent[2] * 2),
               "the two monsters are the same species")
    pinField()
    -- hp writes mark the damage-CALC moment (the per-frame poll would
    -- miss them: pinField restores the value)
    emu.addMemoryCallback(function()
      hpFrames[#hpFrames + 1] = H.frame
    end, emu.callbackType.write, 0x7E3BFC, 0x7E3C07)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log("actor slot " .. actor .. " (CYAN, pending 3 -> Dragon, single target)")
    pinField()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
  end),

  -- open the swdtech submenu, latch row 3 (= the pinned boost 3)
  H.driveUntil(inWindow, 1500, {
    H.call(function() pinField(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "swdtech submenu opens (tools shell $30)"),
  H.call(function()
    pinField()
    H.writeByte(0x895F + actor, 0)
    H.writeByte(0x8963 + actor, 0)
    H.writeByte(0x8967 + actor, 3)          -- row 3 = boost 3 -> Dragon
  end),
  H.waitFrames(2),
  H.driveUntil(function() return not inWindow() end, 900, {
    H.call(function() pinField(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "submenu closes on a latch"),
  H.call(function()
    pinActor = false
    watch = true            -- sampling starts: committed, in flight
  end),
  -- hands off: an open list would pause execution (wait mode); the queued
  -- tech runs to resolution on its own
  H.driveUntil(function() return chargeF ~= nil end, 12000, {
    H.call(function() pinField() end),
    H.waitFrames(2),
  }, "the boosted tech resolves (bp charged)"),
  H.waitFrames(90),         -- let the post-charge repaint land in vram
  H.call(function()
    watch = false
    H.log(string.format("charge frame %d; spent glyph before charge: %s; after: %s",
      chargeF, tostring(spentGlyphBeforeCharge), tostring(spentGlyphAfterF)))
    H.log(string.format("hp-write frames: first %s last %s (n=%d)",
      tostring(hpFrames[1]), tostring(hpFrames[#hpFrames]), #hpFrames))
    H.log(string.format("reveal frames: m%d=%s m%d=%s; numeral-ctr frames: %s",
      msPresent[1], tostring(rclsF[msPresent[1]]),
      msPresent[2], tostring(rclsF[msPresent[2]]),
      table.concat((function() local t = {} for _, f in ipairs(numeralF) do
        t[#t + 1] = tostring(f) end return t end)(), ",")))
    -- 1. PIPS: the bank displays FULL until the charge...
    H.assertEq(spentGlyphBeforeCharge, nil,
      "the charged pip value never shows before Ot6ActionEnd's charge "
      .. "(pre-change: the menu restage painted it hundreds of frames early)")
    -- ...and the drop lands within a handful of frames of the bp write.
    H.assertEq(spentGlyphAfterF ~= nil and spentGlyphAfterF - chargeF <= 8, true,
      string.format("the pip drop lands on the charge frame (charge %s, drop %s)",
        tostring(chargeF), tostring(spentGlyphAfterF)))
    -- 2. REVEALS: committed AFTER damage calc, ON a numeral frame...
    local ra, rb = rclsF[msPresent[1]], rclsF[msPresent[2]]
    H.assertEq(ra ~= nil and rb ~= nil, true, "both same-species guards revealed")
    H.assertEq(ra, rb, "and in the SAME frame (per-species propagation; "
      .. "pre-change only the hit slot revealed)")
    H.assertEq(#hpFrames > 0, true, "the tech landed (damage applied)")
    H.assertEq(ra > hpFrames[#hpFrames], true,
      "the reveal commits AFTER damage calc (pre-change: same frame as calc)")
    local onNumeral = false
    for _, f in ipairs(numeralF) do
      -- the commit runs at GfxCmd_0b's ENTRY; the counter increment the
      -- poll can see lands after the routine's own WaitFrame/WaitA (up to
      -- ~10 frames when an earlier numeral thread is still finishing)
      if f - ra >= -2 and f - ra <= 12 then onNumeral = true end
    end
    H.assertEq(onNumeral, true,
      "the reveal commits on a damage-numeral frame (the damage frame)")
    H.screenshot("clockwork_revealed")
  end),

  -- ------------------- 3. a latched Slot spin ignores L/R, silently -------
  H.call(function()
    phase3 = true
    pinActor = false
    pinField()
  end),
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == 0x08
  end, 6000, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the slot window is up (spin state $08)"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.writeByte(0x3E9C + actor * 2, 3)          -- bp to spend
    H.writeByte(0x3E9D + actor * 2, 1)          -- pending 1 = the latch tier
  end),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),  -- first reel press: LATCHED
  H.call(function()
    H.assertEq(H.readByte(0x7B92) ~= 0, true, "reel 1 press latched the spin")
    H.assertEq(H.readByte(0x57BA), 1, "Ot6SlotRig latched tier 1")
    sfxWatch()
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(16),
  H.pressButtons({ "r" }, 6), H.waitFrames(16),
  H.pressButtons({ "l" }, 6), H.waitFrames(16),
  H.call(function()
    H.assertEq(H.readByte(0x3E9D + actor * 2), 1,
      "L/R during a latched spin bank nothing (the latch decides the charge)")
    H.assertEq(sfx.ching, 0, "no ching: the HUD does not acknowledge inert R")
    H.assertEq(sfx.click, 0, "no click: nor inert L")
    H.assertEq(sfx.error, 0, "and no buzz either -- fully silent")
    H.log("slot-spin L/R gate: pending stayed 1, zero sfx requests")
  end),
  H.logStep(function() return "battle_clockwork complete" end),
})
