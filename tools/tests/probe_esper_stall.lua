-- probe_esper_stall.lua -- SPIKE instrument: the post-Kefka esper scene
-- (map 23) stalls with ev=true and nothing to tap (spike 4 burned 30k
-- frames there).  Re-drive to the stall and dump the interpreter: the
-- event PC names the hanging opcode; the object table names the actor
-- whose scripted move cannot finish.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/spike_doorstep.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function killBitAll()
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end
local function objDump(tag)
  local t = {}
  for i = 0, 17 do
    local b = i * 0x29
    local x, y = H.readWord(0x086a + b) >> 4, H.readWord(0x086d + b) >> 4
    if x < 64 and y < 64 then
      t[#t + 1] = string.format("o%d(%d,%d,m%02X)", i, x, y,
        H.readByte(0x087c + b))
    end
  end
  H.log("[" .. tag .. "] " .. table.concat(t, " "))
end

H.run({ maxFrames = 30000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "A into KEFKA"),
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down")
  end)(),
  -- ride to map 23, then to the stall (no dialog, event running, 600
  -- consecutive frames), tapping dialogs on the way
  (function()
    local aPh, still = 0, 0
    return H.driveUntil(function()
      local stalled = map() == 23 and H.eventRunning()
                  and not H.dialogWaiting() and not H.battleLoadStarted()
      still = stalled and still + 1 or 0
      return still >= 600
    end, 20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.battleLoadStarted() then killBitAll() end
        if H.dialogWaiting() or H.battleLoadStarted() then
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "to the map-23 stall")
  end)(),
  H.call(function()
    H.log(string.format("[stall] f%d PC=%02X%02X%02X stack $e8=%04X " ..
      "$e1=%02X $e2=%02X $e3=%02X", H.frame,
      H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
      H.readWord(0x00e8), H.readByte(0x00e1), H.readByte(0x00e2),
      H.readByte(0x00e3)))
    objDump("stall")
    H.screenshot("esper_stall")
  end),
  -- watch the PC for 300 frames: a loop shows as a small PC orbit
  H.repeatN(6, {
    H.waitFrames(50),
    H.call(function()
      H.log(string.format("[stall+] PC=%02X%02X%02X",
        H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
    end),
  }),
})
