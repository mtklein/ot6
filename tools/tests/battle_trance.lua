-- @suite slow
-- battle_trance.lua -- Terra's Trance (her Morph) takes a full 3-BP boost (#378).
--
-- kits.md "Divines": a divine's one gate is a full 3-BP boost, and Trance is
-- TERRA's Morph command (vanilla's esper form: magic x2, damage taken
-- halved, for as long as the morph gauge lasts).  Picked with fewer than
-- three points pending, Morph buzzes and the command window stays up
-- (Ot6TranceOffer, the C1 stub OpenCmdMenuTbl[$03] points at); at 3 BP she
-- morphs, the three points are spent, and she can do it again in the same
-- battle (Revert is free).
--
-- Played: Continue fc-alcove-v1 (TERRA L26, Morph learned at Zozo, the
-- gauge partly full), walk onto the continent into a random battle, and
-- play TERRA through the real menu (H.kitBattle); everyone else Defends.
-- Nothing is written.  In order:
--   1. Morph at 0 BP: refused at the command (three A presses, the window
--      stays up), no morph, the bank unmoved;
--   2. Morph at 3 BP: she morphs ($3EF9 bit 3), the bank pays 3;
--   3. Revert, then Morph at 3 BP again: she morphs a second time.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/trance/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, MORPH, REVERT = 0x00, 0x03, 0x04

local seat = nil
local morphs, bank0 = 0, nil
local function e() return seat * 2 end
local function morphed() return (H.readByte(0x3EF9 + e()) & 0x08) ~= 0 end
local function bank() return H.readByte(0x3E9C + e()) end

local function arm()
  -- each morph: Cmd_03's status write, read at its edge -- $3EF9 bit 3 going up
  local last = false
  emu.addMemoryCallback(function()
    if seat == nil then return end
    local now = morphed()
    if now and not last then
      morphs = morphs + 1
      H.log(string.format("[trance] f%d TERRA morphed (%d), bank %d, pending %d", H.frame, morphs, bank(),
        H.readByte(0x3E9D + e())))
    end
    last = now
  end, emu.callbackType.write, 0x7E3EF9, 0x7E3EF9 + 6)
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("trance"),
  H.call(function()
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
    H.assertEq(seat ~= nil, true, "TERRA is seated")
    local has = false
    for r = 0, 3 do if H.readByte(0x202E + seat * 12 + r * 3) == MORPH then has = true end end
    H.assertEq(has, true, "TERRA's command list holds Morph (learned at Zozo)")
    H.log(string.format("[trance] TERRA seat %d, bank %d, gauge $1CF6 = %02X", seat, bank(), H.readByte(0x1CF6)))
  end),
  H.kitBattle({ { who = TERRA, cmd = MORPH, boost = 0, refused = "command" } },
    { untilPlanDone = true, idle = "defend" }),
  H.call(function()
    bank0 = bank()
    H.assertEq(H.vars.kit[1] and H.vars.kit[1].refusedSeen, true, "Morph at 0 BP was refused at the command")
    H.assertEq(morphed(), false, "and TERRA did not morph")
  end),
  H.kitBattle({ { who = TERRA, cmd = MORPH, boost = 3, self = true } },
    { untilPlanDone = true, idle = "defend", maxFrames = 60000,
      planDone = function() return morphs >= 1 and H.readByte(0x3E9D + e()) == 0 end }),
  H.call(function()
    H.assertEq(morphs, 1, "Morph at 3 BP: TERRA morphed")
    H.assertEq(H.vars.kit[1].boost, 3, "with three points pending at the pick")
  end),
  H.kitBattle({ { who = TERRA, cmd = REVERT, boost = 0, self = true },
    { who = TERRA, cmd = MORPH, boost = 3, self = true } },
    { untilPlanDone = true, idle = "defend", maxFrames = 90000,
      planDone = function() return morphs >= 2 end }),
  H.call(function()
    H.assertEq(morphs, 2, "after a Revert, a second 3-BP Morph in the same battle morphed her again")
    H.log("[trance] PASS: refused at 0 BP, morphed at 3 BP, and again in the same battle")
  end),
})
