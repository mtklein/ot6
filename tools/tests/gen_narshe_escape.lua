-- gen_narshe_escape.lua -- from arvis_wake.mss: talk to Arvis and ride the
-- wake-flow event (_cca06f) through its dialogs, the character-naming menu
-- (default OCTO; START commits it -- name_change.asm exits on START unless
-- the name is blank), the guards-at-the-gate scene and the knocking at the
-- door, until control returns downstairs with switch $0001 set.  Mint
-- narshe_escape_start.mss there, then leave the way Arvis pointed: the
-- front door at (55,35) stays blocked by its invisible door-NPC (the
-- soldiers are behind it), so the way out is the corridor above the
-- bedroom -- exit (67,26) -> map 20 (Narshe outdoors) at (53,8), high on
-- the cliffs.  Mint narshe_streets.mss at the first calm tile outside.
-- The naming menu is the one story beat advanceStory cannot tap through --
-- $0059 goes 1 while it opens, so the script splits there and presses
-- START itself.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local WAKE = "/Users/mtklein/ot6/build/states/arvis_wake.mss.lua"

-- n consecutive calm frames, optionally with an extra condition
local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function escapeStarted()          -- event switch $0001
  return (H.readByte(0x1e80) & 0x02) ~= 0
end

H.run({ maxFrames = 30000 }, {
  H.loadState(WAKE),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.mapId(), 30, "boot map is Arvis's house")
    H.assertEq(escapeStarted(), false, "escape switch $0001 clear")
  end),

  -- Arvis stands at (64,29), three tiles right of the wake position; walk
  -- beside him, face him (a blocked press just turns), and talk
  H.navTo(63, 29, { maxFrames = 2000 }),
  H.hold({ "right" }), H.waitFrames(6), H.release(), H.waitFrames(4),
  H.pressButtons({ "a" }, 6),
  H.waitUntil(function() return H.dialogWaiting() end, 300, "arvis dialog opens"),

  -- dialogs up to the naming menu ($0059 flips to 1 as it opens)
  H.advanceStory(function() return H.readByte(0x0059) ~= 0 end, 8000),
  H.logStep("naming menu opening; committing the default name"),
  H.waitFrames(180),                    -- menu fade-in
  H.call(function() H.screenshot("escape_naming") end),
  H.pressButtons({ "start" }, 8),
  H.waitFrames(30),

  -- the rest of the scene: name echo dialog, the gate cutscene on map 19,
  -- the knocking, the force-walk downstairs; ends with switch $0001 set
  -- and control returned
  H.advanceStory(calm(30, escapeStarted), 20000),
  H.call(function()
    H.assertEq(escapeStarted(), true, "escape switch $0001 set")
    H.assertEq(H.mapId(), 30, "still in Arvis's house")
    H.log(string.format("escape underway; calm at (%d,%d)",
      H.fieldX(), H.fieldY()))
    H.screenshot("escape_start")
  end),
  H.saveState("narshe_escape_start.mss"),

  -- out via the corridor above the bedroom: (67,26) exits to map 20 (53,8)
  H.navTo(67, 26, { arrive = function() return H.mapId() == 20 end,
                    maxFrames = 4000 }),
  H.waitUntil(calm(30), 900, "streets control"),
  H.waitFrames(90),                     -- let the map fade-in finish
  H.call(function()
    H.assertEq(H.mapId(), 20, "on the Narshe streets (map 20)")
    H.log(string.format("outside at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("narshe_streets")
  end),
  H.saveState("narshe_streets.mss"),
  H.logStep(function()
    return string.format("narshe_streets minted at frame %d", H.frame)
  end),
})
