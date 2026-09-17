-- @manual
-- probe_jidoor_door_walk.lua -- can H.worldNavTo walk ONTO Jidoor's world
-- entrance (27,130) with arrive = "on map 198", playing any random on the
-- way (#195: the baseline sweep's seed 2 timed out holding DOWN into a
-- battle after gen_zozo2_arrival's walk stopped one tile short and a
-- driveUntil took the last step with no battle handling).  Boots the
-- zozogrindlab landing fixture (build/states/zozogrind_landing.mss).
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/zozogrind_landing.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] start (%d,%d) prop(27,130)=%04X prop(22,92)=%04X",
      H.worldX(), H.worldY(), H.worldTileProp(27, 130), H.worldTileProp(22, 92)))
  end),
  H.worldNavTo(27, 130, { maxFrames = 60000, playBattles = "tactical",
                          healPercent = 60, healer = 6,
                          reserve = { [0xE9] = 3 },
                          arrive = function() return map() == 198 and not H.worldMode() end }),
  H.release(),
  H.call(function()
    H.log(string.format("[probe] after the walk: map=%d world=%s (%d,%d)",
      map(), tostring(H.worldMode()), H.fieldX(), H.fieldY()))
    H.assertEq(map(), 198, "the walk onto the entrance tile lands in Jidoor")
  end),
})
