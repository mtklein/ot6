-- gen_wor_passage_hunt.lua -- a branch beside the Falcon arc's side leg (#488, wor-coverage.md section 11): from
-- gen_wor_figaro_sweep's capture in South Figaro (`wor_figaro_sweep_town`: CELES, SABIN and EDGAR after the ruined
-- town's chests), the party goes down Duncan's house into the basement passage (the main line no longer does: the
-- passage and its cellar are the World of Balance's, #350) and walks a lap by the cellar's door until each formation of
-- the passage's pool (field group 65, the World of Balance's: Vector Pup x2 374, Vector Pup x2 with a Commander
-- 373, Commander x3 125 in slots 3 and 4) is won, as a player who pauses there meets them.  No leg boots what it
-- leaves (`wor_passage_hunt`): the hunt's XP stays off the main line (the coordinator's rule for v0.38's sweeps,
-- model gen_wor_thamasa_plain).
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR = 6, 5, 4
local NAMES = { [CELES] = "CELES", [SABIN] = "SABIN", [EDGAR] = "EDGAR" }
local THREE = { CELES, SABIN, EDGAR }
local MAP_PASSAGE = 87
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches = K.map, K.lv, K.say, K.kitLine, K.watches

local PASSAGE65 = { [374] = "Vector Pup x2", [373] = "Vector Pup x2, Commander", [125] = "Commander x3" }
local HUNT87_LAP, PASSAGE_DOORS = { { 36, 49 }, { 37, 49 } }, { { 33, 51 }, { 57, 48 }, { 20, 34 } }

H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/wor_figaro_sweep_town.mss.lua"),
  watches(),
  H.call(function()
    H.assertEq(map(), 74, "booted in South Figaro (map 74), gen_wor_figaro_sweep's capture")
    say("wor", "boot")
    H.log("[kit] " .. kitLine(THREE))
  end),
  H.crossDoor(48, 37, 86, 52, 29, "South Figaro -> Duncan's house 74(48,37)->86(52,29)"),
  H.crossDoor(48, 32, MAP_PASSAGE, 56, 49, "Duncan's stairs 86(48,32)->87(56,49)"),
  H.call(function()
    H.assertEq(map(), MAP_PASSAGE, "down Duncan's stairs into the passage (map 87)")
    say("wor", "in the passage")
  end),
  -- @@setup-end

  -- @@stage hunt
  K.hunt({ what = "the passage (group 65)", lap = HUNT87_LAP, forms = PASSAGE65, avoid = PASSAGE_DOORS }),
  H.fieldCare({ tag = "after the passage's hunt" }),
  H.call(function()
    say("wor", "the hunt done")
    H.log("[kit] " .. kitLine(THREE))
  end),
  H.saveState("wor_passage_hunt.mss"),
  H.logStep(function()
    return string.format("wor_passage_hunt generated: CELES L%d, SABIN L%d and EDGAR L%d in the passage, map %d "
      .. "(%d,%d); its pool won", lv(CELES), lv(SABIN), lv(EDGAR), map(), H.fieldX(), H.fieldY())
  end),
})
