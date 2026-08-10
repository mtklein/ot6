-- gen_post_opera_anchor.lua -- create the v1 battery anchor from blackjack.
--
-- This does not synthesize vanilla save checksums.  It opens the ordinary
-- field menu, enters vanilla's Save selector, chooses slot 3, and lets
-- CopyGameDataToSRAM write the save.  run.sh captures Mesen's complete 32 KiB
-- battery file after shutdown.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/blackjack.mss.lua"

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2
local phase = 0

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end

H.run({ maxFrames = 5000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 1200, "Blackjack fixture fade-in", 10),
  (function()
    local calm = 0
    return H.driveUntil(function()
      local ok = (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
        and H.worldAligned()
        and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
      calm = ok and calm + 1 or 0
      return calm >= 60
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "a", "start" } or {})
      end),
    }, "settle Blackjack arrival")
  end)(),
  H.release(),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 0, "post-Opera anchor starts on WoB map")
    H.assertEq(H.worldHasControl(), true, "Blackjack route has world control")
    H.assertEq(sw(0x034b), 0, "Ultros 2 cleared")
    H.assertEq(sw(0x005d), 1, "Setzer bargain complete")
    H.assertEq(sw(0x005e), 1, "Blackjack arrival complete")
    H.log(string.format("menu preflight: $19=%02x $e7=%02x $59=%02x $26=%02x field=(%d,%d) world=(%d,%d)",
      H.readByte(0x19), H.readByte(0xe7), H.readByte(0x59), H.readByte(0x26),
      H.fieldX(), H.fieldY(), H.worldX(), H.worldY()))
  end),
  -- Cross Vector's entrance once, then immediately leave.  Besides proving
  -- the exact anchor doorstep, the field/world handoff leaves the ordinary
  -- world menu available (the Blackjack-arrival frame itself still carries
  -- special vehicle state that rejects X).
  H.driveUntil(function() return (H.mapId() & 0x1ff) == 323 end, 1200, {
    H.hold({ "right" }),
  }, "step right into Vector"),
  H.release(),
  H.waitUntil(function() return H.hasControl() end, 800, "Vector control", 5),
  H.call(function()
    H.assertEq(H.fieldX(), 2, "Vector entrance x")
    H.assertEq(H.fieldY(), 17, "Vector entrance y")
  end),
  H.navTo(1, 17, { honest = "flee", maxFrames = 600 }),
  H.driveUntil(function() return (H.mapId() & 0x1ff) == 0 end, 800, {
    H.hold({ "left" }),
  }, "leave Vector to its west doorstep"),
  H.release(),
  H.waitFrames(180),
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end,
    500, "field menu open", 5),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- ARM THE HONEST SAVE RECEIPT (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument the
    -- save runs with (codex_saveas's instrument).  This replaces the old
    -- zeroed-$307ff0 sentinel -- an SRAM write -- as the proof that the
    -- real save ran to completion for slot 3.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- THE PAD-DRIVEN SAVE (save-drive rule, tools/tests/README.md;
  -- codex_saveas and probe_banquet_timer_save are the templates): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the menu's own
  -- SelectMainMenuOption_06 path, the slot cursor is STEERED to slot 3 by
  -- pad against its live cell, and A confirms on through any overwrite
  -- prompt.  No ZMENUSTATE poke, no cursor poke, no display-cache poke,
  -- and no witness seeding: the codex payload the battery carries is
  -- whatever the chain EARNED, read and logged below (issue #75).
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 (the context-stable witness, #29)")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    -- the codex witness cells are READ, never seeded (issue #75): the
    -- battery carries whatever the chain actually earned.  The phase-2
    -- anchor re-cuts measure these and the entry contracts follow the
    -- measurement (never the reverse).
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote post-Opera anchor to slot 3")
  end),
})
