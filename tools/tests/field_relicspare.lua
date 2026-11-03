-- @suite savestate=wor_narshe
-- field_relicspare.lua -- the relic plan's step 4b (a Ribbon the plan leaves in the bag goes on after all) arming
-- for a boss, and its Exp. Egg exclusion with a spare Ribbon in hand (#499), read on wor_narshe (gen_wor_narshe:
-- the seated party on the Narshe cliffs' save point before the Ice Dragon, two Ribbons and the Egg among them, the
-- bag as the leg left it).
--
-- H.relicPlan reads only and logs its decisions; nothing here presses a button or writes emulated state.  Each case
-- reads the plan against the same threats' plan with step 4b off (opts.spareRibbon = false, the baseline), and
-- every expectation is derived from the fixture's live state, each precondition asserted by name first:
--   1. the Ice Dragon's threats (gen_wor_tritoch's ICE_THREATS: magic, no status, a boss): the baseline leaves a
--      Ribbon in the bag (the caster's Ribbon slot goes to a ward) while a seated member planned without one can
--      wear it; the plan puts on min(spare, such members) more Ribbons, one a member, each over the lowest-ranked
--      relic planned there that is not a two-weapon relic, a ward or the Egg, and changes nothing else;
--   2. the same threats with no boss named: step 3b puts the Egg on the member furthest behind, and the baseline
--      leaves a Ribbon in the bag that member can wear.  The Egg stays (4b's exclusion), the Ribbon goes over the
--      member's other relic or on another member; and the exclusion is what keeps it: with H.ribbonMayDisplace
--      switched to allow the Egg, the Ribbon goes over the Egg (the fixture reaches the exclusion).
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

local members, owned = {}, 0
local function read()
  local act = H.readByte(0x1A6D) & 7
  for ch = 0, 13 do
    if (H.readByte(0x1850 + ch) & 7) == act then
      members[#members + 1] = { ch, NAMES[ch] }
      for s = 4, 5 do if relicAt(ch, s) == RIBBON then owned = owned + 1 end end
    end
  end
  owned = owned + H.invCountOf(RIBBON)
  H.log(string.format("[relicspare] seated %d; %d Ribbon(s) in the bag or on seated members", #members, owned))
  H.assertEq(owned >= 2, true, "precondition: the party holds two or more Ribbons in the bag or on seated members "
    .. "(step 4b places the Ribbons after the first)")
end

-- step 4b's promises: plan against base (the same threats, 4b off); returns the members it gave a Ribbon
local function spareChecks(plan, base, threats, what)
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

H.run({ maxFrames = 3000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(read),
  H.call(function()
    -- 1. arming for a boss
    local base = H.relicPlan(members, { threats = ICE, tag = "relicspare ice, 4b off", spareRibbon = false })
    local plan = H.relicPlan(members, { threats = ICE, tag = "relicspare ice" })
    spareChecks(plan, base, ICE, "the Ice Dragon (a boss)")
  end),
  H.call(function()
    -- 2. the Egg on, a spare Ribbon in hand
    local t = { s1 = ICE.s1, s2 = ICE.s2, magic = ICE.magic }
    local base = H.relicPlan(members, { threats = t, tag = "relicspare no boss, 4b off", spareRibbon = false })
    local egg = nil
    for _, b in ipairs(base) do
      for s = 4, 5 do if at(b, s) == EGG and egg == nil then egg = { p = b, s = s } end end
    end
    H.assertEq(egg ~= nil, true, "precondition (no boss): step 3b plans the Exp. Egg on a seated member")
    H.assertEq(not hasRibbon(egg.p) and wears(egg.p.ch, RIBBON), true, string.format("precondition (no boss): the "
      .. "Egg's wearer, %s (L%d), is planned without a Ribbon and can wear one", egg.p.name, level(egg.p.ch)))
    local plan = H.relicPlan(members, { threats = t, tag = "relicspare no boss" })
    spareChecks(plan, base, t, "no boss")
    H.assertEq(at(byCh(plan, egg.p.ch), egg.s), EGG, string.format("no boss: the Egg stays on %s's slot %d; the "
      .. "spare Ribbon does not take it", egg.p.name, egg.s))
    -- the exclusion is what keeps it: with the Egg allowed, the Ribbon takes the Egg's slot
    local real = H.ribbonMayDisplace
    H.ribbonMayDisplace = function(cl) return cl ~= nil and not cl.hands and cl.aff ~= "ward" end
    local ok, mplan = pcall(H.relicPlan, members, { threats = t, tag = "relicspare no boss, the Egg not excluded" })
    H.ribbonMayDisplace = real
    H.assertEq(ok, true, "the mutant's plan runs: " .. tostring(mplan))
    H.assertEq(at(byCh(mplan, egg.p.ch), egg.s), RIBBON, string.format("the fixture reaches the exclusion: with the "
      .. "Egg allowed, the spare Ribbon goes over it on %s's slot %d", egg.p.name, egg.s))
    H.log(string.format("[relicspare] PASSED: 4b arming for a boss, and the Egg kept on %s with a spare Ribbon",
      egg.p.name))
  end),
})
