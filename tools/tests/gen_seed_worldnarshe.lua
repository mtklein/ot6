-- gen_seed_worldnarshe.lua -- cut SRM seed `world-narshe-v1`: boot
-- worldmap_narshe (LOCKE + TERRA on foot at WoB (84,34), the Narshe exit
-- spawn), and save through the game's own Save UI into slot 3, right there
-- on the world map -- the first save a human makes, stepping onto the
-- overworld.  run.sh captures the 32 KiB battery on shutdown
-- (OT6_CAPTURE_SRM); `sram_checkpoint.py seal` folds the sidecar into
-- tools/tests/checkpoints/world-narshe-v1/manifest.json.
--
-- The Save UI drive is gen_n024_save_checkpoint.lua's, retargeted to the
-- world map: the menu opens with X the same way, $0201 bit7 gates the Save
-- row the same way (set anywhere on the overworld), and the witness is the
-- same pair -- the CopyGameDataToSRAM exec hook capturing A, and SRAM
-- $307ff0 recording the slot.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT = 0x14
local saveArg = nil

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/worldmap_narshe.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot state is on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.assertEq(H.worldX() == 84 and H.worldY() == 34, true,
      "at the Narshe spawn (84,34)")
    H.assertPartyStanding("world-narshe seed")
  end),

  -- open the menu: edge-press X until the main menu state holds
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
      "menu-flags $0201 bit7 SET -- Save is enabled on the world map")
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
      "SRAM $307ff0 records slot 3")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.log("real Save UI wrote the world-narshe seed to slot 3")
  end),

  -- close the menu back to the overworld
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
  H.call(function()
    H.assertEq(H.worldMode() and H.worldX() == 84 and H.worldY() == 34, true,
      "still at the Narshe spawn after the save")
    H.screenshot("seed_world_narshe")
  end),
  H.logStep(function()
    return string.format("world-narshe-v1 saved via the real Save UI "
      .. "at frame %d -- WoB (84,34), slot 3", H.frame)
  end),
})
