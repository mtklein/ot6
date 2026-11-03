-- gen_wor_tomb_hunt.lua -- a branch beside gen_wor_falcon (#502, wor-coverage.md section 11.9): Continue the
-- `wor-tomb-v1` battery (CELES, SABIN, EDGAR and SETZER on Darill's Tomb's save point, B3's east room 300
-- (122,14)) and lap there until each formation of B3's pool (field group 151) is won: 251 (Mad Oscar), which the
-- line's walk did not meet, with 250 and 248; then up the east room's stair (122,7) into the grave room (299, B2's
-- pool, group 150) and lap below the grave until its three are won: 247 (PowerDemon), unmet on the line, with 249
-- and 250 (K.hunt).  The grave's trigger (100,14) and the monster chest (120,9) are kept off the laps: Dullahan and
-- the chest are gen_wor_falcon's.  Nothing boots what it leaves (the state `wor_tomb_hunt`).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, SABIN, CELES, SETZER = 4, 5, 6, 9
local NAMES = { [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES", [SETZER] = "SETZER" }
local FOUR = { CELES, SABIN, EDGAR, SETZER }
local MAP_B2, MAP_B3 = 299, 300
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, watches, walkInto = K.map, K.say, K.kitLine, K.watches, K.walkInto
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
local B3_151 = { [251] = "Mad Oscar", [250] = "Mad Oscar, Exoray", [248] = "PowerDemon, Exoray x2" }
local B2_150 = { [247] = "PowerDemon", [249] = "Exoray x3", [250] = "Mad Oscar, Exoray" }
-- the east room's doors, the save point and the two chests' tiles; the grave room's door back, its grave and the
-- way past it
local EAST_AVOID = { { 122, 7 }, { 122, 29 }, { 122, 14 }, { 120, 9 }, { 124, 9 } }
local GRAVE_AVOID = { { 100, 29 }, { 100, 14 }, { 100, 7 } }

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), MAP_B3, "the boot stands in Darill's Tomb's B3 (300): gen_wor_tomb's save wor-tomb-v1")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: B3's east room (group 151)" }),
  -- @@stage hunt
  K.hunt({ what = "Darill's Tomb B3 (group 151)", lap = { { 120, 16 }, { 120, 17 } }, forms = B3_151, won = won,
    avoid = EAST_AVOID }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: B3's east room (group 151)" }),
  walkInto(122, 7, MAP_B2, "B3 (122,7) -> the grave room (299 (100,28))", { { 122, 29 }, { 122, 14 }, { 120, 9 },
    { 124, 9 } }),
  H.saveState("wor_tomb_hunt_grave.mss"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the grave room (group 150)" }),
  K.hunt({ what = "Darill's Tomb B2's grave room (group 150)", lap = { { 100, 25 }, { 100, 26 } }, forms = B2_150,
    won = won, avoid = GRAVE_AVOID }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the grave room (group 150)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_tomb_hunt.mss"),
  H.logStep(function()
    return string.format("wor_tomb_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
