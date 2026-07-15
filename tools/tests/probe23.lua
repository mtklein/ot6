-- probe23.lua: POSITIVE CONTROL for input injection after loadSavestate.
-- Loads first_battle.mss (command menu open, cursor on MagiTek), then:
--   press A -> screenshot (submenu must OPEN -> differs from baseline)
--   press B -> screenshot (submenu must CLOSE -> differs from the A shot)
-- Fails loudly if any press has no visible effect.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/first_battle.mss.lua"

local shots = {}
local function snap(name)
  return H.call(function()
    local ok, png = pcall(emu.takeScreenshot)
    assert(ok and type(png) == "string" and #png > 0, "screenshot failed at " .. name)
    shots[name] = png
    H.log(string.format("%s: %d bytes", name, #png))
    H.emitBlob("ctl_" .. name .. ".png", png)
  end)
end

H.run({ maxFrames = 2000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  snap("baseline"),
  H.pressButtons({ "a" }, 6),
  H.waitFrames(24),
  snap("after_a"),
  H.pressButtons({ "b" }, 6),
  H.waitFrames(24),
  snap("after_b"),
  H.call(function()
    H.assertEq(shots.baseline ~= shots.after_a, true,
      "A press changed the screen (submenu opened)")
    H.assertEq(shots.after_a ~= shots.after_b, true,
      "B press changed the screen (submenu closed)")
    H.log("input injection works after loadSavestate")
  end),
})
