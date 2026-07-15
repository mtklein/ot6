-- probe22.lua: resume the captured in-battle state and coax the monster
-- NAME window on screen (press A to enter targeting from the command menu),
-- screenshotting along the way.  Used to visually verify the break-system
-- shield digits render after each enemy name.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/first_battle.mss.lua"

local function glyphs()
  local g = {}
  for a = 0x3ECB, 0x3ED2 do g[#g + 1] = string.format("%02X", H.readByte(a)) end
  return table.concat(g, " ")
end

local function snap(tag)
  return H.call(function()
    H.screenshot(tag)
    H.log(tag .. " glyphs $3ECB+: " .. glyphs())
  end)
end

H.run({ maxFrames = 4000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  snap("resume0"),
  -- press A: command menu -> target cursor (monster name window visible)
  H.pressButtons({ "a" }, 6),
  H.waitFrames(30),
  snap("resume_a1"),
  -- press A again in case the first only confirmed a menu row
  H.pressButtons({ "a" }, 6),
  H.waitFrames(30),
  snap("resume_a2"),
  -- and B to back out, leaving the default battle layout
  H.pressButtons({ "b" }, 6),
  H.waitFrames(30),
  snap("resume_b"),
  H.waitFrames(120),
  snap("resume_late"),
})
