-- gen_wor_zozo_north.lua -- a branch beside the Cyan arc's first leg (#502, wor-coverage.md section 11.9): from
-- gen_wor_cyan's capture by Zozo's merchant after the Rust-Rid (`wor_cyan_rustrid`: TERRA, CELES, SABIN and
-- EDGAR on Zozo's street), the World of Balance's climb to Dadaluma (gen_zozo4_dadaluma) walked again for the four
-- chests past the stair room: the Thief Glove (225 (11,59)), the Fire Knuckle (225 (35,11)), and the rooftop's
-- RunningShoes and X-Potion (226 (72,26), (92,27)).  No leg boots what it leaves (`wor_zozo_north`): the chests and
-- the climb's XP stay off the main line, which goes on from the same capture.
--
-- The stair room's seven walkers (225 NPCs 2-8) climb its one-wide stair in the World of Ruin as in the World of
-- Balance (build/attempts/wt/v038-zozo-tomb/stair/: from this boot and from zozo-outside-v1, each of objects
-- $11-$17 moved 55-57 times in 60 samples 30 frames apart, the same tiles in both worlds), so the stair is the
-- World of Balance's conveyor, walked as a queue (H.tableWalk with the stair's route as a function of the tile).
-- The roofs' z-loop beams are walked from tables: route_data.py field-path's BFS (which carries the z along the
-- path and gives gen_zozo4_dadaluma's measured tables on the same roofs) where the library's planner misreads
-- them, and gen_zozo4_dadaluma's own tables for the west room and the bridge room's shaft.  The crane (221
-- (35,41), _ca963d) asks only when the party stands on it facing down ($01B2); the walks cross it facing right
-- and up, and a field dialog on them fails the walk (noDialog).
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, EDGAR, SABIN, CELES = 0, 4, 5, 6
local NAMES = { [TERRA] = "TERRA", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { TERRA, CELES, SABIN, EDGAR }
local MAP_ZOZO, MAP_ZOZO_IN, MAP_RAMUH = 221, 225, 226
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches, walkInto = K.map, K.lv, K.say, K.kitLine, K.watches, K.walkInto

-- the two maps' doors (short_entrance.dat _221/_225), with 221's building jumps and crane and 225's clock and
-- stair triggers (gen_wor_zozo_hunt's lists)
local ZOZO_DOORS = { { 13, 21 }, { 23, 17 }, { 42, 28 }, { 43, 24 }, { 44, 48 }, { 44, 41 }, { 49, 38 }, { 54, 35 },
  { 38, 57 }, { 35, 53 }, { 34, 50 }, { 30, 42 }, { 35, 33 }, { 31, 30 }, { 30, 21 }, { 35, 15 }, { 15, 39 },
  { 12, 36 }, { 49, 31 }, { 33, 9 }, { 28, 39 }, { 25, 39 }, { 21, 39 }, { 19, 39 }, { 28, 33 }, { 25, 33 },
  { 21, 33 }, { 19, 33 }, { 35, 41 } }
local ZOZO_IN_DOORS = { { 12, 44 }, { 11, 17 }, { 21, 15 }, { 52, 57 }, { 47, 47 }, { 59, 35 }, { 46, 9 },
  { 118, 27 }, { 104, 27 }, { 83, 62 }, { 124, 56 }, { 98, 62 }, { 110, 55 }, { 66, 57 }, { 11, 62 }, { 30, 62 },
  { 30, 34 }, { 35, 14 }, { 98, 59 }, { 103, 55 }, { 125, 46 } }
local function exceptOf(list, x, y)
  local out = {}
  for _, d in ipairs(list) do if not (d[1] == x and d[2] == y) then out[#out + 1] = d end end
  return out
end
local function at(x, y) return H.fieldX() == x and H.fieldY() == y and H.tileAligned() end
local function onMap(m) return function() return map() == m end end

-- the chests (TreasureProp 225/226; item ids const.inc)
local CHESTS = {
  { bit = 0x04B, what = "Thief Glove (225 (11,59))", item = 0xCF },
  { bit = 0x04C, what = "Fire Knuckle (225 (35,11))", item = 0x57 },
  { bit = 0x046, what = "RunningShoes (226 (72,26))", item = 0xBA },
  { bit = 0x047, what = "X-Potion (226 (92,27))", item = 0xEA },
}

-- ---- the walks ----
-- the stair room's conveyor (gen_zozo4_dadaluma's stairDir): the route's move as a function of the tile, from the
-- stair's foot (52,30) up the one-wide column x=53 to the door (46,9)
local function stairDir(x, y)
  if x == 54 and y >= 12 and y <= 14 then return y == 12 and { "left" } or { "up" } end
  if y <= 12 and x >= 46 and x <= 53 then return { "left", "upleft" } end
  if x == 53 then
    if y == 14 then return { "right" } end
    return { "up" }
  end
  if y >= 30 then
    if x < 53 then return { "right" } end
    if x > 53 then return { "left" } end
    return { "up" }
  end
  if x < 53 and y >= 13 and y <= 17 then return { "right" } end
  if x > 54 then return { "left" } end
  return { "up" }
end
-- 221, from route_data.py field-path (build/attempts/wt/v038-zozo-tomb/scripts/paths.sh): the U1 roof (30,43) by
-- the crane's beam and the beam above it to the Thief Glove's door (35,33); back from its landing (35,34) to the
-- J39 row (29,39); the J33 row's landing (28,33) to the bridge room's door (31,30); the top roof (30,22) up its
-- switchback to the Fire Knuckle's door (35,15); its landing (35,16) on to the porch and the rooftop's door (33,9)
local U1_TO_GLOVE = H.movesAlong("30,43 31,43 31,44 32,44 33,43 34,42 35,41 35,40 34,40 33,40 32,40 31,40 31,41 "
  .. "32,41 33,40 34,39 35,38 35,37 34,37 33,37 32,37 31,37 31,38 32,38 33,37 34,36 35,35 35,34 35,33")
local GLOVE_TO_J39 = H.movesAlong("35,34 35,35 34,36 33,37 32,38 31,38 31,37 32,37 33,37 34,37 35,37 35,38 34,39 "
  .. "33,40 32,41 31,41 31,40 30,40 30,39 29,39")
local J33_TO_BRIDGE = H.movesAlong("28,33 29,33 30,33 30,34 30,35 31,35 32,34 33,33 34,32 34,31 33,31 32,31 31,31 "
  .. "31,30")
local TOP_TO_KNUCKLE = H.movesAlong("30,22 31,22 31,23 32,23 33,22 34,21 35,20 35,19 34,19 33,19 32,19 31,19 31,20 "
  .. "32,20 33,19 34,18 35,17 35,16 35,15")
local KNUCKLE_TO_ROOF = H.movesAlong("35,16 34,16 33,16 32,16 31,16 30,16 30,17 31,17 32,16 33,15 34,14 34,13 33,13 "
  .. "32,13 31,13 30,13 30,14 31,14 32,13 33,12 34,11 34,10 33,10 33,9")
-- 225's west room, (118,26) -> (104,27) (gen_zozo4_dadaluma's WESTROOM; the beam's scene at (111,15) is ridden
-- with A)
local WESTROOM = {}
do
  local function wr(x, y, dir) WESTROOM[H.tileKey(x, y)] = dir end
  for yy = 16, 26 do wr(118, yy, "up") end
  for xx = 113, 117 do wr(xx, 15, "left") end
  wr(118, 15, "left"); wr(112, 15, "left")
  wr(111, 15, "upleft"); wr(110, 14, "upleft")
  wr(109, 13, "upleft"); wr(108, 12, "left")
  wr(107, 12, "down"); wr(107, 13, "down"); wr(107, 14, "down"); wr(107, 15, "left")
  wr(106, 15, "down"); wr(106, 16, "left"); wr(105, 16, "left"); wr(104, 16, "down")
  for yy = 17, 26 do wr(104, yy, "down") end
end
-- 225's bridge room shaft, (30,61) -> (30,34) (gen_zozo4_dadaluma's BRIDGE2)
local SHAFT = H.movesAlong("30,61 30,60 30,59 29,59 29,58 29,57 30,57 31,56 32,55 33,54 34,53 35,52 36,51 37,51 "
  .. "37,50 37,49 36,49 35,48 34,47 33,46 32,45 31,44 30,43 29,43 29,42 29,41 30,41 31,40 32,39 33,38 34,37 35,36 "
  .. "36,35 37,34 38,33 39,32 40,32 40,31 39,31 38,31 37,31 36,31 35,31 34,31 33,31 33,32 33,33 32,33 31,33 30,33 "
  .. "30,34")

local function walk(what, moves, done, opts)
  local spec = { what = what, moves = moves, done = done, fight = FIGHT, noDialog = true, hang = 900 }
  for k, v in pairs(opts or {}) do spec[k] = v end
  return H.walkWithCare(spec)
end
local function landed(what) return H.waitUntil(function()
  return H.hasControl() and H.tileAligned() and not H.dialogWaiting() and not H.battleLoadStarted()
end, 2400, what, 5) end

H.run({ maxFrames = 600000 }, {
  H.loadState("build/states/wor_cyan_rustrid.mss.lua"),
  watches(),
  H.call(function()
    H.assertEq(map(), MAP_ZOZO, "booted on Zozo's street (map 221), gen_wor_cyan's capture after the Rust-Rid")
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    for _, c in ipairs(CHESTS) do
      H.assertEq(H.chestOpen(c.bit), false, string.format("the %s's chest (bit %d) is still closed at the boot",
        c.what, c.bit))
    end
  end),
  -- @@setup-end
  H.fieldCare({ tag = "before the climb" }),

  -- @@stage stair
  -- the street (38,57) -> 225, its door (47,47) -> the roof (35,54), (34,50) -> the stair room (59,34)
  walkInto(38, 57, MAP_ZOZO_IN, "Zozo -> 225 (52,56)", exceptOf(ZOZO_DOORS, 38, 57)),
  walkInto(47, 47, MAP_ZOZO, "225 -> the roof (221 (35,54))", exceptOf(ZOZO_IN_DOORS, 47, 47)),
  walkInto(34, 50, MAP_ZOZO_IN, "the roof -> the stair room (225 (59,34))", exceptOf(ZOZO_DOORS, 34, 50)),
  H.walkWithCare({ what = "the stair room: to the stair's foot (52,30)", target = { 52, 30 }, walls = ZOZO_IN_DOORS,
    done = function() return at(52, 30) end, fight = FIGHT, noDialog = true }),
  H.settledCare("before the stair"),
  H.walkWithCare({ what = "the stair's conveyor -> the U1 roof (221 (30,43))", dir = stairDir, done = onMap(MAP_ZOZO),
    fight = FIGHT, noDialog = true, maxFrames = 12000 }),
  landed("the U1 roof settled"),
  H.call(function()
    H.assertEq(at(30, 43), true, "up the stair room's stair onto the U1 roof (221 (30,43))")
    say("route", "up the stair")
  end),
  H.saveState("wor_zozo_north_u1.mss"),

  -- @@stage glove
  walk("the U1 roof -> the Thief Glove's door (221 (35,33))", U1_TO_GLOVE, onMap(MAP_ZOZO_IN)),
  landed("the Thief Glove's room settled"),
  H.openChest({ stand = { 11, 60 }, face = "up", bit = CHESTS[1].bit, what = CHESTS[1].what, item = CHESTS[1].item,
    nav = { fight = FIGHT, avoid = ZOZO_IN_DOORS } }),
  walkInto(11, 62, MAP_ZOZO, "the Thief Glove's room -> 221 (35,34)", exceptOf(ZOZO_IN_DOORS, 11, 62)),
  walk("the Thief Glove's landing -> the J39 row (29,39)", GLOVE_TO_J39, function() return at(29, 39) end),

  -- @@stage west
  H.jumpRow({ what = "the J39 row westbound", dir = "left", fight = FIGHT,
    there = function() return H.fieldX() <= 18 and H.fieldY() == 39 end }),
  walkInto(15, 39, MAP_ZOZO_IN, "the J39 strip -> the west room (225 (118,26))", exceptOf(ZOZO_DOORS, 15, 39)),
  walk("the west room -> (104,27)", WESTROOM, onMap(MAP_ZOZO), { ride = true, noDialog = false }),
  landed("the W33 strip settled"),
  H.walkWithCare({ what = "the W33 strip -> the J33 row (18,33)", target = { 18, 33 }, walls = ZOZO_DOORS,
    done = function() return at(18, 33) end, fight = FIGHT, noDialog = true }),
  H.jumpRow({ what = "the J33 row eastbound", dir = "right", fight = FIGHT,
    there = function() return H.fieldX() >= 28 and H.fieldY() == 33 end }),
  walk("the J33 landing -> the bridge room's door (221 (31,30))", J33_TO_BRIDGE, onMap(MAP_ZOZO_IN)),
  landed("the bridge room settled"),
  walk("the bridge room's shaft -> the top roof (221 (30,22))", SHAFT, onMap(MAP_ZOZO)),
  landed("the top roof settled"),

  -- @@stage knuckle
  walk("the top roof -> the Fire Knuckle's door (221 (35,15))", TOP_TO_KNUCKLE, onMap(MAP_ZOZO_IN)),
  landed("the Fire Knuckle's room settled"),
  H.openChest({ stand = { 35, 12 }, face = "up", bit = CHESTS[2].bit, what = CHESTS[2].what, item = CHESTS[2].item,
    nav = { fight = FIGHT, avoid = ZOZO_IN_DOORS } }),
  walkInto(35, 14, MAP_ZOZO, "the Fire Knuckle's room -> 221 (35,16)", exceptOf(ZOZO_IN_DOORS, 35, 14)),
  walk("the Fire Knuckle's landing -> the rooftop's door (221 (33,9))", KNUCKLE_TO_ROOF, onMap(MAP_RAMUH)),
  landed("the rooftop room settled"),

  -- @@stage rooftop
  H.openChest({ stand = { 72, 27 }, face = "up", bit = CHESTS[3].bit, what = CHESTS[3].what, item = CHESTS[3].item,
    nav = { fight = FIGHT } }),
  H.openChest({ stand = { 91, 27 }, face = "right", bit = CHESTS[4].bit, what = CHESTS[4].what, item = CHESTS[4].item,
    nav = { fight = FIGHT } }),
  H.call(function()
    for _, c in ipairs(CHESTS) do
      H.assertEq(H.chestOpen(c.bit), true, string.format("Zozo: the %s's chest (bit %d) is open", c.what, c.bit))
    end
    say("wor", "the four north chests open")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wor_zozo_north.mss"),
  H.logStep(function()
    return string.format("wor_zozo_north generated: TERRA L%d, CELES L%d, SABIN L%d and EDGAR L%d in Zozo's rooftop "
      .. "room, map %d (%d,%d); the Thief Glove, the Fire Knuckle, the RunningShoes and the X-Potion opened", lv(TERRA),
      lv(CELES), lv(SABIN), lv(EDGAR), map(), H.fieldX(), H.fieldY())
  end),
})
