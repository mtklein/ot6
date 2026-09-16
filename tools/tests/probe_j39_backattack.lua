-- @manual
-- probe_j39_backattack.lua -- off lab_zozo4_j39_snap's _lab_j39_st38 state
-- (the potion-route dadaluma_entry attempt-1 J39-row fight, LOCKE's Fight
-- parked in target select $38): read the target masks, then press LEFT
-- (what the fight driver's focus steer presses when mons == 0) and RIGHT,
-- and report whether either crosses the cursor to the monster side (#176).
local H = dofile("tools/tests/lib/ot6.lua")
local function masks(tag)
  H.log(string.format("[probe] %s f%d st=%02X chars=%02X mons=%02X all=%02X",
    tag, H.frame, H.readByte(0x7BC2), H.readByte(0x7B7D), H.readByte(0x7B7E),
    H.readByte(0x7B7F)))
end
local function press(dir)
  return {
    H.call(function() H.setPad({ [dir] = true }) end), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(12),
    H.call(function() masks("after " .. dir) end),
  }
end
local steps = { H.loadState("build/states/_lab_j39_st38.mss.lua"),
  H.call(function() H.setPad({}) end), H.waitFrames(2),
  H.call(function() masks("loaded") end) }
for _, s in ipairs(press("left")) do steps[#steps + 1] = s end
for _, s in ipairs(press("left")) do steps[#steps + 1] = s end
for _, s in ipairs(press("right")) do steps[#steps + 1] = s end
for _, s in ipairs(press("right")) do steps[#steps + 1] = s end
steps[#steps + 1] = H.call(function() H.screenshot("probe_j39_after_right") end)
H.run({ maxFrames = 600 }, steps)
