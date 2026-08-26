-- probe_moogle_evpc.lua -- traces the event PC through a wave-1 loss.
-- Boots moogle_defense, idles into the wipe, A-mashes through the
-- Annihilated screen, and from the moment the battle module drops out
-- logs every per-frame change of the 24-bit event PC {$e5,$e6,$e7}
-- alongside brightness / pos, for 2500 frames. Zero writes: pad input
-- and reads only.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function evpc()
  return string.format("%02X/%02X%02X", H.readByte(0x00e7),
    H.readByte(0x00e6), H.readByte(0x00e5))
end

local battN, aPhase = 0, 0
local last = nil

H.run({ maxFrames = 45000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 3
  end, 8000, { H.call(function() H.setPad({}) end) }, "wave 1 collision"),
  H.driveUntil((function()
    local calm = 0
    return function()
      calm = (not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 240
    end
  end)(), 30000, { H.call(function() H.setPad({}) end) }, "party wiped, battle gone"),
  -- from here: A-mash through the Annihilated leftovers while tracing
  H.driveUntil((function()
    local n = 0
    return function()
      n = n + 1
      aPhase = (aPhase + 1) % 8
      H.setPad(n < 600 and aPhase < 4 and { "a" } or {})
      local cur = string.format("pc=%s bright=%d pos=(%d,%d)",
        evpc(), bright(), H.fieldX(), H.fieldY())
      if cur ~= last then
        H.log(string.format("f%d %s", H.frame, cur))
        last = cur
      end
      return n >= 2500
    end
  end)(), 3000, {}, "2500-frame event-PC trace done"),
  H.call(function() H.log("trace complete") end),
})
