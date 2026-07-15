-- probe16.lua: savestate round-trip validation using lib/ot6.lua.
-- request save -> clobber WRAM -> request load -> confirm restored.
-- (Savestate create/load go through the exec-callback trampoline; this is
-- also the regression test for that mechanism.)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local ADDR = 0x7E1000
local before, blob, req

H.run({ maxFrames = 2000 }, {
  H.waitFrames(400), -- into the title sequence; WRAM is busy by now
  H.call(function()
    before = H.readWord(ADDR)
    req = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(req, "savestate capture")
    blob = req.blob
    H.log("state blob size: " .. #blob)
    H.writeWord(ADDR, (before ~ 0xFFFF) & 0xFFFF)
  end),
  H.waitFrames(2),
  H.call(function()
    H.log(string.format("before=%04X clobbered=%04X", before, H.readWord(ADDR)))
    req = H.requestLoadState(blob)
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(req, "savestate load")
    H.assertEq(H.readWord(ADDR), before, "WRAM word restored by loadSavestate")
    local head = blob:sub(1, 100000)
    H.assertEq(H.b64decode(H.b64encode(head)) == head, true, "b64 encode/decode round-trip")
  end),
})
