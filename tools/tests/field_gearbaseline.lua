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
--   6. the healer rule's mutant (H.gearHealer naming nobody): the dress under it puts the first Ribbon elsewhere,
--      and the real rule's assert goes red; the dress under the real rule, green;
--   7. the Economizer rule's mutant (H.gearMpOrder reversed): the dress under it moves the Economizer to the
--      smallest MP pool, and the real rule's assert goes red; the dress, green.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_dino.mss.lua"
local RIBBON, ECONOMIZER, WALL_RING = 0xCA, 0xCE, 0xBB
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
  -- 6. the healer rule's mutant
  H.call(function()
    H.realHealer = H.gearHealer
    -- the mutant's healer: the member status hurts least (the last the further Ribbons would reach)
    H.gearHealer = function(m)
      local real, o = H.realHealer(m), H.gearStatusOrder(m)
      for i = #o, 1, -1 do if o[i] ~= real then return o[i] end end
      return real
    end
  end),
  H.gearBaseline({ tag = "6: the dress under the healer mutant" }),
  H.call(function() H.gearHealer = H.realHealer end),
  red("6: the healer mutant's dress, read by the real rule", "the rule puts the Ribbon $CA on"),
  H.gearBaseline({ tag = "6: the dress under the real rule" }),
  green("6: the real rule"),
  -- 7. the Economizer rule's mutant
  H.call(function()
    H.realMp = H.gearMpOrder
    H.gearMpOrder = function(m)
      local o = H.realMp(m)
      local r = {}
      for i = #o, 1, -1 do r[#r + 1] = o[i] end
      return r
    end
  end),
  H.gearBaseline({ tag = "7: the dress under the Economizer mutant" }),
  H.call(function() H.gearMpOrder = H.realMp end),
  red("7: the Economizer mutant's dress, read by the real rule", "the rule puts the Economizer $CE"),
  H.gearBaseline({ tag = "7: the dress under the real rule" }),
  green("7: the real rule"),
  H.call(function() H.log("[gbtest] PASSED: every case red where it should be, and the dress returns to the baseline") end),
})
