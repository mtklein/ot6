-- gen_wor_kt_guardian.lua -- Kefka's Tower, from Atma's save point to Guardian's (docs/design/route-wor-kefka-tower.md
-- sections 2 and 5): Continue the `wor-kt-atma-v1` battery (party 2 on the save point behind Atma, 331 (76,51);
-- party 3 on the factory's after Inferno; party 1 on its landing), then
--   party 3: 293, 334's south (the Rainbow Brsh, the Megalixir), the sparkle (34,53) that opens party 1's door
--            (30,50), 293's north door, 354's east half, the Skull Dragon (event battle 136), the east plate of 337;
--   party 2: the hole (331 (81,60)) to 329, 409, 334's south-west (the Force Shld, the Force Armor), 292's right
--            room (the Ribbon; the switch (87,12) that opens party 1's passage, pressed before party 2 holds a
--            plate: _cc1447 refuses while $02C8 is set), 294, 335, the Gold Dragon (event battle 135), 354's west
--            half, the west plate of 337: with both plates held the locked door (8,11) opens for good ($0080);
--   party 1: 303, 304 (the Fixed Dice), 334's west, 292's left room and the passage, 352, 295, the door party 3
--            opened, the Tack Star, 337's corridor and the chamber (355);
--   the chamber: its gate switches shut each column behind the party that enters, so party 1 takes the east column
--            and drops the east weight (party 3's hole), party 3 comes through and takes the west column and drops
--            the west weight (party 2's hole), party 2 comes through to the middle; the three plates held at once
--            open the north door ($0067);
--   party 2 north to Guardian (291 (12,14): event battle 140; a game over when lost: the runner retries from the
--            save), and Save on the save point it guarded (291 (12,12)): the `wor-kt-guardian-v1` battery.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local GUARDIAN_SAVE = { 12, 12 }
local SKULL, GOLD, GUARDIAN = 0x151, 0x150, 0x112
-- the tower's species whose vanilla weakness a player who knows the tower reads (gen_wor_kt_factory's)
local VECTAUR, BRONTAUR, OSCAR = 0x080, 0x084, 0x0B7
local MACHINES = { [0x0FD] = true, [0x0D9] = true, [0x0EA] = true, [0x0ED] = true, [0x0F6] = true, [0x105] = true,
  [0x0FC] = true, [0x0A1] = true }
local FIRE, ICE, BOLT = 0x00, 0x01, 0x02
local FIGHT = {}
-- the Sky Base first, as a player who knows the factory kills it: its script is L.5 Doom and Doom, and its counter
-- Blaster, all Death; while it stood it killed members from full HP one action at a time and wiped party 1 in 352
-- (formation 413, Sky Base with four IronHitmen: sweep guardian_s8, s13: "entity 1 char 8 from 5475/5475 by slot 0
-- cmd $0C atk $94 (ONE ACTION from >= 80%)").  The IronHitmen fall to the boosted Bolt that hits them all.
FIGHT.focusFirst = { [0x0FC] = true }
FIGHT.nuke = function()
  if H.formationHas({ [OSCAR] = true }) then return { FIRE } end
  if H.formationHas(MACHINES) then return { BOLT } end
  if H.formationHas({ [VECTAUR] = true, [BRONTAUR] = true }) then return { ICE } end
  return nil
end
local BOSS_FIGHT = KT_BOSS_FIGHT or {}
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door, chest = T.walk, T.door, T.chest

-- a boss touched as an NPC: from two tiles below it, the care, absorb-safe arms, the talk and the fight until its
-- show-switch reads clear (the dragon's event clears it after the fight: _cc18d9 $06B3, _cc1906 $06B4; lib
-- T.touchBoss: a random battle can open on the talk's step)
local function npcBoss(x, y, species, mapId, shown, what)
  return H.seqStep({
    walk(x, y + 2, what .. ": two tiles below it"),
    H.absorbSafeArms(nil, { species }, { tag = "arms for " .. what }),
    H.fieldCare({ threshold = 1.0, tag = "before " .. what }),
    H.call(function() say("boss", "before " .. what) end),
    T.touchBoss(x, y, mapId, function() return sw(shown) == 0 end, what, BOSS_FIGHT),
  })
end
-- a weight in a chamber cell: facing down, A, until its switch reads set
local function weight(id, what)
  return H.seqStep({
    H.faceAndHoldA("down", function() return sw(id) == 1 end, 1800, what .. ": face down, A"),
    H.release(),
    H.advanceStory(function() return sw(id) == 1 and settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function() say("route", what .. string.format(" dropped ($%04X)", id)) end),
  })
end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("wor-kt-atma-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (Inferno and Atma beaten, the three parties in the tower, party 2 on Atma's
  -- save point).  Asserted here: party 1 and party 3 where the legs before left them, since each walk starts
  -- there.  Soft, fixed here: HP and MP (the care), the arms (absorbSafeArms before each boss).
  H.call(function()
    say("tower", "boot")
    local m1, x1, y1 = H.partyWhere(1)
    local m3, x3, y3 = H.partyWhere(3)
    H.assertEq(string.format("%d (%d,%d)", m1, x1, y1), "334 (9,16)", "party 1 on its landing (gen_wor_kt_factory)")
    H.assertEq(string.format("%d (%d,%d)", m3, x3, y3), "410 (37,17)",
      "party 3 on the factory's save point (gen_wor_kt_inferno)")
  end),
  -- @@setup-end

  -- ---- 1. party 3: the sparkle, the Skull Dragon, the east plate -------------------------------------------
  -- @@stage skull
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 1 } }),
  H.switchParty(3),
  door(29, 28, 293, "party 3: 410 (29,28) -> 293 (29,47)"),
  door(29, 58, 334, "party 3: 293 (29,58) -> 334 (43,39)"),
  chest(37, 45, 0x0DB, "Rainbow Brsh (334 (37,45))"),
  chest(48, 48, 0x0DE, "Megalixir (334 (48,48))"),
  walk(34, 53, "party 3 onto the sparkle's tile (334 (34,53))"),
  H.faceAndHoldA("left", function() return sw(0x007F) == 1 end, 1200, "the sparkle (334 (34,53)): face left, A"),
  H.release(),
  H.advanceStory(function() return sw(0x007F) == 1 and settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "the door (334 (30,50)) opened for party 1 ($007F)") end),
  door(37, 51, 293, "party 3: 334 (37,51) -> 293 (52,14)"),
  door(52, 2, 354, "party 3: 293 (52,2) -> 354 (82,42)"),
  npcBoss(82, 33, SKULL, 354, 0x06B4, "the Skull Dragon (354 NPC_2)"),
  door(63, 41, 337, "party 3: 354 (63,41) -> 337 (11,27)"),
  walk(12, 12, "party 3 onto the east plate (337 (12,12))"),
  H.waitUntil(function() return sw(0x02CC) == 1 and settled() end, 1200, "the east plate held ($02CC)", 1),
  H.saveState("wor_kt_guardian_skull.mss"),

  -- ---- 2. party 2: the switch, the Gold Dragon, the west plate -----------------------------------------------
  -- @@stage gold
  H.switchParty(2),
  door(81, 60, 329, "party 2: the hole (331 (81,60)) down to 329"),
  door(109, 8, 409, "party 2: 329 (109,8) -> 409 (12,10)"),
  door(0, 7, 334, "party 2: 409 (0,7) -> 334 (17,35)"),
  chest(11, 39, 0x0D9, "Force Shld (334 (11,39))"),
  chest(5, 51, 0x0DA, "Force Armor (334 (5,51))"),
  door(17, 50, 292, "party 2: 334 (17,50) -> 292 (89,7)"),
  chest(89, 12, 0x0D8, "Ribbon (292 (89,12))"),
  walk(87, 12, "party 2 onto the switch (292 (87,12)): party 1's passage"),
  H.waitUntil(function() return sw(0x0062) == 1 and settled() end, 1200, "the passage opened ($0062)", 1),
  door(90, 7, 334, "party 2: 292 (90,7) -> 334 (18,50)"),
  door(23, 47, 294, "party 2: 334 (23,47) -> 294 (52,14)"),
  door(52, 2, 335, "party 2: 294 (52,2) -> 335 (82,42)"),
  npcBoss(82, 33, GOLD, 335, 0x06B3, "the Gold Dragon (335 NPC_1)"),
  door(77, 31, 354, "party 2: 335 (77,31) -> 354 (51,44)"),
  door(55, 41, 337, "party 2: 354 (55,41) -> 337 (5,27)"),
  walk(4, 12, "party 2 onto the west plate (337 (4,12))"),
  H.waitUntil(function() return sw(0x0080) == 1 and settled() end, 1200, "the locked door open ($0080)", 1),
  H.call(function() say("route", "both plates held: the locked door (337 (8,11)) is open") end),
  H.saveState("wor_kt_guardian_plates.mss"),

  -- ---- 3. party 1's lane to the chamber ---------------------------------------------------------------------
  -- @@stage lane
  H.switchParty(1),
  door(18, 20, 303, "party 1: 334 (18,20) -> 303 (14,14)"),
  door(21, 19, 304, "party 1: 303 (21,19) -> 304 (40,45)"),
  chest(33, 35, 0x0D7, "Fixed Dice (304 (33,35))"),
  door(32, 51, 334, "party 1: 304 (32,51) -> 334 (11,33)"),
  door(7, 48, 292, "party 1: 334 (7,48) -> 292 (81,7)"),
  door(85, 19, 352, "party 1: 292 (85,19) -> 352 (3,28)"),
  door(31, 27, 295, "party 1: 352 (31,27) -> 295 (52,57)"),
  door(57, 55, 334, "party 1: 295 (57,55) -> 334 (27,53)"),
  chest(23, 41, 0x0DC, "Tack Star (334 (23,41))"),
  door(29, 36, 337, "party 1: 334 (29,36) -> 337 (8,29)"),
  door(8, 11, 355, "party 1: 337 (8,11) -> the chamber, 355 (39,19)"),

  -- ---- 4. the chamber ------------------------------------------------------------------------------------------
  -- @@stage chamber
  H.switchParty(2),
  walk(4, 13, "party 2 off the west plate"),
  H.switchParty(3),
  walk(12, 13, "party 3 off the east plate"),
  H.switchParty(1),
  walk(43, 9, "party 1 onto the east gate's switch (355 (43,9)): into the east column"),
  door(43, 18, 337, "party 1: the east column (43,18) -> 337's east cell (12,6)"),
  weight(0x0064, "the east weight (337 (12,7)): party 3's hole"),
  door(12, 5, 355, "party 1: the east cell (12,5) -> the east column (43,17)"),
  H.switchParty(3),
  door(8, 11, 355, "party 3: through the east hole and the corridor -> the chamber (39,19)"),
  walk(35, 9, "party 3 onto the west gate's switch (355 (35,9)): into the west column"),
  door(35, 18, 337, "party 3: the west column (35,18) -> 337's west cell (4,6)"),
  weight(0x0063, "the west weight (337 (4,7)): party 2's hole"),
  door(4, 5, 355, "party 3: the west cell (4,5) -> the west column (35,17)"),
  H.switchParty(2),
  door(8, 11, 355, "party 2: through the west hole and the corridor -> the chamber (39,19)"),
  walk(39, 9, "party 2 onto the middle plate (355 (39,9))"),
  H.switchParty(1),
  walk(43, 6, "party 1 onto the east plate (355 (43,6))"),
  H.switchParty(3),
  walk(35, 6, "party 3 onto the west plate (355 (35,6))"),
  H.advanceStory(function() return sw(0x0067) == 1 and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "the chamber's north door open ($0067)") end),
  H.saveState("wor_kt_guardian_chamber.mss"),

  -- ---- 5. Guardian ---------------------------------------------------------------------------------------------
  -- @@stage guardian
  H.switchParty(2),
  door(39, 4, 291, "party 2: the north door (355 (39,4)) -> 291 (12,16)"),
  H.absorbSafeArms(nil, { GUARDIAN }, { tag = "arms for Guardian" }),
  H.fieldCare({ threshold = 1.0, tag = "before Guardian" }),
  H.call(function() say("boss", "before Guardian") end),
  H.navTo(12, 14, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return H.battleLoadStarted() or (H.fieldX() == 12 and H.fieldY() == 14) end }),
  H.advanceStory(function() return sw(0x00BC) == 1 and map() == 291 and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "Guardian beaten") end),

  -- @@stage save
  H.stepOntoSavePoint(GUARDIAN_SAVE[1], GUARDIAN_SAVE[2]),
  H.fieldCare({ threshold = 1.0, tag = "on Guardian's save point" }),
  H.call(function()
    say("tower", "on Guardian's save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-guardian-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_guardian.mss"),
  H.logStep(function()
    return string.format("wor_kt_guardian generated: %s, saved in slot 3", H.partiesLine())
  end),
})
