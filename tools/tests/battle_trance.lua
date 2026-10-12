-- @suite slow
-- battle_trance.lua -- Terra's Morph: any boost, and the boost buys its
-- duration; at 3 BP (Trance, the divine) it lasts the battle (#378, #427).
--
-- kits.md, Terra: Morph is vanilla's esper form (magic x2, damage taken
-- halved).  Under 3 BP it lasts a fixed span that grows with the boost
-- (ot6_trance.asm OT6_MORPH_SPEED: the counter's speed, DecMorphCounter
-- subtracting it from $FFFF once a battle tick); at 3 BP it is vanilla's
-- permanent morph, no morphed character in $3EE2 and nothing clocked, so she
-- stays morphed until the battle ends or she reverts.  Vanilla's
-- cross-battle gauge ($1CF6) neither sets the span nor locks the command.
--
-- Played: Continue fc-alcove-v1 (TERRA L26, Morph learned at Zozo), walk
-- onto the continent into a random battle, and play TERRA through the real
-- menu (H.kitBattle); the others Fight while two or more monsters stand and
-- Defend once one is left, so the battle stays up.  Nothing is written.
-- Four steps, each once:
--   0, 1  Morph at 0 BP, then at 1 BP: she morphs, the clock starts
--         ($3EE2 = her seat), and it runs out after SPAN[b] ticks (the
--         battle tick counter $3A3E); the bank pays b (at 0, it banks);
--   2     Morph picked at 3 BP and taken back to 2 at target select (L):
--         she morphs for the 2-BP span and the bank pays two;
--   3     Morph at 3 BP: she morphs, nothing is clocked ($3EE2 stays $FF,
--         no gauge in $3B04), the bank pays three, and she is still morphed
--         HOLD ticks later (longer than the 2-BP span), or when the battle
--         ends if it ends after the 2-BP span.
-- One step a battle: once it is done the party Fights the battle out and
-- the next step waits for the next random battle (holding one battle up
-- for every span cost a wipe, two Ninjas the party's Fights cannot touch:
-- build/attempts/wt/v029-kits/mac4/new__battle_trance_k3.out).  A battle
-- that ends before its step is done starts it over in the next, up to
-- BATTLES.  Each span's log line also counts
-- TERRA's turns inside it (the duration design's measurement, kits.md).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, MORPH = 0x00, 0x03
local BATTLES = 12
-- the designed spans, in battle ticks, for speeds 110, 82, 66 (a speed s
-- runs $FFFF out in floor(65535 / s) + 1 subtractions)
local SPAN = { [0] = 596, [1] = 800, [2] = 993 }
local HOLD = 1200

local seat, battles = nil, 0
local stepped = false     -- a step finished in this battle: the rest wait for the next
local done = { [0] = false, [1] = false, [2] = false, [3] = false }
local function e() return seat * 2 end
local function ticks() return H.readByte(0x3A3E) | (H.readByte(0x3A3F) << 8) end
local function morphed() return seat ~= nil and (H.readByte(0x3EF9 + e()) & 0x08) ~= 0 end
local function inBattle() return H.battleLoadStarted() end

-- TERRA's Ot6ActionEnd for her Morph ($3A7C = $03): bank at entry, the frame
-- after; her ActionEnds of any command, for the turn count
local ends, turns = {}, 0
-- the morph now watched: { t0 = ticks at the clock's start (or the morph's,
-- at 3 BP), turns0, clocked, t1 = ticks when the clock ran out }
local cur = nil
local function arm()
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if seat == nil or (emu.getState()["cpu.x"] & 0xff) ~= seat * 2 then return end
    turns = turns + 1
    H.log(string.format("[trance] f%d tick %d: TERRA's action ends (command $%02X), morphed %s", H.frame, ticks(),
      H.readByte(0x3A7C), tostring(morphed())))
    if H.readByte(0x3A7C) == MORPH then
      ends[#ends + 1] = { f = H.frame, pre = H.readByte(0x3E9C + seat * 2) }
    end
  end, emu.callbackType.exec, ae, ae)
  local lastM, lastC = false, false
  emu.addEventCallback(function()
    if seat == nil or not H.battleActive() then lastM, lastC = false, false; return end
    local x = ends[#ends]
    if x ~= nil and x.post == nil and H.frame > x.f then x.post = H.readByte(0x3E9C + e()) end
    local m, c = morphed(), H.readByte(0x3EE2) == e()
    if m and not lastM and cur ~= nil and cur.m0 == nil then
      cur.m0, cur.t0m, cur.turns0 = H.frame, ticks(), turns
      H.log(string.format("[trance] f%d tick %d: TERRA morphed (%d BP)", H.frame, ticks(), cur.b))
    end
    if c and not lastC and cur ~= nil then
      cur.clocked, cur.t0 = true, ticks()
      H.log(string.format("[trance] f%d tick %d: her clock starts, speed $3F32 = %d", H.frame, cur.t0,
        H.readByte(0x3F32) | (H.readByte(0x3F33) << 8)))
    end
    if lastC and not c and cur ~= nil and cur.t1 == nil then
      cur.t1, cur.turns1 = ticks(), turns
      H.log(string.format("[trance] f%d the %d-BP clock ran out after %d ticks (%d of TERRA's turns inside it)",
        H.frame, cur.b, cur.t1 - cur.t0, cur.turns1 - cur.turns0))
    end
    lastM, lastC = m, c
  end, emu.eventType.endFrame)
end

local function lastEnd() return ends[#ends] end
-- the step's Morph has resolved (its ActionEnd, the bank read after it), and:
--   under 3 BP, the clock ran out (or she is no longer morphed: a death);
--   at 3 BP, HOLD ticks passed since she morphed
local function stepDone()
  if cur == nil or #ends <= cur.mark or lastEnd().post == nil then return false end
  if cur.m0 == nil then return H.frame > lastEnd().f + 120 end   -- resolved, no morph: the step decides
  if cur.b < 3 then return not morphed() end   -- her clock ran out and the revert landed (or she fell)
  return ticks() - cur.t0m >= HOLD or not morphed()
end

local ONE = { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 150000, planDone = stepDone }

-- the pick must land: TERRA morphs within PICK frames of the step's start
-- (the bank filled by Defends and the menu walked: 80-380 frames on the
-- branch's runs; three Defends from an empty bank, at her ~230 ticks a
-- turn, are ~1,500), unless she falls first.  A ROM that refuses the Morph
-- at the command fails here, by name (main's ROM at 4000 lost her first:
-- build/attempts/wt/v029-kits/r3/old__battle_trance.out).
local PICK = 2400
local function alive() return seat ~= nil and (H.readByte(0x3EE4 + e()) & 0xC2) == 0 end
local function watched(inner)
  return { tick = function(_)
    if cur ~= nil and cur.m0 == nil and alive() and H.battleActive() and H.frame - cur.f0 > PICK then
      H.assertEq(false, true, string.format("Morph at %d BP: TERRA morphs within %d frames of the pick's start "
        .. "(it was refused at the command, or never confirmed)", cur.b, PICK))
    end
    return inner:tick()
  end, reset = function(_) if inner.reset then inner:reset() end end }
end

local function step(b)
  local entry = { who = TERRA, cmd = MORPH, boost = b, self = true }
  if b == 2 then entry = { who = TERRA, cmd = MORPH, boost = 3, self = true, takeBack = 2 } end
  return H.cond(function() return not done[b] and not stepped and inBattle() end, {
    H.call(function() cur = { b = b, mark = #ends, f0 = H.frame } end),
    watched(H.kitBattle({ entry }, ONE)),
    H.call(function()
      local x = lastEnd()
      if #ends <= cur.mark or x.post == nil then
        H.log(string.format("[trance] battle %d ended before the %d-BP Morph resolved: the next", battles, b))
        return
      end
      if cur.m0 == nil and not alive() then
        H.log(string.format("[trance] TERRA fell before the %d-BP Morph: the next battle", b))
        return
      end
      if b == 2 then
        H.assertEq(H.vars.kit[1] ~= nil and H.vars.kit[1].boost, 2, "the Morph was taken back to 2 BP at target select")
      end
      H.assertEq(cur.m0 ~= nil, true, string.format("Morph at %d BP: TERRA morphed", b))
      if b == 0 then
        H.assertEq(x.post >= x.pre, true, "Morph at 0 BP: the bank paid nothing")
      else
        H.assertEq(x.pre - x.post, b, string.format("Morph at %d BP: the bank paid %d", b, b))
      end
      if b < 3 then
        if cur.t1 == nil then
          H.log(string.format("[trance] the %d-BP morph ended without its clock running out (morphed %s): the next battle",
            b, tostring(morphed())))
          return
        end
        H.assertEq(cur.clocked, true, string.format("Morph at %d BP is clocked ($3EE2 = her seat)", b))
        H.assertEq(cur.t1 - cur.t0, SPAN[b], string.format("Morph at %d BP lasts its span, in battle ticks", b))
      else
        H.assertEq(cur.clocked == true, false, "Morph at 3 BP is not clocked ($3EE2 stays $FF)")
        H.assertEq(H.readByte(0x3B04 + e()), 0, "and shows no gauge")
        local held = ticks() - cur.t0m
        if not morphed() then
          H.assertEq(inBattle(), false, string.format("Morph at 3 BP: she is morphed until the battle ends (reverted after %d ticks)", held))
        end
        if held < HOLD then
          H.log(string.format("[trance] the 3-BP morph held %d ticks before the battle ended: the next", held))
          return
        end
        H.log(string.format("[trance] the 3-BP morph held %d ticks (%d of TERRA's turns), clock off, still morphed",
          held, turns - cur.turns0))
      end
      done[b] = true
      stepped = true
    end),
  }, {})
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("trance"),
  H.driveUntil(function() return done[0] and done[1] and done[2] and done[3] end, 850000, {
    H.cond(function() return not inBattle() end, { H.fcPace("trance") }, {}),
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= BATTLES, true, string.format("the four steps within %d battles", BATTLES))
      seat, stepped = nil, false
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
      H.assertEq(seat ~= nil, true, "TERRA is seated")
      local has = false
      for r = 0, 3 do if H.readByte(0x202E + seat * 12 + r * 3) == MORPH then has = true end end
      H.assertEq(has, true, "TERRA's command list holds Morph (learned at Zozo)")
      H.log(string.format("[trance] battle %d: TERRA seat %d, bank %d, vanilla's gauge $1CF6 = %02X (unread)", battles,
        seat, H.readByte(0x3E9C + e()), H.readByte(0x1CF6)))
    end),
    step(0), step(1), step(2), step(3),
    H.call(function()
      if done[0] and done[1] and done[2] and done[3] then
        H.log(string.format("[trance] PASS: Morph at 0, 1 and 2 BP lasts %d, %d and %d ticks and pays its boost "
          .. "(2 by a take-back from 3); at 3 BP nothing is clocked and she holds the morph (battle %d)",
          SPAN[0], SPAN[1], SPAN[2], battles))
      end
    end),
    H.cond(function() return not (done[0] and done[1] and done[2] and done[3]) and inBattle() end, {
      H.kitBattle({}, { untilPlanDone = false }),   -- fight this one out
    }, {}),
  }, "TERRA's four Morphs"),
})
