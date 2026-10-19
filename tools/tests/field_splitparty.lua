-- @suite slow
-- field_splitparty.lua -- the split-party mechanics (#275) in the Phoenix
-- Cave, from the save made there with the party in two
-- (`wor-phoenix-v1`: party 1 on the save point 315 (37,28), party 2 beside
-- the lava switch at (20,11)).  Played: the Continue, Y switches, party 2's
-- walk into a random battle and a care, party 1 onto the bridge plate and
-- party 2 across the bridge.  Nothing is written.
--
-- Asserted, each against the game's own bytes:
--   A. the parties after a Continue: H.partyRoster(p) is the set the save
--      holds in $1850, H.partyWhere(2) the tile the save's $1F81/$1FD3
--      copies put party 2's leader on, $1A6D 1;
--   B. H.switchParty from a tile whose script re-runs under the party (the
--      save point: control one frame in four) to party 2 and back, each
--      landing on the switched-to party's tile with $1A6D read;
--   C. the absorb guard's weapon list (H.partyWeapons) is the walking
--      party's only;
--   D. the ledger: party 2's random battles are charged to party 2, their
--      seats ($3ED8) are party 2's actors, party 1's members gain no
--      experience from them and party 1 is charged no Potion;
--   E. the split reserve: with party 1's share set to the whole bag's
--      Potions (splitBegin shares 99:1), H.splitReserveFor(2) holds them
--      back, and party 2's care, hurt from D (its battles go on until a
--      member is under full HP), spends no Potion;
--   F. the links: a link whose cond is false is not taken by the planner
--      (H.bfsReach), the same link with cond true is; with party 1 off the
--      bridge plate (23,19) no route takes party 2 to (19,25), with party 1
--      on it H.navLinks walks there through the link (19,22) -> (19,25).
-- Mutants and the evidence: build/attempts/wt/v032-splitparty/lab/ (mut2_*, sws3_*;
-- docs/design/split-party.md section 8).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, SABIN, CELES, STRAGO, RELM, MOG, UMARO = 0, 2, 5, 6, 7, 8, 10, 13
local POTION = 0xE9
local MAP_CAVE = 315
local GROUP = { [1] = { TERRA, STRAGO, SABIN, CYAN }, [2] = { CELES, RELM, MOG, UMARO } }
local LINKS = { { 19, 22, "down", 19, 25 }, { 19, 24, "up", 19, 21 } }
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function xp(c) local o = 0x1600 + 37 * c return H.readByte(o + 0x11) | (H.readByte(o + 0x12) << 8) | (H.readByte(o + 0x13) << 16) end
local function setOf(list) local s = {} for _, c in ipairs(list) do s[c] = true end return s end
local function sameSet(a, b)
  if #a ~= #b then return false end
  local sb = setOf(b)
  for _, c in ipairs(a) do if not sb[c] then return false end end
  return true
end

local xp1, battles0, spent1, potions0, reserve2 = {}, 0, nil, 0, 0
local lap, n0 = 1, nil

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-phoenix-v1"),

  -- ---- A. the parties after a Continue ----------------------------------------
  H.call(function()
    H.log("[A] " .. H.partiesLine())
    H.assertEq(H.activeParty(), 1, "A: party 1 walks ($1A6D)")
    for p = 1, 2 do
      H.assertEq(sameSet(H.partyRoster(p), GROUP[p]), true, string.format("A: party %d's roster is the save's", p))
    end
    local m, x, y = H.partyWhere(2)
    H.assertEq(m == MAP_CAVE and x == 20 and y == 11, true,
      string.format("A: party 2's leader stands on 315 (20,11) (read map %s (%s,%s))", tostring(m), tostring(x), tostring(y)))
  end),

  -- ---- B. switching from the save point ----------------------------------------
  H.switchParty(2, { tag = "B: to party 2 from the save point" }),
  H.call(function()
    H.assertEq(H.activeParty(), 2, "B: $1A6D reads 2")
    H.assertEq(H.fieldX() == 20 and H.fieldY() == 11, true, "B: walking party 2's leader at (20,11)")
  end),
  H.switchParty(1, { tag = "B: back to party 1 on the save point" }),
  H.call(function()
    H.assertEq(H.activeParty(), 1, "B: $1A6D reads 1")
    H.assertEq(H.fieldX() == 37 and H.fieldY() == 28, true, "B: party 1 back on the save point (37,28)")
  end),

  -- ---- C. the absorb guard's list -------------------------------------------------
  H.call(function()
    local act = setOf(H.partyRoster(1))
    local n = 0
    for _, w in ipairs(H.partyWeapons()) do
      n = n + 1
      H.assertEq(act[w.char] == true, true, string.format("C: weapon $%02X of char %d is the walking party's", w.item, w.char))
    end
    H.assertEq(n > 0, true, "C: the walking party holds weapons (the list is not empty)")
  end),

  -- ---- D, E. a battle of party 2's, its care -----------------------------------------
  H.switchParty(2, { tag = "D: to party 2" }),
  H.splitBegin({ shares = { [1] = 99, [2] = 1 } }),
  H.call(function()
    for _, c in ipairs(GROUP[1]) do xp1[c] = xp(c) end
    battles0 = #H.split.battles
    spent1 = H.split.spent[1][POTION] or 0
    potions0 = H.invCountOf(POTION)
    reserve2 = H.splitReserveFor(2)[POTION] or 0
    H.log(string.format("[E] potions %d, party 2's reserve %d (base %d + party 1's share %d)", potions0, reserve2,
      H.CARE_RESERVE[POTION] or 0, H.split.budget[1][POTION]))
    H.assertEq(reserve2, (H.CARE_RESERVE[POTION] or 0) + H.split.budget[1][POTION] - spent1,
      "E: party 2's reserve is the floor plus party 1's unspent share")
    H.assertEq(reserve2 >= potions0, true, "E: precondition: the reserve holds every Potion back")
  end),
  -- pace (20,11)-(24,10) until a battle has come and gone and left a
  -- member of party 2 under full HP (a fight can end with everyone whole: a
  -- level-up refills, sws2_k1_*), at most 6 battles; the map's rate is a
  -- battle per 60 steps on average (route_data map 315)
  H.driveUntil(function()
    if n0 == nil then n0 = #H.split.battles end
    local n = #H.split.battles - n0
    if n == 0 or not H.hasControl() then return false end
    local under = false
    for _, c in ipairs(GROUP[2]) do
      if H.charHp(c) < H.charMaxHp(c) then under = true end
    end
    H.assertEq(n <= 6, true, "D/E: precondition: a member of party 2 hurt within 6 battles")
    return under
  end, 400000, {
    H.navTo(function() return lap == 1 and 24 or 20 end, function() return lap == 1 and 10 or 11 end,
      { maxFrames = 4000, playBattles = "tactical", care = false }),
    H.call(function() lap = 3 - lap end),
  }, "D: party 2 meets random battles"),
  H.call(function()
    local want = {}
    for _, c in ipairs(GROUP[2]) do want[H.charActor(c)] = true end
    for i = n0 + 1, #H.split.battles do
      local b = H.split.battles[i]
      H.log(string.format("[D] battle %d: party %d, seats %s, kind %s", b.n, b.party, table.concat(b.seats, ","), b.kind))
      H.assertEq(b.party, 2, "D: the battle is charged to party 2")
      H.assertEq(b.seatsMatch, true, "D: its seats are party 2's actors")
      for _, a in ipairs(b.seats) do H.assertEq(want[a] == true, true, string.format("D: seat actor %d is party 2's", a)) end
    end
    for _, c in ipairs(GROUP[1]) do
      H.assertEq(xp(c), xp1[c], string.format("D: %s (party 1) gained no experience", H.SPLIT_NAMES[c]))
    end
    H.assertEq(H.split.spent[1][POTION] or 0, spent1, "D: party 1 was charged no Potion")
  end),
  H.call(function()
    H.log("[E] after the battles: " .. H.partiesLine() .. string.format("; potions %d", H.invCountOf(POTION)))
    potions0 = H.invCountOf(POTION)
  end),
  H.fieldCare({ threshold = 1.0, magic = false, tent = false, tincture = false, tag = "E: party 2's care" }),
  H.call(function()
    H.assertEq(H.invCountOf(POTION), potions0, "E: party 2's care spent no Potion (party 1's share is held back)")
  end),
  H.splitEnd(),

  -- ---- F. the links ---------------------------------------------------------------------
  H.call(function()
    local x, y = H.fieldX(), H.fieldY()
    local off = { { x, y, "up", 19, 25, function() return false end } }
    local on = { { x, y, "up", 19, 25, function() return true end } }
    H.assertEq(H.bfsReach(nil, nil, nil, off, 19, 25) == nil, true, "F: a link whose cond is false is not taken")
    local legs = H.bfsReach(nil, nil, nil, on, 19, 25)
    H.assertEq(legs ~= nil and legs[1] ~= nil and legs[1].link ~= nil, true, "F: the same link with cond true is the route")
    H.assertEq(sw(0x02D2), 0, "F: precondition: the bridge plate (23,19) is not held")
    local any = false
    for _, z in ipairs({ false, 1, 2 }) do
      if H.bfsReach(nil, nil, z or nil, LINKS, 19, 25) then any = true end
    end
    H.assertEq(any, false, "F: no route to (19,25) while party 1 is off the bridge plate")
  end),
  H.switchParty(1, { tag = "F: to party 1" }),
  H.navLinks(23, 19, LINKS, { what = "F: party 1 onto the bridge plate", playBattles = "tactical" }),
  H.waitUntil(function() return sw(0x02D2) == 1 end, 600, "F: $02D2 set (party 1 on the plate)", 1),
  H.switchParty(2, { tag = "F: to party 2" }),
  H.navLinks(19, 25, LINKS, { what = "F: party 2 over the bridge", playBattles = "tactical" }),
  H.call(function()
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 25, true, "F: party 2 across the bridge at (19,25)")
    H.log("[F] " .. H.partiesLine())
  end),
})
