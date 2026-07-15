
-- visual canary for fight 2 (second formation): same checks as fight 1,
-- run again after an attack round since effect art loads mid-fight.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle2_doorstep.mss.lua"
H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 2 active", 30),
  H.waitFrames(200),
  H.call(function()
    H.screenshot("visual_f2_idle")
    H.glyphCanary()
    H.assertEq(H.fieldHudPresent(), true, "under-monster hud on the field map")
    H.assertEq(H.isPipGlyph(H.pipWord()), true, "party row 1 shows bp pips")
  end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(600),
  H.call(function()
    H.screenshot("visual_f2_after_action")
    H.glyphCanary()   -- effect art must not clobber our font cells
    if H.monstersPresent() then
      H.assertEq(H.fieldHudPresent(), true, "hud survives the attack round")
    end
    H.assertEq(H.isPipGlyph(H.pipWord()), true, "pips survive the attack round")
  end),
})
