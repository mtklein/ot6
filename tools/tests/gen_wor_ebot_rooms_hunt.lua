-- gen_wor_ebot_rooms_hunt.lua -- a branch beside gen_wor_ebot (docs/design/route-wor-gogo.md section 11, #488):
-- boot the graph's capture `wor_ebot_rooms` (the party on its first landing in Ebot's Rock's random rooms, 404)
-- and walk a lap there until each formation of the rooms' pool is won (K.hunt).  Nothing boots what it leaves
-- (the state `wor_ebot_rooms_hunt`).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
local LINKS = {}

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, lv, say, kitLine, watches, walk, walkInto = K.map, K.lv, K.say, K.kitLine, K.watches, K.walk, K.walkInto
local FOUR = { STRAGO, RELM, GOGO, TERRA }
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
-- the rock's step-on tiles (gen_wor_ebot's holes and route_data map 404/405's other triggers), kept off a lap:
-- the lap is the tile the capture stands on and a neighbour one step away, neither a step-on tile (404's walls
-- are drawn at random on each landing, so the lap is read from the live map)
local EBOT_HOLES = { [404] = { { 3, 6 }, { 15, 4 }, { 25, 5 }, { 3, 16 }, { 18, 16 }, { 26, 17 }, { 4, 27 }, { 14, 28 },
  { 28, 27 } }, [405] = { { 8, 9 }, { 7, 15 }, { 23, 22 } } }
local EBOT_TRIGGERS = { [404] = {}, [405] = { { 23, 19 }, { 7, 5 }, { 23, 7 }, { 7, 24 } } }
local function holesHere() return EBOT_HOLES[map()] or {} end
local function offLap(x, y)
  for _, t in ipairs(holesHere()) do if t[1] == x and t[2] == y then return true end end
  for _, t in ipairs(EBOT_TRIGGERS[map()] or {}) do if t[1] == x and t[2] == y then return true end end
  return false
end
local function lapHere(what)
  local x, y = H.fieldX(), H.fieldY()
  for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local nx, ny = x + d[1], y + d[2]
    local p = not offLap(nx, ny) and H.bfsPath(nx, ny) or nil
    if p and #p == 1 then return { { x, y }, { nx, ny } } end
  end
  error(string.format("[hunt] %s: no lap beside map %d (%d,%d)", what, map(), x, y))
end
local ROOMS193 = { [291] = "Opinicus x2", [292] = "Displayer", [293] = "Opinicus, Hipocampus, Eland",
  [294] = "Hipocampus x3" }

H.run({ maxFrames = 800000 }, {
  H.loadState("build/states/wor_ebot_rooms.mss.lua"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 404, "the boot stands in Ebot's Rock's rooms (404): gen_wor_ebot's capture wor_ebot_rooms")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: Ebot's rooms (group 193)" }),
  H.lazy(function()
    H.assertEq(offLap(H.fieldX(), H.fieldY()), false, "Ebot's rooms (group 193): the lap starts off the step-on tiles")
    return K.hunt({ what = "Ebot's rooms (group 193)", lap = lapHere("Ebot's rooms (group 193)"), forms = ROOMS193, won = won, castFirst = true, avoid = holesHere() })
  end),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: Ebot's rooms (group 193)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_ebot_rooms_hunt.mss"),
  H.logStep(function()
    return string.format("wor_ebot_rooms_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
