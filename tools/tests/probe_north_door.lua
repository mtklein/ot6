-- probe_north_door.lua -- walks the town north door (26,8) into map 50 (78,58) and charts it.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/wob_narshe_town.mss.lua"),
  H.waitFrames(8),
  H.navTo(26, 9, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return mapIs(50) end }),
  H.driveUntil(function() return mapIs(50) end, 900,
    { H.call(function() H.setPad({ up = true }) end) }, "into the north mine"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("in 50 at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("north_mine")
    for y = 0, 62, 2 do
      local row = {}
      for x = 0, 100, 2 do row[#row+1] = H.bfsPath(x, y) and "O" or "." end
      H.log(string.format("  m50 y%02d %s", y, table.concat(row)))
    end
  end),
  H.logStep(function() return "done" end),
})
