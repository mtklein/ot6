-- @manual
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- readme_shots_skills.lua -- Continue the wor-locke-v1 battery, open the
-- field menu -> Skills -> LOCKE -> Thief, and screenshot the page (README
-- skills bullet).  Not a test.  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-locke-v1 \
--     tools/tests/run.sh tools/tests/readme_shots_skills.lua <log>
-- Navigation is menu_thiefpage.lua's.  Every row must read as learned (the
-- locked marker is not drawn) or the run fails.
local H = dofile("tools/tests/lib/ot6.lua")
local ZMENUSTATE, ZCURSOR, ZCHARID = 0x26, 0x4b, 0x69
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_THIEF = 0x05, 0x06, 0x0a, 0x30
local SKILLS_ROW_THIEF = 7
local ROWTBL = H.sym("Ot6ThiefRowTbl") & 0x3FFFFF
local function st() return H.readByte(ZMENUSTATE) end
local lockeSlot
H.run({ maxFrames = 30000 }, {
  H.bootCheckpoint("wor-locke-v1"),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(ZCHARID + s) == 0x01 and lockeSlot == nil then lockeSlot = s end
    end
    H.assertEq(lockeSlot ~= nil, true, "LOCKE is in the party")
    for i = 0, 7 do
      local bit = H.readRomByte(ROWTBL + i * 5 + 4)
      local ok = bit == 0 or (H.readByte(0x1E80 + H.readRomByte(ROWTBL + i * 5 + 3)) & bit) ~= 0
      H.log(string.format("thief row %d learned=%s", i, tostring(ok)))
      H.assertEq(ok, true, "thief row " .. i .. " is learned in wor-locke-v1")
    end
  end),
  H.pressButtons({ "down" }, 2), H.waitFrames(6), H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == lockeSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto LOCKE"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills", 5),
  H.waitFrames(10),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "cursor to Thief"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_THIEF end, 300, "thief page", 5),
  H.waitFrames(90),
  H.call(function() H.screenshot("skills_cand1") end),
  H.waitFrames(20),
  H.call(function() H.screenshot("skills_cand2") end),
  H.pressButtons({ "down" }, 2), H.waitFrames(40),
  H.call(function() H.screenshot("skills_cand3_cursor_row1") end),
  H.waitFrames(5),
})
