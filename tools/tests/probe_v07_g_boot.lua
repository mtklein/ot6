-- probe_v07_g_boot.lua -- what a cold Continue of narshe-mission-v1
-- restores.  Not a suite test.  Run with:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/narshe-mission-v1 \
--   tools/tests/run.sh tools/tests/probe_v07_g_boot.lua
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

local function st(tag)
  H.log(string.format("[%s] world=(%d,%d) $34/$38=(%d,%d) $11FA=%02X "
    .. "$11F3=%02X $11F5=%02X $1F60=%d $1F61=%d $1F62=%d $1F63=%d "
    .. "$1F6A=%d $1F6B=%d", tag, H.worldX(), H.worldY(), shipX(), shipY(),
    H.readByte(0x11FA), H.readByte(0x11F3), H.readByte(0x11F5),
    H.readByte(0x1F60), H.readByte(0x1F61), H.readByte(0x1F62),
    H.readByte(0x1F63), H.readByte(0x1F6A), H.readByte(0x1F6B)))
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    st("boot")
    H.screenshot("gboot_1")
  end),
  -- A on the boot tile: whether anything happens
  H.pressButtons({ "a" }, 8),
  H.waitFrames(180),
  H.call(function() st("after A"); H.screenshot("gboot_2") end),
  -- walk to (84,36) and try again
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 84 and H.worldY() == 36 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ down = true }) end),
    }, "walk DOWN to (84,36)")
  end)(),
  H.release(), H.waitFrames(30),
  H.call(function() st("at 84,36"); H.screenshot("gboot_3") end),
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function()
    return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
  end, 900, "liftoff from (84,36)", 5),
  H.waitFrames(120),
  H.call(function() st("airborne"); H.screenshot("gboot_4") end),
  H.logStep("G boot probe complete"),
})
