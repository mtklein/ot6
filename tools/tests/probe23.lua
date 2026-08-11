-- probe23.lua: positive control for input injection after loadSavestate.
-- Loads first_battle.mss (command menu open, cursor on MagiTek), then:
--   press A -> screenshot (the submenu must open, so the shot differs from
--              the baseline)
--   press B -> screenshot (the submenu must close, so the shot differs from
--              the A shot)
-- Fails if any press has no visible effect.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"

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
