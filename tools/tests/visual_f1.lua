
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
    canary(H)
    H.screenshot("visual_f1_idle")
  end),
  H.waitFrames(40),               -- settle: command menu opens on its own
  H.pressButtons({ "a" }, 6),     -- one press: command -> ability list
  H.waitUntil(function()
    local vr = emu.memType.snesVideoRam
    for w = 0x6000, 0x7FF0 do
      if (emu.readWord(w*2, vr) & 0xFF) == 0x85
        and (emu.readWord(w*2+2, vr) & 0xFF) == 0xA2
        and (emu.readWord(w*2+4, vr) & 0xFF) == 0xAB then return true end
    end
    return false
  end, 900, "ability list rendered", 20),
  H.call(function()
    H.screenshot("visual_f1_menu")   -- for humans; goldens use the idle frame
    canary(H)
    -- deterministic menu check: find "Fire Beam" in the ability tilemap and
    -- assert the icon cell after it is the fire glyph in the fire palette
    local vr = emu.memType.snesVideoRam
    local anchor = nil
    for w = 0x6000, 0x7FF0 do
      if (emu.readWord(w*2, vr) & 0xFF) == 0x85
        and (emu.readWord(w*2+2, vr) & 0xFF) == 0xA2
        and (emu.readWord(w*2+4, vr) & 0xFF) == 0xAB then anchor = w break end
    end
    H.assertEq(anchor ~= nil, true, "Fire Beam text present in ability tilemap")
    local icon = emu.readWord((anchor + 10) * 2, vr)
    H.assertEq(icon, 0x3DEB, "fire icon glyph + red palette after Fire Beam")
  end),
})
