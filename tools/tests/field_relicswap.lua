-- @suite savestate=wor_tomb
-- field_relicswap.lua -- H.dressRelics at a relic swap cycle the bag cannot
-- break (#439).  Two members want each other's relic and the bag holds no
-- relic to stand in: the old fallback let the first member keep what he
-- wore and dropped the planned relic ("CYAN keeps Hyper Wrist ...", wor_relm
-- on the v031-robust chain).  The plan has to be met, or fail loudly.
--
-- A synthetic mechanism test (docs/TESTING.md, "Synthetic mechanism
-- tests"): the setup writes the relic slots and empties the bag of relics
-- (state_write_waivers.txt) and hands dressRelics a plan -- the cycle is
-- the property under test, and no play makes it on cue.  Nothing it makes
-- enters a checkpoint.  Run on wor_tomb's CELES and SABIN, with three
-- relics both can wear (Hyper Wrist, Peace Ring, Star Pendant):
--   A. CELES wears Hyper Wrist (slot 4) and Star Pendant (5), SABIN Peace
--      Ring (4); CELES plans Peace Ring, SABIN Hyper Wrist.  Both slots 4.
--   B. the same cycle in slot 5, SABIN first in the queue (so the relic
--      taken off is in slot 5, the second row of the Remove menu).
--   C. a plan no one can meet (an Exp. Egg that nobody holds): dressRelics
--      raises "no swap deadlock" before it opens a menu.
-- Each of A and B asserts every planned slot is worn at the end, the bag's
-- relics are the ones nobody wears (none), and the gear is as before.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tomb.mss.lua"
local CELES, SABIN = 6, 5
local HYPER_WRIST, PEACE_RING, STAR_PENDANT, EGG = 0xD2, 0xB2, 0xB1, 0xE4
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function relicAt(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function setRelic(ch, s, id) H.writeByte(0x1600 + 37 * ch + 0x1F + s, id) end
local function bagRelics()
  local n = 0
  for s = 0, 255 do
    local id, q = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if q > 0 and id ~= 0xFF and (prop(id, 0) & 7) == 5 then n = n + q end
  end
  return n
end
local function emptyBagOfRelics()
  for s = 0, 255 do
    local id = H.readByte(0x1869 + s)
    if id ~= 0xFF and (prop(id, 0) & 7) == 5 then
      H.writeByte(0x1869 + s, 0xFF); H.writeByte(0x1969 + s, 0)
    end
  end
end
local function member(ch, name, cur, want)
  local changes = {}
  for s = 4, 5 do if want[s] ~= cur[s] then changes[#changes + 1] = { s, want[s] } end end
  return { ch = ch, name = name, cur = cur, want = want, changes = changes, filler = {} }
end
-- stage(celes, sabin): both members' relic slots {[4], [5]} and the bag
local function stage(celes, sabin)
  for _, id in ipairs({ HYPER_WRIST, PEACE_RING, STAR_PENDANT }) do
    for _, ch in ipairs({ CELES, SABIN }) do
      H.assertEq(wears(ch, id), true, string.format("precondition: $%02X is wearable by char %d", id, ch))
    end
  end
  emptyBagOfRelics()
  for s = 4, 5 do setRelic(CELES, s, celes[s]); setRelic(SABIN, s, sabin[s]) end
  H.assertEq(bagRelics(), 0, "precondition: the bag holds no relic (no spare to stand in)")
  H.log(string.format("[relicswap] staged: CELES %02X %02X, SABIN %02X %02X, bag relics %d", relicAt(CELES, 4),
    relicAt(CELES, 5), relicAt(SABIN, 4), relicAt(SABIN, 5), bagRelics()))
end
local realPlan = H.relicPlan
local function plan(list) H.relicPlan = function() return list end end
local function worn(ch, a, b, what)
  H.assertEq(relicAt(ch, 4), a, what .. ": slot 4")
  H.assertEq(relicAt(ch, 5), b, what .. ": slot 5")
end

local unmeetable
H.run({ maxFrames = 6000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    H.assertEq((H.readByte(0x1850 + CELES) & 7) ~= 0 and (H.readByte(0x1850 + SABIN) & 7) ~= 0, true,
      "precondition: CELES and SABIN are in the party")
    -- A
    local c = { [4] = HYPER_WRIST, [5] = STAR_PENDANT }
    local s = { [4] = PEACE_RING, [5] = 0xFF }
    stage(c, s)
    plan({ member(CELES, "CELES", c, { [4] = PEACE_RING, [5] = STAR_PENDANT }),
           member(SABIN, "SABIN", s, { [4] = HYPER_WRIST, [5] = 0xFF }) })
  end),
  H.dressRelics({ { CELES, "CELES" }, { SABIN, "SABIN" } }, { tag = "relicswap A" }),
  H.call(function()
    worn(CELES, PEACE_RING, STAR_PENDANT, "A: CELES wears the planned relics")
    worn(SABIN, HYPER_WRIST, 0xFF, "A: SABIN wears the planned relics")
    H.assertEq(bagRelics(), 0, "A: no relic is left in the bag: every one is worn")
    H.log("[relicswap A] the cycle unwound: the planned relics are worn")
    -- B: slot 5, SABIN first in the queue
    local c = { [4] = STAR_PENDANT, [5] = HYPER_WRIST }
    local s = { [4] = 0xFF, [5] = PEACE_RING }
    stage(c, s)
    plan({ member(SABIN, "SABIN", s, { [4] = 0xFF, [5] = HYPER_WRIST }),
           member(CELES, "CELES", c, { [4] = STAR_PENDANT, [5] = PEACE_RING }) })
  end),
  H.dressRelics({ { SABIN, "SABIN" }, { CELES, "CELES" } }, { tag = "relicswap B" }),
  H.call(function()
    worn(CELES, STAR_PENDANT, PEACE_RING, "B: CELES wears the planned relics")
    worn(SABIN, 0xFF, HYPER_WRIST, "B: SABIN wears the planned relics")
    H.assertEq(bagRelics(), 0, "B: no relic is left in the bag: every one is worn")
    H.log("[relicswap B] the cycle unwound in slot 5: the planned relics are worn")
    -- C: a relic nobody holds
    local c = { [4] = HYPER_WRIST, [5] = STAR_PENDANT }
    local s = { [4] = PEACE_RING, [5] = 0xFF }
    stage(c, s)
    plan({ member(CELES, "CELES", c, { [4] = EGG, [5] = STAR_PENDANT }),
           member(SABIN, "SABIN", s, s) })
    unmeetable = H.dressRelics({ { CELES, "CELES" }, { SABIN, "SABIN" } }, { tag = "relicswap C" })
  end),
  H.call(function()
    local ok, err = pcall(function() return unmeetable:tick() end)
    H.assertEq(ok, false, "C: a plan nobody can meet raises")
    H.assertEq(tostring(err):find("no swap deadlock", 1, true) ~= nil, true,
      "C: the raise names the swap deadlock: " .. tostring(err))
    H.log("[relicswap C] raised, as it must: " .. tostring(err))
    worn(CELES, HYPER_WRIST, STAR_PENDANT, "C: CELES still wears what she did")
    H.relicPlan = realPlan
  end),
})
