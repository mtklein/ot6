-- probe_grind.lua -- the airship is FLYABLE + LANDABLE, headless (#132).
--
-- The working technique (owner-guided), for driving the WoB airship:
--   * After Lift-off, WAIT ~150 frames for the flight to settle before input.
--   * MOVE with Y-STRAFE: hold Y + a dpad direction = clean grid movement
--     (west/north/east/south, ~7 tiles / 60f), no momentum -- release to stop
--     dead on a tile. (Turning via left/right + A works but is momentum-y;
--     Y-strafe is "like walking on a grid".)  A + heading is faster for gross
--     travel across the map.
--   * LAND with B (-> LandAirship): only over OPEN interior land with space
--     around the shadow -- NOT near mountains, water, forest, or coast EDGES.
--     A bad tile "bounces" ($19 spikes ~6 then reverts, still airborne);
--     an open tile lands (map leaves airship mode, party on foot).
--   * So landing = strafe the grid trying B at each stop until one takes.
--     [Corrected by probe_land_grind (#133): $c2 bit1 IS authoritative --
--     LandAirship refuses iff it is set, and the descent is unconditional
--     once started.  The "bounce" this header used to describe was a
--     detection artifact: $1f64 bit13 stays SET after a world-map landing
--     (party on foot, $20 leaves 1), so onFoot() below reads airborne
--     forever; it only cleared here because this run's landing hit a
--     location entrance, which loads a field map.]
-- Live state: X=$33/$35, Y=$37/$39 (tile=fine>>12); heading $73; $c2 terrain.
--
-- This probe demonstrates it end to end: cross west off the mountainous Thamasa
-- continent, then Y-strafe-search until the party lands on foot.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function tileX() return (((rd(0x35)<<16)|H.readWord(0x33))>>12)&0xFF end
local function tileY() return (((rd(0x39)<<16)|H.readWord(0x37))>>12)&0xFF end
local function onFoot() return (H.readWord(0x1f64) & 0x2000) == 0 end
local function snap(tag)
  H.log(string.format("f%-6d %-8s pos=(%d,%d) c2=%02X hdg=%d onfoot=%s",
    H.frame, tag, tileX(), tileY(), rd(0xc2), rd(0x73), tostring(onFoot())))
end
local steps = {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(150),
  -- turn west and cross the channel with thrust
  H.hold({ "left", "a" }), H.waitFrames(38), H.release(),
  H.hold({ "a" }), H.waitFrames(300), H.release(), H.waitFrames(20),
  H.call(function() snap("crossed"); H.screenshot("cross") end),
}
-- Y-strafe land-search over the western landmass: snake pattern, B at each stop
local PATH = { "left","up","left","down","left","up","up","left","down","down",
               "left","up","left","down","down","right","up","left" }
for i, dir in ipairs(PATH) do
  steps[#steps+1] = H.cond(function() return not onFoot() end, {
    H.hold({ "y", dir }), H.waitFrames(20), H.release(), H.waitFrames(12),
    H.hold({ "b" }), H.waitFrames(6), H.release(), H.waitFrames(110),
    H.call(function()
      H.log(string.format("  try %d at (%d,%d): %s", i, tileX(), tileY(),
        onFoot() and "LANDED" or "bounced"))
      if i % 6 == 0 then H.screenshot("cr_" .. i) end
    end),
  }, {})
end
steps[#steps+1] = H.waitFrames(60)
steps[#steps+1] = H.call(function()
  H.log(string.format("RESULT onfoot=%s map=%d field=(%d,%d) worldctrl=%s",
    tostring(onFoot()), H.readWord(0x1f64) & 0x3ff, H.fieldX and H.fieldX() or -1,
    H.fieldY and H.fieldY() or -1, tostring(H.worldHasControl and H.worldHasControl())))
  H.screenshot("cr_final")
end)
steps[#steps+1] = H.cond(function() return onFoot() end, { H.saveState("wob_landed.mss") }, {})
steps[#steps+1] = H.logStep(function() return "done" end)
H.run({ maxFrames = 16000 }, steps)
