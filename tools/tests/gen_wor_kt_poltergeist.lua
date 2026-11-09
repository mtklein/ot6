-- gen_wor_kt_poltergeist.lua -- Kefka's Tower, party 2 to the Poltergeist and 412's save point
-- (docs/design/route-wor-kefka-tower.md sections 2, 5 and 6): Continue the `wor-kt-doom-v1` battery (party 3 on
-- Doom's save point, 355 (64,11); party 2 on 337 (8,6), where it opened the cell doors; party 1 on the chamber's east
-- plate), then party 2 north through the chamber's middle and its north door, 291, 287, to 334's north: the Ribbon
-- (29,29), put on at once (H.ribbonsOnSeated: the Back Gauge gives way); its bench levels on that floor (T.trainLap:
-- the tower's own encounters, the owner's direction); dressed against the statue's fire (H.elementDress) and Wall
-- Rings on the members named below (its Stop is reflectable, and a stopped member draws Blaster), a bludgeon in
-- STRAGO's hands (a second key for its break); the Poltergeist
-- (334 (30,16): event battle 100, a game over when lost: the runner retries from the save); the Ribbon handed on
-- through the bag for party 1 (gen_wor_kt_goddess puts it on); through (30,11) to 412, and Save on 412's save point
-- (82,47): the `wor-kt-poltergeist-v1` battery.  412's save point stands above 411's middle plate: party 2's place
-- at the convergence.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local POLTERGEIST = 0x129
local SAVE_412 = { 82, 47 }
local FIRE_ELEMENT = 0x01
local RIBBON, WALL_RING, GENJI, EGG = 0xCA, 0xBB, 0xD1, 0xE4
-- party 2's bench levels to TRAIN_LEVEL on 334's north before the statue (route-wor-kefka-tower.md 6.1: at L46
-- won 7 of 9; at L50 with the Wall Rings, the fire dress and the wards 8 of 9; section 6.2 for this leg's grid)
local TRAIN_LEVEL = KT_TRAIN or 50
-- who wears a Wall Ring for the Poltergeist (section 6.2): its Stop, one target, is reflected off a Wall Ring, and a
-- stopped member draws Blaster; its Fire 3 counter, one target, bounces off a Wall Ring onto the statue, which
-- absorbs fire
local WALLS = KT_WALLS or { [7] = true, [10] = true }
-- the tower's species whose vanilla weakness a player who knows the tower reads (gen_wor_kt_guardian's)
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
-- STRAGO's Pearl Wind (#388, wor-coverage.md 13.8): the party wears Wall Rings, so no Cure reaches it as a party
-- cure (the driver refuses one: it would bounce onto the statue), and Pearl Wind ignores Reflect and heals each
-- member as much as his max HP.  Learned in the wood beside Jidoor's plain (gen_wor_relm); in his AUTO five.
local BOSS_FIGHT = KT_BOSS_FIGHT or { strago = { pearlWind = true, pearlWindBelow = 0.6 } }
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door = T.walk, T.door

local function relic(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function wears(ch, id) return relic(ch, 4) == id or relic(ch, 5) == id end
-- the party-2 member the 334 Ribbon went on (the one who wore none before it), and what it went over
local handed = nil
local wornBefore = {}

-- a Wall Ring onto each member of WALLS who lacks one, over the relic the Relic planner's classes rank lowest; never
-- over a Ribbon, a two-weapon relic or the Exp. Egg
local function wallRings(what)
  return H.lazy(function()
    local steps, have = {}, H.invCountOf(WALL_RING)
    for _, ch in ipairs(H.partyRoster(H.activeParty())) do
      if WALLS[ch] and not wears(ch, WALL_RING) then
        local function rank(r)
          if r == 0xFF then return -1 end
          -- WALLS[ch] == "ribbon": this member's Ribbon may give way (a lab arm: the Wall Ring on every member)
          if r == RIBBON and WALLS[ch] == "ribbon" then return 50 end
          if r == RIBBON or r == GENJI or r == EGG then return 99 end
          local cl = H.relicClassRaw(r, nil)
          if cl == nil then return 1.5 end
          return cl.rank
        end
        local slot = rank(relic(ch, 4)) <= rank(relic(ch, 5)) and 4 or 5
        H.assertEq(rank(relic(ch, slot)) < 99 and have > 0, true, string.format("%s: %s has a relic slot a Wall Ring "
          .. "may take (slots $%02X $%02X), and the bag one (%d)", what, NAMES[ch], relic(ch, 4), relic(ch, 5), have))
        have = have - 1
        H.log(string.format("[wall] %s: %s slot %d $%02X -> Wall Ring", what, NAMES[ch], slot, relic(ch, slot)))
        steps[#steps + 1] = H.keepGear(ch, what .. ": " .. NAMES[ch],
          H.equipKit(ch, { { slot, WALL_RING } }, { tag = what .. ": " .. NAMES[ch] }))
      end
    end
    if #steps == 0 then return H.logStep("[wall] " .. what .. ": nobody takes one") end
    return H.seqStep(steps)
  end)
end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("wor-kt-doom-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (Guardian and Doom beaten, the cell doors open, party 3 on Doom's save
  -- point).  Asserted here: party 2 on 337 (8,6), where gen_wor_kt_doom left it (this leg's walk starts there), and
  -- the Poltergeist not yet fought.  Soft, fixed here: HP and MP (the care), the arms (absorbSafeArms), the dress.
  H.call(function()
    say("tower", "boot")
    local m2, x2, y2 = H.partyWhere(2)
    H.assertEq(string.format("%d (%d,%d)", m2, x2, y2), "337 (8,6)", "party 2 on 337 (8,6), where it opened the cell "
      .. "doors (gen_wor_kt_doom)")
    H.assertEq(sw(0x0074), 0, "the Poltergeist not yet fought ($0074)")
    -- the hard inputs from the bag (#513): a bludgeon STRAGO can hold (the factory's rods and the line's own buys)
    -- and a Wall Ring for each member of WALLS, in the bag or already worn
    local rods = 0
    for _, id in ipairs({ 0x39, 0x3A, 0x3B, 0x46 }) do
      rods = rods + H.invCountOf(id) + ((H.readByte(0x1600 + 37 * 7 + 0x1F) == id) and 1 or 0)
    end
    H.assertEq(rods >= 1, true, "a bludgeon for STRAGO in the bag or his hands (the Pearl Rod, the Gravity Rod, the "
      .. "Punisher, the Morning Star; gen_wor_kt_factory and the line's buys)")
    local need, rings = 0, H.invCountOf(WALL_RING)
    for ch in pairs(WALLS) do
      need = need + 1
      if wears(ch, WALL_RING) then rings = rings + 1 end
    end
    H.assertEq(rings >= need, true, string.format("a Wall Ring for each of the %d members who wear one for the "
      .. "Poltergeist, in the bag or worn (%d)", need, rings))
  end),
  -- @@setup-end

  -- @@stage north
  -- the bag's care stock shared between the two parties still to fight (party 3's statue is behind it)
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 0 } }),
  H.switchParty(2),
  door(8, 4, 355, "party 2: 337 (8,4) -> the chamber (39,19)"),
  door(39, 4, 291, "party 2: the north door (355 (39,4)) -> 291 (12,16)"),
  door(12, 4, 287, "party 2: 291 (12,4) -> 287 (40,32)"),
  door(33, 33, 334, "party 2: 287 (33,33) -> 334 (27,24)"),
  T.chest(29, 29, 0x0F2, "Ribbon (334 (29,29))", true),
  H.call(function()
    for _, ch in ipairs(H.partyRoster(2)) do wornBefore[ch] = wears(ch, RIBBON) end
  end),
  -- on at once, as a player does (Ribbons are worth going out of the way for)
  H.ribbonsOnSeated({ tag = "the 334 Ribbon", noRegroup = true }),
  H.call(function()
    for _, ch in ipairs(H.partyRoster(2)) do
      if wears(ch, RIBBON) and not wornBefore[ch] then handed = ch end
    end
    H.assertEq(handed ~= nil, true, "the 334 Ribbon went on a member of party 2 (H.ribbonsOnSeated)")
    say("tower", "the 334 Ribbon on " .. NAMES[handed])
  end),
  T.trainLap("party 2 on 334's north", TRAIN_LEVEL, { burn = KT_BURN, cap = KT_CAP }),

  -- @@stage poltergeist
  -- the care first: the Equip and Relic menus refuse a fallen member
  H.fieldCare({ threshold = 1.0, tag = "before dressing for the Poltergeist" }),
  H.elementDress(FIRE_ELEMENT, { tag = "dress against the Poltergeist's fire" }),
  wallRings("Wall Rings for the Poltergeist"),
  -- a key for the break (section 6.2): the statue keys the blow and the cards, and in party 2 only LOCKE's Wing Edge
  -- holds one, so STRAGO trades his Imp Halberd (pierce) for the strongest bludgeon in the bag: the Pearl Rod, the
  -- Gravity Rod, the Punisher, the Morning Star.  Asserted: one of them goes on (the bag's rods are the factory's
  -- and the line's own buys; a run without one would meet the statue with one key-holder)
  H.equipKit(7, { { 0, 0x39 }, { 0, 0x3A }, { 0, 0x3B }, { 0, 0x46 } },
    { tag = "a bludgeon for STRAGO", ladder = true, optional = true }),
  H.call(function()
    local w = H.readByte(0x1600 + 37 * 7 + 0x1F)
    H.assertEq(w == 0x39 or w == 0x3A or w == 0x3B or w == 0x46, true,
      string.format("STRAGO holds a bludgeon for the Poltergeist (hand $%02X)", w))
  end),
  H.absorbSafeArms(nil, { POLTERGEIST }, { tag = "arms for the Poltergeist" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Poltergeist" }),
  T.standing("party 2 before the Poltergeist"),
  H.call(function() say("boss", "party 2 before the Poltergeist: " .. H.partiesLine()) end),
  H.navTo(30, 16, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, spare = { POLTERGEIST },
    avoid = T.avoid[334],
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [POLTERGEIST] = true }))
        or (H.fieldX() == 30 and H.fieldY() == 16)
    end }),
  H.advanceStory(function() return sw(0x0074) == 1 and map() == 334 and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "the Poltergeist beaten") end),
  H.saveState("wor_kt_poltergeist_won.mss"),

  -- @@stage save
  -- the 334 Ribbon into the bag for party 1, which holds one Ribbon to party 2's three (gen_wor_kt_goddess puts it
  -- on): the care first, since the Relic menu refuses a fallen member
  H.fieldCare({ threshold = 1.0, tag = "after the Poltergeist" }),
  H.lazy(function()
    local slot = relic(handed, 4) == RIBBON and 4 or 5
    H.assertEq(relic(handed, slot), RIBBON, NAMES[handed] .. " still wears the 334 Ribbon")
    local label = "the 334 Ribbon off " .. NAMES[handed] .. " for party 1"
    return H.keepGear(handed, label, H.unequipRelics(handed, { slot }, { tag = label }))
  end),
  H.call(function()
    H.assertEq(H.invCountOf(RIBBON) >= 1, true, "a Ribbon in the bag for party 1")
    say("tower", string.format("the 334 Ribbon off %s into the bag for party 1", NAMES[handed]))
  end),
  door(30, 11, 412, "party 2: 334 (30,11) -> 412 (82,49)"),
  H.stepOntoSavePoint(SAVE_412[1], SAVE_412[2]),
  H.fieldCare({ threshold = 1.0, tag = "on 412's save point" }),
  H.call(function()
    say("tower", "on 412's save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-poltergeist-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_poltergeist.mss"),
  H.logStep(function()
    return string.format("wor_kt_poltergeist generated: %s, saved in slot 3", H.partiesLine())
  end),
})
