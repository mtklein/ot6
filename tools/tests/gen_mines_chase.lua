-- gen_mines_chase.lua -- from narshe_streets.mss (OCTO alone at (53,8),
-- map 20, high on the cliffs): walk west along the clifftop into the
-- "She's up there!" guard scene at (38,8) (_cca279: guards surround,
-- posture, and leave; a cutscene with no input needed), continue to the
-- mine mouth at (26,8) -> map 50 (mines chase map) at (78,58), and generate
-- mines_chase.mss at the first calm tile inside.  Then north through the
-- mines, clearing random encounters and logging their species, to
-- (55,12), one tile short of the trigger at (55,11) that starts the
-- bridge-collapse -> Kefka flashback -> Moogle-defense chain (a
-- three-party set-piece this harness does not enter).  Generate
-- moogle_entry.mss there, calm, trigger unfired.
--
-- Issue #75: every navigator step passes playBattles=true, so the map-50
-- random pool is fought (tap-A = Fight, confirm at default target) rather
-- than write-cleared.  That is bal_mines.lua's measured baseline policy:
-- 8/8 wins, 0 deaths, ~2 real turns / ~744 frames per battle for solo L5
-- Terra against the full pool (the mines balance measurement), so the cost
-- is roughly +1-2k frames per encounter drawn and the step budgets below
-- carry it.  This gen has no write idiom of its own.
local H = dofile("tools/tests/lib/ot6.lua")
local STREETS = "build/states/narshe_streets.mss.lua"

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function eventFor(n)
  local cnt = 0
  return function()
    cnt = H.eventRunning() and cnt + 1 or 0
    return cnt >= n
  end
end

-- species log: called every frame from arrive predicates; names each
-- battle once on its 3rd consecutive loading frame (same debounce as the
-- library's classifiers)
local battSeen = 0
local function logBattles()
  if H.battleLoadStarted() then
    battSeen = battSeen + 1
    if battSeen == 3 then
      local w = H.formationWords()
      H.log(string.format("encounter: %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
  else
    battSeen = 0
  end
  return false
end

H.run({ maxFrames = 50000 }, {
  H.loadState(STREETS),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.mapId(), 20, "boot map is the Narshe streets")
  end),

  -- west along the clifftop; stepping on (38,8) fires the guard scene.
  -- The scene ends by setting switch $012D, and that switch is the
  -- terminator rather than calm: the party is left standing on the
  -- trigger, and a stood-on trigger re-fires every 4 frames indefinitely
  -- (a no-op once its switch is set, but the event engine still grabs the
  -- party for 3 frames of each cycle, so hasControl never holds).  Walk
  -- off it with a raw held direction, which works because the field module
  -- latches the pad in the 1-frame control windows, and only then expect
  -- calm.
  H.navTo(38, 8, { arrive = eventFor(30), maxFrames = 8000, playBattles = true }),
  H.advanceStory(function()
    return (H.readByte(0x1ea5) & 0x20) ~= 0    -- switch $012D
  end, 8000, { playBattles = true }),
  H.driveUntil(function()
    return H.fieldX() < 38 and H.tileAligned() and H.hasControl()
  end, 600, { H.hold({ "left" }) }, "off the chase trigger"),
  H.release(),
  H.call(function()
    H.log(string.format("guard scene done; calm at (%d,%d)",
      H.fieldX(), H.fieldY()))
    H.screenshot("chase_scene_done")
  end),

  -- into the mine mouth at (26,8) -> map 50 (78,58)
  H.navTo(26, 8, { arrive = function()
    logBattles()
    return H.mapId() == 50
  end, maxFrames = 9000, playBattles = true }),
  H.waitUntil(calm(30), 900, "mines control"),
  H.waitFrames(90),                     -- fade-in
  H.call(function()
    H.assertEq(H.mapId(), 50, "in the mines chase map (map 50)")
    H.log(string.format("mines entry at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("mines_chase")
  end),
  H.saveState("mines_chase.mss"),

  -- north to one tile short of the collapse trigger at (55,11).  Guards
  -- chase through this map (vanilla: mobile NPCs whose touch fires a
  -- catch event with a battle inside); navTo rides those like anything
  -- else, handling control loss and dialogs and fighting the battle with
  -- real input, then re-plans, so the only terminator is standing calm on
  -- the entry-point tile.  BFS never detours through (55,11): the approach
  -- is from the south and the trigger sits beyond the target.  arrive here
  -- is only a logging hook.
  H.navTo(55, 12, { arrive = function() logBattles(); return false end,
                    maxFrames = 24000, playBattles = true }),
  H.call(function()
    H.assertEq(H.mapId(), 50, "still on map 50")
    H.assertEq(H.fieldX() == 55 and H.fieldY() == 12, true,
      "at the moogle entry point (55,12), one south of the trigger")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "entry point is calm (control, at rest)")
    H.assertEq(H.eventRunning(), false, "collapse trigger unfired")
    H.screenshot("moogle_entry")
  end),
  H.saveState("moogle_entry.mss"),
  H.logStep(function()
    return string.format("moogle_entry generated at frame %d", H.frame)
  end),
})
