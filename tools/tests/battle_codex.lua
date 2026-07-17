-- battle_codex: weakness codex - reveals persist across battles (OT-style).
-- fight 1: reveal a poked fire weakness on a guard, assert the codex (sram
-- bank $31) learned it. then win, walk to fight 2, and assert a codex
-- entry poked from lua pre-reveals WITHOUT any attack. savestates would
-- restore sram, so persistence is proven within one continuous run.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end
H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.call(function()
    -- self-cleaning: invalidate the codex so this run proves a fresh
    -- init -> learn -> reapply cycle (the portable srm persists runs)
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 1 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 1 active", 30),
  H.waitFrames(240),
  H.call(function()
    H.assertEq(sram(0x316000), 0x4f, "codex magic 'O' written at first seed")
    H.assertEq(sram(0x316001), 0x37, "codex magic '7' (v2: elements+classes)")
    local species = H.readWord(0x57c4)   -- guard slot (entity $0c) stash
    H.log(string.format("guard species=%d codex byte=%02x", species, sram(0x316010+species)))
    H.writeByte(0x3bec, H.readByte(0x3bec) | 0x01)   -- poke guard 1 fire-weak
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
  end),
  H.driveUntil(function() return (H.readByte(0x3e95) & 1) == 1 end, 10000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "fire weakness revealed in fight 1"),
  H.call(function()
    local species = H.readWord(0x57c4)
    local learned = sram(0x316010+species)
    H.assertEq(learned & 1, 1, "codex learned the guard's fire weakness")
    -- pre-teach every species poison for the fight-2 seed-merge check
    for i = 0, 0x17f do
      emu.write(0x316010+i, sram(0x316010+i) | 0x08, emu.memType.snesMemory)
    end
    H.writeWord(0x3C00, 1); H.writeWord(0x3C02, 1)   -- guards at 1 hp
  end),
  H.driveUntil(function()
    local dead = H.readWord(0x3C00) == 0 and H.readWord(0x3C02) == 0
    return dead or not H.battleLoadStarted()
  end, 24000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "fight 1 won"),
  H.driveUntil(function()
    return not H.battleLoadStarted()
  end, 9000, { H.pressButtons({ "a" }, 6), H.waitFrames(24) }, "back to field"),
  H.waitFrames(60),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 2 active", 30),
  H.waitFrames(240),
  H.call(function()
    -- every present monster must open with poison pre-revealed (no attacks!)
    local checked = 0
    for slot = 0, 5 do
      -- presence per the hud builder's criterion ($3aa8 bit 0), not the
      -- id-table heuristic (stale for empty slots)
      if (H.readByte(0x3aa8 + slot*2) & 1) == 1 then
        local revealed = H.readByte(0x3e91 + slot*2)
        H.log(string.format("slot %d species=%d revealed=%02x",
          slot, H.readWord(0x57c0 + slot*2), revealed))
        H.assertEq(revealed & 0x08, 0x08, "poison pre-revealed from codex, slot "..slot)
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one monster checked")
  end),
})
