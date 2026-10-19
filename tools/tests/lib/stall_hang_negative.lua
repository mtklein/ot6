-- stall_hang_negative.lua -- run.sh's stall watch, negative control 1: the
-- emulation pauses (emu.breakExecution), so no callback runs again and the
-- frame counter itself stops.  (An infinite Lua loop in a callback does not
-- make a hang: Mesen ends it itself after 30 s with "Maximum execution time
-- (30 seconds) exceeded", a FAIL verdict -- build/attempts/wt/v031-heartbeat/.)
-- run.sh must kill the pause as a STALL within the heartbeat window plus its
-- poll slack.  Driven by tools/tests/lib/stall_negative.sh.
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 100000, retries = 1, watchdog = false }, {
  H.waitFrames(120),
  H.call(function()
    H.log("stall_hang_negative: pausing emulation for good")
    emu.breakExecution()
  end),
  H.waitFrames(100000),   -- the run would end here, if a frame ever came
})
