-- gen_wor_dino.lua -- the dinosaur forest, the grind before Kefka's Tower (docs/design/route-wor-side-trips.md):
-- Continue the `wor-colosseum-v1` battery (SHADOW, CELES, CYAN and TERRA beside the Falcon by Maranda), check what
-- the plan depends on, Kohlingen's counter for the grind's supplies, the Falcon down beside the forest north of
-- Gau's father's house (world group 54: Tyranosaur, two Tyranosaurs, Brachosaur), the forest fought until every
-- seated member stands at GOAL_LEVEL (Kefka's Tower's target, level-curve.md), with a trip back to Kohlingen
-- when the bag runs short, and the save on the Falcon's tile: the `wor-dino-v1` battery, the desert's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR",
  [SABIN] = "SABIN", [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG",
  [GAU] = "GAU", [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
-- between the forest's battles the care tops everyone up to full, not to 65%: the two Tyranosaurs open with a
-- Meteor each, and a party that walks in at two thirds does not see its second turn (route-wor-side-trips.md
-- section 4; TERRA's Cure costs her 1 MP under the Economizer)
H.careThreshold = 1.0
-- and it casts before it reaches for the bag (gen_wor_tower's precedent): TERRA's Cure at 1 MP is the cheaper
-- heal, where Potions to full after every battle sent the party back to Kohlingen every four battles
H.careMagic, H.careCastFirst = true, true
-- the dinosaurs are weak to ice (vanilla) and Ice keys their hide: whoever holds Ice casts it while one stands
-- (TERRA's Economizer makes hers 1 MP at any boost), where the driver alone Fights (route-wor-side-trips.md
-- section 4: six forest battles at the boot's levels, Fight 0 of 1 before a wipe, Ice 6 of 6)
-- (the Crawler of the plain by Maranda, where the four ready themselves, is weak to ice too)
FIGHT.nuke = function()
  if H.formationHas({ [0x027] = true, [0x026] = true, [0x05B] = true }) then return { 0x01 } end
  return nil
end

local LINKS = {}
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, board, watches = K.say, K.kitLine, K.board, K.watches
local regroup, liftOff, landNear, partyOf = K.regroup, K.liftOff, K.landNear, K.partyOf
local kohlingenStop = K.kohlingenStop

local FOUR = { SHADOW, CELES, CYAN, TERRA }
local FOREST = 54                                    -- WorldBattleGroup: Tyranosaur (321), x2 (320), Brachosaur (322)
local FOREST_NEAR = { 195, 47 }                      -- one step south of the landing tile (195,46)
local TYRANOSAUR, BRACHOSAUR = 0x027, 0x026
-- Kefka's Tower's target, each of three parties (level-curve.md "The plan by milestone"): the forest is fought
-- until the lowest seated member stands at it
local GOAL_LEVEL = 52
-- the bag the grind leaves the forest for Kohlingen under: half the supply band (guidelines "Supply band")
local bandAt, band = nil, nil
local function bagShort()
  local top = H.activeTopLevel()
  if bandAt ~= top then bandAt, band = top, math.min(99, H.careStockPotions(top, { spend = 30 })) end
  return H.invCountOf(POTION) < band // 2 or H.invCountOf(FENIX) < math.min(20, top) // 2
end
-- the Brachosaur (L77, 46,050 HP, Ultima): route-wor-side-trips.md section 4 is the lab that sets this
local FLEE = { BRACHOSAUR }
local GRIND_BUDGET, TRIPS = 80, 6
-- the forest's two Tyranosaurs cast Meteor twice a round: at the boot's levels (SHADOW and CYAN L41, 2,656 HP)
-- the pair wiped the party in the first battles (route-wor-side-trips.md section 4), so the four ready themselves
-- first on the plain by the Falcon (world group 49, the World of Ruin's grind, level-curve.md) until the lowest
-- stands at READY_LEVEL
local PLAIN, READY_LEVEL, PLAIN_BUDGET = 49, 45, 60
local MARANDA_WORLD = { { 69, 184 }, { 70, 184 } }   -- Maranda's door: the walks step round it
local n0 = 0
-- the most a top-up at Kohlingen's counter spends: 99 Potions, 20 Remedies, 20 Fenix Downs at the World of Ruin's
-- prices (shop 67), rounded up
local GIL_FLOOR = 60000

local function inGroup(group)
  return function(x, y) return H.worldPassable(x, y) and H.worldEncounterGroup(x, y, x, y) == group end
end
local function groupTile(group, nx, ny, what)
  local ok, best, bd = inGroup(group), nil, 1e9
  for dy = -8, 8 do
    for dx = -8, 8 do
      local x, y = nx + dx, ny + dy
      if ok(x, y) and (ok(x + 1, y) or ok(x - 1, y) or ok(x, y + 1) or ok(x, y - 1)) then
        local d = dx * dx + dy * dy
        if d < bd and H.worldBfs(H.worldX(), H.worldY(), nil, x, y) then best, bd = { x, y }, d end
      end
    end
  end
  H.assertEq(best ~= nil, true, string.format("%s: a tile of world group %d near (%d,%d) with a walk to it", what,
    group, nx, ny))
  H.log(string.format("[zone] %s: world group %d at (%d,%d)", what, group, best[1], best[2]))
  return best
end
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, lv(ch)) end
  return m
end
local function seated()
  for _, ch in ipairs(FOUR) do if partyOf(ch) ~= 1 then return false end end
  return true
end
local function tally(from, what)
  local t, keys = {}, {}
  for i = from + 1, #H.outcomes do
    local o = H.outcomes[i]
    local k = string.format("%s %03X", o.kind, o.form & 0x3FF)
    t[k] = (t[k] or 0) + 1
  end
  for k, v in pairs(t) do keys[#keys + 1] = string.format("%s x%d", k, v) end
  table.sort(keys)
  say("wor", string.format("%s: %d battles (%s)", what, #H.outcomes - from, table.concat(keys, ", ")))
end
local function done() return lowest() >= GOAL_LEVEL end
-- on foot on the world, settled between battles: a grind's stop is read only here, never inside a battle or its
-- hand-back (a level or a Potion counted mid-battle ended a pace there, and the walk after it stalled)
local function onWorld()
  return H.worldMode() and H.worldSettled() and H.worldAligned() and not H.battleLoadStarted()
end
-- into the forest from wherever the Falcon put the party down
local function intoForest()
  return H.lazy(function()
    local t = groupTile(FOREST, FOREST_NEAR[1], FOREST_NEAR[2], "the dinosaur forest")
    return H.worldNavTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      fleeSpecies = FLEE })
  end)
end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("wor-colosseum-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract (lib/ot6_contract.lua) already holds the story: SHADOW recruited ($02F3, gen_wor_colosseum)
  -- and the Falcon parked beside the party.  Hard, and asserted here: Ice in the seated four's hands (TERRA's
  -- natural magic or a stone; the forest's dinosaurs and the plain's Crawler are fought with it, section 4), and
  -- gil for Kohlingen's counter on every trip (the line's purse; the wagers and the shops upstream spend it).
  -- Soft, fixed in the leg as a player would: who is seated (the cabin), the bag (Kohlingen's counter) and HP
  -- (the field care).
  H.call(function()
    say("wor", "boot")
    local ice = {}
    for _, ch in ipairs(FOUR) do if H.knowsSpell(ch, 0x01) then ice[#ice + 1] = NAMES[ch] end end
    H.log("[kit] " .. kitLine(FOUR))
    H.log("[deps] Ice: " .. (#ice > 0 and table.concat(ice, ", ") or "nobody"))
    H.assertEq(#ice > 0, true, "one of the four knows Ice (TERRA's natural magic, or a stone the line gave)")
    H.assertEq(H.gil() >= GIL_FLOOR, true, string.format("gil for Kohlingen's top-ups: %d GP, the floor %d (the "
      .. "line's purse, gen_wor_colosseum's boot holds the arcs' gil)", H.gil(), GIL_FLOOR))
    H.log(string.format("[grind] the forest until the lowest of the four stands at L%d (now L%d)", GOAL_LEVEL,
      lowest()))
  end),
  -- @@setup-end

  -- ---- 1. the plain by Maranda, until the four are ready for the forest ------------------------------------
  -- @@stage plain
  H.cond(function() return lowest() < READY_LEVEL end, {
    H.lazy(function()
      local t = groupTile(PLAIN, H.worldX(), H.worldY(), "the plain by Maranda")
      return H.worldNavTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
        avoid = MARANDA_WORLD })
    end),
    H.call(function() n0 = #H.outcomes end),
    K.pace(function() return onWorld() and lowest() >= READY_LEVEL end, PLAIN_BUDGET, "the plain by Maranda", nil,
      { pick = inGroup(PLAIN) }),
    H.call(function() tally(n0, "the plain by Maranda") end),
    H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
      { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = MARANDA_WORLD }),
  }, {}),

  -- ---- 2. the cabin and Kohlingen ------------------------------------------------------------------------
  -- @@stage ready
  -- on foot onto the Falcon's tile, A: the pilot's controls; the cabin only when the four are not seated
  H.cond(function() return not seated() end, { regroup(FOUR), liftOff() }, { board() }),
  kohlingenStop("the top-up before the forest"),
  landNear(FOREST_NEAR[1], FOREST_NEAR[2], "the Falcon down by the dinosaur forest"),
  H.call(function()
    for _, ch in ipairs(FOUR) do H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated") end
  end),
  H.fieldCare({ threshold = 1.0, tag = "before the forest" }),

  -- ---- 3. the forest, and Kohlingen when the bag runs short -------------------------------------------------
  -- @@stage forest
  H.call(function() n0 = #H.outcomes end),
  H.repeatN(TRIPS, {
    H.cond(function() return not done() end, {
      intoForest(),
      K.pace(function() return onWorld() and (done() or bagShort()) end, GRIND_BUDGET, "the dinosaur forest", nil,
        { pick = inGroup(FOREST), flee = FLEE }),
      H.call(function() tally(n0, "the forest so far") end),
      H.cond(function() return not done() end, {
        H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
          { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, fleeSpecies = FLEE }),
        board(),
        kohlingenStop("the bag short in the forest"),
        landNear(FOREST_NEAR[1], FOREST_NEAR[2], "the Falcon back to the dinosaur forest"),
      }, {}),
    }, {}),
  }),
  H.call(function()
    H.assertEq(done(), true, string.format("the four at L%d within %d trips", GOAL_LEVEL, TRIPS))
    tally(n0, "the forest")
    H.log("[kit] " .. kitLine(FOUR))
  end),

  -- ---- 4. back to the Falcon, and the save --------------------------------------------------------------
  -- @@stage save
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, fleeSpecies = FLEE }),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    for _, ch in ipairs(FOUR) do H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated") end
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-dino-v1"),
  H.saveState("wor_dino.mss"),
  H.logStep(function()
    return string.format("wor_dino generated: SHADOW L%d, CELES L%d, CYAN L%d and TERRA L%d beside the Falcon, "
      .. "world (%d,%d), saved in slot 3", lv(SHADOW), lv(CELES), lv(CYAN), lv(TERRA), H.worldX(), H.worldY())
  end),
})
