-- @suite savestate=wor_tomb
-- field_relicplan.lua -- the relic rule's per-fight arming and the Exp. Egg
-- (#351), read on the tomb party (wor_tomb: CELES, SABIN, EDGAR and SETZER
-- on Darill's Tomb's save point, the bag as the leg left it).
--
-- H.relicPlan reads only (the party's records, the bag, the ROM's item
-- records) and logs its decisions; nothing here presses a button or writes
-- emulated state.  Every expectation is derived from the fixture's live
-- state, and each precondition is asserted by name first:
--   1. Dullahan's threats (H.FIGHT_THREATS.dullahan: magic damage, no
--      status a relic guards): a Shell ward the caster -- the member with
--      the most spells learned -- can wear goes on the caster, and no plain
--      guard is planned on the caster's other slots (none covers anything
--      this fight threatens);
--   2. the same threats with `magic` taken out: no ward is ranked, so none
--      is put on from the bag;
--   3. the arc's threats (H.ARC_THREATS["wor-falcon"]): the widest guard
--      goes to the caster, as before #351, and no ward comes out of the bag;
--   4. the Exp. Egg, under each set, read against the same threats' plan
--      with opts.egg = false (the slots before step 3b): on the member
--      furthest behind on levels when one is behind, only into a free slot
--      or over a guard or spare ward that adds no threatened status to its
--      wearer -- never over an acting relic -- and, arming for a boss
--      (Dullahan's threats carry boss = true), not at all while the bag
--      holds another relic the member can wear.
-- The negative controls (a rule switched off, each turning this red) are
-- recorded in the commit that adds the file.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tomb.mss.lua"
local MEMBERS = { { 6, "CELES" }, { 5, "SABIN" }, { 4, "EDGAR" }, { 9, "SETZER" } }
local EGG = 0xE4
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function level(ch) return H.readByte(0x1600 + 37 * ch + 8) end
local function relicAt(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function shell(id) return id ~= 0xFF and ((prop(id, 8) & 0x20) ~= 0 or (prop(id, 13) & 0x01) ~= 0) end
local function spells(ch)
  if ch > 11 then return 0 end
  local n = 0
  for i = 0, 53 do if H.readByte(0x1A6E + 54 * ch + i) == 0xFF then n = n + 1 end end
  return n
end
local function bagHas(pred)
  for s = 0, 255 do
    local id, q = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if q > 0 and id ~= 0xFF and pred(id) then return id end
  end
  return nil
end
local function owned(pred)
  local id = bagHas(pred)
  if id then return id end
  for _, p in ipairs(MEMBERS) do
    for s = 4, 5 do if pred(relicAt(p[1], s)) then return relicAt(p[1], s) end end
  end
  return nil
end
-- the planned relic in a member's slot (the plan's want, else what it wears)
local function planned(plan, ch, s)
  for _, p in ipairs(plan) do
    if p.ch == ch then return p.want[s] or relicAt(ch, s) end
  end
  return nil
end
-- the slots step 4 filled with a leftover (plan[i].filler, by slot)
local function filled(plan, ch, s)
  for _, p in ipairs(plan) do
    if p.ch == ch then return p.filler ~= nil and p.filler[s] == true end
  end
  return false
end
local function covers(id, threats)
  return (prop(id, 6) & (threats.s1 or 0)) | (prop(id, 7) & (threats.s2 or 0))
end
local checked = 0

-- the Egg's promises under one plan, read against the same threats' plan
-- with the Egg left out (opts.egg = false: what the rule puts in each slot
-- before step 3b; the fixture's SETZER already wears the Egg, so what he
-- wears is no baseline)
local function eggChecks(plan, plan0, threats, what)
  local top, low = 0, nil
  for _, p in ipairs(MEMBERS) do if level(p[1]) > top then top = level(p[1]) end end
  for _, p in ipairs(MEMBERS) do
    if level(p[1]) < top and wears(p[1], EGG) and (low == nil or level(p[1]) < level(low[1])) then low = p end
  end
  for _, p in ipairs(MEMBERS) do
    for s = 4, 5 do
      local base, after = planned(plan0, p[1], s), planned(plan, p[1], s)
      -- a slot the Egg-less plan filled only in step 4 (a leftover kept
      -- filled, "a slot nothing above took") was open when the Egg's pass ran
      if after == EGG and base ~= EGG and base ~= 0xFF and not filled(plan0, p[1], s) then
        -- a displacement: never over a threat-critical relic
        H.assertEq(shell(base) and threats.magic == true, false, string.format(
          "%s: the Egg did not displace %s's ward $%02X against this fight's magic", what, p[2], base))
        local others = 0
        local o = planned(plan, p[1], s == 4 and 5 or 4)
        if o ~= nil and o ~= 0xFF then others = covers(o, threats) end
        H.assertEq(covers(base, threats) & ~others, 0, string.format(
          "%s: the Egg did not displace %s's guard $%02X covering a threatened status nothing else on %s covers",
          what, p[2], base, p[2]))
        H.assertEq(level(p[1]) < top, true, string.format(
          "%s: the Egg displaced a relic only on a member behind on levels (%s L%d; the party's highest L%d)",
          what, p[2], level(p[1]), top))
        -- never over an acting relic (the coordinator's call on the review
        -- of f8f9ad66): only a guard or a spare ward gives its slot up
        local bc = H.relicClass(base, threats)
        H.assertEq(bc ~= nil and (bc.aff == "guard" or bc.aff == "spare"), true, string.format(
          "%s: the Egg displaced %s's $%02X, a guard or a spare (not an acting relic: %s)", what, p[2], base,
          bc and tostring(bc.aff) or "unranked"))
        H.assertEq(threats.boss == true, false, string.format(
          "%s: no Egg swap when arming for a boss (%s's slot %d, $%02X)", what, p[2], s, base))
        checked = checked + 1
      end
    end
  end
  if threats.boss then
    -- arming for a boss the Egg keeps a slot only when nothing else the
    -- member can wear is left: here the bag holds another relic for him
    for _, p in ipairs(MEMBERS) do
      for s = 4, 5 do
        if planned(plan, p[1], s) == EGG then
          local other = bagHas(function(id)
            local cl = id ~= EGG and H.relicClass(id, threats) or nil
            return cl ~= nil and not cl.hands and wears(p[1], id)
          end)
          H.assertEq(other, nil, string.format("%s: arming for a boss, the Egg is planned on %s's slot %d only "
            .. "when the bag holds no other relic %s can wear", what, p[2], s, p[2]))
          checked = checked + 1
        end
      end
    end
  end
  if low ~= nil and owned(function(id) return id == EGG end) then
    local on = planned(plan, low[1], 4) == EGG or planned(plan, low[1], 5) == EGG
    -- the lowest member has a slot the Egg may take in the Egg-less plan:
    -- empty, the Egg itself (step 4 kept it), or a guard or spare that adds
    -- no threatened status over its other slot
    local open = false
    for s = 4, 5 do
      local id = planned(plan0, low[1], s)
      local other = planned(plan0, low[1], s == 4 and 5 or 4)
      local cl = id ~= 0xFF and H.relicClass(id, threats) or nil
      if id == 0xFF or id == EGG then open = true
      elseif cl ~= nil and (cl.aff == "guard" or cl.aff == "spare")
         and (covers(id, threats) & ~(other ~= 0xFF and covers(other, threats) or 0)) == 0 then
        open = true
      end
    end
    H.log(string.format("[relicplan] %s: the Egg %s %s (L%d, behind the party's L%d)%s", what,
      on and "is planned on" or "could not go on", low[2], level(low[1]), top,
      open and "" or "; every slot holds something it may not displace"))
    if open and not threats.boss then
      local any = false
      for _, p in ipairs(MEMBERS) do
        if level(p[1]) < top and (planned(plan, p[1], 4) == EGG or planned(plan, p[1], 5) == EGG) then any = true end
      end
      H.assertEq(any, true, string.format("%s: the Egg is planned on a member behind on levels (%s L%d has a "
        .. "slot it may take)", what, low[2], level(low[1])))
      checked = checked + 1
    end
  end
end

H.run({ maxFrames = 3000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    -- the caster: the most spells learned
    local caster = nil
    for _, p in ipairs(MEMBERS) do
      if (H.readByte(0x1850 + p[1]) & 7) ~= 0 and (caster == nil or spells(p[1]) > spells(caster[1])) then caster = p end
    end
    H.assertEq(caster ~= nil and spells(caster[1]) > 0, true, "precondition: a member of the party has spells learned (the caster)")
    local ward = owned(function(id) return shell(id) and wears(caster[1], id) end)
    H.assertEq(ward ~= nil, true, string.format("precondition: the party owns a Shell ward %s can wear "
      .. "(a Czarina Ring, Barrier Ring, Pod Bracelet...)", caster[2]))
    H.log(string.format("[relicplan] the caster is %s (%d spells); the ward owned is $%02X", caster[2],
      spells(caster[1]), ward))

    -- 1. Dullahan's threats
    local dull = H.FIGHT_THREATS.dullahan
    local plan = H.relicPlan(MEMBERS, { threats = dull, tag = "relicplan dullahan" })
    local on = nil
    for s = 4, 5 do if shell(planned(plan, caster[1], s)) then on = planned(plan, caster[1], s) end end
    H.assertEq(on ~= nil, true, string.format("Dullahan's magic: a Shell ward is planned on %s, the caster", caster[2]))
    for s = 4, 5 do
      local id = planned(plan, caster[1], s)
      if id ~= 0xFF and not shell(id) and (prop(id, 12) & 0x38) == 0 then
        H.assertEq(H.relicClass(id, dull) == nil or H.relicClass(id, dull).aff ~= "guard", true, string.format(
          "Dullahan's magic: %s's slot %d is not given to a plain guard ($%02X) over the ward", caster[2], s, id))
      end
    end
    eggChecks(plan, H.relicPlan(MEMBERS, { threats = dull, tag = "relicplan dullahan, egg off", egg = false }),
      dull, "Dullahan")

    -- 2. the same with no magic named: no ward from the bag
    local nomagic = { s1 = dull.s1, s2 = dull.s2 }
    plan = H.relicPlan(MEMBERS, { threats = nomagic, tag = "relicplan no magic" })
    for _, p in ipairs(MEMBERS) do
      for s = 4, 5 do
        local id, was = planned(plan, p[1], s), relicAt(p[1], s)
        if shell(id) and id ~= was then
          H.assertEq(was, 0xFF, string.format("no magic named: the ward $%02X goes on %s only into an empty slot, "
            .. "never over $%02X", id, p[2], was))
        end
      end
    end
    eggChecks(plan, H.relicPlan(MEMBERS, { threats = nomagic, tag = "relicplan no magic, egg off", egg = false }),
      nomagic, "no magic")

    -- 3. the arc's threats: the widest guard to the caster, no ward from the bag
    local arc = H.ARC_THREATS["wor-falcon"]
    plan = H.relicPlan(MEMBERS, { threats = arc, tag = "relicplan arc" })
    local widest, wc = nil, 0
    local function pc(b) local n = 0; while b > 0 do n, b = n + (b & 1), b >> 1 end; return n end
    local function guard(id)
      local cl = H.relicClass(id, arc)
      return cl ~= nil and cl.aff == "guard"
    end
    local pool = {}
    for s = 0, 255 do
      local id, q = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
      if q > 0 and id ~= 0xFF and guard(id) then pool[#pool + 1] = id end
    end
    for _, p in ipairs(MEMBERS) do for s = 4, 5 do if guard(relicAt(p[1], s)) then pool[#pool + 1] = relicAt(p[1], s) end end end
    for _, id in ipairs(pool) do
      local n = pc(covers(id, arc))
      if n > wc and wears(caster[1], id) then widest, wc = id, n end
    end
    if widest then
      H.assertEq(planned(plan, caster[1], 4) == widest or planned(plan, caster[1], 5) == widest, true, string.format(
        "the arc's threats: the widest guard $%02X (%d of them) is planned on %s, the caster", widest, wc, caster[2]))
    end
    for _, p in ipairs(MEMBERS) do
      for s = 4, 5 do
        local id, was = planned(plan, p[1], s), relicAt(p[1], s)
        if shell(id) and id ~= was then
          H.assertEq(was, 0xFF, string.format("the arc: the ward $%02X goes on %s only into an empty slot", id, p[2]))
        end
      end
    end
    eggChecks(plan, H.relicPlan(MEMBERS, { threats = arc, tag = "relicplan arc, egg off", egg = false }),
      arc, "the arc")
    H.log(string.format("[relicplan] PASSED: per-fight wards, the arc's widest guard and %d Egg check(s)", checked))
  end),
})
