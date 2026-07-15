
-- shared canary: assert OT6's sprite tiles still hold OT6's art.
-- catches formation art clobbering our claimed VRAM (the fight-2 bug).
local function ot6TileSum(t)
  local vr = emu.memType.snesVideoRam
  local base = (t < 0x100 and (0x2000 + t*16) or (0x3000 + (t-0x100)*16)) * 2
  local sum = 0
  for b = 0, 31 do sum = sum + emu.read(base + b, vr) end
  return sum
end
local function canary(H)
  local expect = { [0x100]=944, [0x144]=568, [0x0C2]=1736, [0x164]=1683, [0x1A0]=654 }
  for t, want in pairs(expect) do
    local got = ot6TileSum(t)
    H.assertEq(got, want, string.format("OT6 tile %03X intact (VRAM clobber canary)", t))
  end
end

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
    canary(H)   -- pre-action: tiles usually still intact
  end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(600),
  H.call(function()
    H.screenshot("visual_f2_after_action")
    canary(H)   -- KNOWN-FAIL: attack effect art clobbers our sprite tiles
  end),
})
