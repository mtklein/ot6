-- probe_v07_j_negative.lua -- FAIL-BEFORE control for the banquet-done-v1
-- contract (issue #31, the #25 discipline): boot the generated boundary
-- state, PERTURB one contract-checked fact -- seat EDGAR back into party
-- 1, un-doing the banquet's forced TERRA+LOCKE strip that is this
-- boundary's headline (#21's count control, inverted) -- and assert the
-- exit contract.  The expected outcome is a FAILURE naming the party
-- count; this probe passing would mean the contract asserts nothing.
-- NOT a suite test; run by hand, expect exit 1, grep the log for the
-- named diff.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- The PRE-SAVE form is the right one here: a savestate boot carries the
-- FIXTURE's codex bytes, not the boundary battery's (lib/ot6.lua), so the
-- full form's sram witnesses could diff even UNPERTURBED and muddy the
-- control.  The positive
-- control below proves everything else HOLDS on the unperturbed state, so
-- the only cause of the failure that follows is the perturbation itself.
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
