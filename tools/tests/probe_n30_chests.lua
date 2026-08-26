-- probe_n30_chests.lua -- opens the map-30 Elixir chest reachable from
-- kefka_won's boot {60,37} (Narshe interiors).
--
-- Chest bit 2 at (55,30): stand (55,31) face up, reachable.
-- Chest bit 10 at (105,14), the Elder room, is not reachable from any
-- controllable frame of this boot, so it is not opened here.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.call(function()
    H.assertEq(map(), 30, "booted on map 30")
    H.assertEq(H.chestOpen(2), false, "bit 2 still closed at boot")
  end),
  H.openChest{ stand = { 55, 31 }, face = "up", bit = 2, what = "Elixir",
               nav = { playBattles = "tactical" } },
  H.navTo(60, 36, { playBattles = "tactical" }),
  H.navTo(60, 37, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(map() == 30 and H.fieldX() == 60 and H.fieldY() == 37, true,
      "back at {60,37}")
    H.log("[probe] chest A pickup validated end to end")
  end),
})
