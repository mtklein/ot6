-- @suite slow
-- battle_bumrushmimic.lua -- a Bum Rush copied under three points is Pummel (#388, review of 0e07294e..7b94f5f9).
--
-- kits.md ("Divines", "Sabin"): Bum Rush is SABIN's divine, three points pending or not at all.  His own pick is
-- gated at the list (battle_bumrush); a GOGO's Mimic copies the action without the list and reads its boost from
-- GOGO at execution, and under three points the command's own check (Ot6BlitzTake, Cmd_0a) runs it as Pummel at
-- the boost GOGO has.  Mimic is free (guidelines.md "Mimic is free"), so the copy costs GOGO nothing either way.
--
-- Played: Continue wor-kt-guardian-v1 (party 3 -- CYAN, SHADOW, SABIN and GOGO -- on the chamber's west plate in
-- Kefka's Tower), walk gen_wor_kt_doom's route (party 2 opens the cell doors, party 3 down the west column and lane,
-- fighting what comes) to Doom (event battle 98, 63,000 HP), and play his battle through the real menu
-- (H.kitBattle; Defends bank the points, the others Defend): SABIN's Bum Rush at 3 BP, then GOGO's Mimic at 2 BP.
-- Doom outlasts Bum Rush's four blows (at most 4 x 9,999), so the copy runs with no state written (#388: the
-- factory's random battles needed every monster's HP raised to 60,000, a declared expedient this replaces; in them
-- the four blows ended all 12 battles before the copy ran, and in Inferno's SABIN fell before his bank reached
-- three: build/attempts/wt/v041-cleave-bumrush/bumrushmimic/).  The run ends once the copy has resolved; the
-- battle is not fought out (a mechanism test, no claim about play).
-- Asserted, in Doom's battle:
--   SABIN's command entered and ran Bum Rush ($64) at 3 BP pending;
--   GOGO's command entered as Bum Rush ($64, the copy) at 2 BP pending, ran Pummel ($5D: Ot6BlitzTake rewrote $b6),
--   set the multi-attack counter to 1 (Pummel's two blows, not Bum Rush's four), and cost GOGO no MP.
-- Old-ROM red and mutants: build/attempts/wt/v041-cleave-bumrush/bumrushmimic/ (the factory version);
-- build/attempts/wt/v041-tower-laps/bumrushmimic/ (this one).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local SABIN, GOGO = 0x05, 0x0C
local CMD_BLITZ, CMD_MIMIC = 0x0A, 0x12
local BUMRUSH, PUMMEL = 0x64, 0x5D
local MIMIC_BOOST = 2
local DOOM = 0x127

local seats, recs, mode, battles, done = {}, {}, nil, 0, false
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function whoY()
  local y = emu.getState()["cpu.y"] & 0xFF
  for who, s in pairs(seats) do if s * 2 == y then return who end end
  return nil
end
local function whoX()
  local x = emu.getState()["cpu.x"] & 0xFF
  for who, s in pairs(seats) do if s * 2 == x then return who end end
  return nil
end

local function arm()
  local take, hc, ae = H.sym("Ot6BlitzTake"), H.sym("Ot6HitCount"), H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local who = whoY()
    if who == nil or recs[who] ~= nil then return end
    local e = seats[who] * 2
    recs[who] = { cmdId = emu.getState()["cpu.a"] & 0xFF, pend = H.readByte(0x3E9D + e),
      mp0 = H.readWord(0x3C08 + e), f = H.frame, sets = {} }
    recs.open = who
  end, emu.callbackType.exec, take, take)
  emu.addMemoryCallback(function()
    local r = recs.open and recs[recs.open]
    if r == nil or r.ran ~= nil then return end
    r.ran = H.readByte(0xB6)
  end, emu.callbackType.exec, hc, hc)
  emu.addMemoryCallback(function(_, v)
    local r = recs.open and recs[recs.open]
    if r == nil or r.ran == nil or r.ended or v == 0xFF then return end
    r.sets[#r.sets + 1] = v
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  emu.addMemoryCallback(function()
    local who = whoX()
    local r = who and recs[who]
    if r == nil or r.ended or r.ran == nil then return end
    r.ended = H.frame
    r.mp1 = H.readWord(0x3C08 + seats[who] * 2)
    if recs.open == who then recs.open = nil end
  end, emu.callbackType.exec, ae, ae)
end
local function closed() return recs[GOGO] ~= nil and recs[GOGO].ended ~= nil and H.frame > recs[GOGO].ended + 30 end

local function decide()
  battles = battles + 1
  H.assertEq(H.formationHas({ [DOOM] = true }), true, "the battle is Doom's (event battle 98)")
  seats, recs, plan, mode = {}, {}, {}, "play"
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id == SABIN or id == GOGO then seats[id] = s end
  end
  H.assertEq(seats[SABIN] ~= nil and seats[GOGO] ~= nil, true, "SABIN and GOGO are seated (party 3)")
  local function can(who)
    local e = seats[who] * 2
    return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0 and (H.readByte(0x3EE5 + e) & 0x18) == 0
  end
  local sp = H.readWord(0x3C08 + seats[SABIN] * 2)
  H.log(string.format("[bumrushmimic] battle %d: SABIN seat %d MP %d bank %d; GOGO seat %d bank %d", battles,
    seats[SABIN], sp, H.readByte(0x3E9C + seats[SABIN] * 2), seats[GOGO], H.readByte(0x3E9C + seats[GOGO] * 2)))
  H.assertEq(can(SABIN) and can(GOGO), true, "SABIN and GOGO can act as Doom's battle opens")
  H.assertEq(sp >= 99, true, "SABIN holds Bum Rush's 99 MP (the care before Doom)")
  plan = { { who = SABIN, cmd = CMD_BLITZ, row = BUMRUSH, boost = 3, direct = true },
           { who = GOGO, cmd = CMD_MIMIC, boost = MIMIC_BOOST, self = true } }
end

local function judge()
  local s, g = recs[SABIN], recs[GOGO]
  H.log(string.format("[bumrushmimic] SABIN: entered $%02X at %d BP, ran $%02X | GOGO: entered $%02X at %d BP, "
    .. "ran $%02X, $3a70 {%s}, MP %d -> %d", s and s.cmdId or 0, s and s.pend or -1, s and s.ran or 0, g.cmdId,
    g.pend, g.ran or 0, table.concat(g.sets, ","), g.mp0, g.mp1 or -1))
  if s == nil or s.cmdId ~= BUMRUSH or g.cmdId ~= BUMRUSH then
    H.log("[bumrushmimic] GOGO's Mimic did not copy SABIN's Bum Rush here: not counted")
    return false
  end
  H.assertEq(s.pend, 3, "SABIN's Bum Rush ran at 3 BP pending")
  H.assertEq(s.ran, BUMRUSH, "and as Bum Rush")
  H.assertEq(g.pend < 3, true, "GOGO's copy ran under three points pending")
  H.assertEq(g.ran, PUMMEL, "GOGO's copy of Bum Rush under three points ran as Pummel ($5D, Ot6BlitzTake)")
  H.assertEq(#g.sets >= 1 and g.sets[1] == 1, true, "with Pummel's two blows (the multi-attack counter set to 1)")
  H.assertEq(g.mp1, g.mp0, "and cost GOGO nothing (Mimic is free)")
  return true
end

local K = H.worLegKit({ fight = {}, links = {}, names = H.SPLIT_NAMES })
local T = H.kefkaTowerKit(K, {})
local door, walk, sw, settled = T.door, T.walk, K.sw, K.settled
H.NAV_REFIRE_HOLD = true

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-kt-guardian-v1"),
  H.call(function()
    arm()
    H.assertEq(H.readByte(0x1D28) & 0x80, 0x80, "SABIN knows Bum Rush ($1D28 bit 7: Duncan, gen_wor_gau)")
    H.assertEq(sw(0x0072), 0, "Doom not yet fought ($0072)")
  end),
  -- gen_wor_kt_doom's walk, without its training and dress: party 2 opens the cell doors, party 3 to Doom
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 1 } }),
  H.switchParty(2),
  door(12, 17, 355, "party 2: 291 (12,17) -> the chamber's middle (39,5)"),
  door(39, 20, 337, "party 2: the chamber's south door (39,20) -> 337 (8,5)"),
  walk(8, 6, "party 2 onto 337 (8,6): the cell doors"),
  H.waitUntil(function() return sw(0x00D0) == 1 and settled() end, 1200, "the cell doors open ($00D0)", 1),
  H.switchParty(3),
  door(35, 18, 337, "party 3: the west column (35,18) -> 337's west cell (4,6)"),
  door(2, 5, 355, "party 3: the west cell's door (2,5) -> 355 (31,17)"),
  door(31, 8, 291, "party 3: 355 (31,8) -> 291 (6,15)"),
  door(6, 9, 355, "party 3: 291 (6,9) -> 355 (64,19)"),
  H.fieldCare({ threshold = 1.0, tag = "before Doom" }),
  H.call(function()
    H.assertEq(H.activeParty(), 3, "party 3 walks to Doom")
  end),
  H.navTo(64, 12, { maxFrames = 20000, playBattles = "tactical", spare = { DOOM },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [DOOM] = true })) or (H.fieldX() == 64 and H.fieldY() == 12)
    end }),
  H.waitUntil(function() return H.battleActive() and H.formationHas({ [DOOM] = true }) end, 3000,
    "Doom's battle opens", 1),
  H.call(decide),
  H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = closed }),
  H.call(function()
    H.assertEq(closed(), true, "GOGO's copy resolved inside Doom's battle")
    H.assertEq(judge(), true, "GOGO's Mimic copied SABIN's Bum Rush (no other action between)")
    H.log("[bumrushmimic] PASS: GOGO's Mimic of SABIN's Bum Rush, under three of GOGO's points, ran as Pummel "
      .. "and cost nothing")
  end),
})
