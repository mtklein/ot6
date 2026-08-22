-- probe_grind.lua -- INSTRUMENTATION (#132): find the live airship flight
-- position + which inputs move it, to build an autopilot.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function w(a) return H.readWord(a) end
local function snap(tag)
  H.log(string.format("f%-6d %-9s 1f64=%04X 1f60=%d 1f61=%d 33=%04X 35=%02X 3c=%04X 3e=%02X 29=%04X 26=%04X 2d=%04X",
    H.frame, tag, w(0x1f64), rd(0x1f60), rd(0x1f61), w(0x33), rd(0x35), w(0x3c), rd(0x3e),
    w(0x29), w(0x26), w(0x2d)))
end
H.run({ maxFrames = 8000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),          -- helm menu -> Lift-off
  H.pressButtons({ "a" }, 4), H.waitFrames(60),
  H.call(function() snap("aloft") end),
  -- hold A (thrust) + up, see what moves
  H.hold({ "a", "up" }), H.waitFrames(90), H.release(), H.waitFrames(6),
  H.call(function() snap("A+up") end),
  H.hold({ "a", "up" }), H.waitFrames(90), H.release(), H.waitFrames(6),
  H.call(function() snap("A+up2") end),
  -- try plain up (no A)
  H.hold({ "up" }), H.waitFrames(90), H.release(), H.waitFrames(6),
  H.call(function() snap("up") end),
  -- try left (rotate) then A
  H.hold({ "left" }), H.waitFrames(30), H.release(),
  H.hold({ "a" }), H.waitFrames(90), H.release(), H.waitFrames(6),
  H.call(function() snap("rot+A") end),
  H.logStep(function() return "done" end),
})
