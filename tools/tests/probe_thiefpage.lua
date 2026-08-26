-- probe_thiefpage.lua -- the field Skills page's 8th row (Thief) and the
-- thief page behind it, screenshotted in every state the change adds.
--
-- celes_freed: LOCKE (Steal, so the row draws white and the page opens) and
-- CELES (no Steal, so the row draws gray and A on it refuses).  Four shots:
--   skillspage_8rows_locke   the list, Thief white, cursor on it
--   thiefpage_locke          the page: Steal/Filch/Bestow, named and priced
--   thiefpage_back           B pressed: the skills list restored
--   skillspage_8rows_celes   the list for a non-thief, Thief gray
local H = dofile("tools/tests/lib/ot6.lua")
local ZM, CUR = 0x26, 0x4B
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local THIEF_COLOR = 0x80                -- zSkillsTextColor::Thief (menu_ram.inc)
local CHAR_LOCKE, CHAR_CELES = 0x01, 0x06
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_THIEF = 0x05, 0x06, 0x0a, 0x30
local SKILLS_ROW_THIEF = 7
local function st() return H.readByte(ZM) end

local lockeSlot, celesSlot = nil, nil

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/celes_freed.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_LOCKE and lockeSlot == nil then lockeSlot = s end
      if id == CHAR_CELES and celesSlot == nil then celesSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(lockeSlot ~= nil, true, "celes_freed's party contains LOCKE")
    H.assertEq(celesSlot ~= nil, true, "celes_freed's party contains CELES")
  end),
  H.driveUntil(function() return st() == ST_MAIN and H.readByte(CUR) == 1 end,
    900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, "cursor Skills"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "char select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(CUR) == lockeSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto LOCKE"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills page", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(H.readByte(THIEF_COLOR), 0x20,
      "LOCKE has Steal, so the Thief row draws white ($20)")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(CUR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Thief (row 7)"),
  H.waitFrames(30),
  H.call(function() H.screenshot("skillspage_8rows_locke") end),

  -- A opens the thief page (SkillsOption_07 -> MENU_STATE_THIEF $30)
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_THIEF end, 300, "thief page open", 5),
  H.waitFrames(90),
  H.call(function() H.screenshot("thiefpage_locke") end),

  -- B backs out to the skills list
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "B returns to the skills list", 5),
  H.waitFrames(60),
  H.call(function() H.screenshot("thiefpage_back") end),

  -- shoulder R steps to the next character; land on CELES and read the gray
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(0x28) == celesSlot
  end, 900, { H.pressButtons({ "r" }, 2), H.waitFrames(30) },
    "shoulder R to CELES"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(THIEF_COLOR), 0x24,
      "CELES has no Steal, so the Thief row draws gray ($24)")
  end),
  -- A on the gray row refuses (SelectSkillsOption's $20 gate)
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(CUR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "CELES's cursor to Thief"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(st(), ST_SKILLS,
      "A on the gray Thief row goes nowhere -- still on the skills list")
    H.screenshot("skillspage_8rows_celes")
  end),
})
