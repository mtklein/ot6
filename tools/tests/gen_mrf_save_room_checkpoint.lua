-- gen_mrf_save_room_checkpoint.lua -- generate SRAM checkpoint B,
-- `mrf-save-room-v1`: boot ifrit_entry (map 264 {3,7}), walk the {3,5}
-- door into the map-270 save room, walk onto the vanilla save point at
-- {25,10}, and save through the game's own Save UI into slot 3.  run.sh
-- captures Mesen's complete 32 KiB battery file after shutdown.
--
-- Standing on a save tile re-enters the SavePoint script every frame
-- ($01B5 gate -> early return), so hasControl() flickers indefinitely
-- there.  No settle predicate can hold on the tile; arrival is judged on
-- position, $01BF and tile alignment only, and the menu is opened
-- through repeated edge presses.

local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

-- Walk one direction, absorbing dialogs/battles.  calmPred defaults to
-- settled(); the save-tile approach passes a relaxed one.
local function tapInto(dir, pred, maxFrames, what, calmPred)
  local phase, n, ph, calm = 0, 0, 0, 0
  calmPred = calmPred or settled
  return H.driveUntil(function()
    calm = (pred() and calmPred()) and calm + 1 or 0
    return calm >= 8
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        if pred() then return end
        if settled() or (calmPred() and H.tileAligned()) then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function onSaveTile(x, y)
  return function()
    return H.fieldX() == x and H.fieldY() == y and sw(0x01BF) == 1
  end
end
local function tileCalm()
  return H.tileAligned() and not H.dialogWaiting() and not H.battleLoadStarted()
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/ifrit_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 264, "booted on map 264 (ifrit_entry)")
    H.assertEq(H.fieldX(), 3, "boot x")
    H.assertEq(H.fieldY(), 7, "boot y")
  end),

  -- through the {3,5} door into the save room
  H.navTo(3, 6, { playBattles = "flee", maxFrames = 6000 }),
  tapInto("up", function() return map() == 270 end, 9000,
    "door 264 (3,5) -> map 270"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 270, "the save room is map 270")
    H.assertEq(H.fieldX(), 25, "270 landing x")
    H.assertEq(H.fieldY(), 14, "270 landing y")
  end),

  -- onto the save point
  H.navTo(25, 11, { playBattles = "flee", maxFrames = 6000 }),
  tapInto("up", onSaveTile(25, 10), 9000,
    "onto the save tile 270 (25,10)", tileCalm),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script enabled saving")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    -- The boundary table, pre-save: everything but the sram witnesses,
    -- which only the save itself can put into the battery.
    H.assertExitContractPreSave("mrf-save-room-v1")
    H.screenshot("checkpoint_b_save_tile")
  end),

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
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
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
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the mrf-save-room checkpoint to slot 3")
  end),

  -- close the menu and check the game is back in playable field state,
  -- still standing on the boundary tile; then the full exit contract.
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
    H.assertExitContract("mrf-save-room-v1")
    H.screenshot("checkpoint_b_saved")
  end),
  H.logStep(function()
    return string.format("mrf-save-room-v1 saved via the real Save UI at "
      .. "frame %d -- map 270 (25,10), slot 3; run.sh captures the battery "
      .. "on shutdown", H.frame)
  end),
})
