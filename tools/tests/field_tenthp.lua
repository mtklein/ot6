-- @suite savestate=crescent_landing
-- field_tenthp.lua -- #278: the HP half of field care's Tent rule, priced in
-- gil from what the bag would actually spend.
--
-- The rule (docs/design/supply.md): where the item list offers a Tent (a
-- save point, the world map), one is pitched when the heals the bag would
-- spend filling the party's HP hole -- Tonics first, then Potions, whole
-- items at their ROM prices, the reserve kept -- cost at least the Tent's
-- own price, or when the bag cannot lift a member under the threshold at
-- all.  The first cut priced the hole in Tonics (1200 HP) and applied that
-- after the Tonics ran out, so a party 1143 HP short with 0 Tonics drank
-- five Potions (1500 gil) with ten Tents in the bag
-- (build/attempts/wt/emptybag-anydraw/holes.txt).  field_mpband covers the
-- MP half.
--
-- WHAT IS STAGED.  No shipped fixture arrives hurt (the exit contract ships
-- parties whole), so each branch writes its own hole into the party's HP
-- words, and the bag counts the branch needs (Potions, a Tent) into their
-- slots -- field_mpband's staging, one rule over.  The Tonics are taken out
-- of play with the care's own reserve option (a floor of 99, the bag's
-- cap), not a write.  The plan, the
-- menu walk, the item's acceptance, the bag deltas and the pools afterwards
-- are the game's own, read back.  The holes are derived from the live
-- party's maxima and the expected prices re-derived here from the ROM's
-- item records, so the branches hold for whatever party the fixture
-- carries; each asserts the staging landed where its question is.
--
-- Branches (crescent_landing stands on the world map, so a Tent is on offer):
--   A. Potions only, a hole under 1200 HP that Potions would fill for 1200
--      gil or more: the Tent is pitched, no Potion drunk.  (Red on the
--      Tonic-priced rule, which spent the Potions.)
--   B. The same hole with Tonics: they fill it for under 1200, so they are
--      drunk and the Tent is kept.                       (negative control)
--   C. Tonics, a hole they would fill for 1200 or more: the Tent.
--   D. Potions only, a hole they would fill for under 1200: Potions, the
--      Tent kept.                                        (negative control)
--   E. A's staging with opts.tent = false: Potions, no Tent.
--                                                        (negative control)
--   F. Tonics and Potions both reserved away, one member under the
--      threshold: the bag cannot lift them, so the Tent.
--   G. F's bag, nobody under the threshold: nothing to do, the Tent kept.
--                                                        (negative control)
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/crescent_landing.mss.lua"
local TONIC, POTION, TENT = 0xE8, 0xE9, 0xF7
local THRESH = 0.95

-- the item records, read the way the field item routine reads them
local function itemByte(id, off)
  return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off)
end
local function price(id) return itemByte(id, 0x1C) | (itemByte(id, 0x1D) << 8) end
local function yield(id, mx)
  local f, a = itemByte(id, 0x13), itemByte(id, 0x14)
  if (f & 0x08) == 0 then return 0 end
  return (f & 0x80) ~= 0 and mx * a // 16 or a
end

-- every line the lib logs, for assertions on what the visit said
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end

local function hpAddr(c) return 0x1600 + 37 * c + 9 end

-- the bag slot holding `item`, or an empty one, set to n
local function setCount(item, n)
  local slot = H.invSlotOf(item)
  if slot == nil then
    for s = 0, 255 do
      if H.readByte(0x1869 + s) == 0xFF then slot = s; break end
    end
    H.assertEq(slot ~= nil, true, "an empty bag slot to stage into")
    H.writeByte(0x1869 + slot, item)
  end
  H.writeByte(0x1969 + slot, n)
  H.assertEq(H.invCountOf(item), n, string.format("%d x $%02X staged", n, item))
end

-- Hurt the party by `total` HP, in whole multiples of `unit` per member
-- where the maxima allow, biggest pool first, nobody below 1 HP.  Returns
-- the per-member holes.
local function hurt(total, unit)
  local ms = {}
  for _, c in ipairs(H.partyMembers()) do ms[#ms + 1] = c end
  table.sort(ms, function(a, b) return H.charMaxHp(a) > H.charMaxHp(b) end)
  local holes, left = {}, total
  for pass = 1, 2 do
    for _, c in ipairs(ms) do
      if left > 0 then
        local room = H.charMaxHp(c) - 1 - (holes[c] or 0)
        local take = math.min(left, room)
        if pass == 1 then take = take - take % unit end
        if take > 0 then holes[c] = (holes[c] or 0) + take; left = left - take end
      end
    end
  end
  H.assertEq(left, 0, string.format("the party's pools hold a %d HP hole", total))
  for c, h in pairs(holes) do H.writeWord(hpAddr(c), H.charMaxHp(c) - h) end
  return holes
end

-- what filling these holes costs with one item alone, whole items
local function cost(holes, id)
  local g = 0
  for c, h in pairs(holes) do
    local y = yield(id, H.charMaxHp(c))
    g = g + ((h + y - 1) // y) * price(id)
  end
  return g
end
local function holeSum(holes)
  local s = 0
  for _, h in pairs(holes) do s = s + h end
  return s
end

local function partyLine(what)
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  return string.format("[%s] %s | tonic=%d potion=%d tent=%d", what,
    table.concat(t, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(TENT))
end

local before = {}
local function snap()
  before = { tonic = H.invCountOf(TONIC), potion = H.invCountOf(POTION),
             tent = H.invCountOf(TENT) }
end

local function boot(what)
  return H.seqStep({
    H.loadState(FIX),
    H.waitFrames(30),
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() end,
      600, what .. ": world control", 5),
    H.call(function()
      lines = {}
      H.assertEq(H.worldMode(), true, what .. ": crescent_landing is on the world map")
      for _, c in ipairs(H.partyMembers()) do
        H.assertEq(H.charMp(c) >= H.charMaxMp(c) * 0.25, true, string.format(
          "%s: char %d is above the MP band, so no Tent is due on MP", what, c))
      end
    end),
  })
end

-- the visit, then the world back (a Tent is a visit to map 3 and back)
local function care(tag, opts)
  opts.tag, opts.threshold, opts.tincture = tag, opts.threshold or THRESH, false
  return H.seqStep({
    H.call(snap),
    H.fieldCare(opts),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 3000, tag .. ": back on the world map", 20),
    H.call(function() H.log(partyLine(tag .. " after")) end),
  })
end

local function pitched(tag)
  H.assertEq(said("plan: pitch a Tent"), true, tag .. ": the visit planned the Tent")
  H.assertEq(said("pitched a Tent"), true, tag .. ": and saw the tent event end")
  H.assertEq(H.invCountOf(TENT), before.tent - 1, tag .. ": one Tent spent")
  H.assertEq(H.invCountOf(POTION), before.potion, tag .. ": no Potion spent")
  H.assertEq(H.invCountOf(TONIC), before.tonic, tag .. ": no Tonic spent")
  for _, c in ipairs(H.partyMembers()) do
    H.assertEq(H.charHp(c), H.charMaxHp(c), string.format("%s: char %d at full HP", tag, c))
  end
end
local function kept(tag)
  H.assertEq(said("pitch a Tent"), false, tag .. ": no Tent planned")
  H.assertEq(H.invCountOf(TENT), before.tent, tag .. ": the Tent count did not move")
end

local holesA                          -- A's hole, reused by B and E

H.run({ maxFrames = 300000 }, {
  -- ---- A. Potions only: priced in Potions, the Tent ------------------------
  boot("A"),
  H.call(function()
    setCount(POTION, 30)
    setCount(TENT, 2)
    holesA = hurt(1000, yield(POTION, 9999))
    H.log(partyLine("A staged"))
    H.assertEq(holeSum(holesA) < 1200, true, string.format(
      "A: the hole (%d HP) is under the 1200 the Tonic-priced rule waited for", holeSum(holesA)))
    H.assertEq(cost(holesA, POTION) >= price(TENT), true, string.format(
      "A: Potions would fill it for %d gil, at least the Tent's %d",
      cost(holesA, POTION), price(TENT)))
  end),
  care("A potions", { reserve = { [TONIC] = 99, [POTION] = 4 } }),
  H.call(function() pitched("A") end),

  -- ---- B. the same hole with Tonics: drunk, the Tent kept ------------------
  boot("B"),
  H.call(function()
    setCount(POTION, 30)
    setCount(TENT, 2)
    setCount(TONIC, 60)
    for c, h in pairs(holesA) do H.writeWord(hpAddr(c), H.charMaxHp(c) - h) end
    H.log(partyLine("B staged"))
    H.assertEq(cost(holesA, TONIC) < price(TENT), true, string.format(
      "B: Tonics would fill A's hole for %d gil, under the Tent's %d",
      cost(holesA, TONIC), price(TENT)))
  end),
  care("B tonics", {}),
  H.call(function()
    kept("B")
    H.assertEq(said("used $E8 on char"), true, "B: Tonics did the work")
    H.assertEq(H.invCountOf(POTION), before.potion, "B: no Potion spent")
  end),

  -- ---- C. Tonics, a hole they fill for 1200 or more: the Tent --------------
  boot("C"),
  H.call(function()
    setCount(TENT, 2)
    setCount(TONIC, 60)
    local holes = hurt(1250, yield(TONIC, 9999))
    H.log(partyLine("C staged"))
    H.assertEq(cost(holes, TONIC) >= price(TENT), true, string.format(
      "C: Tonics would fill the %d HP hole for %d gil, at least the Tent's %d",
      holeSum(holes), cost(holes, TONIC), price(TENT)))
  end),
  care("C tonics big", {}),
  H.call(function() pitched("C") end),

  -- ---- D. Potions only, a hole they fill for under 1200 ---------------------
  boot("D"),
  H.call(function()
    setCount(POTION, 30)
    setCount(TENT, 2)
    local holes = hurt(750, yield(POTION, 9999))
    H.log(partyLine("D staged"))
    H.assertEq(cost(holes, POTION) < price(TENT), true, string.format(
      "D: Potions would fill the %d HP hole for %d gil, under the Tent's %d",
      holeSum(holes), cost(holes, POTION), price(TENT)))
  end),
  care("D potions small", { reserve = { [TONIC] = 99, [POTION] = 4 } }),
  H.call(function()
    kept("D")
    H.assertEq(said("used $E9 on char"), true, "D: Potions did the work")
  end),

  -- ---- E. A's staging, the Tent arm off --------------------------------------
  boot("E"),
  H.call(function()
    setCount(POTION, 30)
    setCount(TENT, 2)
    for c, h in pairs(holesA) do H.writeWord(hpAddr(c), H.charMaxHp(c) - h) end
    H.log(partyLine("E staged"))
  end),
  care("E tents off", { tent = false, reserve = { [TONIC] = 99, [POTION] = 4 } }),
  H.call(function()
    kept("E")
    H.assertEq(said("used $E9 on char"), true, "E: Potions did the work")
  end),

  -- ---- F. nothing in the bag can lift a member under the threshold ---------
  boot("F"),
  H.call(function()
    setCount(TENT, 2)
    local holes = hurt(200, 1)
    H.log(partyLine("F staged"))
    local under = false
    for c in pairs(holes) do
      if H.charHp(c) < H.charMaxHp(c) * THRESH then under = true end
    end
    H.assertEq(under, true, "F: a member is under the threshold")
  end),
  care("F stranded", { magic = false,
    reserve = { [TONIC] = 99, [POTION] = 99 } }),
  H.call(function()
    H.assertEq(said("the bag cannot lift everyone"), true, "F: the plan says why")
    pitched("F")
  end),

  -- ---- G. the same bag, nobody under the threshold -------------------------
  boot("G"),
  H.call(function()
    setCount(TENT, 2)
    local holes = hurt(200, 1)
    H.log(partyLine("G staged"))
    for c in pairs(holes) do
      H.assertEq(H.charHp(c) >= H.charMaxHp(c) * 0.5, true,
        string.format("G: char %d is above the 0.5 threshold", c))
    end
  end),
  care("G nobody under", { magic = false, threshold = 0.5,
    reserve = { [TONIC] = 99, [POTION] = 99 } }),
  H.call(function()
    kept("G")
    H.assertEq(said("nothing to do"), true, "G: the visit had nothing to do")
  end),
})
