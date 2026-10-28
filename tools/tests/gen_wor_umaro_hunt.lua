-- gen_wor_umaro_hunt.lua -- a branch beside gen_wor_tritoch (docs/design/route-wor-narshe.md section 15, #488):
-- boot the graph's capture `wor_tritoch_cave` (the party just dropped onto Umaro's cave's landing, 281 (14,55)),
-- walk a lap of the landing's pool until each formation is won, then into the X-Ether's pocket (282) and a lap of
-- its pool likewise (the lair 283 deals the same four).  Each hunt is K.hunt (lib/ot6_field.lua): the formations
-- asserted to be the pool the ROM gives the map, the hunt bounded by the worst draws the encounter counters can
-- hold.  Nothing boots what it leaves (the state `wor_umaro_hunt`): a player who pauses in the cave meets these,
-- and the main line, which walks through, does not carry their experience on.
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
local FOUR = { CYAN, TERRA, CELES, MOG }
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
-- the cave's floor drops (gen_wor_tritoch's), kept off the laps and the walk
local DROPS_281, DROPS_282 = { { 10, 54 }, { 11, 53 } }, { { 14, 30 }, { 33, 26 } }
local CAVE166 = { [254] = "Poppers x4", [255] = "Kiwok, Ceritops", [256] = "Kiwok, Poppers x3", [253] = "Pug" }
local CAVE167 = { [259] = "Anemone x4", [258] = "Anemone x2, Tomb Thumb", [260] = "Ceritops, Tomb Thumb x2",
  [257] = "Ceritops x3" }

H.run({ maxFrames = 1500000 }, {
  H.loadState("build/states/wor_tritoch_cave.mss.lua"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 281, "the boot stands on Umaro's cave's landing (281): gen_wor_tritoch's capture wor_tritoch_cave")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: Umaro's cave, the landing (group 166)" }),
  K.hunt({ what = "Umaro's cave, the landing (group 166)", lap = { { 14, 55 }, { 15, 55 } }, forms = CAVE166, won = won, castFirst = true, avoid = DROPS_281 }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: Umaro's cave, the landing (group 166)" }),
  walkInto(15, 51, 282, "the landing -> 282 (22,31)", DROPS_281),
  H.saveState("wor_umaro_hunt_pocket.mss"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: Umaro's cave, the X-Ether's pocket (group 167)" }),
  K.hunt({ what = "Umaro's cave, the X-Ether's pocket (group 167)", lap = { { 21, 31 }, { 20, 31 } }, forms = CAVE167, won = won, castFirst = true, avoid = { { 14, 30 }, { 33, 26 }, { 23, 31 } } }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: Umaro's cave, the X-Ether's pocket (group 167)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_umaro_hunt.mss"),
  H.logStep(function()
    return string.format("wor_umaro_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
