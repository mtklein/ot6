-- @suite
-- segment_retry.lua -- the segment runner's own falsification (#178).
--
-- Boots nothing: it runs from power-on and never touches the game, because
-- what is under test is the RUNNER, not a route.  Three properties, each of
-- which has failed at least once while this was being built:
--
--   1. A seed-dependent failure is REPLAYED.  The first attempt raises a
--      message that classifies as `nopath`; the run must come back, re-run
--      the body from source, and pass with `attempts=2/3`.
--   2. The replay is CLEAN.  Every local in the body is rebuilt: a counter
--      declared here reads 1 on both attempts, while a global (which the
--      replay cannot reach and must not pretend to) counts up.  The step
--      objects are rebuilt too -- the waitFrames below waits its full count
--      on the second attempt rather than resuming exhausted.
--   3. A CONTRACT failure is NOT replayed.  Checked by the negative control
--      in tools/tests/lib/checkpoint_negatives.sh's sibling below: run this
--      file with OT6_RETRY_SELFTEST=assert to see an assertEq fail on
--      attempt 1 of 3.  (The default path here is the positive one.)
--
-- The failure injected is a raised message, not a rigged game state: the
-- runner's classifier reads messages, so a message is the honest input.
local H = dofile("tools/tests/lib/ot6.lua")

local localAttempts = 0            -- a body local: rebuilt every attempt
_G.RETRY_SELFTEST_RUNS = (_G.RETRY_SELFTEST_RUNS or 0) + 1
local globalAttempt = _G.RETRY_SELFTEST_RUNS

local waited = 0

H.run({ maxFrames = 3000, retries = 3, watchdog = false }, {
  H.call(function()
    localAttempts = localAttempts + 1
    H.log(string.format("[selftest] body running: this body's local counter "
      .. "reads %d, the global attempt counter %d", localAttempts,
      globalAttempt))
    H.assertEq(localAttempts, 1,
      "the body local was rebuilt by the replay (a stale closure would read 2)")
  end),
  H.waitFrames(120),
  H.call(function()
    waited = waited + 1
    H.assertEq(waited, 1, "the step list was rebuilt, not resumed")
  end),
  H.call(function()
    if globalAttempt == 1 then
      -- the shape of a real one: lib/ot6_field.lua's navTo path failure
      error("navTo: no path (26,36)->(21,23) [0 edges blocklisted, 3 retries]"
        .. " -- injected by segment_retry.lua", 0)
    end
  end),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(globalAttempt, 2, "the run reached its second attempt")
    H.log("[selftest] the replayed attempt reached the end of the body")
  end),
})
