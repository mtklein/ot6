-- ART REVIEW PROBE, not a test: forces the broken timer on one lobo so a
-- screenshot shows the broken glyph beside intact counts.  It writes battle
-- state directly instead of breaking the monster through play, which is the
-- wrong way to assert BEHAVIOUR -- battle_break drives a real break and is
-- the test that matters.  Here the only thing under review is 16 bytes of
-- art, and this is the cheapest way to put it on screen next to its
-- neighbours.  Not registered in the suite (no @suite marker).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle2_doorstep.mss.lua"
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
    -- slot 0 broken, slot 1 left at its 3 shields for side-by-side contrast
    H.writeByte(0x3e90, 0xff)
    H.log(string.format("slot0 timer=%02x shields=%d | slot1 timer=%02x shields=%d",
      H.readByte(0x3e90), H.readByte(0x3e40),
      H.readByte(0x3e91), H.readByte(0x3e41)))
  end),
  H.waitFrames(90),
  H.call(function()
    H.screenshot("xglyph_broken")
    H.assertEq(H.fieldHudPresent(), true, "strip present for the shot")
  end),
})
