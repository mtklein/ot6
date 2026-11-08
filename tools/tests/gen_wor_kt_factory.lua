-- gen_wor_kt_factory.lua -- into Kefka's Tower (docs/design/route-wor-kefka-tower.md): Continue the
-- `wor-desert-v1` battery (SHADOW, CELES, CYAN and TERRA beside the Falcon by Maranda), check what the plan
-- depends on, fly to the tower (world (137,198): LandAirship's VehicleEvent_04 -> EnterKefkasTower), seat the
-- three groups `party_menu 3` offers (section 4's seating), dress each party, then walk party 3 from its landing
-- (334 (56,22)) down the east ladder, through 339 (in at its top door, (36,14)) to the factory (410), over the hop at (8,14) to the factory's
-- save point (37,17), beside Inferno (event battle 114), and Save there with the three parties in the tower: the
-- `wor-kt-factory-v1` battery, Inferno's retry point.  Parties 1 and 2 stand where the tower set them down.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = H.SPLIT_NAMES
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
-- the bag the tower and Kefka are stocked for at Kohlingen, the last shop before them (gen_wor_kefka asserts its
-- floor at Kefka's boot)
local TOWER_FENIX, TOWER_POTIONS = 40, 99
-- the Barrier Rings party 1's lane wears against the Guardian (gen_wor_kt_guardian's WARDS: EDGAR and SETZER), bought
-- at Thamasa's relic counter (shop 75), the last one before the tower.  The line held two from gen_wor_cyan on only
-- by luck: the Harvesters' rare drop ($04E, MonsterItems: Barrier Ring), two of four kills in the v0.39 play
-- (tracked wor-mtzozo-v1: 2 in the bag) and none in #274's replay (gen_wor_kt_guardian's boot: "the bag holds 2
-- Barrier Ring(s) for party 1's lane (it holds 0 ...)")
local BARRIER_RING, TOWER_BARRIER_RINGS = 0xB7, 2
-- counted as gen_wor_kt_guardian's wardsHeld counts them: the bag, or a ring the lane's wearer has on already
local function barrierRingsOwned()
  local n = H.invCountOf(BARRIER_RING)
  for _, ch in ipairs({ EDGAR, SETZER }) do
    for s = 4, 5 do
      if H.readByte(0x1600 + 37 * ch + 0x1F + s) == BARRIER_RING then n = n + 1 end
    end
  end
  return n
end
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

-- the tower's walking pieces (lib M.kefkaTowerKit: its ladders and hop as links, the push-back tiles kept off, the
-- crane tiles walked over and never pressed A on)
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, board, watches = K.map, K.sw, K.settled, K.say, K.board, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door, chest = T.walk, T.door, T.chest

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
-- a Ribbon in every party (guidelines: Ribbons are worth going out of one's way for).  The three the line holds
-- are worn by TERRA, CYAN and SHADOW, which seats two in party 3 and none in party 2, and party 2's first map
-- deals the Evil Oscar's Sour Mouth (Dark, Poison, Imp, Mute, Muddle, Sleep): without one it wiped there (lab
-- atma1/atma_s16: "formation 00B7 00B7 00B7 ... a6:0/5539 ... a1:0/2653 a10:0/2315").  So a party wearing two
-- hands one over (the Relic menu's Remove, the last wearer in its roster), and the party wearing none puts it on
-- (ribbonsOnSeated's seat), until no party has none while another has two.
local RIBBON = 0xCA
local function ribbonWearers(p)
  local w = {}
  for _, ch in ipairs(H.partyRoster(p)) do
    for s = 4, 5 do
      if H.readByte(0x1600 + 37 * ch + 0x1F + s) == RIBBON then w[#w + 1] = { ch = ch, slot = s } end
    end
  end
  return w
end
local function ribbonsSpread(depth)
  depth = depth or 0
  return H.lazy(function()
    local donor, taker = nil, nil
    for p = 1, 3 do
      local n = #ribbonWearers(p)
      if n >= 2 and donor == nil then donor = p end
      if n == 0 and taker == nil then taker = p end
    end
    if donor == nil or taker == nil or depth >= 3 then
      return H.seqStep({
        H.logStep(string.format("[ribbons] Ribbons by party: %d, %d, %d", #ribbonWearers(1), #ribbonWearers(2),
          #ribbonWearers(3))),
        H.call(function()
          for p = 1, 3 do
            H.assertEq(#ribbonWearers(p) >= 1, true, string.format("a Ribbon in every party: party %d wears %d", p,
              #ribbonWearers(p)))
          end
          for _, ch in ipairs({ GAU, UMARO }) do
            for s = 4, 5 do
              H.assertEq(H.readByte(0x1600 + 37 * ch + 0x1F + s) == RIBBON, false,
                NAMES[ch] .. " (left on the Falcon at the split) wears no Ribbon")
            end
          end
        end),
      })
    end
    local w = ribbonWearers(donor)
    local give = w[#w]
    H.log(string.format("[ribbons] party %d wears %d, party %d none: %s hands slot %d's Ribbon over", donor, #w, taker,
      NAMES[give.ch], give.slot))
    return H.seqStep({
      H.switchParty(donor, { tag = "Ribbon from party " .. donor }),
      H.unequipRelics(give.ch, { give.slot }, { tag = "Ribbon off " .. NAMES[give.ch] }),
      H.switchParty(taker, { tag = "Ribbon to party " .. taker }),
      H.ribbonsOnSeated({ tag = "the Ribbon onto party " .. taker, noRegroup = true }),
      ribbonsSpread(depth + 1),
    })
  end)
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
  -- no shop past this stop: the bag is stocked for the whole tower and Kefka (#274: the line's first play of the
  -- tower spent 14 of 20 Fenix Downs before Kefka, and reached him with 6; route-wor-the-end.md section 6)
  H.cond(function()
    return H.invCountOf(POTION) < TOWER_POTIONS or H.invCountOf(FENIX) < TOWER_FENIX
  end, { K.kohlingenStop("the top-up before Kefka's Tower", { fenix = TOWER_FENIX, potions = TOWER_POTIONS }) }, {}),
  H.cond(function() return barrierRingsOwned() < TOWER_BARRIER_RINGS end, {
    K.thamasaRelicStop("the tower's wards", { { BARRIER_RING, function()
      return math.max(0, TOWER_BARRIER_RINGS - barrierRingsOwned()) end, "BARRIER RING for the Guardian's wards" } }),
  }, {}),
  H.call(function()
    H.log(string.format("[deps] Barrier Rings owned %d (bag %d), the Guardian's lane wears %d", barrierRingsOwned(),
      H.invCountOf(BARRIER_RING), TOWER_BARRIER_RINGS))
    H.assertEq(barrierRingsOwned() >= TOWER_BARRIER_RINGS, true, string.format("the party owns %d Barrier Rings for "
      .. "the Guardian's wards (gen_wor_kt_guardian's WARDS), bought at Thamasa's relic counter", TOWER_BARRIER_RINGS))
  end),
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
  ribbonsSpread(),
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
  -- the hall's two chests (the Gauntlet (49,12), the Nutkin Suit (38,12)) are reached from 296, the room off 339's
  -- foot (the same treasure bits; probe f8: "no side of it is reachable from (48,24)"), a dead end the middle path
  -- leaves (route-wor-kefka-tower.md section 5)
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
