-- gen_mines_chase.lua -- from narshe_streets.mss (OCTO alone at (53,8),
-- map 20, high on the cliffs): walk west along the clifftop into the
-- "She's up there!" guard scene at (38,8) (_cca279 -- guards surround,
-- posture, and leave; pure cutscene, ridden hands-off), continue to the
-- mine mouth at (26,8) -> map 50 (mines chase map) at (78,58), and mint
-- mines_chase.mss at the first calm tile inside.  Then north through the
-- mines -- random encounters cleared and their species logged -- to
-- (55,12), ONE TILE short of the trigger at (55,11) that starts the
-- bridge-collapse -> Kefka flashback -> Moogle-defense chain (a
-- THREE-PARTY set-piece this harness does not enter).  Mint
-- moogle_doorstep.mss there, calm, trigger unfired.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STREETS = "/Users/mtklein/ot6/build/states/narshe_streets.mss.lua"

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

H.run({ maxFrames = 30000 }, {
  H.loadState(STREETS),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.mapId(), 20, "boot map is the Narshe streets")
  end),

  -- west along the clifftop; stepping on (38,8) fires the guard scene.
  -- The scene ends by setting switch $012D -- and that, not calm, is the
  -- terminator: the party is left STANDING ON the trigger, and a stood-on
  -- trigger re-fires every 4 frames forever (a no-op once its switch is
  -- set, but the event engine still grabs the party for 3 frames of each
  -- cycle, so hasControl never holds).  Walk OFF with a raw held
  -- direction -- the field module latches the pad in the 1-frame control
  -- windows -- and only then expect calm.
  H.navTo(38, 8, { arrive = eventFor(30), maxFrames = 5000 }),
  H.advanceStory(function()
    return (H.readByte(0x1ea5) & 0x20) ~= 0    -- switch $012D
  end, 8000),
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
  end, maxFrames = 5000 }),
  H.waitUntil(calm(30), 900, "mines control"),
  H.waitFrames(90),                     -- fade-in
  H.call(function()
    H.assertEq(H.mapId(), 50, "in the mines chase map (map 50)")
    H.log(string.format("mines entry at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("mines_chase")
  end),
  H.saveState("mines_chase.mss"),

  -- north to one tile short of the collapse trigger at (55,11).  Guards
  -- CHASE through this map (vanilla: mobile NPCs whose touch fires a
  -- catch event with a battle inside); navTo rides those like anything
  -- else -- control loss, dialogs, kill-bit the fight -- and re-plans, so
  -- the only terminator is standing calm on the doorstep tile.  BFS never
  -- detours through (55,11): the approach is from the south and the
  -- trigger sits beyond the target.  arrive here is a pure logging hook.
  H.navTo(55, 12, { arrive = function() logBattles(); return false end,
                    maxFrames = 15000 }),
  H.call(function()
    H.assertEq(H.mapId(), 50, "still on map 50")
    H.assertEq(H.fieldX() == 55 and H.fieldY() == 12, true,
      "at the moogle doorstep (55,12), one south of the trigger")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "doorstep is calm (control, at rest)")
    H.assertEq(H.eventRunning(), false, "collapse trigger unfired")
    H.screenshot("moogle_doorstep")
  end),
  H.saveState("moogle_doorstep.mss"),
  H.logStep(function()
    return string.format("moogle_doorstep minted at frame %d", H.frame)
  end),
})
