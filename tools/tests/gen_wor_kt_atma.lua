-- gen_wor_kt_atma.lua -- Kefka's Tower, party 2 to Atma (docs/design/route-wor-kefka-tower.md section 6): Continue
-- the `wor-kt-inferno-v1` battery (party 3 on the factory's save point after Inferno; parties 1 and 2 where the tower
-- set them down), switch to party 2, walk it from its landing (334 (43,21)) north into 338, through 338 to 331, and
-- touch Atma (331 NPC_1 (76,51): event battle 112, a game over when lost: the runner retries from the save), then
-- Save on the save point Atma stood in front of (331 (76,51), shown after the fight): the `wor-kt-atma-v1`
-- battery.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local MAP_TOWER, MAP_338, MAP_331 = 334, 338, 331
local ATMA = 0x17D
local ATMA_SAVE = { 76, 51 }
-- the tower's species whose vanilla weakness a player who knows the tower reads (gen_wor_kt_factory's)
local OSCAR, BRONTAUR = 0x0B7, 0x084
local FIRE, ICE = 0x00, 0x01
local FIGHT = {}
FIGHT.nuke = function()
  if H.formationHas({ [OSCAR] = true }) then return { FIRE } end
  if H.formationHas({ [BRONTAUR] = true }) then return { ICE } end
  return nil
end
local BOSS_FIGHT = KT_BOSS_FIGHT or {}
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door = T.walk, T.door

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint("wor-kt-inferno-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (the three parties in the tower, Inferno beaten).  Asserted here: party 2
  -- stands where the tower set it down, so its walk starts there (gen_wor_kt_factory leaves it).  Soft, fixed
  -- here: HP and MP (the care), the arms (absorbSafeArms).
  H.call(function()
    say("tower", "boot")
    local m, x, y = H.partyWhere(2)
    H.assertEq(string.format("%d (%d,%d)", m, x, y), "334 (43,21)",
      "party 2 on its landing (gen_wor_kt_factory leaves it there)")
  end),
  -- @@setup-end

  -- @@stage walk
  H.splitBegin({ shares = { [1] = 1, [2] = 2, [3] = 1 } }),
  H.switchParty(2),
  door(39, 27, MAP_338, "party 2: 334 (39,27) -> 338 (15,52)"),
  door(5, 60, MAP_331, "party 2: 338 (5,60) -> 331 (86,49)"),
  walk(76, 53, "party 2: two tiles below Atma (331 (76,51))"),

  -- @@stage atma
  H.absorbSafeArms(nil, { ATMA }, { tag = "arms for Atma" }),
  H.fieldCare({ threshold = 1.0, tag = "before Atma" }),
  H.call(function() say("boss", "party 2 before Atma") end),
  H.talkToObj(0x10, "Atma (331 NPC_1)", nil, function() return H.battleLoadStarted() end),
  H.advanceStory(function() return not H.battleLoadStarted() and map() == MAP_331 and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function()
    H.assertEq(sw(0x06BE), 1, "Atma beaten: the save point behind him shown ($06BE, _cc18b4)")
    say("boss", "Atma beaten")
  end),
  H.saveState("wor_kt_atma_won.mss"),

  -- @@stage save
  H.stepOntoSavePoint(ATMA_SAVE[1], ATMA_SAVE[2]),
  H.fieldCare({ threshold = 1.0, tag = "on Atma's save point" }),
  H.call(function()
    say("tower", "on Atma's save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-atma-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_atma.mss"),
  H.logStep(function()
    return string.format("wor_kt_atma generated: %s, saved in slot 3", H.partiesLine())
  end),
})
