
-- visual canary for fight 1 (idle): OT6 font cells intact (vs ROM
-- source), the under-monster hud on the bg3 field map, and bp pips in
-- the party window. the ability-list icon assert lives in battle_break,
-- whose drive reliably traverses the list.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(200),
  H.call(function()
    H.glyphCanary()
    H.assertEq(H.fieldHudPresent(), true, "under-monster hud on the field map")
    H.assertEq(H.pipWord(), 0x2173, "party row 1 shows 1 spendable bp")
    H.screenshot("visual_f1_idle")
  end),
})
