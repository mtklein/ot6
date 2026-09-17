-- gen_seed_train.lua -- lift SRM seed `train-engineer-v1`: gen_sabin_train
-- saved at the Phantom Train's save point (map 146 (20,10), slot 3) in the
-- rear cars, and battery SRAM rides inside .mss savestates, so
-- booting train_done.mss and shutting down cleanly flushes that battery
-- for run.sh's OT6_CAPTURE_SRM to lift.
--
-- #218: the tile was always right; the room was not.  Map 146 is two
-- rooms, and the save used to be attempted from the engineer's-room half
-- at the far end of the run, which cannot reach (20,10) -- so the save was
-- skipped every run and the battery this lifted still held the Kolts
-- summit save (map 103 (57,8)), with nothing in the lift checking.
-- H.assertSavedSlot below reads the slot's own copy of $1F64 and
-- $1FC0/$1FC1 out of SRAM, so the wrong save cannot be lifted as this seed
-- again; manifest.json's "saved" block re-checks it from the payload bytes
-- after the emulator is gone.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/train_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 -- the train save is aboard")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertSavedSlot(146, 20, 10,
      "train-engineer-v1: the Phantom Train save point")
    H.assertPartyStanding("train-engineer seed")
    H.log("battery carries the train save; shutdown flushes it")
  end),
})
