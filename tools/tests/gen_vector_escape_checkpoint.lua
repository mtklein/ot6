-- gen_vector_escape_checkpoint.lua -- generate SRAM checkpoint E,
-- `vector-escape-v1` (the A-F save-point boundary range is lettered in
-- tools/tests/savestate_graph.py): boot n128_won (the nearest generated
-- predecessor, which gen_n128 parks ON the escape map's save point, map 240
-- {58,7}, the sparkle $06AE revealed), re-arm the save-enable flow if the
-- savestate did not carry it, and save through the game's OWN Save UI into
-- slot 3.  run.sh captures the 32 KiB battery on shutdown.
--
-- See gen_mrf_save_room_checkpoint.lua for the hazards this file's shape
-- inherits: the save-tile control flicker (arrival and idle judged without
-- hasControl), the codex witness seeding (a waived #75 poke before the
-- save), and the $307ff0 sentinel as the only context-stable receipt
-- that CopyGameDataToSRAM ran (#29).
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on map 240 (n128_won)")
    H.assertEq(H.fieldX(), 58, "boot x -- ON the save tile")
    H.assertEq(H.fieldY(), 7, "boot y")
    H.assertEq(sw(0x06AE), 1, "$06AE SET -- the sparkle is revealed")
  end),
  -- The savestate was generated standing on the tile with $01BF/$01B5 set; if
  -- a load ever comes up without them, step off and back on to re-fire the
  -- SavePoint script rather than saving through a stale flag.
  H.cond(function() return sw(0x01BF) == 1 end, {}, {
    (function() local calm = 0
      return H.driveUntil(function()
        calm = (H.fieldX() == 58 and H.fieldY() == 7 and sw(0x01BF) == 1
                and H.tileAligned() and not H.dialogWaiting()
                and not H.battleLoadStarted()) and calm + 1 or 0
        return calm >= 8
      end, 6000, {
        H.call(function()
          if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
          if H.dialogWaiting() then H.setPad({ "a" }); return end
          if H.fieldX() == 58 and H.fieldY() == 7 then
            H.setPad({ left = true })      -- step off...
          else
            H.setPad({ right = true })     -- ...and back on
          end
        end),
      }, "re-fire the SavePoint script on (58,7)")
    end)(),
  }),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the save-enable flow ran")
    H.assertExitContractPreSave("vector-escape-v1")
    H.screenshot("checkpoint_e_save_tile")
  end),

  -- Open the ordinary field menu ($0059 blip-proofed; see checkpoint B's
  -- gen).
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) ~= 0) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "field menu open on the save tile")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- Arm the input-driven save receipt (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument the
    -- save runs with (codex_saveas's instrument).  This replaces the old
    -- zeroed-$307ff0 sentinel, which was an SRAM write, as the evidence that
    -- the real save ran to completion for slot 3.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- The pad-driven save (save-drive rule, tools/tests/README.md;
  -- codex_saveas and probe_banquet_timer_save are the templates): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the menu's own
  -- SelectMainMenuOption_06 path, the slot cursor is steered to slot 3 by
  -- pad against its live cell, and A confirms on through any overwrite
  -- prompt.  There is no ZMENUSTATE poke, no cursor poke, no display-cache
  -- poke, and no witness seeding: the codex payload the battery carries is
  -- whatever the chain earned, read and logged below (issue #75).
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
    -- the codex witness cells are read, never seeded (issue #75): the
    -- battery carries whatever the chain earned.  The phase-2 checkpoint
    -- re-cuts measure these, and the entry contracts follow the
    -- measurement rather than the other way round.
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the vector-escape checkpoint to slot 3")
  end),

  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) == 0) and calm + 1 or 0
      return calm >= 30
    end, 900, {
      H.pressButtons({ "b" }, 4), H.waitFrames(20),
    }, "field menu closed")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("vector-escape-v1")
    H.screenshot("checkpoint_e_saved")
  end),
  H.logStep(function()
    return string.format("vector-escape-v1 saved via the real Save UI at "
      .. "frame %d -- map 240 (58,7), slot 3", H.frame)
  end),
})
