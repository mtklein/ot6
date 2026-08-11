-- probe_moogle_fadewatch.lua -- measures what lights the field after a wave
-- loss (issue #74 instrument, not a test).  From moogle_defense: idle so
-- wave 1 wipes party 1, A-mash through the Annihilated screen until the
-- loss bench lands at (14,11), then hands off and log every change of
-- (brightness, ev, batt, pos, $1F41) for 1500 frames, screenshotting each
-- brightness transition.  Read-only + pad input.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local battN, aPhase = 0, 0
local last = nil
local shotN = 0

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
  H.driveUntil(function()
    return (not H.battleLoadStarted()) and H.mapId() == 51
       and H.fieldX() == 14 and H.fieldY() == 11
  end, 6000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "loss path landed (party benched at 14,11)"),
  -- hands off; per-frame transition log
  H.driveUntil((function()
    local n = 0
    return function()
      n = n + 1
      local cur = string.format("bright=%d ev=%s batt=%s pos=(%d,%d) 1F41=%02X",
        bright(), tostring(H.eventRunning()), tostring(H.battleLoadStarted()),
        H.fieldX(), H.fieldY(), H.readByte(0x1f41))
      if cur ~= last then
        H.log(string.format("f%d %s", H.frame, cur))
        local b = tostring(cur:match("bright=(%d+)"))
        local lb = last and tostring(last:match("bright=(%d+)")) or "?"
        if b ~= lb then
          shotN = shotN + 1
          H.screenshot("fadewatch_" .. shotN)
        end
        last = cur
      end
      return n >= 1500
    end
  end)(), 2000, { H.call(function() H.setPad({}) end) }, "1500-frame watch done"),
  H.call(function() H.log("watch complete") end),
})
