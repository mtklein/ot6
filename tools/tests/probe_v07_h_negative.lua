-- probe_v07_h_negative.lua -- fail-before control for the gate-cave-save-v1
-- contract (issue #31, the #25 discipline): boot the generated boundary
-- state, perturb one contract-checked fact (bench SABIN by zeroing his
-- $1850 party nibble), and assert the exit contract.  The expected outcome
-- is a failure naming the party-size count and SABIN's membership; if this
-- probe passes, the contract asserts nothing.  Not a suite test;
-- run by hand, expect exit 1, grep the log for the named diffs.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- The pre-save form is used here because a savestate boot carries the
-- fixture's codex bytes rather than the boundary battery's (lib/ot6.lua), so
-- the full form's sram witnesses could differ even unperturbed and confuse
-- the control.  PreSave asserts everything else; the positive control below
-- shows it holds on the unperturbed state, so the only cause of the
-- failure that follows is the perturbation itself.
H.run({ maxFrames = 4000 }, {
  H.loadState("build/states/gate_cave_save.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertExitContractPreSave("gate-cave-save-v1")
    H.log("[negative] positive control held; now benching SABIN -- the "
      .. "contract must fail by name")
    H.writeByte(0x1850 + 0x05, H.readByte(0x1850 + 0x05) & 0xF8)
    H.assertExitContractPreSave("gate-cave-save-v1")
  end),
})
