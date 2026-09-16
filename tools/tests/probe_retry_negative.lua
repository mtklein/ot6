-- probe_retry_negative.lua -- the segment runner's negative control (#178):
-- a CONTRACT failure must fail on attempt 1 of 3 with no replay.  The
-- expected outcome is a FAIL (run.sh exit 1) whose log carries
--   [retry] attempt 1/3 FAILED class=assert ...
-- and no "attempt 2/3" line.  A suite cannot expect a red run, which is why
-- this is a probe beside tools/tests/segment_retry.lua rather than a
-- second case inside it; tools/tests/lib/retry_negative.sh runs it through
-- run.sh and asserts on that red verdict, as ninja's
-- build/checks/retry_negative.ok (#200).  By hand:
--   tools/tests/run.sh tools/tests/probe_retry_negative.lua build/states/retry_negative.log
local H = dofile("tools/tests/lib/ot6.lua")

_G.RETRY_NEG_RUNS = (_G.RETRY_NEG_RUNS or 0) + 1

H.run({ maxFrames = 3000, retries = 3, watchdog = false }, {
  H.waitFrames(60),
  H.call(function()
    H.assertEq(_G.RETRY_NEG_RUNS, 1, "this body ran exactly once")
    -- the shape of a real contract failure
    H.assertEq(H.mapId() & 0x1ff, 999, "on map 999 (an injected contract miss)")
  end),
})
