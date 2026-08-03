-- @suite frontier=arvis_wake
-- menu_bushidoloadout.lua -- issue #8 Layer B FIELD configurator (Skills->SwdTech).
--
-- Reaching Skills->SwdTech for a real Cyan headlessly needs a party+field fixture
-- we do not mint, so this stages the one data byte that gates the door -- the
-- party leader's battle-command list gets BATTLE_CMD::BUSHIDO ($07), which is
-- what enables the SwdTech row (skills.asm _c34d3d matches command bytes at
-- char+$16..$19 against the enable table) -- and then drives the menu with PAD
-- INPUT ONLY: X -> Skills -> character -> SwdTech row -> A.  That runs
-- SkillsOption_02's real entry (field_menu.asm: Ot6LoadoutInitC3, the $4a
-- self-init sentinel, state $7b) instead of forcing zMenuState and re-arming
-- the sentinel by hand, which skipped the entry's own writes.
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

local ZMENUSTATE = 0x26                     -- direct-page menu vars
local ZCURSOR = 0x4B                        -- generic menu selection cursor
local ZCURSORY = 0x4E                       -- Ot6Loadout*'s row cursor
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
local ST_MAIN, ST_CHARSEL, ST_SKILLS = 0x05, 0x06, 0x0A
local ST_LOADOUT = 0x7B
local ZCHARID = 0x69                        -- zCharID::Slot1 (menu_ram.inc)
local CMD_BUSHIDO = 0x07                    -- BATTLE_CMD::BUSHIDO (const.inc)

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

  -- open the field menu (X) and walk to Skills->SwdTech by pad.  Every drive
  -- below is gated by READING the menu state and cursor back, not by frame
  -- counts, so fades and key-repeat cannot skew which row gets selected.
  -- A single X can be eaten if the field is not polling input on that exact
  -- frame, so press until the field acknowledges (probe_banquet_timer_save
  -- opens its menu the same way).  $59 is the FIELD's own menu-opening flag
  -- (player.asm), readable while the field still owns the zero page;
  -- ZMENUSTATE only means anything once the menu module has taken over, so
  -- it is the second gate, not the first.
  H.driveUntil(function() return H.readByte(0x59) ~= 0 end, 600, {
    H.pressButtons({ "x" }, 4), H.waitFrames(30),
  }, "menu opening ($59, field-side witness)"),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_MAIN end,
    400, "main menu", 5),
  H.waitFrames(30),
  -- Stage the door key: the SwdTech row is enabled iff the selected
  -- character's battle-command list contains BUSHIDO (skills.asm _c34d3d).
  -- The fixture's leader is not Cyan, so grant the command -- data staging on
  -- the same footing as the LEARNED byte above, not a state-machine force.
  -- zCharID is only valid while the menu module owns the zero page, hence
  -- staged here rather than before the X press.
  H.call(function()
    local id = H.readByte(ZCHARID)          -- party slot 1's character
    H.assertEq(id < 16, true, "party leader is a real character")
    local rec = 0x1600 + 37 * id            -- CharPropPtrs stride (menu_init.asm)
    H.writeByte(rec + 0x17, CMD_BUSHIDO)    -- battle command slot 2 of 4
    H.log(string.format("staged BUSHIDO command on character %d ($%04x)",
      id, rec + 0x17))
  end),
  -- DOWN moves the main-menu cursor from Items (0) to Skills (1); A opens
  -- character select; A again picks the leader (CheckSkillValid passes: the
  -- staged command enables at least one skill row).
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_MAIN and H.readByte(ZCURSOR) == 1
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Skills"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_CHARSEL end,
    300, "character select", 5),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_SKILLS end,
    600, "skills submenu", 5),
  -- DOWN to row 2 = SwdTech (Genju, Magic, SwdTech, ...), then A runs
  -- SkillsOption_02: Ot6LoadoutInitC3 + the $4a sentinel + state $7b.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "skills cursor on SwdTech"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_LOADOUT end,
    300, "loadout configurator", 5),
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
  -- park the cursor back on the top row for the ASSIGN step.  Walked by pad,
  -- gated on reading the row back: driveUntil polls the predicate every
  -- frame, so even if key-repeat ever moved a press two rows the drive stops
  -- the frame the cursor lands on 0 -- which ROW the next step edits stays
  -- exact without writing the cursor.  (UP wraps 0->2 pre-decrement, so from
  -- any of the three rows this terminates.)
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_LOADOUT and H.readByte(ZCURSORY) == 0
  end, 600, {
    H.pressButtons({ "up" }, 2), H.waitFrames(10),
  }, "cursor walked back to row 0"),
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
