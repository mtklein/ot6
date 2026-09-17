-- gen_seed_basement.lua -- lift SRM seed `sfigaro-basement-v1`:
-- gen_tunnelarmr saved at the mansion-basement save point (map 88
-- (11,34), slot 3) on LOCKE's escape, and battery SRAM rides inside .mss
-- savestates, so booting sfigaro_escape.mss and shutting down cleanly
-- flushes that battery for run.sh's OT6_CAPTURE_SRM to lift.
--
-- #218: this used to say map 84 (53,57).  That tile is a SavePoint, but it
-- is in a pocket of map 84 the escape cannot enter, gen_tunnelarmr's save
-- step was skipped on every run, and the battery this lifted still held
-- the Kolts summit save (map 103 (57,8)) -- with nothing in the lift
-- checking.  H.assertSavedSlot below reads the slot's own copy of $1F64
-- and $1FC0/$1FC1 out of SRAM, so the wrong save cannot be lifted as this
-- seed again; manifest.json's "saved" block re-checks it from the payload
-- bytes after the emulator is gone.
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
    H.assertSavedSlot(88, 11, 34,
      "sfigaro-basement-v1: the mansion-basement save point")
    H.assertPartyStanding("sfigaro-basement seed")
    H.log("battery carries the basement save; shutdown flushes it")
  end),
})
