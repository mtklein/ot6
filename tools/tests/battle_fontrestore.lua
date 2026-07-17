-- battle_fontrestore: a battle dialogue uploads its text over our font
local goodFire, goodShield
-- cells at vram $5800, and the vanilla small-font restore on close brings
-- back only the vanilla glyphs — so our element icons / hud glyphs
-- vanish until the next battle (the Whelk-dialogue bug the user hit).
-- The fix: the dialogue-close path (_c143b9 -> Ot6FontRestoreMark_ext)
-- runs the vanilla small-font restore to COMPLETION, then sets
-- OT6_FONTDIRTY ($57d5), and the battle NMI re-lays our icons in vblank
-- (flag-after-restore ordering matters: battle_dlgmenu gates the real
-- dialogue flow). This test drives the MECHANISM directly: corrupt the
-- icon cells in vram, raise the flag, and confirm the NMI restores them
-- and clears the flag.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local vr = emu.memType.snesVideoRam
local FONTDIRTY = 0x57d5

-- a couple of our font cells (fire icon $eb, a hud shield glyph $65) at
-- vram $b000 + cell*16 (2bpp small font)
local function cellBytes(cell)
  local t = {}
  for i = 0, 15 do t[#t + 1] = emu.read(0xB000 + cell*16 + i, vr) end
  return table.concat(t, ",")
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  -- baseline: our icons are present (glyphCanary passes elsewhere); snapshot
  H.call(function()
    goodFire = cellBytes(0xeb)
    goodShield = cellBytes(0x65)
    H.log("baseline fire cell: " .. goodFire)
    H.assertEq(goodFire ~= string.rep("0,", 15) .. "0", true,
      "fire icon present before corruption")
  end),
  -- simulate the dialogue clobber: overwrite our cells with garbage, as a
  -- font-restore DMA would. (writing vram directly from lua is fine.)
  H.call(function()
    for _, cell in ipairs({ 0xeb, 0xec, 0xed, 0x64, 0xef, 0xfb, 0xfc, 0xfd,
                            0x65, 0x66, 0x67, 0x71 }) do
      for i = 0, 15 do emu.write(0xB000 + cell*16 + i, 0x5a, vr) end
    end
    H.log("corrupted fire cell: " .. cellBytes(0xeb))
    H.assertEq(cellBytes(0xeb) ~= goodFire, true, "cells corrupted")
  end),
  -- raise the dirty flag exactly as the dialogue-close hook does
  H.call(function() H.writeByte(FONTDIRTY, 1) end),
  -- the battle NMI must re-lay our icons within a frame or two and clear
  -- the flag
  H.waitUntil(function()
    return H.readByte(FONTDIRTY) == 0 and cellBytes(0xeb) == goodFire
  end, 300, "nmi re-laid the font icons", 1),
  H.call(function()
    H.log("restored fire cell: " .. cellBytes(0xeb))
    H.assertEq(cellBytes(0xeb), goodFire, "fire icon restored exactly")
    H.assertEq(cellBytes(0x65), goodShield, "hud shield glyph restored exactly")
    H.assertEq(H.readByte(FONTDIRTY), 0, "dirty flag cleared")
    H.glyphCanary()   -- full VRAM-vs-ROM check of every OT6 font cell
  end),
  -- and it must NOT re-lay every frame (flag stays clear when quiet)
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.readByte(FONTDIRTY), 0, "flag stays clear when no dialogue")
  end),
})
