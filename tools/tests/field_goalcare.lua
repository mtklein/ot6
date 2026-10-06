-- @suite savestate=crescent_landing
-- field_goalcare.lua -- #323: a battle that comes up on a walk's goal tile
-- is cared for before the walk ends.
--
-- The walkers run their between-battles care stop (M.newCareDriver) in the
-- body, once the map has control back, but check their terminator first
-- every frame.  A battle that came up on the step onto the goal tile left
-- the party standing there when control came back, so the terminator ended
-- the walk on that frame and the care stop never ran.  The walkers now hold
-- the walk open until the care a fought battle owes has run.
--
-- Played, no writes: one-tile walks back and forth on the world map
-- (crescent_landing's corridor), battles fought (playBattles "tactical"),
-- until N battles have come up.  Every battle in such a walk comes up on
-- its goal tile, since the walk is one step.  For each walk that met a
-- battle the care stop's roster line ("[care after battle (worldNavTo)]
-- ...", logged whether or not anybody needed anything) must come before
-- the walk's own "satisfied" line.  Then the same on a field map
-- (vargas_entry, Mt Kolts' ledge) with navTo.
--
-- The draw: the corridor's encounters come from the fixture's counters, so
-- which formations meet the party is the fixture's; the property does not
-- depend on them (any battle on the goal tile).  PRE battles are fought
-- first with care off, using up encounters; a copy of this file with PRE
-- raised is how the draw is varied.
local H = dofile("tools/tests/lib/ot6.lua")

local WORLD = "build/states/crescent_landing.mss.lua"
local FIELD = "build/states/vargas_entry.mss.lua"
local WANT = 3                         -- battles per map
local PRE = 0                          -- battles used up first (see above)

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

local battles, inBattle = 0, false
emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then inBattle = true; battles = battles + 1 end
  if not live and inBattle then inBattle = false end
end, emu.eventType.startFrame)

-- A step rebuilt from scratch every time it runs (a navigator keeps its
-- plan; field_care_emptybag's fresh()).
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

local function partyUp()
  for _, c in ipairs(H.partyMembers()) do
    if H.charHp(c) > 0 then return true end
  end
  return false
end

-- one single-step walk; records, for a walk that met a battle, whether the
-- care stop's line came before the walk's end
local results = { world = {}, field = {} }
local A, B = nil, nil                  -- the two tiles walked between
local function walk(kind, care)
  return fresh(function()
    local x, y
    if kind == "world" then x, y = H.worldX(), H.worldY() else x, y = H.fieldX(), H.fieldY() end
    local t = (x == A[1] and y == A[2]) and B or A
    local b0, l0 = battles, #lines + 1
    local tag = kind == "world" and "worldNavTo" or "navTo"
    local nav = kind == "world" and H.worldNavTo or H.navTo
    return {
      nav(t[1], t[2], { maxFrames = 3000, playBattles = "tactical", care = care }),
      H.call(function()
        if not care or battles == b0 then return end
        local careAt, endAt = nil, nil
        for i = l0, #lines do
          if not careAt and lines[i]:find("[care after battle (" .. tag .. ")]", 1, true) then careAt = i end
          if lines[i]:find("driveUntil '" .. tag .. "' satisfied", 1, true) then endAt = i end
        end
        local ok = careAt ~= nil and endAt ~= nil and careAt < endAt
        results[kind][#results[kind] + 1] = ok
        H.log(string.format("[goalcare] %s walk to (%d,%d) met %d battle(s): care line %s, walk end %s: %s",
          kind, t[1], t[2], battles - b0, tostring(careAt), tostring(endAt),
          ok and "cared before the walk ended" or "WALK ENDED WITHOUT ITS CARE"))
      end),
    }
  end)
end

local function measure(kind)
  local n0 = nil
  return {
    H.call(function() n0 = battles end),
    H.driveUntil(function() return battles - n0 >= PRE or not partyUp() end, 400000, {
      walk(kind, false) }, kind .. ": " .. PRE .. " battles used up first, care off"),
    H.call(function() n0 = battles end),
    H.driveUntil(function()
      return #results[kind] >= WANT or not partyUp()
    end, 600000, { walk(kind, true) }, kind .. ": " .. WANT .. " battles on a goal tile"),
    H.call(function()
      H.assertEq(partyUp(), true, kind .. ": the party is standing")
      for i, ok in ipairs(results[kind]) do
        H.assertEq(ok, true, string.format("%s battle %d on a goal tile was cared for before the walk ended", kind, i))
      end
    end),
  }
end

H.run({ maxFrames = 1400000 }, {
  H.loadState(WORLD),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() end,
    600, "world: control", 5),
  H.call(function()
    A = { H.worldX(), H.worldY() }
    B = { A[1], A[2] - 1 }
    H.assertEq(H.worldPassable(B[1], B[2]), true,
      string.format("world: (%d,%d), a step north of the boot tile, is walkable", B[1], B[2]))
  end),
  H.seqStep(measure("world")),

  H.loadState(FIELD),
  H.call(function() B = nil end),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 600, "field: control", 5),
  H.call(function()
    A = { H.fieldX(), H.fieldY() }
    for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }) do
      if B == nil then
        if H.canStep(A[1], A[2], d[1]) then B = { A[1] + d[2], A[2] + d[3], d[1] } end
      end
    end
    H.assertEq(B ~= nil, true, "field: the boot tile has a walkable neighbour")
    H.log(string.format("[goalcare] field: walking (%d,%d) <-> (%d,%d) on map %d",
      A[1], A[2], B[1], B[2], H.mapId() & 0x1ff))
  end),
  H.seqStep(measure("field")),
})
