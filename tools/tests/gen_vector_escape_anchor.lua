-- gen_vector_escape_anchor.lua -- mint battery anchor E, `vector-escape-v1`
-- (save-points-vector.md §5): boot n128_won (the nearest minted
-- predecessor, which gen_n128 parks ON the escape map's save point, map
-- 240 {58,7}, the sparkle $06AE revealed), re-arm the save-enable flow if
-- the savestate did not carry it, and save through the game's OWN Save UI
-- into slot 3.  run.sh captures the 32 KiB battery on shutdown.
--
-- See gen_mrf_save_room_anchor.lua for the traps this file's shape
-- inherits: the save-tile control flicker (arrival/idle judged without
-- hasControl), the codex witness seeding (a waived #75 poke before the
-- save), and the $307ff0 sentinel as the only context-stable receipt
-- that CopyGameDataToSRAM actually ran (#29).
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on map 240 (n128_won)")
    H.assertEq(H.fieldX(), 58, "boot x -- ON the save tile")
    H.assertEq(H.fieldY(), 7, "boot y")
    H.assertEq(sw(0x06AE), 1, "$06AE SET -- the sparkle is revealed")
  end),
  -- The savestate was minted standing on the tile with $01BF/$01B5 set; if
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
          if H.battleLoadStarted() then killBitAll(); H.setPad({ "a" }); return end
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
    H.screenshot("anchor_e_save_tile")
  end),

  -- Open the ordinary field menu ($0059 blip-proofed; see anchor B's gen).
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
    -- witnesses in both candidate source pages + the $307ff0 sentinel
    -- (see gen_mrf_save_room_anchor.lua for why each)
    emu.write(TEMP_ELEM, 0x01, emu.memType.snesMemory)
    emu.write(TEMP_CLASS, 0x01, emu.memType.snesMemory)
    emu.write(0x316810 + ULTROS2, 0x01, emu.memType.snesMemory)
    emu.write(0x316990 + ULTROS2, 0x01, emu.memType.snesMemory)
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
      "slot 3 carries the nonzero element-codex witness")
    H.assertEq(emu.read(0x316990 + ULTROS2, emu.memType.snesMemory), 0x01,
      "slot 3 carries the nonzero class-codex witness")
    H.log("real Save UI wrote the vector-escape anchor to slot 3")
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
    H.screenshot("anchor_e_saved")
  end),
  H.logStep(function()
    return string.format("vector-escape-v1 saved via the real Save UI at "
      .. "frame %d -- map 240 (58,7), slot 3", H.frame)
  end),
})
