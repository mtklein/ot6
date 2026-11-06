-- gen_wor_kt_plates.lua -- Kefka's Tower, the convergence on 411's plates (docs/design/route-wor-kefka-tower.md
-- sections 2 and 5): Continue the `wor-kt-goddess-v1` battery (party 1 on the Goddess's save point, 354 (12,31);
-- party 3 on Doom's, 355 (64,11); party 2 on 412's, (82,47)), then
--   party 1: north from the Goddess's save point through (12,29) to 411 (115,47), onto the right plate (115,42);
--   party 3: up the ladder above Doom's save point (355 (64,10)), through (64,6) to 411 (103,48), onto the left
--            plate (103,43);
--   party 2: on 412's save point, and Save there: the `wor-kt-plates-v1` battery.
-- Each plate holds its own party's bit while that party stands on it (_cc193f: $02C6/$02CA/$02CE); the third party
-- to stand on one starts FinalBattle (Kefka, #274).  So the line's last save in the tower is party 2 on 412's save
-- point with the other two on their plates: Kefka's fight boots from it, and its party 2 drops from 412 (82,45) to
-- 411 (109,42) and steps onto the middle plate (109,40).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local SAVE_412 = { 82, 47 }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door = T.walk, T.door

-- a party onto one of 411's plates: the plate sets the walking party's own bit (_cc193f: party 1 $02C6, party 2
-- $02CA, party 3 $02CE), whichever plate it is
local function plate(x, y, bit, what)
  return H.seqStep({
    walk(x, y, what),
    H.waitUntil(function() return sw(bit) == 1 end, 600, what .. string.format(": its bit ($%04X) set", bit), 1),
    H.call(function() say("route", what .. string.format(": held ($%04X)", bit)) end),
  })
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-kt-goddess-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (the three statues beaten, party 1 on the Goddess's save point).  Asserted
  -- here: party 3 on Doom's save point (gen_wor_kt_doom) and party 2 on 412's (gen_wor_kt_poltergeist), where each
  -- walk starts; no plate held yet.
  H.call(function()
    say("tower", "boot")
    local m2, x2, y2 = H.partyWhere(2)
    local m3, x3, y3 = H.partyWhere(3)
    H.assertEq(string.format("%d (%d,%d)", m3, x3, y3), "355 (64,11)", "party 3 on Doom's save point (gen_wor_kt_doom)")
    H.assertEq(string.format("%d (%d,%d)", m2, x2, y2), "412 (82,47)", "party 2 on 412's save point "
      .. "(gen_wor_kt_poltergeist)")
    for _, b in ipairs({ 0x02C6, 0x02CA, 0x02CE }) do
      H.assertEq(sw(b), 0, string.format("no plate of 411 held yet ($%04X)", b))
    end
  end),
  -- @@setup-end

  -- @@stage plates
  H.switchParty(1),
  door(12, 29, 411, "party 1: 354 (12,29) -> 411 (115,47)"),
  plate(115, 42, 0x02C6, "party 1 onto 411's right plate (115,42)"),
  H.switchParty(3),
  door(64, 6, 411, "party 3: up the ladder (355 (64,10)) and through (64,6) -> 411 (103,48)"),
  plate(103, 43, 0x02CE, "party 3 onto 411's left plate (103,43)"),

  -- @@stage save
  H.switchParty(2),
  H.stepOntoSavePoint(SAVE_412[1], SAVE_412[2]),
  H.fieldCare({ threshold = 1.0, tag = "on 412's save point" }),
  H.call(function()
    say("tower", "on 412's save point, parties 1 and 3 on their plates")
    H.assertEq(string.format("%d %d %d", sw(0x02C6), sw(0x02CA), sw(0x02CE)), "1 0 1",
      "parties 1 and 3 hold their plates at the save, party 2 not yet ($02C6, $02CA, $02CE)")
  end),
  H.saveAtCheckpoint("wor-kt-plates-v1"),
  H.saveState("wor_kt_plates.mss"),
  H.logStep(function()
    return string.format("wor_kt_plates generated: %s, saved in slot 3", H.partiesLine())
  end),
})
