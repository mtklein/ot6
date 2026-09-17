-- probe_checkpoint_env.lua -- #217's control: what a script can actually
-- see of OT6_SRAM_CHECKPOINT.
--
-- Run it twice from the tree root:
--
--   tools/tests/run.sh tools/tests/probe_checkpoint_env.lua \
--       build/lab/217-env-none.log
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/crescent-landing-v1 \
--     tools/tests/run.sh tools/tests/probe_checkpoint_env.lua \
--       build/lab/217-env-checkpoint.log
--
-- Both runs log an `[env]` line with the old reading (os.getenv, through a
-- pcall, the way gen_thamasa_arrive used to switch on it) beside the new
-- one (the global lib/compose.py injects).  os.getenv reads "nil" in BOTH
-- runs -- Mesen's sandbox leaves `os` nil (AllowIoOsAccess=false) -- which
-- is the whole of #217: the checkpoint run took the savestate branch.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local okOs, viaOs = pcall(function() return os.getenv("OT6_SRAM_CHECKPOINT") end)
    local viaGlobal = rawget(_G, "OT6_SRAM_CHECKPOINT")
    H.log(string.format("[env] os present=%s  os.getenv ok=%s -> %s",
      tostring(rawget(_G, "os") ~= nil), tostring(okOs), tostring(viaOs)))
    H.log(string.format("[env] injected global OT6_SRAM_CHECKPOINT=%s",
      tostring(viaGlobal)))
    -- gen_thamasa_arrive's old switch: `pcall(os.getenv)` and take the
    -- value only if the call succeeded.  It cannot succeed here.
    local oldReading = (okOs and viaOs ~= "" ) and viaOs or nil
    H.assertEq(oldReading, nil,
      "the os.getenv reading is nil whether or not a checkpoint was given")
  end),
})
