-- gen_wor_zozo_hunt.lua -- a branch beside the Cyan arc's first leg (#488, wor-coverage.md section 11): from
-- gen_wor_cyan's capture by Zozo's merchant after the Rust-Rid (`wor_cyan_rustrid`: TERRA, CELES, SABIN and
-- EDGAR on Zozo's street), the party walks a lap on the street until each formation of its pool (field group
-- 78) is won, then in the Tonic's room (225, door (23,17)) until each of the buildings' pool (group 77) is won,
-- as a player who pauses in Zozo meets them.  No leg boots what it leaves (`wor_zozo_hunt`): the hunts' XP stays
-- off the main line, which goes on from the same capture (the coordinator's rule for v0.38's sweeps: a draw-gap
-- hunt on a branch leg, model gen_wor_thamasa_plain).
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, EDGAR, SABIN, CELES = 0, 4, 5, 6
local NAMES = { [TERRA] = "TERRA", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { TERRA, CELES, SABIN, EDGAR }
local MAP_ZOZO, MAP_ZOZO_IN = 221, 225
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches, walkInto = K.map, K.lv, K.say, K.kitLine, K.watches, K.walkInto

-- gen_wor_cyan's doors and the street's building jumps and crane, kept off every walk
local ZOZO_DOORS = { { 13, 21 }, { 23, 17 }, { 42, 28 }, { 43, 24 }, { 44, 48 }, { 44, 41 }, { 49, 38 }, { 54, 35 },
  { 38, 57 }, { 35, 53 }, { 34, 50 }, { 30, 42 }, { 35, 33 }, { 31, 30 }, { 30, 21 }, { 35, 15 }, { 15, 39 },
  { 12, 36 }, { 49, 31 }, { 33, 9 } }
local ZOZO_IN_DOORS = { { 12, 44 }, { 11, 17 }, { 21, 15 }, { 52, 57 }, { 47, 47 }, { 59, 35 }, { 46, 9 },
  { 118, 27 }, { 104, 27 }, { 83, 62 }, { 124, 56 }, { 98, 62 }, { 110, 55 }, { 66, 57 }, { 11, 62 }, { 30, 62 },
  { 30, 34 }, { 35, 14 }, { 98, 59 }, { 103, 55 }, { 125, 46 } }
local ZOZO_JUMPS = { { 28, 39 }, { 25, 39 }, { 21, 39 }, { 19, 39 }, { 28, 33 }, { 25, 33 }, { 21, 33 }, { 19, 33 },
  { 35, 41 } }
local function exceptOf(list, x, y)
  local out = {}
  for _, d in ipairs(list) do if not (d[1] == x and d[2] == y) then out[#out + 1] = d end end
  return out
end
local function streetAvoid(x, y)
  local out = exceptOf(ZOZO_DOORS, x or -1, y or -1)
  for _, t in ipairs(ZOZO_JUMPS) do out[#out + 1] = t end
  return out
end
-- the two pools (K.hunt: the list asserted to be the map's pool, the hunt bounded by the worst draws the
-- encounter counters can hold)
local ZOZO78 = { [104] = "Gabbldegak x4", [109] = "Harvester, Gabbldegak x2", [102] = "HadesGigas",
  [110] = "HadesGigas, Harvester" }
local ZOZO77 = { [105] = "SlamDancer", [107] = "Harvester", [108] = "SlamDancer, Harvester x2",
  [106] = "SlamDancer, Gabbldegak x3" }
local HUNT221_LAP, HUNT225_LAP = { { 42, 30 }, { 43, 30 } }, { { 83, 61 }, { 83, 60 } }
local won = {}

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/wor_cyan_rustrid.mss.lua"),
  watches(),
  H.call(function()
    H.assertEq(map(), MAP_ZOZO, "booted on Zozo's street (map 221), gen_wor_cyan's capture after the Rust-Rid")
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  -- @@setup-end

  -- @@stage street
  K.hunt({ what = "Zozo's street (group 78)", lap = HUNT221_LAP, forms = ZOZO78, won = won, avoid = streetAvoid() }),
  H.fieldCare({ tag = "after the street's hunt" }),
  -- @@stage buildings
  walkInto(23, 17, MAP_ZOZO_IN, "Zozo -> the Tonic's room (225 (83,61))", streetAvoid(23, 17)),
  H.saveState("wor_zozo_hunt_225.mss"),
  K.hunt({ what = "Zozo's buildings (group 77)", lap = HUNT225_LAP, forms = ZOZO77, won = won,
    avoid = ZOZO_IN_DOORS }),
  H.fieldCare({ tag = "after the buildings' hunt" }),
  H.call(function()
    say("wor", "both hunts done")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wor_zozo_hunt.mss"),
  H.logStep(function()
    return string.format("wor_zozo_hunt generated: TERRA L%d, CELES L%d, SABIN L%d and EDGAR L%d in Zozo's Tonic room, "
      .. "map %d (%d,%d); both of Zozo's pools won", lv(TERRA), lv(CELES), lv(SABIN), lv(EDGAR), map(), H.fieldX(),
      H.fieldY())
  end),
})
