-- probe_openchest.lua -- smoke tests M.openChest on South Figaro's street
-- chests (map 75, flat town, no encounters).
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "control", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 75, "south_figaro sits on map 75")
  end),
  H.openChest{ stand = {32, 17}, face = "up", bit = 21, what = "Tonic",
               item = 0xE8 },
  H.openChest{ stand = {32, 17}, face = "up", bit = 21,
               what = "Tonic again (idempotence)" },
  H.logStep(function() return "openchest smoke complete" end),
})
