-- gen_seed_terracave.lua -- lift SRM seed `terra-caves-v1`:
-- gen_terra_clifftop saved at the Narshe-caves save point (map 50
-- (66,41), slot 3) on TERRA and BANON's climb, and battery SRAM rides
-- inside .mss savestates, so booting terra_clifftop.mss and shutting
-- down cleanly flushes that battery for run.sh's OT6_CAPTURE_SRM.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/terra_clifftop.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3 -- the cave save is aboard")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "slot 3 has OT6 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "slot 3 has OT6 codex magic 8")
    H.assertPartyStanding("terra-caves seed")
    H.log("battery carries the cave save; shutdown flushes it")
  end),
})
