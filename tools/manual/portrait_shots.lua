-- tools/manual/portrait_shots.lua: the main menu, opened with the X Button,
-- in two graph states whose parties hold the characters the manual has no
-- other picture of; shots.py crops each portrait out.  Not a test;
-- tools/manual/shots.py runs it with OT6_NO_PUBLISH=1.
--   wor_tritoch: TERRA, CELES, MOG, UMARO       -> "menu_tritoch"
--   wor_opera:   CELES, STRAGO, RELM, GOGO      -> "menu_opera"
local H = dofile("tools/tests/lib/ot6.lua")
local ZMENUSTATE, ST_MAIN = 0x26, 0x05

local function menu(path, tag)
  return {
    H.loadState(path),
    H.waitFrames(30),
    H.driveUntil(function() return H.readByte(ZMENUSTATE) == ST_MAIN end, 2400,
      { H.pressButtons({ "x" }, 4), H.waitFrames(40) }, "main menu: " .. tag),
    H.waitFrames(60),
    H.call(function() H.screenshot(tag) end),
    H.waitFrames(4),
  }
end

local steps = { H.waitFrames(20) }
for _, s in ipairs(menu("build/states/wor_tritoch.mss.lua", "menu_tritoch")) do steps[#steps + 1] = s end
for _, s in ipairs(menu("build/states/wor_opera.mss.lua", "menu_opera")) do steps[#steps + 1] = s end
for _, s in ipairs(menu("build/states/wor_kt_doom.mss.lua", "menu_kt_doom")) do steps[#steps + 1] = s end
for _, s in ipairs(menu("build/states/wor_kt_goddess.mss.lua", "menu_kt_goddess")) do steps[#steps + 1] = s end
for _, s in ipairs(menu("build/states/wor_kt_plates.mss.lua", "menu_kt_plates")) do steps[#steps + 1] = s end
for _, s in ipairs(menu("build/states/wor_veldt.mss.lua", "menu_veldt")) do steps[#steps + 1] = s end
H.run({ maxFrames = 24000 }, steps)
