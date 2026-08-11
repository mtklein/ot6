-- @suite savestate=cyan_defence
-- menu_bushidoloadout.lua -- issue #8 Layer B field configurator (Skills->SwdTech).
--
-- Issue #75 conversion: this runs against a real Cyan, with no state writes.
-- This file's header used to open "reaching Skills->SwdTech for a real Cyan
-- headlessly needs a party+field fixture we do not generate"; that is no longer
-- true, because the input-driven chain generates cyan_defence (gen_sabin_camp:
-- Doma castle interior, map 120, CYAN alone in the party with field control).
-- So the two data stagings this file carried are gone:
--   * the BUSHIDO command is not granted to the leader's record; CYAN's own
--     record carries it, and that is asserted (the same realness check
--     menu_blitzpage_sabin.lua makes for Sabin's Blitz);
--   * the learned set $1cf7 and the loadout word $1e1d are read, not written.
--     The word must be $0000, since no reachable save has ever configured a
--     loadout, so AUTO is the state every real Cyan arrives in, and the
--     assign expectations below are derived from the learned set as read, so
--     a fixture whose Cyan joins at a different level moves the numbers
--     without touching this file.
--
-- Storage is a 16-bit little-endian word at $1e1d..$1e1e: slot s occupies
-- bits s*3..s*3+2, and word 0 = AUTO.
--
-- issue #38 put a 1-BP floor under every tech, so the page is three rows
-- (1x/2x/3x) and menu row i edits word slot i+1.  The stored format did not
-- move: same word, same four fields, same sentinel, so no SRAM checkpoint is
-- disturbed, and word slot 0 is retired.  Ot6LoadoutSeedWord still writes
-- it (its auto-tech clamp makes it a mirror of slot 1), and nothing reads it.
-- So:
--   * seeding from AUTO is implicit: entering while AUTO writes nothing (the
--     word stays 0); each drawn row computes its auto tech on the fly through
--     Ot6LoadoutSlotTech.  We assert the word is still 0 after Open.
--   * cursor: three rows, not four, so three Downs wrap back to the top row.
--   * assign: the first edit (R shoulder) first freezes the whole auto window
--     into the word, so the un-touched slots keep their auto techs, then
--     cycles the cursored slot.  The window per Ot6LoadoutAutoTech
--     (ot6_loadout.asm:60): ceiling c = highest learned tech, base
--     b = max(0, c-2), slot s (1..3) shows min(c, b+s-1), and retired slot 0
--     mirrors slot 1.  Cyan's real set here is $03, that is two techs,
--     Dispatch and Retort (the plan doc's "$07 scenario-band set" describes a
--     later Cyan), so c=1, the window is {0,1,1} with the 3x tier clamped to
--     the ceiling, the seed is {0,0,1,1}, and R on row 0 cycles word slot 1
--     from 0 to 1, leaving {0,1,1,1} = $0248, which is nonzero and therefore
--     MANUAL.  All of it is derived from $1cf7 as read, so a fixture whose
--     Cyan joins knowing more techs moves the numbers without touching this
--     file.
--   * revert: Y writes $0000 (AUTO); no reseed is needed, the display
--     recomputes.
-- A screenshot records that the two-pane screen (3 boost slots plus the
-- learned pool) renders.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local ZMENUSTATE = 0x26                     -- direct-page menu vars
local ZCURSOR = 0x4B                        -- generic menu selection cursor
local ZCURSORY = 0x4E                       -- Ot6Loadout*'s row cursor
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
local ST_MAIN, ST_CHARSEL, ST_SKILLS = 0x05, 0x06, 0x0A
local ST_LOADOUT = 0x7B
local ZCHARID = 0x69                        -- zCharID::Slot1 (menu_ram.inc)
local CHAR_CYAN = 0x02                      -- CHAR::CYAN (const.inc)
local CMD_BUSHIDO = 0x07                    -- BATTLE_CMD::BUSHIDO (const.inc)

local function word()      return H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8) end
local function slot(s)     return (word() >> (s * 3)) & 0x07 end   -- s = 0..3

-- Derived from the learned set as read (never written): the auto window per
-- Ot6LoadoutAutoTech and the packed word the first R edit must leave behind.
local t1, t2, t3 = nil, nil, nil            -- window techs for rows 1x/2x/3x
local wantWord = nil                        -- {t1, t1+1, t2, t3} packed
local cyanSlot = nil                        -- CYAN's menu slot, found not assumed

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- The save's own state, read: Cyan's level-derived learned set (contiguous
  -- from tech 0, because vanilla teaches Bushido by level, so a real $1cf7 is
  -- always (1<<n)-1) and a never-configured loadout word.
  H.call(function()
    local L = H.readByte(LEARNED)
    local n = 0
    while (L >> n) & 1 == 1 do n = n + 1 end
    H.log(string.format("$1cf7 = $%02x as saved: %d techs learned", L, n))
    H.assertEq(L, (1 << n) - 1,
      "Cyan's real learned set is contiguous from tech 0 (level-derived)")
    H.assertEq(n >= 2, true,
      "at least two techs learned, so the R cycle below has somewhere to go")
    -- Ot6LoadoutAutoTech: ceiling c, base max(0, c-2), row s -> min(c, b+s-1)
    local c = n - 1
    local b = math.max(0, c - 2)
    t1, t2, t3 = math.min(c, b), math.min(c, b + 1), math.min(c, b + 2)
    -- R cycles word slot 1 from t1 to the next learned tech; t1 < c always
    -- holds for n >= 2, so that is t1+1.
    wantWord = t1 | ((t1 + 1) << 3) | (t2 << 6) | (t3 << 9)
    H.log(string.format("derived: window {%d,%d,%d}, post-edit word $%04x",
      t1, t2, t3, wantWord))
    H.assertEq(word(), 0,
      "the loadout word is $0000 as saved -- no real save has ever configured "
      .. "one, so AUTO is the arrival state and nothing needs zeroing")
  end),

  -- open the field menu (X) and walk to Skills->SwdTech by pad.  Every drive
  -- below is gated by reading the menu state and cursor back rather than by
  -- frame counts, so fades and key-repeat cannot skew which row gets selected.
  -- A single X can be eaten if the field is not polling input on that exact
  -- frame, so press until the field acknowledges (probe_banquet_timer_save
  -- opens its menu the same way).  $59 is the FIELD's own menu-opening flag
  -- (player.asm), readable while the field still owns the zero page;
  -- ZMENUSTATE only means anything once the menu module has taken over, so
  -- it is the second check, not the first.
  H.driveUntil(function() return H.readByte(0x59) ~= 0 end, 600, {
    H.pressButtons({ "x" }, 4), H.waitFrames(30),
  }, "menu opening ($59, field-side check)"),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_MAIN end,
    400, "main menu", 5),
  H.waitFrames(30),
  -- The check that replaced the staged command: CYAN is found in the
  -- party (measured: he does not sit in menu slot 1 on this fixture, where
  -- slot 1 reads $FF, a leftover of the Sabin-scenario party shuffle), and his
  -- own character record carries BUSHIDO.  zCharID is only valid while the
  -- menu module owns the zero page, so it is read here.
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_CYAN and cyanSlot == nil then cyanSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(cyanSlot ~= nil, true,
      "cyan_defence's party contains CYAN -- he IS this fixture; without him "
      .. "this test is not testing the thing it exists to test")
    local rec = 0x1600 + 37 * CHAR_CYAN     -- CharPropPtrs stride (menu_init.asm)
    local has = false
    for i = 0, 3 do
      if H.readByte(rec + 0x16 + i) == CMD_BUSHIDO then has = true end
    end
    H.assertEq(has, true,
      "CYAN's own record carries BATTLE_CMD::BUSHIDO -- the SwdTech row is "
      .. "enabled by the character, not by this test")
  end),
  -- down moves the main-menu cursor from Items (0) to Skills (1); A opens
  -- character select; walk the cursor onto CYAN's slot and confirm
  -- (CheckSkillValid passes: Cyan's real command enables the SwdTech row).
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_MAIN and H.readByte(ZCURSOR) == 1
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Skills"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_CHARSEL end,
    300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == cyanSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto CYAN"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_SKILLS end,
    600, "skills submenu", 5),
  -- down to row 2 = SwdTech (Genju, Magic, SwdTech, ...), then A runs
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

  -- seeding from AUTO is implicit: Open writes nothing, so the word is still
  -- $0000.
  -- The three rows still draw {b, b+1, b+2} because Ot6LoadoutSlotTech computes
  -- the auto window per slot whenever the word is 0.
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "configurator state is live ($7b)")
    H.assertEq(word(), 0, "still AUTO after opening -- Open seeds nothing (word $0000)")
    H.assertEq(H.readByte(ZCURSORY), 0, "Open put the cursor on the top row")
    H.log(string.format(
      "SEED: entering AUTO left the word at $0000; the display computes {%d,%d,%d}",
      t1, t2, t3))
  end),

  -- cursor (#38): three rows.  The exact step count per press depends on the
  -- menu's own key repeat, so this samples the cursor over a walk instead of
  -- pinning one press to one row: the value must never reach 3, and it must
  -- come back to 0, which means the page wraps at three rows, not four.  On the
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
  -- park the cursor back on the top row for the assign step.  Walked by pad
  -- and gated on reading the row back: driveUntil polls the predicate every
  -- frame, so even if key repeat moved a press two rows the drive stops
  -- the frame the cursor lands on 0, which keeps the row the next step edits
  -- exact without writing the cursor.  (Up wraps 0->2 pre-decrement, so from
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

  -- assign: R cycles the cursored row 0 (word slot 1) to the next learned
  -- tech.  The first edit freezes the auto window into the word as {t1, t1,
  -- t2, t3}, with slot 0 mirroring slot 1, then bumps slot 1 from t1 to the
  -- next learned t1+1, so the result is {t1, t1+1, t2, t3}, nonzero and
  -- therefore MANUAL.
  H.pressButtons({ "r" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word() ~= 0, true, "the first edit flipped the loadout to MANUAL (word nonzero)")
    H.assertEq(word(), wantWord, string.format(
      "packed word = {%d,%d,%d,%d} = $%04x, derived from the learned set as read",
      t1, t1 + 1, t2, t3, wantWord))
    H.assertEq(slot(0), t1,
      "the RETIRED slot 0 holds the seed's mirror of slot 1 (" .. t1 .. ")")
    H.assertEq(slot(1), t1 + 1, string.format(
      "R cycled row 0 = slot 1x from auto tech %d to the next learned %d",
      t1, t1 + 1))
    H.assertEq(slot(2), t2, "un-edited slot 2x kept its auto tech " .. t2)
    H.assertEq(slot(3), t3, "un-edited slot 3x kept its auto tech " .. t3)
    H.screenshot("bushido_loadout_edited")
    H.log(string.format(
      "ASSIGN: first edit froze the auto window then cycled slot 1x (word $%04x, MANUAL)",
      word()))
  end),

  -- revert: Y writes $0000 (AUTO).  There is no reseed; the display recomputes
  -- the window.
  H.pressButtons({ "y" }, 3),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(word(), 0, "Y reverted the loadout to AUTO (word $0000)")
    H.log("REVERT: Y cleared the word to $0000; the display recomputes the window")
    H.log("PASSED: field configurator seeds implicitly, assigns (packs the word), and reverts -- for a REAL CYAN, nothing staged")
  end),
})
