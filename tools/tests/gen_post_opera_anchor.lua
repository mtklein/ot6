-- gen_post_opera_anchor.lua -- create the v1 battery anchor from blackjack.
--
-- This does not synthesize vanilla save checksums.  It opens the ordinary
-- field menu, enters vanilla's Save selector, chooses slot 3, and lets
-- CopyGameDataToSRAM write the save.  run.sh captures Mesen's complete 32 KiB
-- battery file after shutdown.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/blackjack.mss.lua"

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
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
  H.navTo(1, 17, { maxFrames = 600 }),
  H.driveUntil(function() return (H.mapId() & 0x1ff) == 0 end, 800, {
    H.hold({ "left" }),
  }, "leave Vector to its west doorstep"),
  H.release(),
  H.waitFrames(180),
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end,
    500, "field menu open", 5),
  H.call(function()
    -- World-map saving is legal.  Enter the normal Save selector just as the
    -- menu's Save command does; the selection and write below are unmodified.
    -- Seed one explicit compatibility witness in the active transient codex.
    -- A cold load must recover these nonzero payload bytes from bank $31;
    -- unlike the O8 signature, load-time initialization cannot recreate them.
    emu.write(TEMP_ELEM, 0x01, emu.memType.snesMemory)
    emu.write(TEMP_CLASS, 0x01, emu.memType.snesMemory)
    -- SENTINEL: zero SRAM's last-saved-slot marker.  CopyGameDataToSRAM
    -- rewrites it (menu/save.asm:48), and NOTHING else does -- so the
    -- marker returning to 3 is the loud, context-stable receipt that the
    -- real save ran to completion.  The receipt used to be WRAM $021f,
    -- which is wSaveSlotToLoad only while the menu module owns the $0200
    -- region (issue #29, HANDOFF trap #1): the world module block-restores
    -- its own variable there after any menu closes, so a WRAM receipt read
    -- in the wrong frame window can lie.  The B-F anchor gens
    -- (gen_n024_save_anchor and friends) established this SRAM sentinel as
    -- the pattern; this file now matches them.
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 0,
      "slot marker zeroed -- the 3 below cannot pre-exist this save")
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
  end, 800, {
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
    H.log("real Save UI wrote post-Opera anchor to slot 3")
  end),
})
