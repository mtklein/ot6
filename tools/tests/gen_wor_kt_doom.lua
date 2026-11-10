-- gen_wor_kt_doom.lua -- Kefka's Tower, the cell doors and party 3 to Doom (docs/design/route-wor-kefka-tower.md
-- sections 2, 5 and 6): Continue the `wor-kt-guardian-v1` battery (party 2 on Guardian's save point, 291 (12,12);
-- party 1 on the chamber's east plate, party 3 on its west plate), then
--   party 2: back through the chamber and its south door to 337 (8,6), which opens the cell doors to the west and
--            east lanes ($00D0), and stays there;
--   party 3: down the west column to 337's west cell, through its door into 355's west lane, 291's west room and
--            back into 355 below Doom; its bench levels on that floor (T.trainLap: the tower's own encounters, the
--            owner's direction); dressed against his ice (H.elementDress); Doom (355 (64,12): event battle 98, a game
--            over when lost: the runner retries from the save), and Save on the save point he guarded (355 (64,11)):
--            the `wor-kt-doom-v1` battery.  The ladder above it leads to 411's left plate: party 3's place at the
--            convergence.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local DOOM = 0x127
local DOOM_SAVE = { 64, 11 }
local ICE_ELEMENT = 0x02
-- party 3's bench levels to TRAIN_LEVEL below Doom (route-wor-kefka-tower.md section 6: at the bench's L40-46 Doom
-- won 10 of 16 (b0); trained to L46, 13 of 14 (a2 t46); trained and dressed against his ice, 9 of 9, 8 distinct
-- keys (a2 td))
local TRAIN_LEVEL = KT_TRAIN or 46
local FIGHT = {}
local MACHINES = { [0x0FD] = true, [0x0D9] = true, [0x0EA] = true, [0x0ED] = true, [0x0F6] = true, [0x105] = true,
  [0x0FC] = true, [0x0A1] = true }
local BOLT = 0x02
FIGHT.nuke = function()
  if H.formationHas(MACHINES) then return { BOLT } end
  return nil
end
-- CYAN's Cleave and SABIN's Bum Rush, the divines (#388, Driver:divineLine; wor-coverage.md 13.9: with both, Doom
-- won 28 of 31 distinct fights against the stock fight's 23, not outside chance, with fewer deaths, 52 against 78,
-- and sooner, though most flipped fights had no divine land; a landed Bum Rush takes over half his HP).  KT_BOSS_FIGHT, a lab's global, overrides it ({} is the
-- stock fight)
local BOSS_FIGHT = KT_BOSS_FIGHT or { divines = true }
-- the lap's (and the walk's) random battles: KT_LAP_DIVINES, a lab's global, sets Driver:divineLine's options there
if KT_LAP_DIVINES ~= nil then FIGHT.divines = KT_LAP_DIVINES end
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door = T.walk, T.door

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("wor-kt-guardian-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (Guardian beaten, the chamber's north door open, party 2 on his save point).
  -- Asserted here: parties 1 and 3 on the chamber's plates, where gen_wor_kt_guardian left them (the lanes behind
  -- the cell doors start there), and the cell doors still shut (this leg opens them).  Soft, fixed here: HP and MP
  -- (the care), the arms (absorbSafeArms), the dress.
  H.call(function()
    say("tower", "boot")
    local m1, x1, y1 = H.partyWhere(1)
    local m3, x3, y3 = H.partyWhere(3)
    H.assertEq(string.format("%d (%d,%d)", m3, x3, y3), "355 (35,6)", "party 3 on the chamber's west plate "
      .. "(gen_wor_kt_guardian)")
    H.assertEq(string.format("%d (%d,%d)", m1, x1, y1), "355 (43,6)", "party 1 on the chamber's east plate "
      .. "(gen_wor_kt_guardian)")
    H.assertEq(sw(0x00D0), 0, "the cell doors still shut ($00D0): this leg opens them")
  end),
  -- @@setup-end

  -- @@stage cells
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 1 } }),
  H.switchParty(2),
  door(12, 17, 355, "party 2: 291 (12,17) -> the chamber's middle (39,5)"),
  door(39, 20, 337, "party 2: the chamber's south door (39,20) -> 337 (8,5)"),
  walk(8, 6, "party 2 onto 337 (8,6): the cell doors"),
  H.waitUntil(function() return sw(0x00D0) == 1 and settled() end, 1200, "the cell doors open ($00D0)", 1),
  H.call(function() say("route", "the cell doors (337 (2,4), (14,4)) open for the west and east lanes") end),

  -- @@stage lane
  H.switchParty(3),
  door(35, 18, 337, "party 3: the west column (35,18) -> 337's west cell (4,6)"),
  door(2, 5, 355, "party 3: the west cell's door (2,5) -> 355 (31,17)"),
  door(31, 8, 291, "party 3: 355 (31,8) -> 291 (6,15)"),
  door(6, 9, 355, "party 3: 291 (6,9) -> 355 (64,19)"),
  T.trainLap("party 3 below Doom", TRAIN_LEVEL),

  -- @@stage doom
  -- dressed against his ice (Ice 3, N. Cross, Absolute 0; ai_script.asm _295), as a player who knows him does: the
  -- care first, since the Equip menu refuses a fallen member
  H.fieldCare({ threshold = 1.0, tag = "before dressing for Doom" }),
  H.elementDress(ICE_ELEMENT, { tag = "dress against Doom's ice" }),
  H.absorbSafeArms(nil, { DOOM }, { tag = "arms for Doom" }),
  H.fieldCare({ threshold = 1.0, tag = "before Doom" }),
  T.standing("party 3 before Doom"),
  H.call(function() say("boss", "party 3 before Doom: " .. H.partiesLine()) end),
  H.navTo(64, 12, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, spare = { DOOM },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [DOOM] = true })) or (H.fieldX() == 64 and H.fieldY() == 12)
    end }),
  H.advanceStory(function() return sw(0x0072) == 1 and map() == 355 and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "Doom beaten") end),
  H.saveState("wor_kt_doom_won.mss"),

  -- @@stage save
  H.stepOntoSavePoint(DOOM_SAVE[1], DOOM_SAVE[2]),
  H.fieldCare({ threshold = 1.0, tag = "on Doom's save point" }),
  H.call(function()
    say("tower", "on Doom's save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-doom-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_doom.mss"),
  H.logStep(function()
    return string.format("wor_kt_doom generated: %s, saved in slot 3", H.partiesLine())
  end),
})
