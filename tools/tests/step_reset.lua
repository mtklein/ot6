-- @suite
-- step_reset.lua -- #196: a step nested in a repeatN body really runs again
-- on every pass.
--
-- Boots nothing (power-on, the game untouched, like segment_retry.lua):
-- what is under test is the step combinators, so the only clock is H.frame.
--
-- The contract.  Step objects close over their state; repeatN calls
-- body:reset() after each pass, and seqStep forwards a reset to every
-- child that has one.  The lib's own state (a fold's done-count, a
-- drive's frame count, a wait's counter, a navigator's plan) is the lib's
-- to clear; a test's own counters are the test's, cleared in the body's
-- first H.call (`begin` below).  Three shapes, each measured on HEAD as
-- running once and passing instantly on every later pass:
--
--   1. repeatN(1, {...}) is the fold every battle_* suite uses to make a
--      list one step.  Inside a repeatN(3) body its done-count survived the
--      pass, so passes 2 and 3 returned "done" on their first tick
--      (battle_steal, 2026-09-16: one "[bare 0-bp attempt]" line, the same
--      draw scored as attempts 1, 2 and 3).
--   2. a body abandoned mid-cycle resumed there: pred fired while the body
--      sat in a waitFrames, and the next pass began inside that wait, so
--      the body's first step never ran again.
--   3. driveUntil's `waited` survived: three 40-frame drives under one
--      100-frame cap timed out on pass 3 at 20 frames in.  (Last, because
--      on HEAD it is a raised timeout, not a soft miss.)
--   4. the same drive under a cond (the seq() fold suites and the lib
--      build on H.cond): cond's reset cleared its choice but never reached
--      the branch's children, so the drive under it kept its count.  Also
--      a raised timeout on HEAD, so it comes after shape 3.
local H = dofile("tools/tests/lib/ot6.lua")

local pass, t0, firstSteps = 0, 0, 0
local fails = {}
local function begin(shape)          -- the caller's half: its own counters
  return H.call(function()
    pass = pass + 1
    t0, firstSteps = H.frame, 0
    H.log(string.format("[reset] %s: pass %d begins at f%d", shape, pass, t0))
  end)
end
local function took() return H.frame - t0 end
local function miss(msg)
  fails[#fails + 1] = msg
  H.log("[reset] MISS: " .. msg)
end
local function checkDrove(shape, n)
  return H.call(function()
    H.log(string.format("[reset] %s: pass %d took %d frames (wanted >= %d)",
      shape, pass, took(), n))
    if took() < n then
      miss(string.format("%s: pass %d took %d frames, not >= %d -- the step "
        .. "reported itself done without running again", shape, pass, took(), n))
    end
  end)
end

H.run({ maxFrames = 3000, watchdog = false }, {
  H.waitFrames(30),

  -- 1. the repeatN(1) fold around a driveUntil
  H.call(function() pass = 0 end),
  H.repeatN(3, {
    begin("shape 1 (repeatN(1) fold)"),
    H.repeatN(1, {
      H.driveUntil(function() return took() >= 30 end, 600, {
        H.call(function() firstSteps = firstSteps + 1 end), H.waitFrames(1),
      }, "30 frames of driving inside a repeatN(1) fold"),
    }),
    checkDrove("shape 1 (repeatN(1) fold)", 30),
  }),

  -- 2. a body abandoned mid-cycle: pred fires 5 frames into a 20-frame wait
  H.call(function() pass = 0 end),
  H.repeatN(3, {
    begin("shape 2 (body abandoned mid-wait)"),
    H.driveUntil(function() return took() >= 5 end, 600, {
      H.call(function() firstSteps = firstSteps + 1 end), H.waitFrames(20),
    }, "5 frames, ending inside the body's wait"),
    H.call(function()
      H.log(string.format("[reset] shape 2 (body abandoned mid-wait): pass %d "
        .. "ran the body's first step %d time(s)", pass, firstSteps))
      if firstSteps ~= 1 then
        miss(string.format("shape 2: pass %d ran the body's first step %d "
          .. "time(s), not 1 -- the body resumed inside its wait", pass, firstSteps))
      end
    end),
  }),

  -- 3. the drive's own cap is per pass: 3 x 40 frames under a 100-frame cap
  H.call(function() pass = 0 end),
  H.repeatN(3, {
    begin("shape 3 (bare driveUntil, cap per pass)"),
    H.driveUntil(function() return took() >= 40 end, 100, {
      H.call(function() firstSteps = firstSteps + 1 end), H.waitFrames(1),
    }, "40 frames of driving under a 100-frame cap"),
    checkDrove("shape 3 (bare driveUntil, cap per pass)", 40),
  }),

  -- 4. the same drive under a cond fold
  H.call(function() pass = 0 end),
  H.repeatN(3, {
    begin("shape 4 (driveUntil under a cond)"),
    H.cond(function() return true end, {
      H.driveUntil(function() return took() >= 40 end, 100, {
        H.call(function() firstSteps = firstSteps + 1 end), H.waitFrames(1),
      }, "40 frames of driving under a cond, 100-frame cap"),
    }),
    checkDrove("shape 4 (driveUntil under a cond)", 40),
  }),

  H.call(function()
    H.assertEq(#fails, 0, "every nested step ran again on every pass"
      .. (#fails > 0 and (":\n  " .. table.concat(fails, "\n  ")) or ""))
    H.log("[reset] repeatN, driveUntil, cond and the fold all reset per pass")
  end),
})
