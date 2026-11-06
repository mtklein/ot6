-- gen_wor_kt_inferno.lua -- Kefka's Tower, Inferno (docs/design/route-wor-kefka-tower.md section 6): Continue the
-- `wor-kt-factory-v1` battery (party 3 on the factory's save point, map 410 (37,17); parties 1 and 2 where the tower
-- set them down), care, step onto the trigger (31,18) where No. 128 calls Inferno down (_cc1872: event battle 114,
-- Inferno with its arms Striker and Rough; a loss is a game over: the runner retries from the save), back onto the
-- save point and Save there: the `wor-kt-inferno-v1` battery.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local MAP_FACTORY = 410
local FACTORY_SAVE = { 37, 17 }
local INFERNO_TILE = { 31, 18 }
local INFERNO, STRIKER, ROUGH = 0x10C, 0x142, 0x141
local FIGHT = {}
-- Inferno is a machine weak to bolt; its arms are not (Striker absorbs ice, Rough absorbs bolt), so a player who
-- knows the fight casts Bolt while Inferno stands and leaves the arms to the blades (KT_BOSS_FIGHT, a lab's global,
-- overrides it)
local BOSS_FIGHT = KT_BOSS_FIGHT or {}
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint("wor-kt-factory-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (the three parties in the tower, party 3 walking on the factory's save
  -- point, Inferno not yet fought: $00BD clear).  Soft, fixed here: HP and MP (the care, casting first).
  H.call(function()
    say("tower", "boot")
    H.assertEq(H.activeParty(), 3, "party 3 walks (gen_wor_kt_factory left it on the factory's save point)")
    H.assertEq(sw(0x00BD), 0, "Inferno not yet fought ($00BD, _cc1872)")
  end),
  -- @@setup-end

  -- @@stage inferno
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 2 } }),
  -- Inferno absorbs fire (SABIN's Fire Knuckle healed it: the absorb guard's refusal, lab inf2): each hand holding
  -- a weapon one of the three absorbs takes the bag's strongest one none does, as a player re-arms for a known boss
  H.absorbSafeArms(nil, { INFERNO, STRIKER, ROUGH }, { tag = "arms for Inferno" }),
  H.fieldCare({ threshold = 1.0, tag = "before Inferno" }),
  H.call(function() say("boss", "party 3 before Inferno: " .. H.partiesLine()) end),
  H.navTo(INFERNO_TILE[1], INFERNO_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return H.battleLoadStarted() or (H.fieldX() == 31 and H.fieldY() == 18) end }),
  H.advanceStory(function() return sw(0x00BD) == 1 and map() == MAP_FACTORY and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "Inferno beaten") end),
  H.saveState("wor_kt_inferno_won.mss"),

  -- @@stage save
  H.stepOntoSavePoint(FACTORY_SAVE[1], FACTORY_SAVE[2]),
  H.fieldCare({ threshold = 1.0, tag = "on the factory's save point after Inferno" }),
  H.call(function()
    say("tower", "on the factory's save point after Inferno")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-inferno-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_inferno.mss"),
  H.logStep(function()
    return string.format("wor_kt_inferno generated: %s, saved in slot 3", H.partiesLine())
  end),
})
