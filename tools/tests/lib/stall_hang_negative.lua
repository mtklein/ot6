-- stall_hang_negative.lua -- run.sh's stall watch, negative control 1: the
-- script hangs inside a frame callback (an infinite Lua loop), so the frame
-- counter itself stops.  run.sh must kill it as a STALL within the heartbeat
-- window plus its poll slack.  Driven by tools/tests/lib/stall_negative.sh.
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 100000, retries = 1, watchdog = false }, {
  H.waitFrames(120),
  H.call(function()
    H.log("stall_hang_negative: spinning forever inside the frame callback")
    local n = 0
    while true do n = n + 1 end
  end),
})
