-- probe_v07_j_negative.lua -- fail-before control for the banquet-done-v1
-- contract: boot the generated boundary state, perturb one contract-checked
-- fact (seat EDGAR back into party 1, undoing the banquet's forced
-- TERRA+LOCKE strip), and assert the exit contract.  The expected outcome
-- is a failure naming the party count.  Not a suite test; run by hand,
-- expect exit 1.
local H = dofile("tools/tests/lib/ot6.lua")

-- The pre-save form is used because a savestate boot carries the fixture's
-- codex bytes rather than the boundary battery's, so the full form's sram
-- witnesses could differ even unperturbed and confuse the control.
H.run({ maxFrames = 4000 }, {
  H.loadState("build/states/banquet_done.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertExitContractPreSave("banquet-done-v1")
    H.log("[negative] positive control held; now seating EDGAR (char 04) "
      .. "back into party 1 -- the contract must fail by name")
    H.writeByte(0x1850 + 0x04,
      (H.readByte(0x1850 + 0x04) & 0xF8) | 0x01)
    H.assertExitContractPreSave("banquet-done-v1")
  end),
})
