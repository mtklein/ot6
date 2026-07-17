-- shot_final.lua -- two release-verification screenshots on the current
-- build: a mines random encounter (settled, hud up) and the Whelk fight.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local MINES = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"
local WHELK = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"

local aPhase = 0

H.run({ maxFrames = 30000 }, {
  H.loadState(MINES),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 1200, "mines control", 10),
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      H.setPad({ [(H.fieldX() >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "random encounter fires"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(300),
  H.call(function() H.screenshot("final_random_encounter") end),

  H.loadState(WHELK),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 1200, "whelk control", 10),
  H.driveUntil(function() return H.battleLoadStarted() end, 3300, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk active", 30),
  H.waitFrames(400),
  H.call(function() H.screenshot("final_whelk") end),
})
