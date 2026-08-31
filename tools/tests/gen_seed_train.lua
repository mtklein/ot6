-- gen_seed_train.lua -- lift SRM seed `train-engineer-v1`: gen_sabin_train
-- saved at the engineer-room save point (map 146 (20,10), slot 3) before
-- the GhostTrain, and battery SRAM rides inside .mss savestates, so
-- booting train_done.mss and shutting down cleanly flushes that battery
-- for run.sh's OT6_CAPTURE_SRM to lift.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/train_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 -- the engineer save is aboard")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertPartyStanding("train-engineer seed")
    H.log("battery carries the engineer save; shutdown flushes it")
  end),
})
