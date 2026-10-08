-- One-off legal recapture of the retained Gate ACT machine snapshot.
local H = dofile("tools/tests/lib/ot6.lua")
local function xp(c)
  local p = 0x1611 + 37*c
  return H.readByte(p) + 256*H.readByte(p+1) + 65536*H.readByte(p+2)
end
H.run({maxFrames=12000}, {
  H.loadState("build/lab/xp-input/gate_cave_save.mss.lua"),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 386, "retained Gate map")
    H.assertEq(xp(0), 28143, "Terra retained total XP (22832 entry + 5311 earned)")
    for _,c in ipairs({0,1,4,5}) do
      H.log(string.format("[xp-continuation-entry] char=%d xp=%d", c,xp(c)))
    end
    H.screenshot("xp_continuation_entry")
  end),
  H.saveGame({slot=3, tag="retained ACT Gate continuation"}),
  H.call(function()
    H.assertEq(xp(0), 28143, "Save UI preserves Terra XP")
    H.assertExitContract("gate-cave-save-v1")
    H.screenshot("xp_continuation_saved")
  end),
})
