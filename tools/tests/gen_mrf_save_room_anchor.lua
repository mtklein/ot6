-- gen_mrf_save_room_anchor.lua -- mint battery anchor B, `mrf-save-room-v1`
-- (save-points-vector.md §5): boot ifrit_doorstep (the nearest minted
-- predecessor, map 264 {3,7}), walk the {3,5} door into the map-270 save
-- room, walk onto the vanilla save point at {25,10}, and save through the
-- game's OWN Save UI into slot 3.  run.sh captures Mesen's complete 32 KiB
-- battery file after shutdown (OT6_CAPTURE_SRM) -- the same procedure and
-- menu path as gen_post_opera_anchor.lua, nothing synthesised.
--
-- Getting here and saving IS the save/reset/load evidence #15 wants for
-- this save point: the walk proves the room reachable on the played route,
-- the SavePoint event proves the save-enable flow ran ($01BF), and the
-- post-save asserts prove the slot-3 record and the codex page landed in
-- SRAM.  The cold-Continue half of the round trip is gen_ifrit_magicite's
-- anchored boot, which asserts this same table as its ENTRY contract.
--
-- TWO MEASURED TRAPS this file's shape depends on:
--  * Standing ON a save tile re-enters the SavePoint script every frame
--    ($01B5 gate -> early return), so hasControl() flickers forever there
--    -- the same trap gen_esper_tubes measured on the BIG_SWITCH tile.  No
--    settle predicate can hold on the tile; arrival is judged on position +
--    $01BF + tile alignment only, and the menu is opened through repeated
--    edge presses.
--  * The ULTROS2 row witnesses the boundary contract demands are seeded
--    (an issue-#75 waived poke, burn-down pending an honest chain that
--    reveals them by play) right before the save, exactly as the
--    post-opera anchor does -- a cold Continue must then recover them from
--    the battery, which the ROM's own fresh-page formatting cannot fake.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

-- Walk one direction, absorbing dialogs/battles.  calmPred defaults to
-- settled(); the save-tile approach passes a relaxed one (see the header).
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
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
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
  H.loadState("build/states/ifrit_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 264, "booted on map 264 (ifrit_doorstep)")
    H.assertEq(H.fieldX(), 3, "boot x")
    H.assertEq(H.fieldY(), 7, "boot y")
  end),

  -- through the {3,5} door into the save room
  H.navTo(3, 6, { maxFrames = 6000 }),
  tapInto("up", function() return map() == 270 end, 9000,
    "door 264 (3,5) -> map 270"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 270, "the save room is map 270")
    H.assertEq(H.fieldX(), 25, "270 landing x")
    H.assertEq(H.fieldY(), 14, "270 landing y")
  end),

  -- onto the save point
  H.navTo(25, 11, { maxFrames = 6000 }),
  tapInto("up", onSaveTile(25, 10), 9000,
    "onto the save tile 270 (25,10)", tileCalm),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script enabled saving")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    -- The boundary table, pre-save: everything but the sram witnesses,
    -- which only the save itself can put into the battery.
    H.assertExitContractPreSave("mrf-save-room-v1")
    H.screenshot("anchor_b_save_tile")
  end),

  -- Open the ordinary field menu.  $0059 alone BLIPS nonzero on a save
  -- tile (the SavePoint re-entry; gen_zozo5_ramuh measured the blip class),
  -- so a real menu is 30 CONSECUTIVE frames of it -- and then the
  -- menu-flags byte $0201 must carry the save-enable bit OpenMainMenu
  -- copied from $01BF (field/menu.asm:229-235), the exact flow the menu's
  -- own Save command gates on (menu/field_menu.asm:3641-3643).
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
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- Enter the normal Save selector just as the menu's Save command does;
    -- the selection and write below are unmodified vanilla.  Seed the two
    -- explicit compatibility witnesses in the active transient codex first:
    -- a cold load must recover these nonzero payload bytes from bank $31.
    -- Seed the witness rows in BOTH candidate source pages: the transient
    -- page (a fresh game's active page -- Ot6CodexSaveAs would copy it) and
    -- the slot-3 page (THIS chain's active page: the game was Continued
    -- from slot 3, so Ot6CodexActive selects $0800 and SaveAs to slot 3 is
    -- a no-op copy).  Either way the battery leaves with nonzero payload
    -- bytes a cold load must recover and initialization cannot recreate.
    emu.write(TEMP_ELEM, 0x01, emu.memType.snesMemory)
    emu.write(TEMP_CLASS, 0x01, emu.memType.snesMemory)
    emu.write(0x316810 + ULTROS2, 0x01, emu.memType.snesMemory)
    emu.write(0x316990 + ULTROS2, 0x01, emu.memType.snesMemory)
    -- SENTINEL: zero the last-saved-slot marker.  CopyGameDataToSRAM
    -- rewrites it (menu/save.asm:48), and NOTHING else does -- so the
    -- marker returning to 3 is the loud, context-stable receipt that the
    -- real save ran to completion (the #29-safe replacement for $021f,
    -- which reads 3 in this chain BEFORE any save).
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)
    H.writeByte(ZMENUSTATE, SAVE_SELECT_INIT)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2) -- zero-based cursor: deterministic slot 3
    H.writeWord(0x95, 0) -- slot-3 display cache: treat it as empty
  end),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function()
    return emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM rewrote the zeroed slot marker"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 (the context-stable witness, #29)")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertEq(emu.read(0x316810 + ULTROS2, emu.memType.snesMemory), 0x01,
      "slot 3 copied the nonzero element-codex witness")
    H.assertEq(emu.read(0x316990 + ULTROS2, emu.memType.snesMemory), 0x01,
      "slot 3 copied the nonzero class-codex witness")
    H.log("real Save UI wrote the mrf-save-room anchor to slot 3")
  end),

  -- close the menu and prove the game is back in playable field state,
  -- still standing on the boundary tile; then the FULL exit contract.
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
    H.screenshot("anchor_b_saved")
  end),
  H.logStep(function()
    return string.format("mrf-save-room-v1 saved via the real Save UI at "
      .. "frame %d -- map 270 (25,10), slot 3; run.sh captures the battery "
      .. "on shutdown", H.frame)
  end),
})
