-- probe_v07_i_negative.lua -- FAIL-BEFORE control for the vector-crash-v1
-- contract (issue #31, the #25 discipline): boot the generated boundary
-- state, PERTURB one contract-checked fact -- clear $007A, the
-- airship-dead switch the whole post-crash section plans around -- and
-- assert the exit contract.  The expected outcome is a FAILURE that names
-- the switch; this probe passing would mean the contract asserts nothing.
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
