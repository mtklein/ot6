-- gen_wor_ancient_hunt.lua -- a branch beside gen_wor_ancient (docs/design/route-wor-dreams.md section 10,
-- #488): boot the graph's capture `wor_ancient_yard` (the party in the Ancient Castle's courtyard, 407, after the
-- flashback), walk a lap there until each formation of its pool is won, then into the castle (406) and a lap
-- below Odin's statue likewise (K.hunt).  Nothing boots what it leaves (the state `wor_ancient_hunt`).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
local LINKS = {}
-- 406's same-map doors (gen_wor_ancient's)
LINKS[406] = H.doorLinks({ { 15, 14, 24, 13 }, { 54, 28, 38, 9 }, { 45, 56, 35, 51 }, { 38, 7, 54, 27 },
  { 24, 12, 15, 13 }, { 9, 31, 33, 30 }, { 10, 31, 33, 30 }, { 11, 31, 33, 30 }, { 33, 31, 10, 32 },
  { 34, 31, 10, 32 } })
-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, lv, say, kitLine, watches, walk, walkInto = K.map, K.lv, K.say, K.kitLine, K.watches, K.walk, K.walkInto
local FOUR = { CELES, RELM, CYAN, TERRA }
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
local YARD145 = { [301] = "Goblin x2", [317] = "Barb-e, Samurai, Suriander", [302] = "Goblin, Figaliz x2" }
local HALL144 = { [305] = "Lethal Wpn", [304] = "Boxed Set", [303] = "Boxed Set x2, Figaliz x2", [308] = "Boxed Set x4" }

H.run({ maxFrames = 1500000 }, {
  H.loadState("build/states/wor_ancient_yard.mss.lua"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 407, "the boot stands in the Ancient Castle's courtyard (407): gen_wor_ancient's capture wor_ancient_yard")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the courtyard (group 145)" }),
  K.hunt({ what = "the courtyard (group 145)", lap = { { 16, 13 }, { 16, 14 } }, forms = YARD145, won = won, castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the courtyard (group 145)" }),
  walkInto(15, 10, 406, "407 (15,10) -> the castle (406)"),
  walk(32, 12, "beside Odin's statue (32,12)", { { 34, 14 } }),
  H.saveState("wor_ancient_hunt_hall.mss"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the castle (group 144)" }),
  K.hunt({ what = "the castle (group 144)", lap = { { 32, 12 }, { 33, 12 } }, forms = HALL144, won = won, castFirst = true, avoid = { { 34, 14 } } }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the castle (group 144)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_ancient_hunt.mss"),
  H.logStep(function()
    return string.format("wor_ancient_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
