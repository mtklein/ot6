-- probe_mpu_boot.lua -- measurement instrument for probe_mp_universal's
-- boot step: what state does a cold Continue of terra-returned-v1 land in,
-- and which inputs take off / land / disembark.  Not a suite test.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function st(tag)
  return H.call(function()
    H.log(string.format(
      "[%s] $1f64=%04X $1f66=%02X world=(%d,%d) ship34=(%d,%d) ctrl=%s $0201=%02X $c2=%02X",
      tag, H.readWord(0x1f64), H.readByte(0x1f66),
      H.worldX(), H.worldY(),
      H.readWord(0x34) >> 4, H.readWord(0x38) >> 4,
      tostring(H.worldHasControl()), H.readByte(0x0201), H.readByte(0xc2)))
    H.screenshot("mpuboot_" .. tag)
  end)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  st("boot"),

  -- try movement: whether holding a direction taxis or flies the ship
  H.hold({ "down" }), H.waitFrames(120), H.release(),
  st("after_hold_down"),

  -- try A: whether it takes off
  H.pressButtons({ "a" }, 8), H.waitFrames(180),
  st("after_a"),

  -- try another A + direction
  H.hold({ "down" }), H.waitFrames(120), H.release(),
  st("after_a_down"),

  -- try B: whether it lands or disembarks
  H.pressButtons({ "b" }, 8), H.waitFrames(240),
  st("after_b"),

  H.pressButtons({ "b" }, 8), H.waitFrames(240),
  st("after_b2"),

  H.logStep(function() return "probe_mpu_boot complete" end),
})
