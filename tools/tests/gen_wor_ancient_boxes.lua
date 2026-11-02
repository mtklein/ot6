-- gen_wor_ancient_boxes.lua -- a branch beside gen_wor_ancient (#487, the monster boxes; wor-coverage.md section 12):
-- boot the graph's capture `wor_ancient_yard` (CELES, RELM, CYAN and TERRA in the Ancient Castle's courtyard, 407,
-- after the flashback) and open the castle's two monster boxes: the castle's (406 (10,17), event group 95: a
-- KatanaSoul, L61, 37,620 HP, which drops an Offering), by the courtyard's door (11,10); then back through the
-- courtyard and the save point's room (402) into the cave (401) and its box (58,43) (event group 113: a Master Pug,
-- L73, 22,000 HP, which drops a Graedus).  Each is an event battle and a game over when lost (TreasureMonster:
-- _ca5ea9); the runner retries from the boot.  Each box is K.monsterBox (lib/ot6_field.lua): care to full and the
-- arms against the body's absorbs before it, then its bit, its win and its sure drop asserted.  No leg boots what
-- it leaves (the state `wor_ancient_boxes`): the boxes pay no XP, and the main line, the middle path, walks by them.
-- Every battle's [outcome] is asserted said, judged on its own end reading, and paid as due.
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
local links = H.doorLinks
local LINKS = {}
local MAP_ACAVE, MAP_ASAVE, MAP_AYARD, MAP_AHALL = 401, 402, 407, 406
-- 401's same-map doors and 406's (gen_wor_ancient's)
LINKS[MAP_ACAVE] = links({ { 43, 26, 43, 41 }, { 43, 39, 43, 25 }, { 50, 26, 50, 38 }, { 50, 36, 50, 25 },
  { 58, 26, 58, 38 }, { 58, 36, 58, 25 }, { 33, 41, 27, 6 }, { 33, 42, 27, 6 }, { 28, 6, 34, 41 }, { 28, 7, 34, 41 } })
LINKS[MAP_AHALL] = links({ { 15, 14, 24, 13 }, { 54, 28, 38, 9 }, { 45, 56, 35, 51 }, { 38, 7, 54, 27 },
  { 24, 12, 15, 13 }, { 9, 31, 33, 30 }, { 10, 31, 33, 30 }, { 11, 31, 33, 30 }, { 33, 31, 10, 32 },
  { 34, 31, 10, 32 } })
-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, lv, say, kitLine, watches, walk, settled = K.map, K.lv, K.say, K.kitLine, K.watches, K.walk, K.settled
local FOUR = { CELES, RELM, CYAN, TERRA }
local opened = {}
local function done(line) opened[#opened + 1] = line end
-- the boxes (TreasureProp 406 and 401; wor-coverage.md 5.1): the bit, the event group's formation, its species
local BOX_HALL = { x = 10, y = 17, bit = 205, form = 465, species = 0x124, what = "the castle's box (406 (10,17))",
  done = done }
local BOX_CAVE = { x = 58, y = 43, bit = 198, form = 483, species = 0x138, what = "the cave's box (401 (58,43))",
  done = done }

-- every battle's [outcome] said, on its own end reading, paid as due (gen_wor_sabin's checkOutcomes)
local seen, outcome0, battles0 = 0, 0, 0
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own end reading",
        what, i - outcome0, o.form & 0x3FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x3FF, o.kind))
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    seen = #H.outcomes
  end)
end
-- a door onto another map, the walk playing its battles; arrives when the map reads dst
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, nil, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 3000, what .. ": control on map " .. dst, 1),
    checkOutcomes(what),
    H.call(function() say("route", what) end),
  })
end

H.run({ maxFrames = 2000000 }, {
  H.loadState("build/states/wor_ancient_yard.mss.lua"),
  watches(),
  H.call(function()
    outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
    seen = outcome0
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), MAP_AYARD, "the boot stands in the Ancient Castle's courtyard (407): gen_wor_ancient's capture wor_ancient_yard")
    for _, ch in ipairs(FOUR) do
      H.assertEq(K.partyOf(ch), 1, NAMES[ch] .. " is seated (gen_wor_ancient's four)")
    end
    for _, o in ipairs({ BOX_HALL, BOX_CAVE }) do
      H.assertEq(H.chestOpen(o.bit), false, o.what .. " is shut (bit " .. o.bit .. ")")
    end
  end),
  -- @@setup-end
  -- the castle's box, by the courtyard's door (11,10) -> 406 (10,21), and back by (10,22)
  door(11, 10, MAP_AHALL, "407 (11,10) -> the castle's west corner (406)"),
  K.monsterBox(BOX_HALL),
  checkOutcomes(BOX_HALL.what),
  door(10, 22, MAP_AYARD, "406 (10,22) -> the courtyard (407)"),
  -- the cave's box: the courtyard's south edge -> 402, 402 (22,42) -> the cave (401)
  walk(15, 47, "407's south edge -> 402", nil, function() return map() == MAP_ASAVE end),
  H.waitUntil(function() return map() == MAP_ASAVE and settled() end, 3000, "402", 1),
  door(22, 42, MAP_ACAVE, "402 (22,42) -> the cave (401)"),
  K.monsterBox(BOX_CAVE),
  checkOutcomes(BOX_CAVE.what),
  door(19, 16, MAP_ASAVE, "the cave (19,16) -> 402"),
  H.fieldCare({ threshold = 1.0, tag = "at the save point after the boxes" }),
  H.call(function()
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(#opened, 2, "both boxes opened and won")
  end),
  H.saveState("wor_ancient_boxes.mss"),
  H.logStep(function()
    return string.format("wor_ancient_boxes generated: map %d (%d,%d); CELES L%d, RELM L%d, CYAN L%d, TERRA L%d; boxes: %s",
      map(), H.fieldX(), H.fieldY(), lv(CELES), lv(RELM), lv(CYAN), lv(TERRA), table.concat(opened, "; "))
  end),
})
