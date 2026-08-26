-- probe_v07_h_negative.lua -- fail-before control for the gate-cave-save-v1
-- contract: boot the generated boundary state, perturb one contract-checked
-- fact (bench SABIN by zeroing his $1850 party nibble), and assert the exit
-- contract.  The expected outcome is a failure naming the party-size count
-- and SABIN's membership.  Not a suite test; run by hand, expect exit 1.
local H = dofile("tools/tests/lib/ot6.lua")

-- The pre-save form is used because a savestate boot carries the fixture's
-- codex bytes rather than the boundary battery's, so the full form's sram
-- witnesses could differ even unperturbed and confuse the control.
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
