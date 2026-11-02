-- gen_wor_ancient_boxes.lua -- a branch beside gen_wor_ancient (#487, the monster boxes; wor-coverage.md section 12):
-- boot the graph's capture `wor_ancient_yard` (CELES, RELM, CYAN and TERRA in the Ancient Castle's courtyard, 407,
-- after the flashback) and open the castle's two monster boxes: the castle's (406 (10,17), event group 95: a
-- KatanaSoul, L61, 37,620 HP, which drops an Offering), by the courtyard's door (11,10); then back through the
-- courtyard and the save point's room (402) into the cave (401) and its box (58,43) (event group 113: a Master Pug,
-- L73, 22,000 HP, which drops a Graedus).  Each is an event battle and a game over when lost (TreasureMonster:
-- _ca5ea9); the runner retries from the boot.  Before each the party is cared for to full, and armed against the
-- body's absorbs (H.absorbSafeArms).  No leg boots what it leaves (the state `wor_ancient_boxes`): the boxes pay
-- no XP, and the main line, the middle path, walks by them.
-- Every battle's [outcome] is asserted said, judged on its own end reading, and paid as due.
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local POTION, XPOTION, FENIX, REMEDY, TINCTURE, ETHER, ELIXIR = 0xE9, 0xEA, 0xF0, 0xF5, 0xEB, 0xEC, 0xEE
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
-- the boxes (TreasureProp 406 and 401; wor-coverage.md 5.1): the bit, the event group's formation, its species
local KATANASOUL, MASTER_PUG = 0x124, 0x138
local BOX_HALL = { x = 10, y = 17, bit = 205, form = 465, species = KATANASOUL, what = "the castle's box (406 (10,17))" }
local BOX_CAVE = { x = 58, y = 43, bit = 198, form = 483, species = MASTER_PUG, what = "the cave's box (401 (58,43))" }

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
local opened = {}
-- a box from whichever side of it the party can reach: care to full, the arms against its body's absorbs, the
-- battle heals on top of the bag, then A on it and its battle played out by the tactical driver; its bit and the
-- win asserted
local function box(o)
  local n0
  return H.lazy(function()
    for _, s in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      if H.bfsReach(nil, nil, nil, LINKS[map()] or {}, o.x + s[1], o.y + s[2]) then
        return H.seqStep({
          walk(o.x + s[1], o.y + s[2], o.what .. ": beside it"),
          checkOutcomes(o.what .. ": the walk"),
          H.absorbSafeArms(nil, { o.species }, { tag = "arms for " .. o.what }),
          H.bagArrange({ POTION, FENIX, XPOTION, ELIXIR, ETHER, REMEDY, TINCTURE }, { tag = "bag: the battle heals on top" }),
          H.fieldCare({ threshold = 1.0, tag = "before " .. o.what }),
          H.call(function()
            H.assertEq(H.chestOpen(o.bit), false, o.what .. ": its bit " .. o.bit .. " is clear")
            n0 = #H.outcomes
            H.log("[kit] " .. kitLine(FOUR))
            say("box", o.what .. ": opening")
          end),
          H.faceAndHoldA(s[3], function() return H.battleLoadStarted() end, 3000,
            o.what .. ": face " .. s[3] .. ", A (Monster-in-a-box!, EventCmd_8e)"),
          H.release(),
          H.advanceStory(function()
            return H.chestOpen(o.bit) and not H.battleLoadStarted() and settled()
          end, 600000, { playBattles = "tactical", fight = FIGHT }),
          checkOutcomes(o.what),
          H.call(function()
            H.assertEq(H.chestOpen(o.bit), true, string.format("%d: %s (bit %d) is open", map(), o.what, o.bit))
            local last = H.outcomes[#H.outcomes]
            H.assertEq(#H.outcomes > n0 and (last.form & 0x3FF) == o.form and last.kind == "won", true,
              string.format("%s: its battle (formation %d) was won", o.what, o.form))
            opened[#opened + 1] = string.format("%d won", o.form)
            H.log(string.format("[chest] chest bit %d (%s): OPENED, formation %d won", o.bit, o.what, o.form))
            say("box", o.what .. ": won")
          end),
          H.fieldCare({ threshold = 1.0, tag = "after " .. o.what }),
        })
      end
    end
    error(string.format("[box] %s (%d,%d): no side of it is reachable from (%d,%d)", o.what, o.x, o.y,
      H.fieldX(), H.fieldY()))
  end)
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
      H.assertEq(H.readByte(0x1850 + ch) & 7, 1, NAMES[ch] .. " is seated (gen_wor_ancient's four)")
    end
    for _, o in ipairs({ BOX_HALL, BOX_CAVE }) do
      H.assertEq(H.chestOpen(o.bit), false, o.what .. " is shut (bit " .. o.bit .. ")")
    end
  end),
  -- @@setup-end
  -- the castle's box, by the courtyard's door (11,10) -> 406 (10,21), and back by (10,22)
  door(11, 10, MAP_AHALL, "407 (11,10) -> the castle's west corner (406)"),
  box(BOX_HALL),
  door(10, 22, MAP_AYARD, "406 (10,22) -> the courtyard (407)"),
  -- the cave's box: the courtyard's south edge -> 402, 402 (22,42) -> the cave (401)
  walk(15, 47, "407's south edge -> 402", nil, function() return map() == MAP_ASAVE end),
  H.waitUntil(function() return map() == MAP_ASAVE and settled() end, 3000, "402", 1),
  door(22, 42, MAP_ACAVE, "402 (22,42) -> the cave (401)"),
  box(BOX_CAVE),
  door(19, 16, MAP_ASAVE, "the cave (19,16) -> 402"),
  H.fieldCare({ threshold = 1.0, tag = "at the save point after the boxes" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_ancient_boxes.mss"),
  H.logStep(function()
    return string.format("wor_ancient_boxes generated: map %d (%d,%d); CELES L%d, RELM L%d, CYAN L%d, TERRA L%d; boxes: %s",
      map(), H.fieldX(), H.fieldY(), lv(CELES), lv(RELM), lv(CYAN), lv(TERRA), table.concat(opened, ", "))
  end),
})
