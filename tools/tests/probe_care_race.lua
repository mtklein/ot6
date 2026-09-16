-- @manual
-- probe_care_race.lua -- #184: the care stop asked for K frames BEFORE a
-- world-map random opens, for a sweep of K, from one legitimately reached
-- state (crescent_landing, the walk field_care_emptybag plays).  Lap 52 of
-- gen_zozo2_arrival attempt 1 had this shape: the care's X presses began
-- on the frame a worldNavTo reported arrival, the last step's encounter
-- fired, and "field menu open" was satisfied by ZMENUSTATE reading 05
-- with the battle up.  Which K lands X on the encounter-step's end is what
-- the sweep measures; what the care driver does about it is the finding.
--
-- F_REL is battle 2's load frame relative to the fixture load, measured
-- by field_care_emptybag attempt 2 (loaded at f3, battle 2 loading at
-- f4156); the walk here is the same walk, so the encounter fires on the
-- same step.  Every variant reloads the fixture and replays it.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/crescent_landing.mss.lua"
local TONIC, POTION = 0xE8, 0xE9
local THRESH = 0.95
local NORTH, SOUTH = { 232, 144 }, { 232, 150 }
local F_REL = 4153
local KS = { 0, 8, 16, 24, 32, 40, 48, 64, 80, 96 }

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end

local battles, inBattle = 0, false
emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then inBattle = true; battles = battles + 1 end
  if not live and inBattle then inBattle = false end
end, emu.eventType.startFrame)

local function worst()
  local w, r = nil, 1.0
  for _, c in ipairs(H.partyMembers()) do
    local f = H.charHp(c) / H.charMaxHp(c)
    if H.charHp(c) > 0 and f < r then w, r = c, f end
  end
  return w, r
end
local function hurt() local _, r = worst(); return r < THRESH end
local function settled()
  return H.worldMode() and H.worldHasControl() and H.worldAligned()
     and not H.battleLoadStarted()
end

local function fresh(build)
  local inner = nil
  return {
    tick = function()
      inner = inner or H.seqStep(build())
      local r = inner:tick()
      if r == "done" then inner = nil end
      return r
    end,
    reset = function() inner = nil end,
  }
end

local legN = 0
local function leg(stop)
  legN = legN + 1
  local t = (legN % 2 == 1) and NORTH or SOUTH
  if H.worldX() == t[1] and H.worldY() == t[2] then
    t = (t == NORTH) and SOUTH or NORTH
  end
  return {
    H.worldNavTo(t[1], t[2],
      { maxFrames = 20000, playBattles = "tactical", care = false, arrive = stop }),
    H.release(),
  }
end
local function walkUntilHurt(n)
  local function stop() return battles >= 1 and hurt() and settled() end
  return H.repeatN(n, {
    H.cond(function() return not stop() end,
      { fresh(function() return leg(stop) end) }, {}),
  })
end

local function state(tag)
  H.log(string.format("[race] %s: f%d $26=$%02X battle=%s worldCtl=%s aligned=%s (%d,%d) potion=%d",
    tag, H.frame, H.readByte(0x26), tostring(H.battleLoadStarted()),
    tostring(H.worldHasControl()), tostring(H.worldAligned()), H.worldX(), H.worldY(),
    H.invCountOf(POTION)))
end

local steps = { H.waitFrames(20) }
for _, K in ipairs(KS) do
  local t0, tStop, W = nil, nil, nil
  local function stopAt() return (H.frame - t0) >= (F_REL - K) or H.battleLoadStarted() end
  local these = {
    H.loadState(FIX),
    H.call(function() t0 = H.frame; battles, inBattle, legN = 0, false, 0; lines = {} end),
    H.waitFrames(60),
    H.waitUntil(settled, 1200, "world control at the landing", 5),
    walkUntilHurt(12),
    H.call(function()
      H.assertEq(hurt(), true, string.format("K=%d: somebody is hurt before the race", K))
    end),
    H.repeatN(24, {
      H.cond(function() return not stopAt() end,
        { fresh(function() return leg(stopAt) end) }, {}),
    }),
    H.release(),
    H.call(function()
      tStop = H.frame
      state(string.format("K=%d: walk stopped %d frames after the load; care stop starts", K, H.frame - t0))
      lines = {}
    end),
    H.careStop(string.format("care K=%d", K), { threshold = THRESH }),
    H.call(function()
      state(string.format("K=%d: care stop returned after %d frames", K, H.frame - tStop))
      H.log(string.format("[race] K=%d: said yielding=%s REFUSED=%s never-closed=%s scene-owns=%s used-potion=%s nothing-to-do=%s",
        K, tostring(said("yielding to the fight")), tostring(said("REFUSED")),
        tostring(said("the menu never closed")), tostring(said("a scene owns the field")),
        tostring(said("used $E9")), tostring(said("nothing to do"))))
    end),
    -- whatever is up now, play it out so the next variant starts clean
    H.call(function() W = H.newWalkFighter(string.format("K=%d aftermath", K), { care = false }) end),
    H.driveUntil(function() return not W.frame() end, 40000, {}, string.format("K=%d aftermath", K)),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      state(string.format("K=%d: after the aftermath (battles seen %d)", K, battles))
    end),
  }
  for _, s in ipairs(these) do steps[#steps + 1] = s end
end

H.run({ maxFrames = 400000 }, steps)
