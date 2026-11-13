-- gen_wob_esper_mtn_hunt.lua -- a branch beside gen_massacre (docs/design/wob-side-trips.md, #283): Continue the
-- `ultros-won-v1` battery (TERRA, LOCKE, STRAGO and RELM at Esper Mountain's save point, map 375 (8,44), Ultros
-- beaten and RELM joined) and walk the mountain's two pools until every formation of each has been won (K.hunt,
-- lib/ot6_field.lua: the pool asserted against the ROM's, the hunt bounded by the worst draws): the slopes of
-- 375 (group 90: Adamanchyt and Slurm) by the save, then, past gen_massacre's shortcut, the side cave 374 (group 89:
-- Mandrake, Insecare, Abolisher), whose chest holds the Chocobo Suit.  No leg boots what it leaves (the state
-- `wob_esper_mtn_hunt`); gen_massacre goes on from the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, STRAGO, RELM = 0, 1, 7, 8
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [STRAGO] = "STRAGO", [RELM] = "RELM" }
local FOUR = { TERRA, LOCKE, STRAGO, RELM }
local FIGHT = { tactical = true, boost = true, bank = 2, items = true, healPercent = 50, nuke = { 2, 1, 0 } }
H.NAV_REFIRE_HOLD = true
local CHOCOBO_SUIT = 0x9E

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches, settled = K.map, K.lv, K.say, K.kitLine, K.watches, K.settled
local won = {}

-- a lap of the tile the party stands on and a neighbour one step away (gen_wor_ebot_hunt's)
local function lapHere(what)
  local x, y = H.fieldX(), H.fieldY()
  for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local p = H.bfsPath(x + d[1], y + d[2])
    if p and #p == 1 then return { { x, y }, { x + d[1], y + d[2] } } end
  end
  error(string.format("[hunt] %s: no lap beside map %d (%d,%d)", what, map(), x, y))
end
-- through a door or shortcut tile: navTo it until `arrive`, then settle (gen_massacre's hop)
local function hop(sx, sy, arrive, what)
  return H.seqStep({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "tactical", fight = FIGHT, arrive = arrive }),
    H.release(),
    H.waitUntil(function() return arrive() and settled() and not H.dialogWaiting() end, 6000, what, 10),
    H.call(function() say("route", what) end),
  })
end
local SLOPES = { [164] = "Adamanchyt, Slurm x2", [165] = "Adamanchyt x2", [166] = "Slurm x5" }
local CAVE = { [167] = "Mandrake x3", [168] = "Mandrake, Insecare x2", [169] = "Abolisher x2" }

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("ultros-won-v1"),
  watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    for _, ch in ipairs(FOUR) do
      H.assertEq(K.partyOf(ch), 1, string.format("%s is seated (ultros-won-v1: gen_ultros's party)", NAMES[ch]))
    end
  end),
  -- @@setup-end
  -- off the save tile, whose trigger re-fires while the party stands on it (gen_massacre's)
  H.navTo(7, 44, { maxFrames = 3000 }),
  H.waitUntil(function() return settled() and not H.dialogWaiting() end, 3000, "off the save tile", 5),
  H.fieldCare({ threshold = 1.0, tag = "before the slopes (group 90)" }),
  H.lazy(function()
    return K.hunt({ what = "Esper Mountain's slopes (375, group 90)", lap = lapHere("the slopes"), forms = SLOPES,
      won = won })
  end),
  H.fieldCare({ threshold = 1.0, tag = "after the slopes" }),
  -- gen_massacre's shortcut: 375 (11,51) retiles and carries the party to (39,51), the compartment that holds the
  -- doors of 372 and 374
  hop(11, 51, function() return map() == 375 and H.fieldX() >= 30 end, "375 (11,51): the shortcut east"),
  hop(36, 41, function() return map() == 374 end, "375 (36,41) -> the side cave 374"),
  K.chestAt(18, 9, 108, "the side cave's chest (the Chocobo Suit)", CHOCOBO_SUIT),
  H.fieldCare({ threshold = 1.0, tag = "before the side cave (group 89)" }),
  H.lazy(function()
    return K.hunt({ what = "the side cave (374, group 89)", lap = lapHere("the side cave"), forms = CAVE, won = won })
  end),
  H.fieldCare({ threshold = 1.0, tag = "after the side cave" }),
  H.call(function()
    H.assertEq(H.invCountOf(CHOCOBO_SUIT) >= 1, true, "the Chocobo Suit is in the bag")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wob_esper_mtn_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_esper_mtn_hunt generated: TERRA L%d, LOCKE L%d, STRAGO L%d, RELM L%d on map %d "
      .. "(%d,%d); formations won: %s", lv(TERRA), lv(LOCKE), lv(STRAGO), lv(RELM), map(), H.fieldX(), H.fieldY(),
      table.concat(t, " "))
  end),
})
