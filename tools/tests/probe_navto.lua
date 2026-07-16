-- probe_navto: demonstrate closed-loop navigation. Boot the player's
-- save, land on the field, read the start coord, then navTo a nearby
-- target and confirm we arrive (self-calibrating movement, wall
-- fallback, encounter clearing all exercised by the cramped mine).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

local startX, startY, startMap, hitBattle

H.run({ maxFrames = 30000 }, {
  H.waitFrames(5),
  H.call(function()
    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.hasControl() end, 2000, "field control", 10),
  H.call(function()
    startX, startY = H.fieldX(), H.fieldY()
    startMap = H.mapId()
    H.log(string.format("start x=%d y=%d map=%d", startX, startY, startMap))
  end),
  -- Explore: aim far down the corridor and walk until EITHER a random
  -- encounter fires or we transition maps. This exercises the whole
  -- play-the-game loop — control detection, self-calibrating movement,
  -- wall-following — and always terminates (the mine has encounters).
  H.navTo(0, 60, {
    arrive = function() return H.battleActive() or H.mapId() ~= startMap end,
    maxFrames = 24000,
    stuckCap = 60,
  }),
  H.call(function()
    hitBattle = H.battleActive()
    H.log(string.format("stopped x=%d y=%d map=%d battle=%s | calibrated: %s",
      H.fieldX(), H.fieldY(), H.mapId(), tostring(hitBattle), H.navDump()))
    H.screenshot("navto_stopped")
    -- proof: movement was calibrated (we learned the map's directions)
    -- and we made real progress toward the goal
    H.assertEq(H.navDump() ~= "", true, "nav calibrated at least one direction")
    local moved = math.abs(H.fieldY() - startY) + math.abs(H.fieldX() - startX)
    H.assertEq(moved >= 2 or hitBattle or H.mapId() ~= startMap, true,
      "closed-loop nav made progress toward the goal")
  end),
  -- and if we hit a fight, clearBattle wins it headlessly
  H.cond(function() return hitBattle end, {
    H.clearBattle(),
    H.waitUntil(function() return H.hasControl() end, 4000, "back on field", 20),
    H.call(function()
      H.screenshot("navto_after_fight")
      H.log("cleared the encounter; back to x=" .. H.fieldX() .. " y=" .. H.fieldY())
    end),
  }),
})
