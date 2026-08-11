-- probe_v07_h_negative.lua -- FAIL-BEFORE control for the gate-cave-save-v1
-- contract (issue #31, the #25 discipline): boot the generated boundary
-- state, PERTURB one contract-checked fact (bench SABIN -- zero his $1850
-- party nibble), and assert the exit contract.  The expected outcome is a
-- FAILURE that names the party-size count and SABIN's membership; this
-- probe passing would mean the contract asserts nothing.  NOT a suite test;
-- run by hand, expect exit 1, grep the log for the named diffs.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- The PRE-SAVE form is the right one here: a savestate boot carries the
-- FIXTURE's codex bytes, not the boundary battery's (lib/ot6.lua), so the
-- full form's sram witnesses could diff even UNPERTURBED and muddy the
-- control.  PreSave asserts everything else; the positive control below
-- proves it HOLDS on the unperturbed state, so the only cause of the
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
