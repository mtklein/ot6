-- @suite savestate=wor_tomb
-- field_relicswap.lua -- H.dressRelics at a relic swap cycle the bag cannot
-- break (#439).  Two members want each other's relic and the bag holds no
-- relic to stand in: the old fallback let the first member keep what he
-- wore and dropped the planned relic ("CYAN keeps Hyper Wrist ...", wor_relm
-- on the v031-robust chain); the plan has to be met, or fail loudly.
--
-- A synthetic mechanism test (docs/TESTING.md, "Synthetic mechanism
-- tests"): the setup writes the relic slots and empties the bag of relics
-- (state_write_waivers.txt) and hands dressRelics a plan -- the cycle is
-- the property under test, and no play makes it on cue.  Nothing it makes
-- enters a checkpoint.  Run on wor_tomb's CELES and SABIN, with three
-- relics both can wear:
--   CELES wears Hyper Wrist (slot 4), Star Pendant (5), and plans Peace Ring
--   SABIN wears Peace Ring (slot 4), nothing in 5, and plans Hyper Wrist
-- then asserts every planned slot is worn and the bag's relics are the
-- ones nobody wears (here: none).  A second plan names a relic nobody has
-- (an Exp. Egg in no bag, no hand): that cannot be met and must raise, with
-- the swap-deadlock message, rather than leave a member on his old relics.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tomb.mss.lua"
local CELES, SABIN = 6, 5
local HYPER_WRIST, PEACE_RING, STAR_PENDANT = 0xD2, 0xB2, 0xB1
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
local function plan(celes4, sabin4)
  return {
    { ch = CELES, name = "CELES", cur = { [4] = HYPER_WRIST, [5] = STAR_PENDANT }, want = { [4] = celes4, [5] = STAR_PENDANT },
      changes = { { 4, celes4 } }, filler = {} },
    { ch = SABIN, name = "SABIN", cur = { [4] = PEACE_RING, [5] = 0xFF }, want = { [4] = sabin4, [5] = 0xFF },
      changes = { { 4, sabin4 } }, filler = {} },
  }
end
local realPlan = H.relicPlan
local function stage(p)
  for _, id in ipairs({ HYPER_WRIST, PEACE_RING, STAR_PENDANT }) do
    for _, ch in ipairs({ CELES, SABIN }) do
      H.assertEq(wears(ch, id), true, string.format("precondition: $%02X is wearable by char %d", id, ch))
    end
  end
  emptyBagOfRelics()
  setRelic(CELES, 4, HYPER_WRIST); setRelic(CELES, 5, STAR_PENDANT)
  setRelic(SABIN, 4, PEACE_RING); setRelic(SABIN, 5, 0xFF)
  H.assertEq(bagRelics(), 0, "precondition: the bag holds no relic (no spare to stand in)")
  H.relicPlan = function() return p end
end

H.run({ maxFrames = 6000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    H.assertEq((H.readByte(0x1850 + CELES) & 7) ~= 0 and (H.readByte(0x1850 + SABIN) & 7) ~= 0, true,
      "precondition: CELES and SABIN are in the party")
    stage(plan(PEACE_RING, HYPER_WRIST))
    H.log(string.format("[relicswap] staged: CELES %02X %02X, SABIN %02X %02X, bag relics %d", relicAt(CELES, 4),
      relicAt(CELES, 5), relicAt(SABIN, 4), relicAt(SABIN, 5), bagRelics()))
  end),
  H.dressRelics({ { CELES, "CELES" }, { SABIN, "SABIN" } }, { tag = "relicswap" }),
  H.call(function()
    H.assertEq(relicAt(CELES, 4), PEACE_RING, "CELES wears the planned Peace Ring")
    H.assertEq(relicAt(CELES, 5), STAR_PENDANT, "CELES keeps the Star Pendant (planned)")
    H.assertEq(relicAt(SABIN, 4), HYPER_WRIST, "SABIN wears the planned Hyper Wrist")
    H.assertEq(bagRelics(), 0, "no relic is left in the bag: every one is worn")
    H.log("[relicswap] the cycle unwound: the planned relics are worn")
  end),
  -- an unmeetable plan raises, loudly (the old assertion's message): a relic
  -- that is neither in the bag nor worn by a member waiting on one of his
  H.call(function()
    emptyBagOfRelics()
    setRelic(CELES, 4, HYPER_WRIST); setRelic(CELES, 5, STAR_PENDANT)
    setRelic(SABIN, 4, PEACE_RING); setRelic(SABIN, 5, 0xFF)
    stage(plan(0xE4, HYPER_WRIST))
    local ok, err = pcall(function()
      local step = H.dressRelics({ { CELES, "CELES" }, { SABIN, "SABIN" } }, { tag = "relicswap unmeetable" })
      H.__unmeetable = step
    end)
    H.assertEq(ok, true, "building the second dressRelics step")
  end),
  H.call(function()
    -- tick the step until it raises: it must raise on its first tick, before
    -- it opens any menu (nothing can put an Exp. Egg in a bag)
    local ok, err = pcall(function() return H.__unmeetable:tick() end)
    H.assertEq(ok, false, "an unmeetable plan raises")
    H.assertEq(tostring(err):find("no swap deadlock", 1, true) ~= nil, true,
      "the raise names the swap deadlock: " .. tostring(err))
    H.log("[relicswap] the unmeetable plan raised: " .. tostring(err))
    H.assertEq(relicAt(CELES, 4), HYPER_WRIST, "CELES still wears what she did")
    H.relicPlan = realPlan
  end),
})
