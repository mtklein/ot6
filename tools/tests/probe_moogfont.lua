-- probe_moogfont.lua -- ROOT-CAUSE the OT6 HUD font-tile corruption seen in the
-- moogle_doorstep fight (Narshe, Kefka + Soldiers): probe_hudspray6 measured the
-- 24 OT6 glyph cells at vram $B000 diverging from their bank-F0 source for 5104
-- of 9000 frames, with OT6_FONTDIRTY==0 (no re-lay pending) -- so the HUD map,
-- which still references those cells, renders junk over the enemies.
--
-- Here: catch the clean->dirty transition, dump what the cells BECAME (blank?
-- dialogue font? sprite/monster art?), and log the battle context (dialogue
-- state, active gfx command) so the clobber can be named.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/moogle_doorstep.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom

local iconsBase, bgBase = nil, nil
local iconCells = {0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}
local allCells = {}
local function findRom()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base + i - 1, ROM) ~= sig[i] then hit = false break end
      end
      if hit then return base end
    end
    return nil
  end
  iconsBase = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                       0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  bgBase = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                    0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(iconsBase ~= nil and bgBase ~= nil, true, "OT6 glyph data in rom")
  for k, c in ipairs(iconCells) do allCells[c] = iconsBase + (k - 1) * 16 end
  for k = 1, 16 do allCells[emu.read(bgBase - 17 + k, ROM)] = bgBase + (k - 1) * 16 end
end
local function dirtyList()
  local d = {}
  for cell, romBase in pairs(allCells) do
    local bad = false
    for i = 0, 15 do if emu.read(0xB000 + cell * 16 + i, VR) ~= emu.read(romBase + i, ROM) then bad = true break end end
    if bad then d[#d + 1] = cell end
  end
  table.sort(d)
  return d
end
local function hex16(cell)
  local s = {}
  for i = 0, 15 do s[#s + 1] = string.format("%02x", emu.read(0xB000 + cell * 16 + i, VR)) end
  return table.concat(s)
end
local function romhex16(cell)
  local rb = allCells[cell]
  local s = {}
  for i = 0, 15 do s[#s + 1] = string.format("%02x", emu.read(rb + i, ROM)) end
  return table.concat(s)
end
-- dialogue / battle-message state (battle msg flag $62ac, dialog $ba/$d3)
local function ctx()
  return string.format("msg62ac=%02x 64d5=%02x ee9c3=%02x 7b83=%02x 7bc2=%02x fontdirty=%02x present=%d",
    H.readByte(0x62ac), H.readByte(0x64d5), H.readByte(0xe9c3), H.readByte(0x7b83),
    H.readByte(0x7bc2), H.readByte(0x57b9), H.monstersPresent())
end

local phase = "clean"
local transitions = 0
local aPhase = 0

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() findRom(); H.log("[moogfont] map " .. (H.mapId() & 0x1ff)) end),
  H.driveUntil(function() return H.battleLoadStarted() end, 12000, {
    H.hold({ "up" }), H.waitFrames(12), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4), H.waitFrames(6),
  }, "the Narshe fight starts"),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle up", 10),
  H.waitFrames(120),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[moogfont] formation %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    local d = dirtyList()
    H.log(string.format("[moogfont] at settle: dirty=%d %s", #d, ctx()))
    H.screenshot("moogfont_settle")
  end),
  -- watch for the first clobber, and each transition, for a while
  (function()
    local f = 0
    return H.driveUntil(function() f = f + 1; return f > 4000 or transitions >= 6 end, 4200, {
      H.call(function()
        aPhase = (aPhase + 1) % 90
        if aPhase % 30 < 4 and H.readByte(0x7bca) ~= 0 then H.setPad({ "a" })
        elseif H.dialogWaiting() then H.setPad(aPhase % 20 < 3 and { "a" } or {})
        else H.setPad({}) end
        local d = dirtyList()
        local nowDirty = #d > 0
        if nowDirty and phase == "clean" then
          phase = "dirty"; transitions = transitions + 1
          H.log(string.format("[moogfont] === CLEAN->DIRTY f=%d dirtyCells=%d [%s] %s",
            H.frame, #d, table.concat((function() local t={} for _,c in ipairs(d) do t[#t+1]=string.format("%02x",c) end return t end)(), " "), ctx()))
          local sample = d[1]
          H.log(string.format("[moogfont]   cell %02x vram=%s", sample, hex16(sample)))
          H.log(string.format("[moogfont]   cell %02x  rom=%s", sample, romhex16(sample)))
          H.screenshot(string.format("moogfont_dirty_f%d", H.frame))
        elseif not nowDirty and phase == "dirty" then
          phase = "clean"; transitions = transitions + 1
          H.log(string.format("[moogfont] === DIRTY->CLEAN f=%d %s", H.frame, ctx()))
        end
        if f % 500 == 0 then
          H.log(string.format("[moogfont] +%d dirty=%d %s", f, #d, ctx()))
        end
      end),
      H.waitFrames(1),
    }, "font-clobber transitions observed")
  end)(),
  H.call(function()
    H.log(string.format("[moogfont] observed %d transitions; final dirty=%d %s",
      transitions, #dirtyList(), ctx()))
    H.screenshot("moogfont_end")
  end),
})
