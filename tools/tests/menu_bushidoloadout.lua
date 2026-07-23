-- @suite frontier=arvis_wake
-- menu_bushidoloadout.lua -- issue #8 Layer B FIELD configurator (Skills->SwdTech).
--
-- Reaching Skills->SwdTech for a real Cyan headlessly needs a party+field fixture
-- we do not mint, so this drives the configurator DIRECTLY: from the open field
-- menu it forces zMenuState to the loadout state ($7b), whose handler self-inits
-- (jsl Ot6LoadoutInitC3 -> LoadCursor + Ot6LoadoutOpen seed + draw).  That
-- exercises the real bank-F0 logic the C3 shim delegates to:
--   * SEED-FROM-AUTO: entering while AUTO fills the four slots from the moving
--     window (ceiling = popcount($1cf7)-1).  $1cf7 = 0xFF -> window {4,5,6,7}.
--   * ASSIGN writes $1e1d: R (shoulder) cycles the cursored slot to the next
--     learned tech and flips mode to MANUAL ($1e1d = 1).
--   * REVERT clears mode: Select sets $1e1d = 0 and reseeds from the window.
-- A screenshot proves the two-pane screen (4 boost slots + LEARNED pool) renders.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/arvis_wake.mss.lua"

local ZMENUSTATE, SENTINEL = 0x26, 0x4A     -- direct-page menu vars
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
local ST_LOADOUT = 0x7B

local function mode()    return H.readByte(LOADOUT) end
local function slot(i)   return H.readByte(LOADOUT + i) end   -- i = 1..4

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- Cyan's learned set + a clean AUTO loadout with GARBAGE slots (to prove the
  -- seed overwrites them).
  H.call(function()
    H.writeByte(LEARNED, 0xFF)              -- all eight techs learned
    H.writeByte(LOADOUT, 0)                 -- AUTO
    for i = 1, 4 do H.writeByte(LOADOUT + i, 0xEE) end
  end),

  -- open the field menu (X), then force the loadout state; the handler self-inits.
  H.pressButtons({ "x" }, 4),
  H.waitFrames(120),
  H.call(function()
    H.writeByte(SENTINEL, 0)                -- re-arm self-init
    H.writeByte(ZMENUSTATE, ST_LOADOUT)     -- jump into MenuState_7b
  end),
  H.waitFrames(60),
  H.call(function() H.screenshot("bushido_loadout_field") end),

  -- SEED-FROM-AUTO: $1cf7 = 0xFF -> ceiling 7, base 4 -> slots {4,5,6,7}
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "configurator state is live ($7b)")
    H.assertEq(slot(1), 4, "seed slot 0x = auto tech 4")
    H.assertEq(slot(2), 5, "seed slot 1x = auto tech 5")
    H.assertEq(slot(3), 6, "seed slot 2x = auto tech 6")
    H.assertEq(slot(4), 7, "seed slot 3x = auto tech 7")
    H.assertEq(mode(), 0, "still AUTO after seeding (edits have not begun)")
    H.log("SEED: entering AUTO seeded the four slots from the window {4,5,6,7}")
  end),

  -- ASSIGN: R cycles the cursored slot 0 to the next learned tech, mode -> MANUAL
  H.pressButtons({ "r" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(mode(), 1, "the first edit flipped the loadout to MANUAL ($1e1d = 1)")
    H.assertEq(slot(1), 5, "R cycled slot 0x from tech 4 to the next learned tech 5")
    H.screenshot("bushido_loadout_edited")
    H.log("ASSIGN: R wrote a new tech into the cursored slot and set MANUAL")
  end),

  -- REVERT: Y restores AUTO and reseeds the window
  H.pressButtons({ "y" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(mode(), 0, "Y reverted the loadout to AUTO ($1e1d = 0)")
    H.assertEq(slot(1), 4, "revert reseeded slot 0x back to the auto tech 4")
    H.log("REVERT: Y cleared the mode byte and reseeded from the window")
    H.log("PASSED: field configurator seeds, assigns (writes $1e1d), and reverts")
  end),
})
