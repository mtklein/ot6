-- @suite savestate=wor_dino
-- field_gearbaseline.lua -- the gear baseline every save holds (#524; lib/ot6_field.lua "the gear baseline"): its
-- assert goes red on each kind of violation, and the dress returns the party to it.  The fixture, wor_dino
-- (gen_wor_dino's end: the party on the Falcon's tile by the dinosaur forest, just saved, so at its baseline),
-- supplies a party with the Colosseum's Economizer and the route's Ribbons, the Wall Rings in the bag and members
-- waiting aboard; each precondition is asserted by name first.  Every change below is made through the Relic and
-- Equip menus (presses only), so the party moves away from the baseline the way a player's hand would move it:
--   0. the fixture: H.gearBaseline changes nothing it should not and its assert passes;
--   1. an overlay left open (H.overlayOn with nothing taken off): red, "the overlay ... is still on";
--   2. an overlay relic left on: a Wall Ring put on a member's slot: red; H.gearBaseline takes it off, green;
--   3. a Ribbon left in the bag: the healer's Ribbon taken off (the Relic menu's Remove): red; the dress puts it
--      back on the healer, green;
--   4. a prize on a member waiting aboard: the check read through a reader that has an aboard member wear a Ribbon
--      (the field menu cannot reach an aboard member, so no press can stage it): red;
--   5. a member below the bag's best: a worse armor or helmet from the bag put on: red; the dress, green;
--   6. the healer rule's mutant (H.gearHealer naming another member), with one Ribbon held in the bag so the Ribbons
--      are fewer than the members who can wear one: the dress under it puts the first Ribbon elsewhere, and the real
--      rule's assert goes red; the dress under the real rule, green; the Ribbon released, green;
--   7. the Economizer by expected MP spent (owner, 2026-11-11): a history (H.mpSpent, the run's tally of spells
--      cast, set as the battle observers would leave it) naming a caster with a small pool: red, the rule names
--      him; the old largest-pool rule's dress (the mutant) stays red; the dress, green, the relic on him; the history
--      gone, the wearer keeps it, green; the relic off into the bag, the rule names the main caster (the highest
--      magic with a spell), red; the dress, green;
--   8. the Exp. Egg, a prize (#524 review): on the seated member furthest behind on levels after the dress; taken off
--      into the bag, red; the dress, green; and on a member waiting aboard (the reader, as 4), red;
--   9. a prize's slot (H.gearPrizeSlotKey): a Ribbon or the Economizer never takes a slot where the Egg stays, nor a
--      two-weapon relic's; the mutant keyed on rank alone (the first landing's) would take the Egg's (rank 0);
--  10. the contracts' items (H.contractDiffs): an item a seated member wears counts as held; one the party does not
--      own does not (the negative control); and a named wearer stays the only one that counts.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_dino.mss.lua"
local RIBBON, ECONOMIZER, WALL_RING, EGG = 0xCA, 0xCE, 0xBB, 0xE4
local function rec(ch, off) return H.readByte(0x1600 + 37 * ch + off) end
local function violations(opts)
  local v = H.gearBaselineViolations(opts)
  for _, l in ipairs(v) do H.log("[gbtest] violation: " .. l) end
  return v
end
local function has(v, pat)
  for _, l in ipairs(v) do if l:find(pat, 1, true) then return true end end
  return false
end
-- red: the assert fails, and a violation names `pat`
local function red(what, pat, opts)
  return H.call(function()
    local v = violations(opts)
    H.assertEq(has(v, pat), true, string.format("%s: a violation names %q (got %d: %s)", what, pat, #v,
      table.concat(v, "; ")))
    local ok = pcall(H.assertGearBaseline, what, opts)
    H.assertEq(ok, false, what .. ": H.assertGearBaseline fails")
    H.log(string.format("[gbtest] RED as it should be: %s", what))
  end)
end
local function green(what)
  return H.call(function()
    local v = violations()
    H.assertEq(#v, 0, what .. ": no violation (" .. table.concat(v, "; ") .. ")")
    H.assertGearBaseline(what)
    H.log(string.format("[gbtest] green: %s", what))
  end)
end
local ms, healer, ribbonSlot, spare = nil, nil, nil, nil
local function members() return H.gearBaselineMembers(true) end
-- 5's staging: a member, an armor slot and a bag piece that fits and scores below what is worn
local worse = nil
local function findWorse()
  for _, m in ipairs(members()) do
    if H.charActor(m.ch) <= 12 then
      for _, slot in ipairs({ 3, 2 }) do
        local wornV = H.gearValue(m.ch, rec(m.ch, 0x1F + slot))
        for s = 0, 255 do
          local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
          if id ~= 0xFF and n > 0 and worse == nil then
            local t = H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30) & 7
            local mask = H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + 1)
              | (H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + 2) << 8)
            if t == (slot == 3 and 2 or 4) and ((mask >> m.ch) & 1) == 1 and H.gearValue(m.ch, id) < wornV then
              worse = { m = m, slot = slot, id = id, was = rec(m.ch, 0x1F + slot) }
            end
          end
        end
      end
    end
  end
  return worse
end

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    ms = members()
    healer = H.gearHealer(ms)
    H.log(string.format("[gbtest] seated %d; healer %s; Ribbons in the bag %d; Economizer in the bag %d; Wall Rings "
      .. "in the bag %d; %s", #ms, healer and healer.name or "none", H.invCountOf(RIBBON), H.invCountOf(ECONOMIZER),
      H.invCountOf(WALL_RING), H.gearBaselineLine()))
    H.assertEq(#ms >= 3, true, "precondition: three or more seated members the menus take")
    H.assertEq(healer ~= nil, true, "precondition: a seated member can cast a Cure (the healer)")
    H.assertEq(H.invCountOf(WALL_RING) > 0, true, "precondition: a Wall Ring in the bag (gen_wor_ragnarok's chest)")
    local pp = H.gearPrizePlan(ms)
    H.assertEq(pp.owned[RIBBON] >= 1, true, "precondition: the party owns a Ribbon")
    H.assertEq(pp.owned[ECONOMIZER] >= 1, true, "precondition: the party owns the Economizer (gen_wor_colosseum)")
    local aboard = 0
    for ch = 0, 13 do
      local sw = 0x02F0 + ch
      if (H.readByte(0x1E80 + (sw >> 3)) >> (sw & 7)) & 1 == 1 and (H.readByte(0x1850 + ch) & 7) == 0 then
        aboard = aboard + 1
      end
    end
    H.assertEq(aboard >= 1, true, "precondition: a member waits aboard the Falcon")
  end),
  -- 0. the fixture, at its baseline after the dress
  H.gearBaseline({ tag = "0: the fixture" }),
  green("0: the fixture"),
  H.call(function()
    for s = 4, 5 do if rec(healer.ch, 0x1F + s) == RIBBON then ribbonSlot = s end end
    H.assertEq(ribbonSlot ~= nil, true, "0: the healer " .. healer.name .. " wears the first Ribbon")
    -- 2's member: a seated member with a slot holding neither a prize nor a two-weapon relic
    for _, m in ipairs(members()) do
      for s = 4, 5 do
        local cur = rec(m.ch, 0x1F + s)
        local cl = cur ~= 0xFF and H.relicClass(cur) or nil
        if spare == nil and not H.gearIsPrize(cur) and not (cl and cl.hands) then spare = { m = m, slot = s } end
      end
    end
    H.assertEq(spare ~= nil, true, "precondition: a seated member has a relic slot with no prize or two-weapon relic")
  end),
  -- 1. an overlay left open
  H.overlayOn("Wall Rings", "field_gearbaseline case 1"),
  red("1: an overlay left open", "the overlay Wall Rings is still on"),
  H.overlayOff("Wall Rings"),
  green("1: the overlay closed"),
  -- 2. an overlay relic left on
  H.lazy(function()
    local label = "2: a Wall Ring on " .. spare.m.name
    return H.keepGear(spare.m.ch, label, H.equipKit(spare.m.ch, { { spare.slot, WALL_RING } }, { tag = label }))
  end),
  red("2: a Wall Ring left on", "wears the overlay relic $BB"),
  H.gearBaseline({ tag = "2: the dress" }),
  green("2: the Wall Ring off"),
  -- 3. a Ribbon left in the bag
  H.lazy(function()
    local label = "3: the healer's Ribbon off"
    return H.keepGear(healer.ch, label, H.unequipRelics(healer.ch, { ribbonSlot }, { tag = label }))
  end),
  H.lazy(function() return red("3: a Ribbon in the bag", "the rule puts the Ribbon $CA on " .. healer.name) end),
  H.gearBaseline({ tag = "3: the dress" }),
  green("3: the Ribbon back on the healer"),
  -- 4. a prize on a member waiting aboard
  H.lazy(function()
    local who = nil
    for ch = 0, 13 do
      local sw = 0x02F0 + ch
      if who == nil and (H.readByte(0x1E80 + (sw >> 3)) >> (sw & 7)) & 1 == 1 and (H.readByte(0x1850 + ch) & 7) == 0 then
        who = ch
      end
    end
    local reader = function(ch, s) if ch == who and s == 5 then return RIBBON end return rec(ch, 0x1F + s) end
    return red("4: a Ribbon on " .. H.SPLIT_NAMES[who] .. " aboard", "waiting aboard in no party, wears the Ribbon",
      { aboard = reader })
  end),
  -- 5. a member below the bag's best
  H.lazy(function()
    H.assertEq(findWorse() ~= nil, true, "precondition: the bag holds an armor or helmet worse than a member wears")
    H.log(string.format("[gbtest] 5: %s slot %d $%02X (value %d) -> $%02X (value %d)", worse.m.name, worse.slot, worse.was,
      H.gearValue(worse.m.ch, worse.was), worse.id, H.gearValue(worse.m.ch, worse.id)))
    return H.equipKit(worse.m.ch, { { worse.slot, worse.id } }, { tag = "5: a worse piece on " .. worse.m.name })
  end),
  H.lazy(function() return red("5: a worse piece on " .. worse.m.name, "the gear rule puts") end),
  H.gearBaseline({ tag = "5: the dress" }),
  green("5: the best back on"),
  -- 6. the healer rule's mutant.  The rule shows only where the Ribbons are fewer than the members who can take one:
  -- wor_dino with EDGAR seated has three Ribbons and three such members (EDGAR's two relic slots hold the Egg and the
  -- Economizer, prizes that stay), so the healer's Ribbon goes into the bag through the Relic menu and is held there
  -- (H.reservePrize), leaving two for three, and the mutant names one of those the real plan leaves without
  H.lazy(function()
    local label, slot = "6: the healer's Ribbon off, held in the bag", nil
    for s = 4, 5 do if rec(healer.ch, 0x1F + s) == RIBBON then slot = s end end
    H.assertEq(slot ~= nil, true, "6: the healer " .. healer.name .. " wears a Ribbon after case 5's dress")
    return H.keepGear(healer.ch, label, H.unequipRelics(healer.ch, { slot }, { tag = label }))
  end),
  -- all but one held: the Ribbons the party owns (the line's count moves: four at f916b884, where two for three
  -- let the mutant's dress land on a state the real rule also keeps), so the healer's is the only one in play
  H.lazy(function()
    local n = H.invCountOf(RIBBON)
    for _, m in ipairs(members()) do
      for s = 4, 5 do if rec(m.ch, 0x1F + s) == RIBBON then n = n + 1 end end
    end
    H.log(string.format("[gbtest] 6: the party owns %d Ribbon(s); %d held", n, n - 1))
    H.assertEq(n >= 2, true, "precondition 6: two Ribbons or more, so one held leaves a choice")
    return H.reservePrize(RIBBON, n - 1, "field_gearbaseline case 6: one Ribbon in play")
  end),
  H.lazy(function()
    H.realHealer = H.gearHealer
    local realPlan = H.gearPrizePlan(members())
    local ribboned = {}
    for _, t in ipairs(realPlan.targets) do if t.id == RIBBON then ribboned[t.m.ch] = true end end
    local function canTake(ch)
      for s = 4, 5 do
        if H.gearPrizeSlotKey(rec(ch, 0x1F + s), RIBBON, true) ~= nil then return true end
      end
      return false
    end
    local cands = {}
    local o = H.gearStatusOrder(members())
    for i = #o, 1, -1 do
      if o[i].ch ~= healer.ch and not ribboned[o[i].ch] and canTake(o[i].ch) then cands[#cands + 1] = o[i] end
    end
    H.assertEq(#cands > 0, true, "precondition 6: a member who can take a Ribbon and gets none from the real plan")
    -- the real rule keeps a worn prize where its plan can, so a mutant's dress can land on a state the real rule
    -- also accepts (the #328 line at f916b884: the mutant named EDGAR, and its dress, EDGAR, CYAN and TERRA in
    -- Ribbons, read clean: 'a violation names "the rule puts the Ribbon $CA on" (got 0: )').  Such a mutant
    -- proves nothing either way: the dress goes back to the real rule's and the next candidate is named
    local function try(i)
      local pick = cands[i]
      return H.seqStep({
        H.call(function()
          H.log(string.format("[gbtest] 6: the mutant's healer: %s", pick.name))
          H.gearHealer = function(m)
            for _, x in ipairs(m) do if x.ch == pick.ch then return x end end
            return H.realHealer(m)
          end
        end),
        H.gearBaseline({ tag = "6: the dress under the healer mutant" }),
        H.call(function() H.gearHealer = H.realHealer end),
        H.lazy(function()
          if has(violations(), "the rule puts the Ribbon $CA on") or i == #cands then
            return red("6: the healer mutant's dress, read by the real rule", "the rule puts the Ribbon $CA on")
          end
          H.log(string.format("[gbtest] 6: %s as healer dresses a state the real rule accepts; the next", pick.name))
          return H.seqStep({ H.gearBaseline({ tag = "6: back to the real rule" }), try(i + 1) })
        end),
      })
    end
    return try(1)
  end),
  H.gearBaseline({ tag = "6: the dress under the real rule" }),
  green("6: the real rule"),
  H.reservePrize(RIBBON, 0),
  H.gearBaseline({ tag = "6: the held Ribbon back" }),
  green("6: the held Ribbon back on"),
  -- 7. the Economizer: by MP spent this run, else its wearer, else the main caster
  H.call(function()
    -- the fixture's history is empty (the load starts it again); its wearer keeps the relic
    H.assertEq(next(H.mpSpent) == nil, true, "7: no casts this run after the load")
    local wearer, spender = nil, nil
    for _, m in ipairs(members()) do
      if rec(m.ch, 0x23) == ECONOMIZER or rec(m.ch, 0x24) == ECONOMIZER then wearer = m end
    end
    H.assertEq(wearer ~= nil, true, "7: a seated member wears the Economizer after the dress")
    -- the spender: a seated member, not the wearer and not the old rule's pick (the largest pool among members with
    -- a learned spell), the smallest MP pool.  A granted spell counts as a cast (the stones grant spells while worn:
    -- wor_dino's EDGAR paid 765 MP for his), so the spender need not have learned one; with EDGAR seated the only
    -- learner is TERRA, the old rule's pick, and a learner-only spender was TERRA too, so the mutant matched the rule
    local oldPick = nil
    for _, m in ipairs(members()) do
      if m.ch <= 11 and H.gearSpellsLearned(m.ch) > 0
         and (oldPick == nil or H.charMaxMp(m.ch) > H.charMaxMp(oldPick.ch)) then oldPick = m end
    end
    -- (and a relic slot the Economizer may take: not a two-weapon relic, not another prize that stays)
    local function slotFor(ch)
      for s = 4, 5 do
        if H.gearPrizeSlotKey(rec(ch, 0x1F + s), ECONOMIZER, true) ~= nil then return true end
      end
      return false
    end
    for _, m in ipairs(members()) do
      if m.ch ~= wearer.ch and m.ch <= 11 and (oldPick == nil or m.ch ~= oldPick.ch) and H.charMaxMp(m.ch) > 0
         and slotFor(m.ch) and (spender == nil or H.charMaxMp(m.ch) < H.charMaxMp(spender.ch)) then spender = m end
    end
    H.assertEq(spender ~= nil, true, "precondition: a seated member other than the Economizer's wearer and the old "
      .. "rule's pick")
    H.log(string.format("[gbtest] 7: wearer %s (MP %d), spender %s (MP %d)", wearer.name, H.charMaxMp(wearer.ch),
      spender.name, H.charMaxMp(spender.ch)))
    -- recent play: the spender cast 3 x 20 MP of spells, the wearer one 5 MP spell (the observers' tally, set as
    -- the battle hooks would have left it)
    H.mpSpent = { [H.charActor(spender.ch)] = 60, [H.charActor(wearer.ch)] = 5 }
    H.vars.econ = { wearer = wearer, spender = spender }
  end),
  H.lazy(function()
    return red("7: the spender's history", "the rule puts the Economizer $CE on " .. H.vars.econ.spender.name .. "'s")
  end),
  -- the mutant: the old rule, the largest MP pool; its dress leaves the relic off the spender
  H.call(function()
    H.realMp = H.gearMpOrder
    H.gearMpOrder = function(ms2)
      local o = {}
      for _, m in ipairs(ms2) do o[#o + 1] = m end
      table.sort(o, function(a, b)
        local ka = H.gearSpellsLearned(a.ch) > 0 and H.charMaxMp(a.ch) or -1
        local kb = H.gearSpellsLearned(b.ch) > 0 and H.charMaxMp(b.ch) or -1
        if ka ~= kb then return ka > kb end
        return a.order < b.order
      end)
      return o
    end
  end),
  H.gearBaseline({ tag = "7: the dress under the largest-pool mutant" }),
  H.call(function() H.gearMpOrder = H.realMp end),
  H.lazy(function()
    return red("7: the mutant's dress, read by the real rule",
      "the rule puts the Economizer $CE on " .. H.vars.econ.spender.name .. "'s")
  end),
  H.gearBaseline({ tag = "7: the dress under the real rule" }),
  green("7: the real rule"),
  H.call(function()
    local sp = H.vars.econ.spender
    H.assertEq(rec(sp.ch, 0x23) == ECONOMIZER or rec(sp.ch, 0x24) == ECONOMIZER, true,
      "7: the Economizer is on the spender " .. sp.name)
    -- the history gone (a new leg's boot): the wearer keeps it
    H.mpSpent = {}
  end),
  green("7: no history, the wearer kept"),
  -- and no wearer: off into the bag, the main caster takes it (a member with a spell, the highest magic)
  H.lazy(function()
    local sp = H.vars.econ.spender
    local slot = rec(sp.ch, 0x23) == ECONOMIZER and 4 or 5
    local label = "7: the Economizer off " .. sp.name
    return H.keepGear(sp.ch, label, H.unequipRelics(sp.ch, { slot }, { tag = label }))
  end),
  H.lazy(function()
    local main = nil
    for _, m in ipairs(members()) do
      if H.gearSpellsLearned(m.ch) > 0 and (main == nil or rec(m.ch, 0x1D) > rec(main.ch, 0x1D)) then main = m end
    end
    H.vars.econ.main = main
    H.log(string.format("[gbtest] 7: the main caster %s (magic %d)", main.name, rec(main.ch, 0x1D)))
    return red("7: the Economizer in the bag", "the rule puts the Economizer $CE on " .. main.name .. "'s")
  end),
  H.gearBaseline({ tag = "7: the dress, no history" }),
  green("7: the main caster"),
  H.call(function()
    local mc = H.vars.econ.main
    H.assertEq(rec(mc.ch, 0x23) == ECONOMIZER or rec(mc.ch, 0x24) == ECONOMIZER, true,
      "7: the Economizer is on the main caster " .. mc.name)
  end),
  -- 8. the Exp. Egg
  H.call(function()
    local pp = H.gearPrizePlan(members())
    H.assertEq(pp.owned[EGG] >= 1, true, "precondition: the party owns the Exp. Egg (gen_wor_colosseum's chain)")
    -- the lowest level among the members with a slot the Egg may take (a Ribbon that stays and a two-weapon relic
    -- keep theirs: H.gearPrizeSlotKey; wor_dino's CYAN wears both)
    local low, wearer = 255, nil
    for _, m in ipairs(members()) do
      local can = false
      for s = 4, 5 do
        local cur = rec(m.ch, 0x1F + s)
        if cur == EGG or H.gearPrizeSlotKey(cur, EGG, H.gearIsPrize(cur)) ~= nil then can = true end
      end
      if can then low = math.min(low, rec(m.ch, 8)) end
      if rec(m.ch, 0x23) == EGG or rec(m.ch, 0x24) == EGG then wearer = m end
    end
    H.assertEq(wearer ~= nil and rec(wearer.ch, 8) == low, true, string.format("8: the Egg is on a seated member at the "
      .. "lowest level of those with a slot it may take, L%d (%s)", low, wearer and wearer.name or "nobody"))
    H.vars.eggWearer = wearer
  end),
  H.lazy(function()
    local w = H.vars.eggWearer
    local slot = rec(w.ch, 0x23) == EGG and 4 or 5
    local label = "8: the Egg off " .. w.name
    return H.keepGear(w.ch, label, H.unequipRelics(w.ch, { slot }, { tag = label }))
  end),
  red("8: the Exp. Egg in the bag", "the rule puts the Exp. Egg $E4 on"),
  H.gearBaseline({ tag = "8: the dress" }),
  green("8: the Egg back on"),
  H.lazy(function()
    local who = nil
    for ch = 0, 13 do
      local sw = 0x02F0 + ch
      if who == nil and (H.readByte(0x1E80 + (sw >> 3)) >> (sw & 7)) & 1 == 1 and (H.readByte(0x1850 + ch) & 7) == 0 then
        who = ch
      end
    end
    local reader = function(ch, s) if ch == who and s == 4 then return EGG end return rec(ch, 0x1F + s) end
    return red("8: the Exp. Egg on " .. H.SPLIT_NAMES[who] .. " aboard", "waiting aboard in no party, wears the Exp. Egg",
      { aboard = reader })
  end),
  -- 9. a prize's slot
  H.call(function()
    local GENJI = 0xD1
    for _, id in ipairs({ RIBBON, ECONOMIZER }) do
      H.assertEq(H.gearPrizeSlotKey(EGG, id, true), nil, string.format("9: $%02X never takes a slot where the Egg stays", id))
      H.assertEq(H.gearPrizeSlotKey(GENJI, id, false), nil, string.format("9: $%02X never takes a Genji Glove's slot", id))
      H.assertEq(H.gearPrizeSlotKey(EGG, id, false) ~= nil, true, string.format("9: $%02X may take a slot the Egg leaves", id))
    end
    -- the mutant: the first landing's key, the relic's rank (a prize last), with the Egg not counted a prize
    local cl = H.relicClass(EGG)
    local mutantKey = cl and cl.rank or 1.5
    H.assertEq(mutantKey < 100, true, string.format("9: keyed on rank alone the Egg's slot ranks %s, below any acting "
      .. "relic: the mutant would put a Ribbon over it", tostring(mutantKey)))
    H.assertEq(H.ribbonMayDisplace(cl), false, "9: and ribbonMayDisplace forbids it, which the new key keeps")
    H.log("[gbtest] 9: the prize slot rule holds")
  end),
  -- 10. the contracts' items
  H.call(function()
    local worn, wearer = nil, nil
    for _, m in ipairs(members()) do
      for s = 0, 3 do
        local id = rec(m.ch, 0x1F + s)
        if worn == nil and id ~= 0xFF and H.invCountOf(id) == 0 then worn, wearer = id, m end
      end
    end
    H.assertEq(worn ~= nil, true, "precondition: a seated member wears a piece the bag holds none of")
    local unowned = nil
    for id = 0x00, 0x5F do
      if unowned == nil and H.invCountOf(id) == 0 then
        local anyone = false
        for ch = 0, 13 do for s = 0, 5 do if rec(ch, 0x1F + s) == id then anyone = true end end end
        if not anyone then unowned = id end
      end
    end
    H.assertEq(unowned ~= nil, true, "precondition: a weapon id nobody owns")
    local other = nil
    for _, m in ipairs(members()) do if m.ch ~= wearer.ch then other = other or m.ch end end
    local d1 = H.contractDiffs({ items = { { worn, 1, "worn by a seated member" } } })
    local d2 = H.contractDiffs({ items = { { unowned, 1, "owned by nobody (the negative control)" } } })
    local d3 = H.contractDiffs({ items = { { worn, 1, "worn, but another member named", other } } })
    local d4 = H.contractDiffs({ items = { { worn, 1, "worn by the named member", wearer.ch } } })
    H.assertEq(#d1, 0, string.format("10: $%02X on %s counts as held", worn, wearer.name))
    H.assertEq(#d2, 1, string.format("10: $%02X, owned by nobody, does not", unowned))
    H.assertEq(#d3, 1, string.format("10: $%02X with char %d named does not count on %s", worn, other, wearer.name))
    H.assertEq(#d4, 0, string.format("10: $%02X with %s named counts", worn, wearer.name))
    H.log("[gbtest] 10: the contracts' items read as they should")
  end),
  H.call(function() H.log("[gbtest] PASSED: every case red where it should be, and the dress returns to the baseline") end),
})
