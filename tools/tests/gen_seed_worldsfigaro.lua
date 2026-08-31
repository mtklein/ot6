-- gen_seed_worldsfigaro.lua -- cut SRM seed `world-sfigaro-v1`: boot
-- south_figaro (TERRA+LOCKE+EDGAR at SOUTH FIGARO's west gate, map 75
-- (1,28), shops done -- Tonics 99, Fenix 15, gear bought), step west off
-- the gate onto the world map, and save through the game's own Save UI
-- into slot 3.  The natural human save: provisions bought, Mt. Kolts ahead.
-- run.sh captures the battery (OT6_CAPTURE_SRM); seal folds the sidecar
-- into tools/tests/checkpoints/world-sfigaro-v1/manifest.json.
--
-- Save UI drive: gen_n024_save_checkpoint.lua's, on the world map (same as
-- gen_seed_worldnarshe.lua).
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT = 0x14
local saveArg = nil

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 75, "booted on map 75, SOUTH FIGARO")
    H.assertEq(H.fieldX() == 1 and H.fieldY() == 28, true,
      "at the west gate (1,28)")
    H.assertPartyStanding("world-sfigaro seed")
  end),

  -- step west off the gate onto the world map
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.worldMode() and H.worldHasControl() and H.worldAligned())
             and calm + 1 or 0
      return calm >= 20
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 16
        if H.worldMode() then H.setPad({}); return end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(ph < 8 and { left = true } or {})
      end),
    }, "out the west gate to the world map")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.log(string.format("world position (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- open the menu
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(ZMENUSTATE) == 0x05) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(ZMENUSTATE) == 0x05 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "main menu open on the world map")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- Save enabled")
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
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.log("real Save UI wrote the world-sfigaro seed to slot 3")
  end),

  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.readByte(ZMENUSTATE) ~= 0x05 and H.worldMode()
              and H.worldHasControl()) and calm + 1 or 0
      return calm >= 30
    end, 900, {
      H.pressButtons({ "b" }, 4), H.waitFrames(20),
    }, "menu closed, overworld control back")
  end)(),
  H.waitFrames(45),
  H.call(function() H.screenshot("seed_world_sfigaro") end),
  H.logStep(function()
    return string.format("world-sfigaro-v1 saved via the real Save UI "
      .. "at frame %d, slot 3", H.frame)
  end),
})
