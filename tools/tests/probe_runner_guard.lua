-- @manual
-- probe_runner_guard.lua -- the segment runner's own error guard: a Lua
-- error raised OUTSIDE the step pcall (here: in the canary's in-game latch,
-- which reads H.hasControl on its own every frame) must still end the run
-- with a FAIL line, never with a dead script and no verdict.  Expected:
--   [ot6] FAIL: segment runner internal error (attempt 1/1, phase run, f...): ...boom...
-- and run.sh exit 1.
local H = dofile("tools/tests/lib/ot6.lua")

H.hasControl = function()
  if H.frame >= 30 then error("boom -- injected by probe_runner_guard.lua", 0) end
  return false
end

H.run({ maxFrames = 600, retries = 1, watchdog = false }, {
  H.waitFrames(120),
})
