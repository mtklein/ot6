-- gen_seed_basement.lua -- lift SRM seed `sfigaro-basement-v1`:
-- gen_tunnelarmr saved at the mansion-basement save point (map 84
-- (53,57), slot 3) on LOCKE's escape, and battery SRAM rides inside .mss
-- savestates, so booting sfigaro_escape.mss and shutting down cleanly
-- flushes that battery for run.sh's OT6_CAPTURE_SRM to lift.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/sfigaro_escape.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 -- the basement save is aboard")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertPartyStanding("sfigaro-basement seed")
    H.log("battery carries the basement save; shutdown flushes it")
  end),
})
