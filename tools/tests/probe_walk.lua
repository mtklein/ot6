-- probe_walk: route explorer toward Whelk. From the fight-2 doorstep:
-- win the fight fast (enemies poked to 1 hp, beams finish), then walk a
-- direction schedule, fighting through any forced encounters the same
-- way, screenshotting at each waypoint so the route can be extended by
-- eye, iteration by iteration.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle2_doorstep.mss.lua"

-- direction schedule: extend as the shots reveal the map
local ROUTE = {
  { "up", 240 }, { "up", 240 }, { "up", 240 },
  { "up", 240 }, { "left", 180 }, { "up", 240 },
}

-- monster hp words live at $3bf4 + 8 + slot*2 (entities 8..)
local function weakenMonsters()
  for slot = 0, 5 do
    local a = 0x3bf4 + 8 + slot*2
    if H.readWord(a) > 1 then H.writeWord(a, 1) end
  end
end

-- poke ONCE (weaken + berserk: menu-less auto-actions finish any
-- fight; repeated poking stalls it), wait it out, then tap A through
-- the victory text for a fixed beat
local function addFightClear(steps, tag)
  steps[#steps + 1] = H.waitFrames(200)  -- battle transitions settle
  steps[#steps + 1] = H.driveUntil(function()
    return not H.battleActive()
  end, 9000, {
    H.call(function()
      if H.battleActive() then
        -- no player actions needed: declare every present monster dead
        -- through its own status byte and let the engine tear down
        for slot = 0, 5 do
          local a = 0x3eec + slot*2
          if H.readByte(0x3aa8 + slot*2) % 2 == 1 then
            H.writeByte(a, H.readByte(a) | 0x80)
          end
        end
        H.setPad({ "a" })   -- also advance victory/exp text
      end
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, tag)
  for _ = 1, 10 do
    steps[#steps + 1] = H.pressButtons({ "a" }, 4)
    steps[#steps + 1] = H.waitFrames(26)
  end
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "fight 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "fight 2 active", 30),
  H.waitFrames(120),
}
addFightClear(steps, "fight 2 cleared")
steps[#steps + 1] = H.waitFrames(240)
steps[#steps + 1] = H.call(function() H.screenshot("walk_00") end)

for i, leg in ipairs(ROUTE) do
  steps[#steps + 1] = H.hold({ leg[1] })
  steps[#steps + 1] = H.waitFrames(leg[2])
  steps[#steps + 1] = H.release()
  steps[#steps + 1] = H.waitFrames(10)
  addFightClear(steps, "leg " .. i .. " clear")
  steps[#steps + 1] = H.call(function()
    H.screenshot(string.format("walk_%02d", i))
  end)
end

H.run({ maxFrames = 60000 }, steps)
