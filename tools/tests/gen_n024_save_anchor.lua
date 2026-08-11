-- gen_n024_save_anchor.lua -- generate SRAM checkpoint C,
-- `n024-doorstep-save-v1` (the A-F save-point boundary range is lettered in
-- tools/tests/frontier_graph.py): boot n024_doorstep (the nearest generated
-- predecessor, map 273 {25,52} facing NUMBER 024), step off the entry
-- point, walk onto the NEW #10 save point at {26,53}, and save through the
-- game's OWN Save UI into slot 3.  run.sh captures the 32 KiB battery on
-- shutdown.
--
-- THIS IS ALSO THE FIRST LIVE EXERCISE OF THE 273 SAVE POINT that ends in a
-- real battery save (#15's save/reset/load item for #10's one authored
-- placement).  What it proves, in order:
--  * the sparkle NPC renders at {26,53} -- asserted on the LIVE object
--    table (object $11's tile coords), not on the npc_prop source, and
--    screenshotted before and after stepping on;
--  * stepping onto {26,53} fires the shared SavePoint script -- $01BF
--    (save-enable) and $01B5 (once-per-tile latch) both set;
--  * the vanilla Save UI writes a slot-3 record from that tile, and a cold
--    Continue of the captured battery boots gen_esper_tubes'
--    checkpoint-booted step, which asserts this same table as its ENTRY
--    contract.
--
-- The approach never presses A while facing NUMBER 024 -- the first move
-- is a plain RIGHT step off the contact line ({25,52} -> {26,52}), then
-- DOWN onto the save tile.  See gen_mrf_save_room_anchor.lua for the two
-- measured traps (save-tile control flicker; codex witness seeding) this
-- file's shape inherits.
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

-- object k's live tile position (the party is objects 0-3; map NPCs start
-- at $10 in record order, so 273's NUMBER_024 is $10 and the appended
-- sparkle is $11)
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/n024_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 273, "booted on map 273 (n024_doorstep)")
    H.assertEq(H.fieldX(), 25, "boot x")
    H.assertEq(H.fieldY(), 52, "boot y")
    -- the sparkle NPC is LIVE at the authored tile, before we go near it
    local nx, ny = objAt(0x10)
    H.assertEq(nx, 25, "object $10 (NUMBER 024) x")
    H.assertEq(ny, 51, "object $10 (NUMBER 024) y")
    local sx, sy = objAt(0x11)
    H.assertEq(sx, 26, "object $11 (the NEW save sparkle) renders at x=26")
    H.assertEq(sy, 53, "object $11 (the NEW save sparkle) renders at y=53")
    H.assertEq(sw(0x0632), 1, "$0632 SET -- the standing sparkle switch")
    H.screenshot("anchor_c_sparkle_before")
  end),

  -- off the 024 contact line, then down onto the sparkle
  H.navTo(26, 52, { playBattles = "flee", maxFrames = 6000 }),
  tapInto("down", onSaveTile(26, 53), 9000,
    "onto the NEW save tile 273 (26,53)", tileCalm),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1,
      "$01BF SET -- the NEW 273 save point runs the shared SavePoint script")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertExitContractPreSave("n024-doorstep-save-v1")
    H.screenshot("anchor_c_save_tile")
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
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- ARM THE input-driven save receipt (issue #75): a read-only exec hook on
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
    -- checkpoint re-cuts measure these and the entry contracts follow the
    -- measurement (never the reverse).
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the n024-doorstep-save checkpoint to slot 3")
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
    H.assertExitContract("n024-doorstep-save-v1")
    H.screenshot("anchor_c_saved")
  end),
  H.logStep(function()
    return string.format("n024-doorstep-save-v1 saved via the real Save UI "
      .. "at frame %d -- map 273 (26,53), slot 3; the NEW #10 save point's "
      .. "first battery save", H.frame)
  end),
})
