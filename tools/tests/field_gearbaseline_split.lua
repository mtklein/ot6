-- @suite savestate=wor_kt_guardian
-- field_gearbaseline_split.lua -- the gear baseline across a split dungeon's parties (#524 review: party 1's Barrier
-- Rings stayed on through three of Kefka's Tower's saves while another party walked).  The fixture, wor_kt_guardian
-- (gen_wor_kt_guardian's end: the parties spread through the tower, just saved, so at its baseline), supplies two
-- or more parties and an overlay relic in the bag; each precondition is asserted by name first.  Every change is
-- made through the menus (the party switch, the Relic menu):
--   0. the fixture: the dress, then no violation;
--   1. a party that is not walking wears an overlay relic (put on while it walked, then the walking party back):
--      red, "in party N, wears the overlay relic"; the walking party's dress takes it off that party's member
--      (switching to it and back), green, and the same party walks after;
--   2. an overlay declared open while its relic is still worn on that other party: the dress closes it only once the
--      relic is off (the registry reads empty after, and the relic is in no party's slot).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_kt_guardian.mss.lua"
local OVERLAY = { [0xBB] = "Wall Rings", [0xB7] = "Barrier Rings", [0xDC] = "Safety Bit" }
local function rec(ch, off) return H.readByte(0x1600 + 37 * ch + off) end
local walking, other, who, item, slot = nil, nil, nil, nil, nil
local function violations()
  local v = H.gearBaselineViolations()
  for _, l in ipairs(v) do H.log("[gbsplit] violation: " .. l) end
  return v
end
local function has(v, pat)
  for _, l in ipairs(v) do if l:find(pat, 1, true) then return true end end
  return false
end
local function stage()
  return H.lazy(function()
    local label = string.format("1: $%02X on %s (party %d)", item, H.SPLIT_NAMES[who], other)
    return H.seqStep({
      H.switchParty(other, { tag = "1: party " .. other .. " walks" }),
      H.keepGear(who, label, H.equipKit(who, { { slot, item } }, { tag = label })),
      H.call(function() H.assertEq(rec(who, 0x1F + slot), item, label .. ": worn") end),
      H.switchParty(walking, { tag = "1: party " .. walking .. " walks again" }),
    })
  end)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    walking = H.activeParty()
    local ps = H.partyNumbers()
    H.assertEq(#ps >= 2, true, "precondition: two or more parties (a split dungeon)")
    H.assertEq((H.readByte(0x1EB9) & 0x40) ~= 0, true, "precondition: party switching is on ($1EB9 bit 6)")
    for _, p in ipairs(ps) do if p ~= walking and other == nil then other = p end end
    for id in pairs(OVERLAY) do if item == nil and H.invCountOf(id) > 0 then item = id end end
    H.assertEq(item ~= nil, true, "precondition: an overlay relic in the bag (the Barrier Rings the saves take off)")
    local ip = H.sym("ItemProp") & 0x3FFFFF
    for _, ch in ipairs(H.partyRoster(other)) do
      if who == nil and ch <= 13 and not H.relicMenuRefuses(ch)
         and (((H.readRomByte(ip + item * 30 + 1) | (H.readRomByte(ip + item * 30 + 2) << 8)) >> ch) & 1) == 1 then
        for s = 4, 5 do
          local cur = rec(ch, 0x1F + s)
          local cl = cur ~= 0xFF and H.relicClass(cur) or nil
          if slot == nil and not H.gearIsPrize(cur) and not (cl and cl.hands) then who, slot = ch, s end
        end
        if slot == nil then who = nil end
      end
    end
    H.assertEq(who ~= nil, true, "precondition: a member of the other party can wear it in a free relic slot")
    H.log(string.format("[gbsplit] walking party %d; party %d's %s takes $%02X in slot %d", walking, other,
      H.SPLIT_NAMES[who], item, slot))
  end),
  -- 0. the fixture, dressed (the save made it at its baseline; the dress then changes nothing)
  H.gearBaseline({ tag = "0: the fixture" }),
  H.call(function()
    local v = violations()
    H.assertEq(#v, 0, "0: the fixture is at its baseline (" .. table.concat(v, "; ") .. ")")
  end),
  -- 1. another party's overlay relic
  stage(),
  H.call(function()
    H.assertEq(H.activeParty(), walking, "1: the walking party walks again")
    local v = violations()
    H.assertEq(has(v, string.format("in party %d, wears the overlay relic $%02X", other, item)), true,
      "1: a violation names the other party's overlay relic (" .. table.concat(v, "; ") .. ")")
    H.assertEq(pcall(H.assertGearBaseline, "1"), false, "1: H.assertGearBaseline fails")
    H.log("[gbsplit] 1: RED as it should be")
  end),
  -- 2. declared open while it is worn there
  H.call(function() H.gearOverlaysOpen = {} end),
  H.lazy(function() return H.overlayOn(OVERLAY[item], "field_gearbaseline_split case 2") end),
  H.call(function()
    H.assertEq(H.gearOverlayWorn(OVERLAY[item]), true, "2: the overlay's relic is worn (on party " .. other .. ")")
  end),
  H.gearBaseline({ tag = "1: the dress" }),
  H.call(function()
    H.assertEq(H.activeParty(), walking, "1: the walking party walks after the dress")
    H.assertEq(rec(who, 0x23) ~= item and rec(who, 0x24) ~= item, true, string.format("1: %s's $%02X came off",
      H.SPLIT_NAMES[who], item))
    H.assertEq(#violations(), 0, "1: no violation after the dress")
    H.assertEq(H.gearOverlaysOpen[OVERLAY[item]], nil, "2: the overlay closed once its relic came off")
    H.assertEq(H.gearOverlayWorn(OVERLAY[item]), false, "2: its relic is on no party's member")
    H.log("[gbsplit] PASSED: another party's overlay relic is red, and the dress takes it off that party")
  end),
})
