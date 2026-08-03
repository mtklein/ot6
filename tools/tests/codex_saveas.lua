-- @suite frontier=worldmap_narshe
-- codex_saveas.lua -- an unsaved New Game's transient codex follows its first
-- real in-game save into the chosen slot.
--
-- The world-map fixture supplies a legitimate Save menu. We stage transient
-- knowledge, drive the ordinary field menu's Save command with PAD INPUT
-- ONLY (save-drive rule, tools/tests/README; probe_banquet_timer_save is the
-- template -- the old forced-ZMENUSTATE shortcut skipped the menu entry's own
-- writes and left menu tasks running on a corrupted exit), save into empty
-- slot 3, and assert both the payload transfer and the active-page lifecycle
-- marker. This exercises CopyGameDataToSRAM's real Ot6CodexSaveAs hook rather
-- than calling an OT6 helper directly.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
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
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    300, "main menu", 5),
  -- UP wraps the main-menu cursor from Items straight down to Save (row 6);
  -- A then runs SelectMainMenuOption_06 itself (field_menu.asm), so the
  -- $9e/$9f exit bookkeeping and the save-enabled check are the real code
  -- path, not an imitation.  World-map saving is legal, so it lets us in.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  -- Walk the slot cursor to slot 3 (zero-based 2) by pad, confirming by
  -- READING the cursor back each frame -- no cursor pokes, no checksum-cache
  -- pokes.  This run's SRAM is fresh so slot 3 saves instantly; were it
  -- occupied, the driveUntil below presses A on through the overwrite
  -- confirm, same as probe_banquet_timer_save.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.pressButtons({ "a" }, 4),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("save drive: state=$%02x cursor=%d selected=%d arg=%s active=%d last=%d magic=%02x%02x",
      H.readByte(ZMENUSTATE), H.readByte(0x4b), H.readByte(0x66),
      tostring(saveArg), H.readByte(ACTIVE), sram(0x307ff0),
      sram(0x316801), sram(0x316800)))
  end),
  -- $021f is wSaveSlotToLoad ONLY while the menu module owns that RAM.
  -- The moment the world module resumes (menu close + ~30 frames), a block
  -- restore puts the world's own variable back in that cell -- measured
  -- 2026-07-27: CopyGameDataToSRAM stores 3 from c3:1538, and at world
  -- resume the cell reads 5 with no CPU write ever firing. The old fixture
  -- happened to hold 3 there, so reading it post-menu passed by
  -- coincidence for months. Observe the save through channels that are
  -- context-stable instead: the SRAM last-saved-slot marker ($307ff0), the
  -- captured CopyGameDataToSRAM argument, and the codex payload itself.
  H.driveUntil(function()
    return sram(0x307ff0) == 3 and sram(0x316800) == 0x4f
  end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 3"),
  H.call(function()
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.assertEq(sram(0x307ff0), 3, "SRAM last-saved-slot marker is 3")
    H.assertEq(sram(0x316800), 0x4f, "slot 3 codex magic 'O'")
    H.assertEq(sram(0x316801), 0x38, "slot 3 codex magic '8'")
    H.assertEq(sram(SLOT3_ELEM) & 0x01, 0x01,
      "first save transferred transient fire knowledge into slot 3")
    H.assertEq(sram(TEMP_ELEM) & 0x01, 0x01,
      "Save As did not destroy the transient source page")
  end),
})
