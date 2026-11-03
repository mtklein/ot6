-- gen_wor_mtzozo_hunt.lua -- a branch beside gen_wor_storm (#502, wor-coverage.md section 11.9): Continue the
-- `wor-mtzozo-v1` battery (CYAN, TERRA, CELES and SABIN on Mt. Zozo's save point, 179 (40,15)), walk down the east
-- face into the east cave (178, door (51,40)) and a lap there until each formation of the caves' pool (field group
-- 162, which the west cave 177 shares) is won (K.hunt): 261 (Luridan x3) and 264 (Borras, Ursus, Scrapper), which
-- the line's walks through the caves (about three battles there) did not meet, and 266 (Luridan x6).  Nothing boots
-- what it leaves (the state `wor_mtzozo_hunt`).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, SABIN, CELES = 0, 2, 5, 6
local NAMES = { [TERRA] = "TERRA", [CYAN] = "CYAN", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { CYAN, TERRA, CELES, SABIN }
local MAP_MTZOZO, MAP_MTZOZO_E = 179, 178
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, watches, walkInto = K.map, K.say, K.kitLine, K.watches, K.walkInto
-- Mt. Zozo's doors, the Storm Dragon's trigger and the save point (gen_wor_cyan's MZ_DOORS)
local MZ_DOORS = { { 25, 30 }, { 11, 10 }, { 18, 5 }, { 56, 16 }, { 48, 11 }, { 40, 15 } }
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
local CAVES162 = { [261] = "Luridan x3", [264] = "Borras, Ursus, Scrapper", [266] = "Luridan x6" }

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("wor-mtzozo-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), MAP_MTZOZO, "the boot stands on Mt. Zozo's east face (179): gen_wor_cyan's save wor-mtzozo-v1")
  end),
  -- @@setup-end
  walkInto(51, 40, MAP_MTZOZO_E, "Mt. Zozo's east face -> the east cave (178 (10,11))", MZ_DOORS),
  H.saveState("wor_mtzozo_hunt_cave.mss"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the east cave (group 162)" }),
  -- @@stage hunt
  K.hunt({ what = "Mt. Zozo's east cave (group 162)", lap = { { 14, 12 }, { 15, 12 } }, forms = CAVES162, won = won,
    avoid = { { 9, 11 }, { 22, 10 } } }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the east cave (group 162)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_mtzozo_hunt.mss"),
  H.logStep(function()
    return string.format("wor_mtzozo_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(),
      H.fieldY(), wonLine())
  end),
})
