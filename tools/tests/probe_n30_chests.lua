-- probe_n30_chests.lua -- #84 measurements for the two map-30 Elixirs
-- assigned to gen_kefka_won (Narshe interiors; kefka_won boots {60,37}).
--
-- Findings (2026-08-17, all measured from kefka_won.mss):
--  * Chest bit 2 at (55,30): stand (55,31) face up, reachable (BFS 11).
--    This probe opens it live below, the same calls gen_kefka_won now makes.
--  * Chest bit 10 at (105,14), the Elder room: NOT reachable from any
--    controllable frame of gen_kefka_won.  BFS from {60,37} reaches no
--    stand tile of it; map 30's rooms connect only through map 20, the
--    front-door street region reaches only the south gate, the corridor
--    region only mine 50, and the one entrance chain onward
--    (50 -> 49 -> 48 -> 20 west -> Elder door (18,22) -> 30 (110,25))
--    crosses map 49's tripwire maze (EventTrigger::_49, twenty triggers
--    over x=106-116 y=12-23): stepping on (112,13) fired _cce15d, stole
--    control, and left BFS pathless to the south door (0 edges
--    blocklisted, 20 navTo retries).  The chest was "seen" by the route
--    because the win-tail cutscene stands the party in the Elder room.
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
