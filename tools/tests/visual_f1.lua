
-- visual canary for fight 1: OT6 font cells intact (vs ROM source), the
-- under-monster hud on the bg3 field map, and bp pips in the party window.
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
    H.glyphCanary()
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
