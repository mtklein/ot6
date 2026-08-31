-- gen_seed_hub.lua -- cut SRM seed `hub-v1`: boot scenario_hub (SCENARIO
-- MOG alone on map 9, the three-scenario split, no scenario yet played),
-- walk onto the hub's own save point at (8,6), and save through the game's
-- Save UI into slot 3.  This is the vanilla game's designated branch-point
-- save -- the seed future work forks all three scenarios from.
-- run.sh captures the battery (OT6_CAPTURE_SRM); seal folds the sidecar
-- into tools/tests/checkpoints/hub-v1/manifest.json.
--
-- The save tile is approached like gen_n024_save_checkpoint.lua's sparkle:
-- navTo a neighbor, then tap into it (the sparkle object blocks BFS), and
-- $01BF (the shared SavePoint script's switch) is the arrival witness.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT = 0x14
local saveArg = nil

local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function onSaveTile()
  return H.fieldX() == 8 and H.fieldY() == 6 and sw(0x01BF) == 1
end
local function tileCalm()
  return H.tileAligned() and not H.dialogWaiting() and not H.battleLoadStarted()
end

-- gen_n024_save_checkpoint.lua's tapInto, verbatim
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

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/scenario_hub.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 9, "booted on map 9, the scenario hub")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true,
      "SCENARIO_MOG (char 13) is the party")
    H.assertEq(sw(0x001E), 0, "LOCKE's scenario not done")
    H.assertEq(sw(0x0044), 0, "SABIN's scenario not done")
    H.assertEq(sw(0x0021), 0, "TERRA/BANON's scenario not done")
    H.log(string.format("hub boot at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- to the save point: neighbor below, then tap up onto (8,6)
  H.navTo(8, 7, { maxFrames = 6000, playBattles = true }),
  tapInto("up", onSaveTile, 9000, "onto the hub save tile (8,6)", tileCalm),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1,
      "$01BF SET -- the shared SavePoint script ran")
    H.screenshot("seed_hub_tile")
  end),

  -- open the field menu on the save tile
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
      "menu-flags $0201 bit7 SET -- Save enabled on the save point")
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
    H.log("real Save UI wrote the hub seed to slot 3")
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
  H.call(function() H.screenshot("seed_hub_saved") end),
  H.logStep(function()
    return string.format("hub-v1 saved via the real Save UI at frame %d "
      .. "-- map 9 (8,6), slot 3", H.frame)
  end),
})
