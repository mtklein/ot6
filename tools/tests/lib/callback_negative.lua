-- callback_negative.lua -- the callback-error negative control (#438):
-- an assert raised inside an emu.addMemoryCallback is swallowed by Mesen,
-- so the run used to PASS.  The library records the error and fails the
-- run at the next frame with the original message and traceback.  The
-- expected outcome here is a FAIL (run.sh exit 1) whose log carries the
-- injected message; tools/tests/lib/callback_negative.sh runs it through
-- run.sh and asserts on that red verdict (ninja's
-- build/checks/callback_negative.ok).  By hand:
--   tools/tests/run.sh tools/tests/lib/callback_negative.lua build/states/callback_negative.log
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 3000, retries = 1, watchdog = false }, {
  H.call(function()
    local fired = false
    emu.addMemoryCallback(function()
      if fired then return end
      fired = true
      H.assertEq(1, 2, "an injected miss inside a memory callback")
    end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  end),
  H.waitFrames(300),
})
