-- probe_wonhang.lua (#519 lab): load the REAL hung state (nav519_hung.mss, the tower's
-- formation $0AD with every monster at 0 HP) with the watchdogs enforcing and let them trip.
-- Expected: FAIL class=wonhang "battle-won-never-ended:" inside ~2,000 frames.
local H = dofile("tools/tests/lib/ot6.lua")
local steps = {
  H.waitFrames(20),
  H.loadState("build/states/nav519_hung.mss.lua"),
  H.driveUntil(function() return false end, 6000, {
    H.call(function() H.setPad({}) end),
  }, "the hung battle sits"),
}
H.run({ maxFrames = 8000, retries = 1, watchdog = true }, steps)
