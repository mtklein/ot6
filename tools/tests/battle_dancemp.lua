-- @suite
-- battle_dancemp.lua -- issue #34: Dance costs MP -- flat, paid at
-- dance-START, per docs/design/mp-economy.md:96.
--
-- Ot6AbilityCost's cmd-$13 arm charges Ot6DanceCost (8 MP) when the
-- actor's DANCE status ($3ef8 bit 0) is still clear -- the commit moment --
-- and 0 on every mid-dance turn (RandDanceAction re-queues cmd $13 through
-- the same CreateAction with the bit set).  The Dance menu shows the cost
-- through the #35 display pattern's second consumer: Ot6DanceRowDecorate
-- re-lays each column to [font][cost][name] (the Ot6ToolRowDecorate
-- transform) and greys an unaffordable row via Ot6AbilityGrey; the #35
-- wallet paints the actor's current MP on the window's top edge.
--
-- STAGING (labeled): Mog is not in the supported frontier yet, so every
-- slot is poked to MOG with a Dance-only command list (battle_blitzgrey's
-- install pattern); the natural-boot test lands with his rung.  The known
-- dance is pinned to the one MATCHING the current battle background
-- (BattleBGDance), so Cmd_13's 50% bg-mismatch stumble never fires and the
-- multi-turn measurement is deterministic.
--
-- Asserted:
--   1. MENU: the dance row renders [cost 8][name] with the #35 pattern
--      (cost tiles at the row head), white when affordable; the wallet
--      shows the actor's current MP on the window.
--   2. CHARGE AT START: the cost queue prices the commit at 8, MP drops
--      exactly 8, and the DANCE status locks in.
--   3. FREE STEPS: two further auto-queued dance turns price at 0 and MP
--      stays put (one payment per battle).
--   4. REFUSAL: with MP pinned below 8 the commit fizzles through the
--      standard surface -- the row greys ($25), and the universal
--      insufficient-MP gate refuses: no dance status, MP unmoved.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local DANCE_COST = 8
local WALLET = 0x7C16
local msPresent = {}
local danceId, mp0 = nil, 30
local costs = {}          -- cost-queue stores while cmd $13 queues

local function pinField()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
      H.writeByte(0x3ED8 + s * 2, 0x0A)                 -- CHAR::MOG (staged)
      H.writeByte(0x202E + s * 12 + 0 * 3, 0x13)        -- Dance, alone
      H.writeByte(0x2031 + s * 12, 0xFF)
      H.writeByte(0x2034 + s * 12, 0xFF)
      H.writeByte(0x2037 + s * 12, 0xFF)
      H.writeWord(0x3BF4 + s * 2, 999)
    end
  end
  H.writeByte(0x1D4C, 1 << danceId)                     -- the matching dance
  for i = 0, 7 do                                       -- $267e is built from
    H.writeByte(0x267E + i, i == danceId and i or 0xFF) -- $1d4c at InitSkills
  end                                                   -- (battle init) -- the
                                                        -- staged poke re-does it
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)   -- stopped
    if H.readWord(0x3BFC + m * 2) < 0x6000 then
      H.writeWord(0x3BFC + m * 2, 0xF000)
    end
    H.writeByte(0x3AA1 + e, H.readByte(0x3AA1 + e) | 0x04)   -- death-proof
  end
end

local function openDance(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == 0x21 end, 1500, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, what)
end

local function mapWord(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end

local actor

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
    -- the dance whose home is THIS battle background never stumbles
    local bg = H.readByte(0x11E2)
    danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg)
    H.log(string.format("battle bg %02x -> matching dance %d", bg, danceId))
    pinField()
    emu.addMemoryCallback(function(_, v)
      if H.readByte(0x3A7A) == 0x13 then costs[#costs + 1] = v end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.writeWord(0x3C30 + actor * 2, 99)
    H.writeWord(0x3C08 + actor * 2, mp0)      -- staged pool (Mog is poked in)
    H.log("actor slot " .. actor .. " (MOG staged), MP " .. mp0)
  end),

  -- 1. the menu: cost display + wallet -------------------------------------
  openDance("the dance list opens"),
  H.waitFrames(20),
  H.call(function()
    H.log(string.format("dance browse mstate=%02x", H.readByte(MSTATE)))

    local w = {}
    for i = 0, 4 do w[#w + 1] = string.format("%04x", mapWord(WALLET + i)) end
    H.log("wallet cells: " .. table.concat(w, " "))
    -- the known dance (the bg-matching one, index 3) sits in list row 1's
    -- RIGHT column; the decorator's [font][cost][name] re-layout puts its
    -- cost tiles at map row 3 cols 14-15 and the name at 16-27 (measured:
    -- probe_dancerow found "Love" at $7c70 = row 3 col 16)
    H.assertEq(mapWord(0x7C6E), 0x21FF, "cost tens place blank, white")
    H.assertEq(mapWord(0x7C6F), 0x2100 + 0xB4 + DANCE_COST,
      "the dance row leads with its cost (8), white -- the #35 pattern")
    H.assertEq(mapWord(0x7C70) & 0xFF, 0x8B,
      "the dance name follows its cost ('L' of Love Sonata)")
    -- the wallet shows the actor's current MP
    H.assertEq(mapWord(WALLET) & 0xFF, 0x8C, "wallet 'M' on the dance window")
    H.assertEq(mapWord(WALLET + 1) & 0xFF, 0x8F, "wallet 'P'")
    H.assertEq(mapWord(WALLET + 3) & 0xFF, 0xB4 + math.floor(mp0 / 10),
      "wallet tens digit = the staged pool's")
    H.assertEq(mapWord(WALLET + 4) & 0xFF, 0xB4 + mp0 % 10,
      "wallet ones digit")
    H.screenshot("dancemp_menu")
  end),

  -- 2. charge at dance start ----------------------------------------------
  H.call(function() costs = {} end),
  -- the known dance is cell 3 (row 1, right column): walk the cursor there
  H.pressButtons({ "down" }, 4), H.waitFrames(10),
  H.pressButtons({ "right" }, 4), H.waitFrames(10),
  -- confirm the dance, then its target prompt; hands off once our actor's
  -- action is queued (another A would open the NEXT character's menu)
  H.driveUntil(function()
    return H.readByte(0x32CC + actor * 2) ~= 0xFF
           or (H.readByte(0x3EF8 + actor * 2) & 0x01) == 1
  end, 1800, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the dance commits (action queued)"),
  H.driveUntil(function()
    return H.readWord(0x3C08 + actor * 2) ~= mp0
  end, 12000, {
    H.call(function() pinField() end),   -- hands off otherwise (wait mode)
    H.waitFrames(2),
  }, "the dance-start charge lands"),
  H.call(function()
    H.assertEq(H.readWord(0x3C08 + actor * 2), mp0 - DANCE_COST,
      "dance-start charged exactly the flat 8")
    H.assertEq(costs[1], DANCE_COST,
      "the cost queue priced the commit at 8 (Ot6AbilityCost cmd $13)")
    H.assertEq(H.readByte(0x3EF8 + actor * 2) & 0x01, 1,
      "the DANCE status locked in (whole-battle state bought)")
  end),

  -- 3. the locked-in steps are free ----------------------------------------
  H.driveUntil(function() return #costs >= 3 end, 20000, {
    H.call(function() pinField() end),
    H.waitFrames(2),
  }, "two more dance turns queue"),
  H.call(function()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = tostring(v) end
    H.log("cmd-$13 cost queue: {" .. table.concat(c, ",") .. "}")
    H.assertEq(costs[2], 0, "mid-dance turn 1 queues at 0 MP")
    H.assertEq(costs[3], 0, "mid-dance turn 2 queues at 0 MP")
    H.assertEq(H.readWord(0x3C08 + actor * 2), mp0 - DANCE_COST,
      "MP unmoved across the locked-in steps -- one payment per battle")
    H.screenshot("dancemp_locked")
  end),

  -- 4. refusal below the price ---------------------------------------------
  H.driveUntil(function()
    local who = H.readByte(ACTOR)
    return H.readByte(MENU) ~= 0 and who ~= actor
           and H.readByte(0x3EF8 + who * 2) & 0x01 == 0
  end, 12000, {
    H.call(function() pinField() end),
    H.waitFrames(4),
  }, "a second (not yet dancing) actor's menu"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.writeWord(0x3C30 + actor * 2, 99)
    H.writeWord(0x3C08 + actor * 2, DANCE_COST - 1)   -- one short
    costs = {}
  end),
  openDance("the poor dancer's list opens"),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 4), H.waitFrames(10),
  H.pressButtons({ "right" }, 4), H.waitFrames(10),
  H.call(function()
    -- the row greys: cost AND name carry $25 (the standard refusal surface)
    H.assertEq(mapWord(0x7C6F), 0x2500 + 0xB4 + DANCE_COST,
      "the unaffordable row's cost greys ($25 -- Ot6AbilityGrey)")
    H.assertEq(mapWord(0x7C70) >> 8, 0x25,
      "...and the name greys with it (one font colors the pair)")
    H.screenshot("dancemp_grey")
  end),
  -- the menu lets the commit through (the block deliberately stays out of
  -- C1 -- Ot6AbilityGrey's SCOPE comment); the refusal is the universal
  -- execution-time fizzle
  H.driveUntil(function()
    return H.readByte(0x32CC + actor * 2) ~= 0xFF
  end, 1800, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the refused dance still commits (action queued)"),
  H.driveUntil(function()
    return H.readByte(0x32CC + actor * 2) == 0xFF
  end, 12000, {
    H.call(function() pinField() end),
    H.waitFrames(2),
  }, "the queued dance drains (fizzles at execution)"),
  H.waitFrames(120),
  H.call(function()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = tostring(v) end
    H.log("refusal cost queue: {" .. table.concat(c, ",") .. "}")
    H.assertEq(costs[1], DANCE_COST,
      "the commit was priced at 8 (it reached the queue -- not a vacuous pass)")
    H.assertEq(H.readWord(0x3C08 + actor * 2), DANCE_COST - 1,
      "the universal insufficient-MP gate refused: MP unmoved")
    H.assertEq(H.readByte(0x3EF8 + actor * 2) & 0x01, 0,
      "and the dance never started (no whole-battle state for free)")
  end),
  H.logStep(function() return "battle_dancemp complete" end),
})
