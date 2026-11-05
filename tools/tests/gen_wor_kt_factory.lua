-- gen_wor_kt_factory.lua -- into Kefka's Tower (docs/design/route-wor-kefka-tower.md): Continue the
-- `wor-desert-v1` battery (SHADOW, CELES, CYAN and TERRA beside the Falcon by Maranda), check what the plan
-- depends on, fly to the tower (world (137,198): LandAirship's VehicleEvent_04 -> EnterKefkasTower), seat the
-- three groups `party_menu 3` offers (section 4's seating), dress each party, then walk party 3 from its landing
-- (334 (56,22)) down the east ladder, through 339 to the factory (410), over the hop at (8,14) to the factory's
-- save point (37,17), beside Inferno (event battle 114), and Save there with the three parties in the tower: the
-- `wor-kt-factory-v1` battery, Inferno's retry point.  Parties 1 and 2 stand where the tower set them down.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = H.SPLIT_NAMES
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
-- the three groups (route-wor-kefka-tower.md section 4): each party a carrier with a cure beside two of the bench;
-- party 3 walks the factory (Inferno, the Skull Dragon), party 2 the long way west (Atma, the Gold Dragon), party 1
-- the north-west and the machines' hall.  KT_SPLIT (a lab's global) overrides it.
local SPLIT = KT_SPLIT or {
  { TERRA, RELM, EDGAR, SETZER },
  { CELES, STRAGO, LOCKE, MOG },
  { CYAN, SHADOW, SABIN, GOGO },
}
local TOWER_LANDING = { 137, 198 }
local MAP_TOWER, MAP_339, MAP_FACTORY = 334, 339, 410
local FACTORY_SAVE = { 37, 17 }
-- the tower's species whose vanilla weakness a player who knows the tower reads (the forest's legs' way): the
-- machines and Inferno take bolt, the Vectaur and the Brontaur ice, the Evil Oscar fire (it absorbs the rest)
local VECTAUR, BRONTAUR, OSCAR = 0x080, 0x084, 0x0B7
local MACHINES = { [0x0FD] = true, [0x0D9] = true, [0x0EA] = true, [0x0ED] = true, [0x0F6] = true, [0x105] = true,
  [0x0FC] = true, [0x0A1] = true }
local FIRE, ICE, BOLT = 0x00, 0x01, 0x02
local FIGHT = {}
FIGHT.nuke = function()
  if H.formationHas({ [OSCAR] = true }) then return { FIRE } end
  if H.formationHas(MACHINES) then return { BOLT } end
  if H.formationHas({ [VECTAUR] = true, [BRONTAUR] = true }) then return { ICE } end
  return nil
end
H.NAV_REFIRE_HOLD = true
-- the care between battles tops everyone up and casts first, as the forest's and the desert's legs do; the tower has
-- no counter, so the cures are cast before the bag is reached for
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

-- the tower's tile events that carry a party (event_main.asm _cc1008.._cc1046: a ladder's column carries the party
-- the way it was entered; the column beside it pushes a party entering the wrong way back one); a link is
-- { x, y, move, tx, ty }: entering (x, y) moving `move` lands on (tx, ty)
local LINKS = {
  [MAP_TOWER] = {
    { 6, 20, "down", 6, 22 }, { 7, 21, "up", 7, 19 }, { 16, 42, "down", 16, 45 }, { 11, 50, "up", 11, 44 },
    { 55, 24, "down", 55, 29 }, { 56, 28, "up", 56, 23 }, { 34, 51, "up", 34, 49 }, { 39, 43, "up", 39, 41 },
  },
  -- the hop at (8,14), entered facing up (_cc1398): a jump through 410 (36,46) to (48,24)
  [MAP_FACTORY] = { { 8, 14, "up", 48, 24 } },
}
-- the ladders' push-back tiles, and the six tiles that ride the crane out of the tower on A (EnterKefkasTower's
-- crane: _cc0fc3/_cc0fd4/_cc0fe5 and _ca03ba/_ca03c9/_ca03d8, the party back on the Falcon's deck): never stood on
local AVOID = {
  [MAP_TOWER] = { { 6, 21 }, { 7, 20 }, { 16, 44 }, { 11, 45 }, { 55, 28 }, { 56, 24 }, { 34, 50 }, { 39, 42 },
    { 57, 44 }, { 35, 21 }, { 8, 37 }, { 41, 18 }, { 14, 17 } },
  [MAP_FACTORY] = { { 31, 18 } },                    -- Inferno's trigger
}

local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, settled, say, board, watches = K.map, K.sw, K.settled, K.say, K.board, K.watches

local function walk(x, y, what, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
        fight = FIGHT, avoid = AVOID[map()], arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- through an exit to another map: onto (x, y) until the map reads dst
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- a chest from whichever side of it the party can reach; a line when none is
local function chest(cx, cy, bit, what)
  return H.lazy(function()
    if H.chestOpen(bit) then return H.logStep(string.format("[chest] %s: already open", what)) end
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      if H.bfsReach(nil, nil, nil, LINKS[map()] or {}, cx + o[1], cy + o[2], AVOID[map()]) then
        return H.seqStep({
          walk(cx + o[1], cy + o[2], what .. ": beside it"),
          H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what,
            nav = { fight = FIGHT, playBattles = "tactical" } }),
        })
      end
    end
    return H.logStep(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end

-- each party's kit once it walks: the relics in the bag, and a stone for each member who wears none (UMARO and GOGO
-- take none), from the owned stones no one wears, the healing ones first (gen_wor_phoenix's)
local STONE_ORDER = { 25, 21, 2, 1, 3, 5, 9, 10, 18, 20, 6, 0, 4, 7, 8, 11, 12, 13, 14, 15, 16, 17, 19, 22, 23, 24 }
local function owns(e) return (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 end
local function stoneFor()
  local worn = {}
  for ch = 0, 15 do worn[H.readByte(0x1600 + 37 * ch + 0x1E)] = true end
  for _, e in ipairs(STONE_ORDER) do
    if owns(e) and not worn[e] then return e end
  end
  return nil
end
local function dressParty(p)
  local steps = { H.switchParty(p, { tag = "dress party " .. p }) }
  for i = 1, 4 do
    steps[#steps + 1] = H.lazy(function()
      local ch = H.partyRoster(p)[i]
      if ch == nil or ch == UMARO or ch == GOGO or H.readByte(0x1600 + 37 * ch + 0x1E) ~= 0xFF then
        return H.call(function() end)
      end
      local e = stoneFor()
      if e == nil then return H.logStep("[kit] no stone left for " .. NAMES[ch]) end
      return H.equipEsper(function() return (H.readByte(0x1850 + ch) >> 3) & 3 end, e,
        { tag = string.format("stone %d -> %s (party %d)", e, NAMES[ch], p) })
    end)
  end
  steps[#steps + 1] = H.lazy(function()
    local m = {}
    for _, ch in ipairs(H.partyRoster(p)) do m[#m + 1] = { ch, NAMES[ch] } end
    return H.dressRelics(m, { tag = "relics, party " .. p })
  end)
  steps[#steps + 1] = H.call(function() say("kit", "party " .. p .. " dressed") end)
  return H.seqStep(steps)
end

local function recruited(mask, ch) return (mask >> ch) & 1 == 1 end
local GIL_FLOOR = 60000

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-desert-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- Hard, asserted here: every member the seating names recruited (the party menu's mask $1EDE: the arcs up to
  -- gen_wor_colosseum), and gil for a top-up (the line's purse).  Soft, fixed in the leg as a player would: the
  -- bag (Kohlingen's counter, when it is short of the band), each party's stones and relics (dressParty), HP (the
  -- care).
  H.call(function()
    say("wor", "boot")
    local mask = H.readWord(0x1EDE)
    local missing = {}
    for _, g in ipairs(SPLIT) do
      for _, ch in ipairs(g) do
        if not recruited(mask, ch) then missing[#missing + 1] = NAMES[ch] end
      end
    end
    H.log(string.format("[deps] recruited mask $%04X; missing: %s", mask,
      #missing > 0 and table.concat(missing, ", ") or "none"))
    H.assertEq(#missing, 0, "every member the tower's seating names is recruited ($1EDE: the arcs up to "
      .. "gen_wor_colosseum)")
    H.assertEq(H.gil() >= GIL_FLOOR, true, string.format("gil for a top-up at Kohlingen: %d GP, the floor %d (the "
      .. "line's purse)", H.gil(), GIL_FLOOR))
  end),
  -- @@setup-end

  -- ---- 1. the bag, the flight and the split -----------------------------------------------------------------
  -- @@stage split
  board(),
  H.cond(function()
    return H.invCountOf(POTION) < 99 or H.invCountOf(FENIX) < 20
  end, { K.kohlingenStop("the top-up before Kefka's Tower") }, {}),
  H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
  H.flyTo(TOWER_LANDING[1], TOWER_LANDING[2], { what = "the Falcon to Kefka's Tower", entersMap = true, fight = FIGHT,
    maxFrames = 20000 }),
  H.driveUntil(function() return H.readByte(0x0059) ~= 0 and H.readByte(0x26) == 0x2d end, 9000, {
    H.call(function() H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {}) end),
  }, "the tower's party menu (party_menu 3)"),
  H.waitFrames(20),
  H.partySelect(SPLIT, { tag = "the tower's three groups" }),
  H.advanceStory(function() return map() == MAP_TOWER and settled() end, 12000, { playBattles = "tactical",
    fight = FIGHT }),
  H.call(function()
    for g, ids in ipairs(SPLIT) do
      for _, ch in ipairs(ids) do
        H.assertEq(H.partyOfChar(ch), g, string.format("%s is in party %d", NAMES[ch], g))
      end
    end
    H.assertEq(sw(0x01CE), 1, "party switching on ($01CE, EnterKefkasTower)")
    say("tower", "in the tower")
  end),
  -- one bag for three parties: party 3 walks first and furthest in this leg
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 2 } }),
  dressParty(1),
  dressParty(2),
  dressParty(3),
  H.saveState("wor_kt_split.mss"),

  -- ---- 2. party 3: the east ladder, 339 and the factory ----------------------------------------------------------
  -- @@stage factory
  H.switchParty(3),
  chest(47, 40, 0x0DD, "Red Cap (334 (47,40))"),
  door(52, 47, MAP_339, "party 3: 334 (52,47) -> 339 (36,14)"),
  door(30, 12, MAP_FACTORY, "party 3: 339 (30,12) -> the factory, 410 (11,19)"),
  chest(10, 17, 0x0E2, "Hero Ring (410 (10,17))"),
  chest(7, 42, 0x0F1, "Aegis Shld (410 (7,42))"),
  walk(48, 24, "party 3: the hop (8,14) into the factory's hall, 410 (48,24)"),
  chest(49, 12, 0x0EB, "Gauntlet (410 (49,12))"),
  chest(38, 12, 0x0E1, "Nutkin Suit (410 (38,12))"),
  H.saveState("wor_kt_factory_hall.mss"),

  -- ---- 3. the save point -----------------------------------------------------------------------------------
  -- @@stage save
  H.stepOntoSavePoint(FACTORY_SAVE[1], FACTORY_SAVE[2]),
  H.splitCare({ parties = { 3, 1, 2 }, threshold = 1.0, tag = "care at the factory's save point" }),
  H.call(function()
    say("tower", "at the factory's save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-factory-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_factory.mss"),
  H.logStep(function()
    return string.format("wor_kt_factory generated: %s, saved in slot 3", H.partiesLine())
  end),
})
