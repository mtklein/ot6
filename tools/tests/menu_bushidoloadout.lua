-- @suite frontier=arvis_wake
-- menu_bushidoloadout.lua -- issue #8 Layer B FIELD configurator (Skills->SwdTech).
--
-- Reaching Skills->SwdTech for a real Cyan headlessly needs a party+field fixture
-- we do not mint, so this drives the configurator DIRECTLY: from the open field
-- menu it forces zMenuState to the loadout state ($7b), whose handler self-inits
-- (jsl Ot6LoadoutInitC3 -> LoadCursor + Ot6LoadoutOpen + draw).  That exercises
-- the real bank-F0 logic the C3 shim delegates to.
--
-- Storage is a 16-bit little-endian WORD at $1e1d..$1e1e: slot s occupies
-- bits s*3..s*3+2, and word 0 = AUTO.
--
-- issue #38 put a 1-BP floor under every tech, so the page is THREE rows
-- (1x/2x/3x) and menu row i edits WORD SLOT i+1.  The stored format did not
-- move -- same word, same four fields, same sentinel, so no battery anchor is
-- disturbed -- word slot 0 is simply retired.  Ot6LoadoutSeedWord still writes
-- it (its auto-tech clamp makes it a mirror of slot 1), and nothing reads it.
-- So:
--   * SEED-FROM-AUTO is IMPLICIT: entering while AUTO writes NOTHING (the
--     word stays 0); each drawn row computes its auto tech on the fly through
--     Ot6LoadoutSlotTech.  We assert the word is still 0 after Open.
--   * CURSOR: three rows, not four -- three Downs wrap back to the top row.
--   * ASSIGN: the FIRST edit (R shoulder) first FREEZES the whole auto window
--     into the word (so the un-touched slots keep their auto techs), then cycles
--     the cursored slot.  $1cf7 = 0xFF -> ceiling 7 -> three-rung auto window
--     {5,6,7} at 1x/2x/3x (slot 0 mirrors slot 1 at 5), i.e. the seed is
--     {5,5,6,7} = $0fad; R on row 0 then cycles WORD SLOT 1 from tech 5 to 6,
--     leaving {5,6,6,7} = word $0fb5 (nonzero = MANUAL).
--   * REVERT: Y writes $0000 (AUTO) -- no reseed needed, the display recomputes.
-- A screenshot proves the two-pane screen (3 boost slots + LEARNED pool) renders.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, SENTINEL = 0x26, 0x4A     -- direct-page menu vars
local ZCURSORY = 0x4E                       -- Ot6Loadout*'s row cursor
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
  -- The three rows still draw {5,6,7} because Ot6LoadoutSlotTech computes the
  -- auto window per slot whenever the word is 0.
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "configurator state is live ($7b)")
    H.assertEq(word(), 0, "still AUTO after opening -- Open seeds nothing (word $0000)")
    H.assertEq(H.readByte(ZCURSORY), 0, "Open put the cursor on the top row")
    H.log("SEED: entering AUTO left the word at $0000; the display computes {5,6,7}")
  end),

  -- CURSOR (#38): three rows.  The exact step count per press is the menu's
  -- own repeat business, so this samples the cursor over a walk instead of
  -- pinning one press to one row: the value must never reach 3, and it must
  -- come back to 0 -- i.e. the page wraps at three rows, not four.  On the
  -- four-row page row 3 was reachable and this fails on the first sample.
  H.call(function()
    _G.__maxrow = 0
    emu.addEventCallback(function()
      if H.readByte(ZMENUSTATE) == ST_LOADOUT then
        local c = H.readByte(ZCURSORY)
        if c > _G.__maxrow then _G.__maxrow = c end
      end
    end, emu.eventType.startFrame)
  end),
  H.repeatN(8, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }),
  H.call(function()
    H.log("highest cursor row seen over the walk: " .. _G.__maxrow)
    H.assertEq(_G.__maxrow, 2,
      "the cursor never leaves the three-row page -- row 3 is unreachable (#38)")
    H.assertEq(word(), 0, "walking the cursor wrote nothing")
  end),
  -- park the cursor back on the top row for the ASSIGN step.  Written rather
  -- than walked: the menu's key-repeat makes "how many rows does one press
  -- move" a race, and which ROW the next step edits has to be exact.
  H.call(function() H.writeByte(ZCURSORY, 0) end),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ZCURSORY), 0, "cursor parked on row 0 (1x) for the edit")
  end),

  -- ASSIGN: R cycles the cursored row 0 (= WORD SLOT 1) to the next learned
  -- tech.  The first edit freezes the auto window into the word -- {5,5,6,7},
  -- slot 0 mirroring slot 1 -- THEN bumps slot 1 from 5 to 6, so the result is
  -- {5,6,6,7} = $0fb5 and mode is now MANUAL (nonzero).
  H.pressButtons({ "r" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word() ~= 0, true, "the first edit flipped the loadout to MANUAL (word nonzero)")
    H.assertEq(word(), 0x0FB5, "packed word = {5,6,6,7} = $0fb5")
    H.assertEq(slot(0), 5, "the RETIRED slot 0 holds the seed's mirror of slot 1 (5)")
    H.assertEq(slot(1), 6, "R cycled row 0 = slot 1x from auto tech 5 to the next learned 6")
    H.assertEq(slot(2), 6, "un-edited slot 2x kept its auto tech 6")
    H.assertEq(slot(3), 7, "un-edited slot 3x kept its auto tech 7")
    H.screenshot("bushido_loadout_edited")
    H.log("ASSIGN: first edit froze the auto window then cycled slot 1x (word $0fb5, MANUAL)")
  end),

  -- REVERT: Y writes $0000 (AUTO).  No reseed -- the display recomputes the window.
  H.pressButtons({ "y" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word(), 0, "Y reverted the loadout to AUTO (word $0000)")
    H.log("REVERT: Y cleared the word to $0000; the display recomputes {5,6,7}")
    H.log("PASSED: field configurator seeds implicitly, assigns (packs the word), and reverts")
  end),
})
