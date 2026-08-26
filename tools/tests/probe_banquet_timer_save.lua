-- probe_banquet_timer_save.lua -- completes a banquet timer save using pad
-- input only (X to Save, A on slot 3, A through the overwrite confirm) and
-- reads the live timer block ($1188) before and after.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local STAGE = 5400
local function timerCount() return H.readWord(0x1189) end
local function sram(off) return emu.read(off, emu.memType.snesMemory) end
local function blockHex()
  local s = ""
  for i = 0, 5 do s = s .. string.format("%02X ", H.readByte(0x1188 + i)) end
  return s
end

H.run({ maxFrames = 30000 }, {
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
  H.call(function()
    H.writeByte(0x1188, 0x72)
    H.writeWord(0x1189, STAGE)
    H.writeByte(0x118B, 0x96)
    H.writeByte(0x118C, 0x8A)
    H.writeByte(0x118D, 0x02)
    H.writeWord(0x1FC2, 17)
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)  -- SRAM sentinel only
    H.log("[stage] block: " .. blockHex())
  end),
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end, 500, "menu", 5),
  H.waitFrames(30),
  H.pressButtons({ "up" }, 6), H.waitFrames(20),
  H.pressButtons({ "a" }, 6),
  H.waitUntil(function() return H.readByte(0x26) == 0x14 end, 400,
    "save select (natural)", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[save select] cursor $4b=%02X block: %s",
      H.readByte(0x4b), blockHex()))
  end),
  -- A on the preselected slot, then A through the overwrite confirm.
  H.driveUntil(function() return sram(0x307ff0) == 3 end, 1200, {
    H.pressButtons({ "a" }, 6), H.waitFrames(40),
  }, "natural save confirmed (slot marker back to 3)"),
  H.waitFrames(90),
  H.call(function()
    local sc = sram(0x307400 + 0x9A8 + 1) + 256 * sram(0x307400 + 0x9A8 + 2)
    local sf = sram(0x307400 + 0x9A8)
    H.log(string.format("[after save] WRAM block: %s (count=%d) | SRAM flags=%02X count=%d",
      blockHex(), timerCount(), sf, sc))
    H.screenshot("banquet_timer_aftersave")
  end),
  -- close the menu, give the field/world a moment, read again
  H.repeatN(4, { H.pressButtons({ "b" }, 6), H.waitFrames(40) }),
  H.waitUntil(function() return H.readByte(0x59) == 0 end, 600, "menu closed", 5),
  H.waitFrames(60),
  H.call(function()
    local f = H.readByte(0x1188)
    H.log(string.format("[verdict] post-save, menu closed: block: %s (count=%d)",
      blockHex(), timerCount()))
    if f == 0x72 then
      H.log("[verdict] live timer SURVIVED a natural completed save")
    else
      H.log("[verdict] live timer CORRUPTED by a natural completed save")
    end
  end),
})
