-- probe_v07_i_negative.lua -- fail-before control for the vector-crash-v1
-- contract (issue #31, the #25 discipline): boot the generated boundary
-- state, perturb one contract-checked fact (clear $007A, the
-- airship-dead switch the post-crash section plans around), and
-- assert the exit contract.  The expected outcome is a failure naming
-- the switch; if this probe passes, the contract asserts nothing.
-- Not a suite test; run by hand, expect exit 1, grep the log for the
-- named diff.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- The pre-save form is used here because a savestate boot carries the
-- fixture's codex bytes rather than the boundary battery's (lib/ot6.lua), so
-- the full form's sram witnesses could differ even unperturbed and confuse
-- the control.  The positive
-- control below shows everything else holds on the unperturbed state, so
-- the only cause of the failure that follows is the perturbation itself.
H.run({ maxFrames = 4000 }, {
  H.loadState("build/states/vector_crash.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertExitContractPreSave("vector-crash-v1")
    H.log("[negative] positive control held; now clearing $007A -- the "
      .. "contract must fail by name")
    local id = 0x007A
    local addr = 0x1E80 + (id >> 3)
    H.writeByte(addr, H.readByte(addr) & ~(1 << (id & 7)))
    H.assertExitContractPreSave("vector-crash-v1")
  end),
})
