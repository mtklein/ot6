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
--   4     Morph at 3 BP, then Revert boosted to 2 BP (#430): the permanent
--         morph reverts (her morph bit clears in the battle), and the
--         Revert charges nothing: a boost on it buys nothing, so it is
--         refunded (Ot6RevertTake) and the turn ends as an unboosted one,
--         its regen pip included (bank after = bank before + 1, capped at 5).
-- One step a battle: once it is done the party Fights the battle out and
-- the next step waits for the next random battle (holding one battle up
-- for every span cost a wipe, two Ninjas the party's Fights cannot touch:
-- build/attempts/wt/v029-kits/mac4/new__battle_trance_k3.out).  A battle
-- that ends before its step is done starts it over in the next, up to
-- BATTLES.  Each span's log line also counts
-- TERRA's turns inside it (the duration design's measurement, kits.md).
-- Old-ROM red (main's ROM refuses Morph under 3 BP at the command) and
-- mutants (a span's speed off by one, 3 BP clocked, the boost never
-- reaching the span): build/attempts/wt/v029-kits/r7/ (old ROM) and r8/
-- (mutants; and four encounter histories, PACE_BURN 0-3, green).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, MORPH, REVERT = 0x00, 0x03, 0x04
local FD = H.newFightDriver("trance", { tactical = true, boost = true, items = true, healPercent = 60, nuke = { 0x02 } })
local BATTLES = 15
-- the designed spans, in battle ticks, for speeds 110, 82, 66 (a speed s
-- runs $FFFF out in floor(65535 / s) + 1 subtractions)
local SPAN = { [0] = 596, [1] = 800, [2] = 993 }
local HOLD = 1200

local seat, battles = nil, 0
local stepped = false     -- a step finished in this battle: the rest wait for the next
local done = { [0] = false, [1] = false, [2] = false, [3] = false, [4] = false }
local function e() return seat * 2 end
local function ticks() return H.readByte(0x3A3E) | (H.readByte(0x3A3F) << 8) end
local function morphed() return seat ~= nil and (H.readByte(0x3EF9 + e()) & 0x08) ~= 0 end
local function inBattle() return H.battleLoadStarted() end

-- TERRA's Ot6ActionEnd for her Morph ($3A7C = $03): bank at entry, the frame
-- after; her ActionEnds of any command, for the turn count
local ends, turns = {}, 0
local revEnds = {}   -- her Reverts' ActionEnds: { f, pre, post }
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
    if H.readByte(0x3A7C) == REVERT then
      revEnds[#revEnds + 1] = { f = H.frame, pre = H.readByte(0x3E9C + seat * 2),
        pending = H.readByte(0x3E9D + seat * 2) }
      H.log(string.format("[trance] f%d her Revert ends: bank %d, pending %d at Ot6ActionEnd", H.frame,
        revEnds[#revEnds].pre, revEnds[#revEnds].pending))
    end
  end, emu.callbackType.exec, ae, ae)
  local lastM, lastC = false, false
  emu.addEventCallback(function()
    if seat == nil or not H.battleActive() then lastM, lastC = false, false; return end
    local x = ends[#ends]
    if x ~= nil and x.post == nil and H.frame > x.f then x.post = H.readByte(0x3E9C + e()) end
    local r = revEnds[#revEnds]
    if r ~= nil and r.post == nil and H.frame > r.f then r.post = H.readByte(0x3E9C + e()) end
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
-- the party is in trouble: a member down or under a third of max HP.  A
-- step does not start then, and one under way is let go (the route's
-- driver plays the battle out and the step waits for the next battle):
-- holding a battle up with Defends while two Ninjas cut the party down
-- wiped it (build/attempts/wt/v029-kits/r7/new__battle_trance_k3.out)
local function danger()
  for s = 0, 3 do
    if (H.readByte(0x3AA0 + s * 2) & 1) == 1 then
      local hp, mx = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
      if hp == 0 or hp * 3 < mx then return true end
    end
  end
  return false
end
-- the step's Morph has resolved (its ActionEnd, the bank read after it), and:
--   under 3 BP, the clock ran out (or she is no longer morphed: a death);
--   at 3 BP, HOLD ticks passed since she morphed
local function stepDone()
  if cur ~= nil and danger() then cur.abandoned = true; return true end
  if cur == nil or #ends <= cur.mark or lastEnd().post == nil then return false end
  if cur.m0 == nil then return H.frame > lastEnd().f + 120 end   -- resolved, no morph: the step decides
  if cur.b < 3 then return not morphed() end   -- her clock ran out and the revert landed (or she fell)
  return ticks() - cur.t0m >= HOLD or not morphed()
end

local ONE = { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 150000, planDone = stepDone }

-- the pick must land: TERRA morphs before her command window ($62CA her
-- seat, $7BC2 state $05) has been up PICK frames in the step (a Defend or
-- the Morph pick each take it for well under a hundred), unless she falls
-- first.  A ROM that refuses the Morph at the command keeps it up and fails
-- here, by name.  (Counted in frames since the step began, 2400 was too
-- few when a fresh battle's bank had to be filled and too many on main's
-- ROM, which lost her first: build/attempts/wt/v029-kits/r6/ and r3/.)
local PICK = 900
local function alive() return seat ~= nil and (H.readByte(0x3EE4 + e()) & 0xC2) == 0 end
local function watched(inner)
  return { tick = function(_)
    if cur ~= nil and cur.m0 == nil and H.battleActive() and H.readByte(0x62CA) == seat
        and H.readByte(0x7BC2) == 0x05 then
      cur.window = (cur.window or 0) + 1   -- a frame of her command window up
    end
    if cur ~= nil and cur.m0 == nil and alive() and H.battleActive() and (cur.window or 0) > PICK then
      H.assertEq(false, true, string.format("Morph at %d BP: TERRA morphs before her command window has been "
        .. "up %d frames (it was refused at the command, or never confirmed)", cur.b, PICK))
    end
    return inner:tick()
  end, reset = function(_) if inner.reset then inner:reset() end end }
end

local function step(b)
  local entry = { who = TERRA, cmd = MORPH, boost = b, self = true }
  if b == 2 then entry = { who = TERRA, cmd = MORPH, boost = 3, self = true, takeBack = 2 } end
  return H.cond(function() return not done[b] and not stepped and inBattle() and not danger() end, {
    H.call(function() cur = { b = b, mark = #ends, f0 = H.frame } end),
    watched(H.kitBattle({ entry }, ONE)),
    H.call(function()
      local x = lastEnd()
      if cur.abandoned then
        H.log(string.format("[trance] the party is in trouble: the %d-BP step is let go, the next battle", b))
        stepped = true
        return
      end
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

-- step 4 (#430): Morph at 3 BP, then Revert at 2 BP in the same battle.
-- The Revert's resolution is its ActionEnd (command $04) and the bank read
-- the frame after; the morph bit is read some frames on, when the revert's
-- animation has run.
local REVERT_BOOST = 2
local function revertDone()
  if cur ~= nil and danger() then cur.abandoned = true; return true end
  if cur == nil then return false end
  local r = revEnds[#revEnds]
  if #revEnds <= cur.rmark or r.post == nil then return false end
  return H.frame > r.f + 120
end
local function step4()
  local plan = { { who = TERRA, cmd = MORPH, boost = 3, self = true },
    { who = TERRA, cmd = REVERT, boost = REVERT_BOOST, self = true } }
  local opts = { untilPlanDone = true, idle = "defend", others = "thin", maxFrames = 150000, planDone = revertDone }
  return H.cond(function() return not done[4] and not stepped and inBattle() and not danger() and not morphed() end, {
    H.call(function() cur = { b = 3, mark = #ends, rmark = #revEnds, f0 = H.frame } end),
    watched(H.kitBattle(plan, opts)),
    H.call(function()
      local r = revEnds[#revEnds]
      if cur.abandoned then
        H.log("[trance] the party is in trouble: the Revert step is let go, the next battle")
        stepped = true
        return
      end
      if cur.m0 == nil then
        H.log(string.format("[trance] battle %d: the 3-BP Morph before the Revert did not land: the next", battles))
        return
      end
      if #revEnds <= cur.rmark or r.post == nil then
        H.log(string.format("[trance] battle %d ended before the Revert resolved: the next", battles))
        return
      end
      H.assertEq(cur.clocked == true, false, "the Morph before the Revert is the 3-BP one (not clocked)")
      local k = H.vars.kit[#H.vars.kit]
      H.assertEq(k ~= nil and k.boost, REVERT_BOOST, string.format("the Revert was confirmed at %d BP pending",
        REVERT_BOOST))
      H.assertEq(morphed(), false, "after a 3-BP Morph, Revert reverts her (her morph bit clears)")
      H.assertEq(r.pending, 0, string.format("the Revert's %d-BP boost is dropped before Ot6ActionEnd (pending 0)",
        REVERT_BOOST))
      H.assertEq(r.post, math.min(r.pre + 1, 5), string.format("Revert at %d BP charges nothing and the turn "
        .. "regens a pip (bank %d -> %d)", REVERT_BOOST, r.pre, r.post))
      H.log(string.format("[trance] the Revert at %d BP after a 3-BP Morph: reverted, bank %d -> %d (battle %d)",
        REVERT_BOOST, r.pre, r.post, battles))
      done[4] = true
      stepped = true
    end),
  }, {})
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("trance"),
  H.driveUntil(function() return done[0] and done[1] and done[2] and done[3] and done[4] end, 850000, {
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
    step(0), step(1), step(2), step(3), step4(),
    H.call(function()
      if done[0] and done[1] and done[2] and done[3] and done[4] then
        H.log(string.format("[trance] PASS: Morph at 0, 1 and 2 BP lasts %d, %d and %d ticks and pays its boost "
          .. "(2 by a take-back from 3); at 3 BP nothing is clocked and she holds the morph; a boosted Revert "
          .. "after it reverts and charges nothing (battle %d)",
          SPAN[0], SPAN[1], SPAN[2], battles))
      end
    end),
    H.cond(function() return not (done[0] and done[1] and done[2] and done[3] and done[4]) and inBattle() end, {
      -- the rest of this battle: the route's fight driver plays it out
      -- (Bolt for the Floating Continent's bolt-weak pool, care, boosts);
      -- everyone's plain Fights lost to two Vanished Ninjas (r6, k3)
      H.driveUntil(function() return not inBattle() end, 60000, {
        H.call(function() FD.frame() end),
      }, "the battle played out"),
    }, {}),
  }, "TERRA's four Morphs and a Revert"),
})
