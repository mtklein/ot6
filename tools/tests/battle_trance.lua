-- @suite slow
-- battle_trance.lua -- Terra's Trance (her Morph) takes a full 3-BP boost (#378).
--
-- kits.md "Divines": a divine's one gate is a full 3-BP boost, and Trance is
-- TERRA's Morph command (vanilla's esper form: magic x2, damage taken
-- halved, for as long as the morph gauge lasts).  Picked with fewer than
-- three points pending, Morph buzzes and the command window stays up
-- (Ot6TranceOffer, the C1 stub OpenCmdMenuTbl[$03] points at); picked at
-- three and taken back at target select, it does nothing and charges
-- nothing (Ot6TranceGate zeroes the pending boost); at 3 BP she morphs, the
-- three points are spent, and she can do it again in the same battle
-- (Revert is free).
--
-- Played: Continue fc-alcove-v1 (TERRA L26, Morph learned at Zozo, the
-- gauge partly full), walk onto the continent into a random battle, and
-- play TERRA through the real menu (H.kitBattle); the others Fight while two
-- or more monsters stand and Defend once one is left, so the party outlasts
-- the continent's hardest draws and the battle stays up.  Nothing is
-- written.  In one battle:
--   1. Morph at 0, 1 and 2 BP: each refused at the command (three A
--      presses, the window stays up), and she does not morph;
--   2. Morph picked at 3 BP and taken back to 2 at target select (L): her
--      action resolves, she does not morph, and the bank pays nothing;
--   3. Morph at 3 BP: she morphs ($3EF9 bit 3), and the bank pays all
--      three points (read at her Morph's Ot6ActionEnd and the frame after);
--   4. Revert, then Morph at 3 BP again: she morphs a second time.
-- A battle that ends before all four (the others' Fights fell the last
-- body) is left and the next random battle starts them over, up to BATTLES.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_trance.out).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, MORPH, REVERT = 0x00, 0x03, 0x04
local BATTLES = 6

local seat = nil
local morphs, refused, done, battles = 0, false, false, 0
local tookBack, spent = false, false
-- TERRA's Ot6ActionEnd for her Morph command ($3A7C): { f, pre = the bank
-- at its entry, post = the bank the frame after (the charge landed) }
local ends = {}
local function e() return seat * 2 end
local function morphed() return seat ~= nil and (H.readByte(0x3EF9 + e()) & 0x08) ~= 0 end

local function arm()
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if seat ~= nil and (emu.getState()["cpu.x"] & 0xff) == seat * 2 and H.readByte(0x3A7C) == MORPH then
      ends[#ends + 1] = { f = H.frame, pre = H.readByte(0x3E9C + seat * 2) }
    end
  end, emu.callbackType.exec, ae, ae)
  emu.addEventCallback(function()
    local x = ends[#ends]
    if x ~= nil and x.post == nil and H.frame > x.f and seat ~= nil and H.battleActive() then
      x.post = H.readByte(0x3E9C + seat * 2)
    end
  end, emu.eventType.endFrame)
  -- each morph: $3EF9 bit 3 going up for TERRA's seat, read at each
  -- frame's end (a write callback sees the byte before the write lands)
  local last = false
  emu.addEventCallback(function()
    if seat == nil or not H.battleActive() then return end   -- (battle RAM is torn down at the end)
    local now = morphed()
    if now and not last then
      morphs = morphs + 1
      H.log(string.format("[trance] f%d TERRA morphed (%d this battle), bank %d, pending %d", H.frame, morphs,
        H.readByte(0x3E9C + e()), H.readByte(0x3E9D + e())))
    end
    last = now
  end, emu.eventType.endFrame)
end

local function inBattle() return H.battleLoadStarted() end
-- a Morph of hers picked in this step has resolved: its Ot6ActionEnd came
-- (after ends.mark) and the frame after it read the bank
local function resolved()
  return #ends > ends.mark and ends[#ends].post ~= nil and H.frame > ends[#ends].f + 30
end
local ONE = { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 60000 }

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("trance"),
  H.driveUntil(function() return done end, 500000, {
    H.cond(function() return not inBattle() end, { H.fcPace("trance") }, {}),
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= BATTLES, true, string.format("the four steps within %d battles", BATTLES))
      seat, morphs, refused, tookBack, spent = nil, 0, false, false, false
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
      H.assertEq(seat ~= nil, true, "TERRA is seated")
      local has = false
      for r = 0, 3 do if H.readByte(0x202E + seat * 12 + r * 3) == MORPH then has = true end end
      H.assertEq(has, true, "TERRA's command list holds Morph (learned at Zozo)")
      H.log(string.format("[trance] battle %d: TERRA seat %d, bank %d, gauge $1CF6 = %02X", battles, seat,
        H.readByte(0x3E9C + e()), H.readByte(0x1CF6)))
    end),
    H.kitBattle({ { who = TERRA, cmd = MORPH, boost = 0, refused = "command" },
      { who = TERRA, cmd = MORPH, boost = 1, refused = "command" },
      { who = TERRA, cmd = MORPH, boost = 2, refused = "command" } }, ONE),
    H.call(function()
      if not inBattle() then return end
      local kit = H.vars.kit
      refused = #kit == 3
      for i = 1, #kit do refused = refused and kit[i].refusedSeen end
      H.assertEq(refused, true, "Morph at 0, 1 and 2 BP was refused at the command")
      H.assertEq(morphed(), false, "and TERRA did not morph")
    end),
    H.call(function() ends.mark = #ends end),
    H.kitBattle({ { who = TERRA, cmd = MORPH, boost = 3, self = true, takeBack = 2 } },
      { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 60000, planDone = resolved }),
    H.call(function()
      if not inBattle() or #ends == ends.mark then return end
      local x = ends[#ends]
      H.log(string.format("[trance] taken back: her Morph resolved at f%d, bank %d -> %d, morphs %d", x.f, x.pre,
        x.post, morphs))
      H.assertEq(H.vars.kit[1] ~= nil and H.vars.kit[1].boost, 2, "the Morph was taken back to 2 BP at target select")
      H.assertEq(morphs, 0, "Morph taken back under 3 BP: TERRA did not morph")
      H.assertEq(x.post >= x.pre, true, "and the bank paid nothing (Ot6TranceGate zeroed the pending boost)")
      tookBack = true
    end),
    H.call(function() ends.mark = #ends end),
    -- her Morph has resolved (her Ot6ActionEnd for command $03 after the
    -- pick; an earlier Defend of hers can end after it), whatever it did
    H.kitBattle({ { who = TERRA, cmd = MORPH, boost = 3, self = true } },
      { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 60000, planDone = resolved }),
    H.call(function()
      if not inBattle() or #ends == ends.mark then return end
      local x = ends[#ends]
      H.log(string.format("[trance] at 3 BP: her Morph resolved at f%d, bank %d -> %d", x.f, x.pre, x.post))
      H.assertEq(morphs, 1, "Morph at 3 BP: TERRA morphed")
      H.assertEq(x.pre - x.post, 3, "and the bank paid all three points")
      spent = true
    end),
    H.kitBattle({ { who = TERRA, cmd = REVERT, boost = 0, self = true },
      { who = TERRA, cmd = MORPH, boost = 3, self = true } },
      { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 90000,
        planDone = function() return morphs >= 2 end }),
    H.call(function()
      if refused and tookBack and spent and morphs >= 2 then
        done = true
        H.log(string.format("[trance] PASS: refused at 0, 1 and 2 BP, taken back at target select for nothing, "
          .. "morphed at 3 BP for all three points, and again in the same battle (battle %d)", battles))
      else
        H.log(string.format("[trance] battle %d ended before the four steps (refused %s, taken back %s, spent %s, "
          .. "morphs %d): the next", battles, tostring(refused), tostring(tookBack), tostring(spent), morphs))
      end
    end),
    H.cond(function() return not done and inBattle() end, {
      H.kitBattle({}, { untilPlanDone = false }),   -- fight this one out
    }, {}),
  }, "TERRA's four steps in one battle"),
})
