-- @suite frontier=worldmap_narshe
-- codex_saveas.lua -- an unsaved New Game's transient codex follows its first
-- real in-game save into the chosen slot.
--
-- The world-map fixture supplies a legitimate Save menu. We stage transient
-- knowledge, force the save-select state after opening the ordinary field
-- menu, save into empty slot 3, and assert both the payload transfer and the
-- active-page lifecycle marker. This exercises CopyGameDataToSRAM's real
-- Ot6CodexSaveAs hook rather than calling an OT6 helper directly.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14
local ACTIVE = 0x021f
local TEMP_ELEM, SLOT3_ELEM = 0x316c10, 0x316810

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local saveArg
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end

H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  H.call(function()
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      local st = emu.getState()
      saveArg = st["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
    -- Simulate knowledge earned before a New Game's first save. Slot 3 is
    -- empty/independent; the transient page knows fire for species 0.
    H.writeByte(ACTIVE, 0)
    emu.write(0x316c00, 0x4f, emu.memType.snesMemory)
    emu.write(0x316c01, 0x38, emu.memType.snesMemory)
    emu.write(TEMP_ELEM, 0x01, emu.memType.snesMemory)
    emu.write(0x316800, 0, emu.memType.snesMemory)
    emu.write(0x316801, 0, emu.memType.snesMemory)
    emu.write(SLOT3_ELEM, 0, emu.memType.snesMemory)
  end),

  H.pressButtons({ "x" }, 4),
  H.waitFrames(120),
  H.call(function()
    -- Enter vanilla's save-select initializer; world-map saving is legal.
    H.writeByte(ZMENUSTATE, SAVE_SELECT_INIT)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2) -- zero-based cursor: slot 3
    H.writeWord(0x95, 0) -- save-menu checksum cache: make slot 3 empty
  end),
  H.pressButtons({ "a" }, 4),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("save drive: state=$%02x cursor=%d selected=%d arg=%s active=%d last=%d magic=%02x%02x",
      H.readByte(ZMENUSTATE), H.readByte(0x4b), H.readByte(0x66),
      tostring(saveArg), H.readByte(ACTIVE), sram(0x307ff0),
      sram(0x316801), sram(0x316800)))
  end),
  H.driveUntil(function() return H.readByte(ACTIVE) == 3 end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 3"),
  H.call(function()
    H.assertEq(H.readByte(ACTIVE), 3, "first save selected persistent slot 3")
    H.assertEq(sram(0x316800), 0x4f, "slot 3 codex magic 'O'")
    H.assertEq(sram(0x316801), 0x38, "slot 3 codex magic '8'")
    H.assertEq(sram(SLOT3_ELEM) & 0x01, 0x01,
      "first save transferred transient fire knowledge into slot 3")
    H.assertEq(sram(TEMP_ELEM) & 0x01, 0x01,
      "Save As did not destroy the transient source page")
  end),
})
