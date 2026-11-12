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
local TOWER_FENIX, TOWER_POTIONS = 35, 99
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
-- The Exp. Egg across the split (#524 review item 7): the three parties are all seated, so the Egg goes to the member
-- furthest behind on levels among all twelve (relicPlan step 3b's rule, the gear baseline's first layer), not to the
-- furthest behind in whichever party its last wearer lands in.  The gear baseline's first replay left it on SABIN
-- (party 3, L40) while SETZER (party 1, L32) trained by party 1's landing without it: SETZER met the Guardian's
-- lane at L47 where v0.41's line, whose Egg rode with him, had him at L54 ("SETZER L32 1698/1698 ... Exp. Egg" at
-- v0.41's wor_kt_factory; wor_kt_guardian's end "SETZER L54" against "L47"), and the Goddess felled him three times
-- in the replay's wipe.  So before the parties dress, the Egg comes off a wearer in another party than the split's
-- furthest behind (that party walks for its Relic session), and only that member's party may put it on
-- (dressParty's exclude for the others).
local EGG = 0xE4
local eggParty = nil
local function eggToTheSplit()
  return H.lazy(function()
    local low, wearer = nil, nil
    for p = 1, 3 do
      for _, ch in ipairs(H.partyRoster(p)) do
        local lv = H.readByte(0x1600 + 37 * ch + 8)
        if H.charActor(ch) <= 13 and (low == nil or lv < low.lv) then low = { ch = ch, p = p, lv = lv } end
        for s = 4, 5 do
          if H.readByte(0x1600 + 37 * ch + 0x1F + s) == EGG then wearer = { ch = ch, p = p, slot = s } end
        end
      end
    end
    H.assertEq(low ~= nil, true, "the split seats a member")
    eggParty = low.p
    local owned = H.invCountOf(EGG) + (wearer and 1 or 0)
    H.log(string.format("[egg] the split's furthest behind: %s (party %d, L%d); the Egg %s", NAMES[low.ch], low.p,
      low.lv, wearer and string.format("on %s (party %d)", NAMES[wearer.ch], wearer.p)
        or (owned > 0 and "in the bag" or "not owned")))
    if wearer == nil or wearer.p == low.p then return H.call(function() end) end
    local label = string.format("the Egg off %s for party %d", NAMES[wearer.ch], low.p)
    return H.seqStep({
      H.switchParty(wearer.p, { tag = label }),
      H.keepGear(wearer.ch, label, H.unequipRelics(wearer.ch, { wearer.slot }, { tag = label })),
      H.call(function() H.assertEq(H.invCountOf(EGG) >= 1, true, label .. ": the Egg is in the bag") end),
    })
  end)
end
local function eggOnTheSplit()
  return H.call(function()
    local on = nil
    for p = 1, 3 do
      for _, ch in ipairs(H.partyRoster(p)) do
        for s = 4, 5 do if H.readByte(0x1600 + 37 * ch + 0x1F + s) == EGG then on = { ch = ch, p = p } end end
      end
    end
    if eggParty == nil or (on == nil and H.invCountOf(EGG) == 0) then return end
    H.assertEq(on ~= nil and on.p == eggParty, true, string.format("the Exp. Egg is worn in party %d, the split's "
      .. "furthest behind's (on %s)", eggParty, on and NAMES[on.ch] or "nobody"))
    H.log(string.format("[egg] the Exp. Egg on %s (party %d)", NAMES[on.ch], on.p))
  end)
end
-- L.5 Doom (the factory's and 339's Vectaur hordes, #524 review item 7): it kills a member whose level is a multiple of
-- five and who wears no death guard (the Memento Ring $DB, the Safety Bit $DC).  The gear baseline's replay lost three
-- of party 3 to it in the factory leg ("char 5 from 2552/2552 by slot 2 cmd $0C atk $94 (ONE ACTION ...)", SABIN L40,
-- and GOGO L45 the same way), where v0.41's line lost one: its GOGO still wore the Fanatics' Tower's Safety Bit, which
-- the baseline now takes off.  So party 3 walks with its death guards on the members at a multiple of five or one
-- level short of one (a level the factory's battles can add), taken from the bag or from a member of party 3 at
-- neither; the Safety Bit is the declared overlay, and the save's baseline returns the rest to the relic rule.
local DEATH_GUARDS = { 0xDB, 0xDC }
local function isGuard(id) return id == 0xDB or id == 0xDC end
local function atRisk(ch)
  local lv = H.readByte(0x1600 + 37 * ch + 8)
  return lv % 5 == 0 or lv % 5 == 4
end
local function deathGuards(p)
  return H.lazy(function()
    local rec = function(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
    local function guarded(ch) return isGuard(rec(ch, 4)) or isGuard(rec(ch, 5)) end
    local need, donors = {}, {}
    for _, ch in ipairs(H.partyRoster(p)) do
      if H.charActor(ch) <= 13 and not H.relicMenuRefuses(ch) then
        if atRisk(ch) and not guarded(ch) then need[#need + 1] = ch end
        if not atRisk(ch) then
          for s = 4, 5 do if isGuard(rec(ch, s)) then donors[#donors + 1] = { ch = ch, slot = s, id = rec(ch, s) } end end
        end
      end
    end
    local bag = {}
    for _, id in ipairs(DEATH_GUARDS) do for _ = 1, H.invCountOf(id) do bag[#bag + 1] = id end end
    local lines = {}
    for _, ch in ipairs(H.partyRoster(p)) do
      lines[#lines + 1] = string.format("%s L%d%s", NAMES[ch], H.readByte(0x1600 + 37 * ch + 8),
        guarded(ch) and " (guarded)" or "")
    end
    H.log(string.format("[deathguards] party %d: %s; at risk unguarded %d, guards in the bag %d, on members at no risk %d",
      p, table.concat(lines, ", "), #need, #bag, #donors))
    local steps, safety = {}, false
    for _, ch in ipairs(need) do
      local slot = nil
      for _, s in ipairs({ 5, 4 }) do
        local cur = rec(ch, s)
        local cl = cur ~= 0xFF and H.relicClass(cur) or nil
        if slot == nil and not H.gearIsPrize(cur) and not (cl and cl.hands) then slot = s end
      end
      -- a guard the member can wear (the Memento Ring is RELM's and SHADOW's alone: "$DB is not in this character's
      -- list (unequippable)" on SABIN, the first try)
      local id = nil
      local function fits(g) return H.wearsItem(ch, g) end
      for i, g in ipairs(bag) do
        if id == nil and slot ~= nil and fits(g) then id = table.remove(bag, i) end
      end
      if id == nil and slot ~= nil then
        for i, d in ipairs(donors) do
          if id == nil and fits(d.id) then
            table.remove(donors, i)
            id = d.id
            local label = string.format("the death guard $%02X off %s for %s", d.id, NAMES[d.ch], NAMES[ch])
            steps[#steps + 1] = H.keepGear(d.ch, label, H.unequipRelics(d.ch, { d.slot }, { tag = label }))
          end
        end
      end
      if id ~= nil then
        if id == 0xDC then safety = true end
        local label = string.format("the death guard $%02X on %s (L.5 Doom)", id, NAMES[ch])
        steps[#steps + 1] = H.keepGear(ch, label, H.equipKit(ch, { { slot, id } }, { tag = label }))
      else
        H.log(string.format("[deathguards] %s stays unguarded: %s", NAMES[ch],
          slot == nil and "no slot free of a prize or a two-weapon relic" or "no guard left that he can wear"))
      end
    end
    if safety then steps[#steps + 1] = H.overlayOn("Safety Bit", "L.5 Doom in Kefka's Tower's factory (party 3)") end
    steps[#steps + 1] = H.call(function()
      for _, ch in ipairs(need) do
        H.log(string.format("[deathguards] %s L%d: %s", NAMES[ch], H.readByte(0x1600 + 37 * ch + 8),
          guarded(ch) and "guarded" or "unguarded"))
      end
    end)
    return H.seqStep(steps)
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
    return H.dressRelics(m, { tag = "relics, party " .. p,
      exclude = (eggParty ~= nil and eggParty ~= p) and { [EGG] = true } or nil })
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
  -- tower spent 14 of 20 Fenix Downs before Kefka, and reached him with 6; route-wor-the-end.md section 6; #388:
  -- stocked with 40, the whole tower (Inferno to the plates) spent 29 of 38 on a reshuffled draw and stopped at
  -- gen_wor_kefka's floor of 10, the Goddess leg's laps 15 of them: wor-coverage.md 13.9; raised to 50 as a stopgap.
  -- #521: party 1's bench now trains by its landing (gen_wor_kt_guardian), not in 355's east lane, whose Scullion
  -- condemned a member in most battles, and past L.5 Doom's multiples of five; the tower's random battles still
  -- spend a few (the GtBehemoth's Meteor on 334, the Innocs' Muddle), and Kefka wants 10: stocked with 30 the line
  -- spent 21 to the plates (6 of them at Doom, 15 on the way) and stopped at the floor with 9, so 35)
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
  eggToTheSplit(),
  dressParty(1),
  dressParty(2),
  dressParty(3),
  eggOnTheSplit(),
  H.saveState("wor_kt_split.mss"),

  -- ---- 2. party 3: the east ladder, 339 and the factory ----------------------------------------------------------
  -- @@stage factory
  H.switchParty(3),
  deathGuards(3),
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
