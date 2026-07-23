-- @suite frontier=arvis_wake
-- menu_bushidoloadout.lua -- issue #8 Layer B FIELD configurator (Skills->SwdTech).
--
-- Reaching Skills->SwdTech for a real Cyan headlessly needs a party+field fixture
-- we do not mint, so this drives the configurator DIRECTLY: from the open field
-- menu it forces zMenuState to the loadout state ($7b), whose handler self-inits
-- (jsl Ot6LoadoutInitC3 -> LoadCursor + Ot6LoadoutOpen + draw).  That exercises
-- the real bank-F0 logic the C3 shim delegates to.
--
-- Storage is now a 16-bit little-endian WORD at $1e1d..$1e1e: slot s occupies
-- bits s*3..s*3+2, and word 0 = AUTO.  So:
--   * SEED-FROM-AUTO is now IMPLICIT: entering while AUTO writes NOTHING (the
--     word stays 0); each drawn row computes its auto tech on the fly through
--     Ot6LoadoutSlotTech.  We assert the word is still 0 after Open.
--   * ASSIGN: the FIRST edit (R shoulder) first FREEZES the whole auto window
--     into the word (so the un-touched slots keep their auto techs), then cycles
--     the cursored slot.  $1cf7 = 0xFF -> auto window {4,5,6,7}; R on slot 0
--     cycles tech 4 -> 5, leaving {5,5,6,7} = word $0fad (nonzero = MANUAL).
--   * REVERT: Y writes $0000 (AUTO) -- no reseed needed, the display recomputes.
-- A screenshot proves the two-pane screen (4 boost slots + LEARNED pool) renders.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/arvis_wake.mss.lua"

local ZMENUSTATE, SENTINEL = 0x26, 0x4A     -- direct-page menu vars
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
local ST_LOADOUT = 0x7B

local function word()      return H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8) end
local function slot(s)     return (word() >> (s * 3)) & 0x07 end   -- s = 0..3

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- Cyan's learned set + a clean AUTO word ($0000).  (No display bytes to seed
  -- any more -- the word IS the storage, and 0 = AUTO.)
  H.call(function()
    H.writeByte(LEARNED, 0xFF)              -- all eight techs learned
    H.writeByte(LOADOUT, 0)                 -- word low  = 0 (AUTO)
    H.writeByte(LOADOUT + 1, 0)             -- word high = 0
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

  -- SEED-FROM-AUTO (implicit): Open writes nothing, so the word is still $0000.
  -- The four rows still draw {4,5,6,7} because Ot6LoadoutSlotTech computes the
  -- auto window per slot whenever the word is 0.
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "configurator state is live ($7b)")
    H.assertEq(word(), 0, "still AUTO after opening -- Open seeds nothing (word $0000)")
    H.log("SEED: entering AUTO left the word at $0000; the display computes {4,5,6,7}")
  end),

  -- ASSIGN: R cycles the cursored slot 0 to the next learned tech.  The first
  -- edit freezes the auto window {4,5,6,7} into the word, THEN bumps slot 0 to 5,
  -- so the result is {5,5,6,7} = $0fad and mode is now MANUAL (nonzero).
  H.pressButtons({ "r" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word() ~= 0, true, "the first edit flipped the loadout to MANUAL (word nonzero)")
    H.assertEq(word(), 0x0FAD, "packed word = {5,5,6,7} = $0fad")
    H.assertEq(slot(0), 5, "R cycled slot 0x from auto tech 4 to the next learned tech 5")
    H.assertEq(slot(1), 5, "un-edited slot 1x kept its auto tech 5")
    H.assertEq(slot(2), 6, "un-edited slot 2x kept its auto tech 6")
    H.assertEq(slot(3), 7, "un-edited slot 3x kept its auto tech 7")
    H.screenshot("bushido_loadout_edited")
    H.log("ASSIGN: first edit froze the auto window then cycled slot 0 (word $0fad, MANUAL)")
  end),

  -- REVERT: Y writes $0000 (AUTO).  No reseed -- the display recomputes the window.
  H.pressButtons({ "y" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word(), 0, "Y reverted the loadout to AUTO (word $0000)")
    H.log("REVERT: Y cleared the word to $0000; the display recomputes {4,5,6,7}")
    H.log("PASSED: field configurator seeds implicitly, assigns (packs the word), and reverts")
  end),
})
