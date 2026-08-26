-- probe_kolts_chests.lua -- smoke the seven South Figaro street/yard chest
-- pickups from south_figaro.mss, including the through-the-house detour
-- into the Fenix Down chest's fenced yard.
local H = dofile("tools/tests/lib/ot6.lua")
local M75_AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 },
  { 18, 55 }, { 19, 55 }, { 20, 55 },
  { 48, 37 }, { 34, 35 }, { 22, 14 },
}
local function map() return H.mapId() & 0x1ff end
local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end
local function settle(dstMap, what)
  return H.cond(function() return true end, {
    H.waitFrames(90),
    -- no hasControl term: town NPC async scripts flicker it; navTo
    -- debounces control on its own
    H.waitUntil(function()
      return H.tileAligned() and map() == dstMap
    end, 2400, what, 20),
    H.waitFrames(30),
    H.call(function() H.assertEq(map(), dstMap, what) end),
  })
end
H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "control", 5),
  H.call(function()
    H.assertEq(map(), 75, "south_figaro sits on map 75")
  end),
  H.openChest{ stand = {5, 31}, face = "right", bit = 24, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {13, 28}, face = "right", bit = 25,
               what = "Green Cherry",
               nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {11, 24}, face = "up", bit = 231, what = "Warp Stone",
               nav = { playBattles = "flee", avoid = M75_AVOID } },
  -- the Fenix Down yard, through the house at doormat (15,20) (bump door;
  -- the entrance src (15,18) sits behind a $F7 door tile)
  H.navTo(15, 20, { maxFrames = 20000, playBattles = "flee",
                    avoid = M75_AVOID }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 81 end, 1800, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "into the yard house"),
  H.release(),
  settle(81, "inside the house, map 81"),
  H.navTo(16, 15, { maxFrames = 20000, playBattles = "flee",
                    avoid = { { 4, 17 }, { 16, 16 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "out the back door into the yard"),
  H.release(),
  settle(75, "in the yard"),
  H.openChest{ stand = {22, 19}, face = "up", bit = 20, what = "Fenix Down",
               item = 0xF0, nav = { playBattles = "flee" } },
  H.navTo(23, 17, { maxFrames = 20000, playBattles = "flee" }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 81 end, 1800, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "back into the house from the yard"),
  H.release(),
  settle(81, "back inside the house"),
  H.navTo(4, 16, { maxFrames = 20000, playBattles = "flee",
                   avoid = { { 16, 16 }, { 4, 17 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "back out to the street"),
  H.release(),
  settle(75, "back on the street"),
  H.openChest{ stand = {32, 17}, face = "up", bit = 21, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {15, 46}, face = "up", bit = 22, what = "Antidote",
               item = 0xF2, nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {15, 46}, face = "down", bit = 23, what = "Eyedrop",
               nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.logStep(function() return "kolts chest smoke complete" end),
})
