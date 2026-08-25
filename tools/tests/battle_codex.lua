-- @suite slow
-- battle_codex: weakness codex is migrated, persistent, and per-save-slot.
-- Seed an old cartridge-global O7 codex, assert its knowledge migrates into
-- all three O8 slot pages even when slot 2 is loaded first, then teach slot 2
-- after migration. Fight 2 runs as slot 1 and must see the migrated knowledge
-- but not slot 2's new learning.
--
-- Quarantined mechanism test (issue #75); state writes are sanctioned.
-- Owner-named on the #75 policy list: legacy-format codex migration.  The
-- input under test is a cartridge from the O7 era, a layout no current
-- build can produce by play and can only inherit, so seeding it is the only
-- way the migration path can run at all.  (The post-migration teaching
-- half writes knowledge a real fight could learn; it converts if this
-- test ever splits.)  It keeps its waivers, and it must never produce
-- fixtures.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end
H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    -- Plant legacy O7 over the entry-point fixture's codex pages (the fixture
    -- is generated from a cold boot, so they arrive unformatted; this write
    -- fully specifies page 1 either way).
    -- Poison is old global knowledge; O8 migration must preserve it in all
    -- slots.  Slot 2 is loaded first on purpose: migration must not depend on
    -- slot 1 being the first page exercised.
    H.writeByte(0x0224, 2)
    H.writeByte(0x021f, 2)
    emu.write(0x316000, 0x4f, emu.memType.snesMemory)
    emu.write(0x316001, 0x37, emu.memType.snesMemory)
    for i = 0, 0x17f do
      emu.write(0x316010+i, 0x08, emu.memType.snesMemory)
      emu.write(0x316190+i, 0x00, emu.memType.snesMemory)
    end
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 1 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 1 active", 30),
  H.waitFrames(240),
  H.call(function()
    for n, base in ipairs({ 0x316000, 0x316400, 0x316800 }) do
      if n == 1 then
        -- slot 1's magic was deliberately broken above (0x37 planted),
        -- so these two CAN fail: the engine re-magicked the header.
        -- Slots 2 and 3 were never planted, and H.loadState writes
        -- 0x4f/0x38 into all four page headers on every load
        -- (lib/ot6.lua:306-312), so asserting them was a
        -- write-then-read tautology that no ROM change could fail
        -- (#71 item 9) -- dropped for those slots.
        H.assertEq(sram(base), 0x4f, "slot "..n.." codex magic 'O' " ..
          "(re-magicked from the planted 0x37)")
        H.assertEq(sram(base+1), 0x38, "slot "..n.." codex magic '8'")
      end
      H.assertEq(sram(base+0x10) & 0x08, 0x08,
        "legacy knowledge migrated into slot "..n)
    end
    local species = H.readWord(0x57c4)   -- guard slot (entity $0c) stash
    H.log(string.format("guard species=%d slot2 codex byte=%02x",
      species, sram(0x316410+species)))
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
    local learned = sram(0x316410+species)
    H.assertEq(learned & 1, 1, "slot 2 codex learned the guard's fire weakness")
    -- Teach every species FIRE in slot 2 only, after O7 migration.  Slot 1
    -- must not acquire this knowledge from switching to it.
    for i = 0, 0x17f do
      emu.write(0x316410+i, sram(0x316410+i) | 0x01, emu.memType.snesMemory)
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
  H.call(function()
    H.writeByte(0x0224, 1)       -- load/switch to save slot 1
    H.writeByte(0x021f, 1)
    H.assertEq(sram(0x316410) & 0x01, 0x01, "slot 2 retained new fire knowledge")
    H.assertEq(sram(0x316010) & 0x01, 0x00, "slot 1 isolated from slot 2")
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 2 active", 30),
  H.waitFrames(240),
  H.call(function()
    -- Slot 1 gets migrated poison, but not slot 2's post-migration fire.
    local checked = 0
    for slot = 0, 5 do
      -- presence per the hud builder's criterion ($3aa8 bit 0), not the
      -- id-table heuristic (stale for empty slots)
      if (H.readByte(0x3aa8 + slot*2) & 1) == 1 then
        local revealed = H.readByte(0x3e91 + slot*2)
        H.log(string.format("slot %d species=%d revealed=%02x",
          slot, H.readWord(0x57c0 + slot*2), revealed))
        H.assertEq(revealed & 0x08, 0x08,
          "migrated poison pre-revealed, monster slot "..slot)
        H.assertEq(revealed & 0x01, 0x00,
          "slot 2 fire remains hidden in save slot 1, monster slot "..slot)
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one monster checked")
  end),
})
