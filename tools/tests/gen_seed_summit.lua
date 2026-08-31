-- gen_seed_summit.lua -- lift SRM seed `kolts-summit-v1`: gen_kolts saved
-- at the Mt. Kolts summit save point (map 103 (57,8), slot 3) on the way
-- to Vargas, and battery SRAM rides inside .mss savestates, so booting
-- vargas_entry.mss and shutting down cleanly flushes that battery for
-- run.sh's OT6_CAPTURE_SRM to lift.  No replay, no navigation: the seed
-- IS the save the story generator made.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/vargas_entry.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "booted on map 98 (vargas_entry)")
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 -- the summit save is aboard")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertPartyStanding("kolts-summit seed")
    H.log("battery carries the summit save; shutdown flushes it")
  end),
})
