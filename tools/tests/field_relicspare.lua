-- @suite savestate=wor_narshe
-- field_relicspare.lua -- the relic plan's step 4b (a Ribbon the plan leaves in the bag goes on after all) arming
-- for a boss, its Exp. Egg exclusion and its ward clause, with a spare Ribbon in hand (#499), on constructed relic
-- sets.  The fixture, wor_narshe (gen_wor_narshe: the seated party on the Narshe cliffs' save point before the Ice
-- Dragon), supplies only who is seated and what the ROM's item records say; whom the plan dresses in what moves
-- with every draw of the chain above it (2026-11-03: the Hyper Wrist took the Ribbon's slot, the baseline planned
-- no Ribbon at all, and the cases read off the fixture went red), so each case STAGES its own relics: two seated
-- members' relic slots and the bag are set (one writeByte site, a declared waiver in state_write_waivers.txt: no
-- play empties a bag on cue, and the property is the plan's rule, not a route), then H.relicPlan, which reads only
-- and logs its decisions, is planned on those two members.  Each case reads the plan against the same threats'
-- plan with step 4b off (opts.spareRibbon = false, the baseline), every expectation is derived from the staged
-- state and the ROM's item records, each precondition asserted by name first:
--   1. the Ice Dragon's threats (gen_wor_tritoch's ICE_THREATS: magic, no status, a boss): one member wears a
--      Ribbon and a guard, the other two guards, a second Ribbon in the bag: the baseline leaves it there while a
--      member planned without one can wear it; the plan puts on min(spare, such members) more Ribbons, one a
--      member, each over the lowest-ranked relic planned there that is not a two-weapon relic, a ward or the Egg,
--      and changes nothing else;
--   2. the same threats with no boss named, the Egg in the bag and the two members on different levels: step 3b
--      puts the Egg on the member behind, and the baseline leaves a Ribbon in the bag that member can wear.  The
--      Egg stays (4b's exclusion), the Ribbon goes over the member's other relic; and the exclusion is what keeps
--      it: with H.ribbonMayDisplace switched to allow the Egg, the Ribbon goes over the Egg;
--   3. the Ice Dragon's threats again: the member with more spells in two wards and the other with a Ribbon, a
--      spare Ribbon in the bag.  It has nowhere to go but over a ward, so it stays in the bag and the wards stay
--      (4b's ward clause: field_relicspare's ward_allowed mutant turns this red).
-- The negative for case 1 (the `not boss` guard 4b had before #495, put back) is recorded in the commit that adds
-- the file.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_narshe.mss.lua"
local RIBBON, EGG = 0xCA, 0xE4
-- gen_wor_tritoch's ICE_THREATS, the arc's three bosses (the Ice Dragon, Tritoch, Umaro)
local ICE = { s1 = 0x00, s2 = 0x00, magic = true, boss = true }
local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER",
  "MOG", "GAU", "GOGO", "UMARO" }
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function relicAt(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function level(ch) return H.readByte(0x1600 + 37 * ch + 8) end
local function at(p, s) return p.want[s] or p.cur[s] end
local function byCh(plan, ch) for _, p in ipairs(plan) do if p.ch == ch then return p end end end
local function ribbons(plan)
  local n = 0
  for _, p in ipairs(plan) do for s = 4, 5 do if at(p, s) == RIBBON then n = n + 1 end end end
  return n
end
local function hasRibbon(p) return at(p, 4) == RIBBON or at(p, 5) == RIBBON end
-- a slot the plan keeps on its wearer (a worn relic it does not rank, or a two-weapon relic): step 4b never takes it
local function kept(id, threats)
  if id == 0xFF then return false end
  local cl = H.relicClass(id, threats)
  return cl == nil or cl.hands == true
end
-- what step 4b may take a slot from, read from the item records here, not from the lib's own test: an empty
-- slot (-1), else the rank of a relic that is not a two-weapon relic, a ward or the Egg; nil otherwise
local function key(id, threats)
  if id == nil or id == 0xFF then return -1 end
  if id == EGG then return nil end
  local cl = H.relicClass(id, threats)
  if cl == nil or cl.hands or cl.aff == "ward" then return nil end
  return cl.rank
end

local members = {}
local function read()
  local act = H.readByte(0x1A6D) & 7
  for ch = 0, 13 do
    if (H.readByte(0x1850 + ch) & 7) == act then members[#members + 1] = { ch, NAMES[ch] } end
  end
  H.log(string.format("[relicspare] seated %d", #members))
  H.assertEq(#members >= 2, true, "precondition: two or more seated members")
end

local function put(addr, v) H.writeByte(addr, v) end
local function spells(ch)
  local n = 0
  for i = 0, 53 do if ch <= 11 and H.readByte(0x1A6E + 54 * ch + i) == 0xFF then n = n + 1 end end
  return n
end
-- the items of a class under the threats that every given member can wear (the ROM's records), in id order,
-- Ribbon and Egg excluded
local function wearable(pair, threats, pred)
  local out = {}
  for id = 0, 255 do
    local cl = id ~= RIBBON and id ~= EGG and H.relicClass(id, threats)
    if cl and pred(cl) then
      local ok = true
      for _, m in ipairs(pair) do ok = ok and wears(m[1], id) end
      if ok then out[#out + 1] = id end
    end
  end
  return out
end
-- the seated members that can wear a Ribbon, the first with the most spells (ties by seat order)
local function ribbonWearers()
  local c = {}
  for _, m in ipairs(members) do if wears(m[1], RIBBON) then c[#c + 1] = m end end
  table.sort(c, function(a, b)
    local x, y = spells(a[1]), spells(b[1])
    if x ~= y then return x > y end
    return a[1] < b[1]
  end)
  return c
end
-- set the pair's four relic slots (kit[i] = { slot4, slot5 }) and the bag (a list of { id, count })
local function stage(pair, kit, bag)
  for i, m in ipairs(pair) do for s = 4, 5 do put(0x1600 + 37 * m[1] + 0x1F + s, kit[i][s - 3]) end end
  for s = 0, 255 do put(0x1869 + s, 0xFF); put(0x1969 + s, 0) end
  for i, b in ipairs(bag) do put(0x1869 + i - 1, b[1]); put(0x1969 + i - 1, b[2]) end
end
local function ownedOf(pair)
  local n = H.invCountOf(RIBBON)
  for _, m in ipairs(pair) do for s = 4, 5 do if relicAt(m[1], s) == RIBBON then n = n + 1 end end end
  return n
end

-- step 4b's promises: plan against base (the same threats, 4b off); returns the members it gave a Ribbon
local function spareChecks(plan, base, threats, what, owned)
  local spare = owned - ribbons(base)
  local able = {}
  for _, b in ipairs(base) do
    if not hasRibbon(b) and wears(b.ch, RIBBON) then
      for s = 4, 5 do
        if not kept(b.cur[s], threats) and key(at(b, s), threats) ~= nil then able[b.ch] = true end
      end
    end
  end
  local nAble = 0
  for _ in pairs(able) do nAble = nAble + 1 end
  H.log(string.format("[relicspare] %s: the baseline plans %d Ribbon(s), leaves %d in the bag; %d seated member(s) "
    .. "planned without one can wear one in a slot 4b may take", what, ribbons(base), spare, nAble))
  H.assertEq(ribbons(base) >= 1 and spare >= 1, true, string.format("precondition (%s): the baseline plans a Ribbon "
    .. "and leaves another in the bag", what))
  H.assertEq(nAble >= 1, true, string.format("precondition (%s): a seated member planned without a Ribbon can wear "
    .. "one in a slot step 4b may take", what))
  local gave = {}
  for _, p in ipairs(plan) do
    local b = byCh(base, p.ch)
    for s = 4, 5 do
      if at(p, s) ~= at(b, s) then
        H.assertEq(at(p, s), RIBBON, string.format("%s: the only change 4b makes is a Ribbon (%s's slot %d: $%02X -> "
          .. "$%02X)", what, p.name, s, at(b, s), at(p, s)))
        H.assertEq(able[p.ch] == true and not gave[p.ch], true, string.format("%s: the Ribbon goes on a member planned "
          .. "without one who can wear it, one a member (%s)", what, p.name))
        local k = key(at(b, s), threats)
        H.assertEq(k ~= nil and not kept(p.cur[s], threats), true, string.format("%s: the Ribbon goes over a relic "
          .. "that is not a two-weapon relic, a ward or the Egg (%s's slot %d held $%02X)", what, p.name, s, at(b, s)))
        gave[p.ch] = { s = s, key = k, over = at(b, s) }
      end
    end
  end
  local n = 0
  for _ in pairs(gave) do n = n + 1 end
  H.assertEq(n, math.min(spare, nAble), string.format("%s: 4b puts on min(%d spare, %d able) Ribbon(s)", what, spare,
    nAble))
  -- the lowest-ranked slot: no slot left to a member still without one ranks below a slot 4b took
  for ch, g in pairs(gave) do
    for _, p in ipairs(plan) do
      if able[p.ch] and not hasRibbon(p) then
        for s = 4, 5 do
          local k = not kept(p.cur[s], threats) and key(at(p, s), threats) or nil
          H.assertEq(k == nil or k >= g.key, true, string.format("%s: 4b took %s's slot %d ($%02X, rank %d), the "
            .. "lowest-ranked; %s's slot %d ($%02X) ranks %s", what, NAMES[ch], g.s, g.over, g.key, p.name, s,
            at(p, s), tostring(k)))
        end
      end
    end
    H.log(string.format("[relicspare] %s: the spare Ribbon goes on %s's slot %d over $%02X (rank %d)", what,
      NAMES[ch], g.s, g.over, g.key))
  end
  return gave
end

-- the staged pair for cases 1 and 2: two ribbon-wearers and two guards (rank 1, wearable by both and classed a
-- guard under both threat sets), one worn by the first member, the other two by the second
local function guards(pair, ts)
  local g = wearable(pair, ts[1], function(cl) return cl.aff == "guard" end)
  local both = {}
  for _, id in ipairs(g) do
    local cl = H.relicClass(id, ts[2])
    if cl and cl.aff == "guard" then both[#both + 1] = id end
  end
  H.assertEq(#both >= 2, true, "precondition: two guards the pair can wear, ranked guards under the Ice Dragon's "
    .. "threats and without the boss")
  return both[1], both[2]
end

local function bossCase()
  local c = ribbonWearers()
  H.assertEq(#c >= 2, true, "precondition (the Ice Dragon): two seated members can wear a Ribbon")
  local A, B = c[1], c[2]
  local t = { s1 = ICE.s1, s2 = ICE.s2, magic = ICE.magic }
  local g1, g2 = guards({ A, B }, { ICE, t })
  stage({ A, B }, { { RIBBON, g1 }, { g1, g2 } }, { { RIBBON, 1 } })
  local pair = { A, B }
  local owned = ownedOf(pair)
  H.log(string.format("[relicspare] the Ice Dragon: %s wears Ribbon and $%02X, %s $%02X and $%02X, a Ribbon in the bag",
    A[2], g1, B[2], g1, g2))
  local base = H.relicPlan(pair, { threats = ICE, tag = "relicspare ice, 4b off", spareRibbon = false })
  local plan = H.relicPlan(pair, { threats = ICE, tag = "relicspare ice" })
  spareChecks(plan, base, ICE, "the Ice Dragon (a boss)", owned)
end

local function eggCase()
  -- the member behind on levels: the lower-level of two ribbon-wearers (the Egg goes to a member below the
  -- party's highest level)
  local c = ribbonWearers()
  local lo, hi = nil, nil
  for _, m in ipairs(c) do
    if lo == nil or level(m[1]) < level(lo[1]) then lo = m end
    if hi == nil or level(m[1]) > level(hi[1]) then hi = m end
  end
  H.assertEq(lo ~= nil and level(lo[1]) < level(hi[1]), true, "precondition (no boss): two seated members that can "
    .. "wear a Ribbon stand on different levels, so step 3b has a member behind")
  H.assertEq(wears(lo[1], EGG), true, string.format("precondition (no boss): %s (L%d) can wear the Exp. Egg", lo[2],
    level(lo[1])))
  local t = { s1 = ICE.s1, s2 = ICE.s2, magic = ICE.magic }
  local g1, g2 = guards({ hi, lo }, { ICE, t })
  stage({ hi, lo }, { { RIBBON, g1 }, { g1, g2 } }, { { RIBBON, 1 }, { EGG, 1 } })
  local pair = { hi, lo }
  local owned = ownedOf(pair)
  local base = H.relicPlan(pair, { threats = t, tag = "relicspare no boss, 4b off", spareRibbon = false })
  local egg = nil
  for _, b in ipairs(base) do
    for s = 4, 5 do if at(b, s) == EGG and egg == nil then egg = { p = b, s = s } end end
  end
  H.assertEq(egg ~= nil, true, "precondition (no boss): step 3b plans the Exp. Egg on a seated member")
  H.assertEq(not hasRibbon(egg.p) and wears(egg.p.ch, RIBBON), true, string.format("precondition (no boss): the "
    .. "Egg's wearer, %s (L%d), is planned without a Ribbon and can wear one", egg.p.name, level(egg.p.ch)))
  local plan = H.relicPlan(pair, { threats = t, tag = "relicspare no boss" })
  spareChecks(plan, base, t, "no boss", owned)
  H.assertEq(at(byCh(plan, egg.p.ch), egg.s), EGG, string.format("no boss: the Egg stays on %s's slot %d; the "
    .. "spare Ribbon does not take it", egg.p.name, egg.s))
  -- the exclusion is what keeps it: with the Egg allowed, the Ribbon takes the Egg's slot
  local real = H.ribbonMayDisplace
  H.ribbonMayDisplace = function(cl) return cl ~= nil and not cl.hands and cl.aff ~= "ward" end
  local ok, mplan = pcall(H.relicPlan, pair, { threats = t, tag = "relicspare no boss, the Egg not excluded" })
  H.ribbonMayDisplace = real
  H.assertEq(ok, true, "the mutant's plan runs: " .. tostring(mplan))
  H.assertEq(at(byCh(mplan, egg.p.ch), egg.s), RIBBON, string.format("the exclusion is reached: with the Egg "
    .. "allowed, the spare Ribbon goes over it on %s's slot %d", egg.p.name, egg.s))
  H.log(string.format("[relicspare] PASSED: 4b arming for a boss, and the Egg kept on %s with a spare Ribbon",
    egg.p.name))
end

-- the ward clause: the caster (the most spells; the plan serves wards to her first) in two wards, another member
-- with a Ribbon, a spare Ribbon in the bag
local function wardCase()
  local c = ribbonWearers()
  H.assertEq(#c >= 2, true, "precondition (wards): two seated members can wear a Ribbon")
  local Wm, Rm = c[1], c[2]
  H.assertEq(spells(Wm[1]) > spells(Rm[1]), true, string.format("precondition (wards): the caster %s (%d spells) "
    .. "learned more than %s (%d), so the plan serves the wards to %s first", Wm[2], spells(Wm[1]), Rm[2],
    spells(Rm[1]), Wm[2]))
  local wards = wearable({ Wm, Rm }, ICE, function(cl) return cl.aff == "ward" end)
  H.assertEq(#wards >= 1, true, "precondition (wards): an item the Ice Dragon's threats rank as a ward that both "
    .. "can wear")
  local wardId = wards[1]
  stage({ Wm, Rm }, { { 0xFF, 0xFF }, { 0xFF, 0xFF } }, { { RIBBON, 2 }, { wardId, 2 } })
  local two = { Wm, Rm }
  local owned2 = ownedOf(two)
  local base2 = H.relicPlan(two, { threats = ICE, tag = "relicspare wards (two members), 4b off", spareRibbon = false })
  local plan2 = H.relicPlan(two, { threats = ICE, tag = "relicspare wards (two members)" })
  local w0, w1 = byCh(base2, Wm[1]), byCh(plan2, Wm[1])
  H.log(string.format("[relicspare] wards: %s and %s, ward $%02X; the baseline plans %d of %d Ribbon(s); %s planned "
    .. "$%02X/$%02X", Wm[2], Rm[2], wardId, ribbons(base2), owned2, Wm[2], at(w0, 4), at(w0, 5)))
  H.assertEq(ribbons(base2) >= 1 and owned2 - ribbons(base2) >= 1 and not hasRibbon(w0), true,
    string.format("precondition (wards): on %s and %s the baseline plans a Ribbon, leaves one in the bag and plans "
      .. "%s without one", Wm[2], Rm[2], Wm[2]))
  for s = 4, 5 do
    H.assertEq(at(w0, s), wardId, string.format("precondition (wards): %s's slot %d is planned the ward ($%02X)",
      Wm[2], s, at(w0, s)))
    H.assertEq(at(w1, s), at(w0, s), string.format("wards: the spare Ribbon does not go over %s's ward in slot %d "
      .. "($%02X)", Wm[2], s, at(w0, s)))
  end
  H.assertEq(ribbons(plan2), ribbons(base2), "wards: the spare Ribbon stays in the bag (no slot 4b may take)")
  H.log(string.format("[relicspare] wards: the spare Ribbon stays in the bag; %s keeps $%02X/$%02X", Wm[2], at(w1, 4),
    at(w1, 5)))
end

H.run({ maxFrames = 3000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(read),
  H.call(bossCase),
  H.call(eggCase),
  H.call(wardCase),
})
