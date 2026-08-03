-- gen_tunnelarmr.lua -- from celes_freed.mss (LOCKE + CELES in the South
-- Figaro basement) out through the clock's secret passage, across the world
-- to the Figaro cave, to the doorstep of the TunnelArmr fight that ends the
-- Locke scenario.
-- Mints:
--   sfigaro_escape.mss    on the world map, out of occupied South Figaro
--   tunnelarmr_doorstep.mss  map 70, one tile short of the (47,38) trigger
--
-- THE CLOCK IS THE ESCAPE, and this is the correction to gen_celes's note 6.
-- All three of the basement's forward exits are dead-end pockets -- map 84's
-- (8,57) landing does not reach its (57,54) door, map 88 is a save closet,
-- map 89's (106,54) landing reaches only the way back -- and the way UP is
-- blocked by _ca8632's "This passage leads out" shove at (29,9).  The ONLY
-- way on is the clock: winding it (map 84 (18,49)) opens BG at (13,50)
-- (_caecf8, map 84's init _caecf2) and THAT is what makes (15,51) -> map 87
-- reachable.  Measured: (15,51) is walled off before the wind and 17 steps
-- away after it.  So the escape is 84 (clock) -> 87 -> 86 -> town -> world.
--
-- THE CLOCK'S WIND GATE is the $01Bx control-flag alias (gen_celes's note),
-- and the interaction that satisfies it: stand ON the trigger tile (18,49)
-- FACING UP with A held.  CheckEventTriggers re-fires _ca7913 every frame
-- the party is aligned there (field/event.asm:5740), UpdateCtrlFlags (:5416)
-- sets $1EB6 bit0 (facing up) and bit4 (A) the frame before, and the "Wind
-- the clock?" prompt then appears (option 0 = Yes).  (18,48) above is a wall
-- so holding UP pins the facing without moving; A is EDGED so the prompt is
-- not confirmed on the same hold.  Standing BELOW it, or holding UP+A as one
-- continuous press, both fail (measured).
--
-- THE CAVE, with $001A=1 (set on the raft for every scenario), loads map 70
-- -- the TunnelArmr copy -- from its lobby trigger _ca5ef7, where gen_kolts
-- with $001A=0 got map 73.  The cave graph is gen_kolts's, walked the other
-- way: world (75,103) -> map 72 -> ... -> map 71 -> [trigger] -> map 70.
--
-- ISSUE #75 (the honesty conversion): ZERO state writes, and the first
-- honest TunnelArmr in the mint chain's history.  The fight is PLAYED the
-- way it was designed: CELES re-raises RUNIC every turn -- the boss's AI
-- (AIScript::_260) is `attack BATTLE, BOLT, FIRE / wait / attack POISON,
-- SPECIAL, FIRE`, so most of its script rolls a runic-able spell, and the
-- stance eats it, refunds her MP and banks her a BP per absorb -- while
-- LOCKE chips the 5 OT6_PIERCE shields with boosted Fights (R raises his
-- pending boost from the 1 bp every character opens with, A-A-A confirms
-- the boosted Fight; the same drive that beat the Marshal in gen_moogle).
-- Break the shields and the damage window finishes the 1300 HP.  A loss
-- on an event battle is GAME OVER, so the fight rides a retry ladder: the
-- doorstep blob is captured beside the doorstep mint, and each attempt
-- reloads it and waits a different number of frames before stepping onto
-- the trigger -- the battle RNG seed is the frame phase at battle init
-- (gen_whelk_poweron's finding), so each retry genuinely replays a
-- different fight.  This file also carried gen_sfigaro's whole battle
-- toolkit (rideOut's HP pin + kill-bit, clearGateSoldier, stealDriver's
-- command-table pokes) without ever calling any of it -- dead code,
-- deleted in the same pass.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/celes_freed.mss.lua"

-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- party facing, through the party-object offset ($0803)
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); H.cond with an always-true
-- predicate is the library's public way to wrap a list into ONE step
local function seq(steps) return H.cond(function() return true end, steps) end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
-- all EIGHT for door staging: a door at the head of a stair can only be
-- entered diagonally (gen_edgar's finding), and a diagonal candidate has to
-- clear one extra test -- the engine must actually produce that move there
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}

local WATCH = { 0x0103, 0x0104, 0x0105, 0x0107, 0x001C, 0x001D, 0x001E,
                0x0317, 0x01D0, 0x01F0, 0x01F1 }
local function where(tag)
  local out = {}
  for _, s in ipairs(WATCH) do out[#out + 1] = string.format("%04X=%d", s, sw(s)) end
  H.log(string.format("[%s] f%d map=%d (%d,%d) bright=%d ctl=%s | %s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.hasControl()), table.concat(out, " ")))
end

-- Settle after a map load: a fully lit screen plus whatever else the caller
-- names, held for 20 CONSECUTIVE frames, then the 30-frame margin every
-- field fixture uses.  Both halves are load-bearing (gen_kolts's header):
-- a cutscene can report control on a black screen, and a single-sample gate
-- passes mid-load while the field module still holds the old map's state.
-- It DRIVES rather than waits so a dialog on the arrival tile cannot stall
-- it; on a quiet field advanceStory holds the pad empty.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { honest = true }),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- One SHORT leg to a waypoint on the current map.  See note 4: long BFS
-- queries on map 75 run the 4096-node cap dry and answer "no path" for
-- tiles that are plainly walkable, so every cross-town walk is a chain of
-- these rather than one query.
local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000, honest = true }),
    H.release(),
    H.call(function()
      H.assertEq(H.fieldX(), tx, what .. ": at x=" .. tx)
      H.assertEq(H.fieldY(), ty, what .. ": at y=" .. ty)
    end),
  })
end

-- One crossing, all three flavours in one step:
--   * ordinary walkable entrance tile    -> navTo straight onto it
--   * door tile (a wall until CheckDoor)  -> stage on a neighbour, hold in
--   * same-map warp (maps 78/83/86 are built out of them)
-- CheckDoor (field/player.asm:958-1010) only opens a tile whose TILEMAP
-- BYTE is $15/$17/$1C, and only for a party standing directly above or
-- below it; anything else is a wall no amount of holding will move.
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()                       -- see note 5
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  -- THE STAGING TILE IS RE-RESOLVED, NOT LATCHED.  Town NPCs wander, and
  -- the object map they occupy is an input to every passability query, so
  -- the answer is only true for the instant it was asked: measured, the
  -- cafe's annex warp (33,46) resolved as "walkable, stand on it" on one
  -- run and, 36 frames earlier on the next, as "unreachable -- stage at
  -- (33,47)" -- and then navTo could not reach (33,47) either, because the
  -- npc had moved again by the time it planned.  Latching the first answer
  -- turns a transient into a route failure; re-asking every 90 frames lets
  -- the walk recover on its own.
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }                  -- walkable: stand on it
      else
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            fresh = { cx, cy, press }; break
          end
        end
      end
      fresh = fresh or pick or { sx, sy + 1, "up" }
      if pick == nil or fresh[1] ~= pick[1] or fresh[2] ~= pick[2]
         or fresh[3] ~= pick[3] then
        pick = fresh
        H.log(string.format("%s: staging (%d,%d)%s at f%d", what,
          pick[1], pick[2],
          pick[3] and (", hold " .. pick[3] .. " into (" .. sx .. "," .. sy .. ")")
                  or " (walk straight onto the entrance tile)", H.frame))
      end
    end
    return pick
  end
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 20000, arrive = arrived, honest = true }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          H.setPad({ [stage()[3]] = true })
        end),
      }, what .. ": hold into the door"),
    }, {}),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what,
        map(), H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Wind the South Figaro clock: stand ON (18,49) facing UP, edge-tap A until
-- the "Wind the clock?" prompt confirms ($010D=1).  See the header.
-- STEP-BY-STEP BFS WALK to (tx,ty), re-planning EVERY frame and taking only
-- the first step, tapping A through dialogs.  Map 70 needs this over navTo:
-- its verify/re-plan machinery bounces the party off the (47,40)->map 71
-- mouth and the (50,31) "what IS that noise?" trigger into a teleport to
-- (8,3), while a plain "one BFS step at a time" walk threads the same route
-- to (47,38) cleanly (measured: navTo -> (8,3), safeWalk -> (47,38)).
local function safeWalk(tx, ty, what, budget)
  local ph = 0
  local DP = { up = "up", down = "down", left = "left", right = "right",
    upleft = "left", upright = "right", downleft = "left", downright = "right" }
  return seq({
    H.driveUntil(function()
      return H.fieldX() == tx and H.fieldY() == ty and H.hasControl()
    end, budget or 8000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local p = H.bfsPath(tx, ty)
        if p and #p > 0 then H.setPad({ [DP[p[1]]] = true })
        else H.setPad({}) end
      end),
    }, what),
    H.release(),
  })
end

-- Cross a SAME-MAP warp: walk onto (sx,sy), arrival is the destination tile
-- (dx,dy) -- `map changed` is no signal inside a map built of warps.
local function warpTo(sx, sy, dx, dy, dmap, what)
  return seq({
    H.logStep(function()
      return string.format("%s: from (%d,%d)", what, H.fieldX(), H.fieldY())
    end),
    H.navTo(sx, sy, { maxFrames = 20000, honest = true, arrive = function()
      return H.fieldX() == dx and H.fieldY() == dy
    end }),
    H.release(),
    settleField(dmap),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at x=" .. dx)
      H.assertEq(H.fieldY(), dy, what .. ": landed at y=" .. dy)
    end),
  })
end

local function windClock()
  local ph = 0
  return seq({
    hop(18, 49, "onto the clock trigger (18,49)"),
    H.driveUntil(function() return sw(0x010D) == 1 end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "wind the clock ($010D)"),
    H.release(),
    settleField(84),
    H.call(function()
      H.assertEq(sw(0x010D), 1, "$010D -- the clock is wound")
      H.assertEq(H.bfsPath(15, 51) ~= nil, true,
        "the clock passage opened the way to (15,51) -> map 87")
      where("clock wound")
    end),
  })
end

-- gen_kolts's world settle: control + alignment + a lit screen on the
-- overworld engine, held for a while.
local function settleWorld(n)
  local cnt = 0
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 20)
  end
end

-- --------------------------------------------- the honest TunnelArmr win --
-- Battle 67, formation 436: TunnelArmr $0104, 1300 HP behind 5 OT6_PIERCE
-- shields, and an event battle -- a loss is GAME OVER, not a revive.  The
-- policy is the fight's own design (issue #75; the kill-bit that used to
-- end it is gone):
--   * CELES re-raises RUNIC every turn she gets ("down","a": Runic is one
--     row below the resting cursor, and the stance queues with no target
--     select).  The boss's script -- `attack BATTLE, BOLT, FIRE / wait /
--     attack POISON, SPECIAL, FIRE` (AIScript::_260) -- rolls a
--     runic-able spell on most turns, and every absorb refunds her MP
--     and banks her a BP (Ot6RunicBP).  This is the tutorial vanilla
--     wrote for this exact fight, with OT6's economy on top.
--   * LOCKE spends his turns on boosted Fights ("r","a","a","a"): R
--     raises pending boost out of the 1 bp every character opens with
--     (Ot6InitBP; +1 regen per unboosted turn), the A's confirm Fight on
--     the default target.  The R buzzes harmlessly on an empty bank, so
--     the same sequence alternates boosted and plain hits, chips the
--     pierce shields, and the break window multiplies the finish -- the
--     drive that beat the Marshal in gen_moogle.
-- The menu-episode machine is gen_arvis's: presses start only after the
-- menu flag holds 4 consecutive pulses, one button per ~31-frame pulse,
-- and an exhausted sequence backs out with B and rebuilds.
--
-- THE RETRY LADDER.  The fight's RNG seed is the frame phase at battle
-- init (`lda $021e / asl2 / sta $be`, gen_whelk_poweron's measurement),
-- so a lost fight is retried by reloading the doorstep blob captured
-- beside the tunnelarmr_doorstep mint and waiting a different number of
-- frames before stepping onto the trigger -- each attempt genuinely
-- plays a different fight.  Three attempts, then fail loudly.
local MENU, ACTOR, CHID = 0x7BCA, 0x62CA, 0x3ED8
local CHAR_CELES = 0x06
local armrBlob, armrWon = nil, false

local function armrSlot()               -- the boss's monster slot, live
  for i = 0, 5 do
    if H.readByte(0x3aa8 + i * 2) % 2 == 1
       and H.readWord(0x57c0 + i * 2) == 0x0104 then return i end
  end
  return nil
end

local function armrPulse()              -- fresh menu machine per attempt
  local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
  return function()
    if H.readByte(MENU) == 0 then
      mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
      mNoMenu = mNoMenu + 1
      return mNoMenu % 2 == 0 and { "a" } or {}
    end
    mNoMenu = 0
    mStreak = mStreak + 1
    if mStreak < 4 then return {} end
    if mSeq == nil then
      local actor = H.readByte(ACTOR)
      local chid = H.readByte(CHID + actor * 2)
      mSeq = chid == CHAR_CELES and { "down", "a" }      -- Runic
                                 or { "r", "a", "a", "a" } -- boosted Fight
      mIdx = 1
      local s = armrSlot()
      H.log(string.format(
        "armr turn f%d actor=%d chid=%02X seq=%s | armr hp=%d sh=%d | " ..
        "party hp %d/%d bp %d/%d",
        H.frame, actor, chid, table.concat(mSeq, ","),
        s and H.readWord(0x3bfc + s * 2) or -1,
        s and H.readByte(0x3e40 + s * 2) or -1,
        H.readWord(0x3bf4), H.readWord(0x3bf6),
        H.readByte(0x3e9c), H.readByte(0x3e9e)))
    end
    if mIdx <= #mSeq then
      local b = mSeq[mIdx]
      mIdx = mIdx + 1
      return { b }
    end
    mStall = mStall + 1
    if mStall > 2 then
      mSeq, mStall = nil, 0             -- back out; rebuild from scratch
      return { "b" }
    end
    return { "a" }
  end
end

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Reloads the doorstep blob (attempt 1
-- runs in place -- the live timeline IS the blob's timeline), offsets the
-- phase, steps onto the trigger, plays the fight, and decides the outcome
-- on $001E: the win tail sets it on map 70 within ~2000 frames of the
-- teardown, while a loss rides the Annihilated screen into GAME OVER and
-- never sets it.
local function armrAttempt(n)
  local pulse = armrPulse()
  local aPh, giveUp = 0, 0
  local loadReq
  return H.cond(function() return armrWon end, {}, {
    H.logStep(function()
      return string.format("TunnelArmr attempt %d (phase offset %d) at f%d",
        n, (n - 1) * 37, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(armrBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "doorstep reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 70, "reloaded onto map 70")
        H.assertEq(H.fieldX() == 47 and H.fieldY() == 37, true,
          "reloaded at the (47,37) doorstep")
      end),
    }) or seq({}),
    H.waitFrames((n - 1) * 37),         -- vary the battle RNG seed
    H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if H.fieldX() == 47 and H.fieldY() == 37 then
          H.setPad({ down = true }); return
        end
        H.setPad({})
      end),
    }, "step onto (47,38) -> battle 67"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "TunnelArmr up", 10),
    H.waitFrames(120),
    H.call(function()
      H.assertEq(H.formationHas({ [0x0104] = true }), true,
        "battle 67 is TunnelArmr $0104")
      local s = armrSlot()
      H.log(string.format(
        "TunnelArmr up: hp=%d shields=%d/%d (table authors 5, OT6_PIERCE)",
        H.readWord(0x3bfc + (s or 0) * 2), H.readByte(0x3e40 + (s or 0) * 2),
        H.readByte(0x3e41 + (s or 0) * 2)))
      H.assertEq(H.readByte(0x3e40 + (s or 0) * 2), 5,
        "5 shields seeded, per Ot6ShieldTbl $0104")
    end),
    H.driveUntil(function() return not H.battleLoadStarted() end, 60000, {
      H.call(function() H.setPad(pulse()) end),
      H.waitFrames(6),
      H.call(function() H.setPad({}) end),
      H.waitFrames(24),
    }, "TunnelArmr fight (Runic + boosted Fights)"),
    H.logStep(function()
      return string.format("battle 67 torn down at f%d; deciding", H.frame)
    end),
    -- won or lost?  Tap A while control is away (pages the win tail's
    -- "Whew!" and, on a loss, the Annihilated screen); give the tail 3000
    -- frames to flip $001E before calling the attempt lost.
    H.driveUntil(function()
      giveUp = giveUp + 1
      return sw(0x001E) == 1 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not H.hasControl() then H.setPad(aPh < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $001E (or the loss shows itself)"),
    H.call(function()
      H.setPad({})
      if sw(0x001E) == 1 then
        armrWon = true
        H.log(string.format("TunnelArmr BEATEN HONESTLY on attempt %d, f%d",
          n, H.frame))
      else
        H.log(string.format("attempt %d LOST (no $001E after teardown), f%d",
          n, H.frame))
      end
    end),
  })
end

H.run({ maxFrames = 300000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 83, "booted in the basement (map 83)")
    H.assertEq(sw(0x001D), 1, "$001D -- Celes is freed")
    H.assertEq(sw(0x01D1), 1, "$01D1 -- the clock key is in hand")
    H.assertEq(sw(0x001A), 1, "$001A -- the cave will load map 70")
    where("boot (celes_freed)")
  end),

  -- ===================================================================== --
  -- PHASE 1: THE CLOCK.  Down to map 84, wind it, and take the passage it
  -- opens: (15,51) -> map 87 -> (57,48) -> map 86.
  -- ===================================================================== --
  go(57, 13, 83, 35, 14, "celes room -> corridor"),
  go(45, 12, 84, 8, 57, "corridor (45,12) -> map 84 (8,57)"),
  windClock(),
  go(15, 51, 87, 20, 33, "clock passage (15,51) -> map 87 (20,33)"),
  go(57, 48, 86, 49, 31, "map 87 (57,48) -> map 86 (49,31)"),

  -- ===================================================================== --
  -- PHASE 2: OUT OF SOUTH FIGARO.  The "why are you helping me" scene at
  -- (52,29), then (52,27) -> town, then the world.
  -- ===================================================================== --
  -- (52,29)'s "why are you helping me" scene (_ca8973) is flavor -- pure
  -- conversation, sets only $001B.  The crossing to the town door (52,27)
  -- passes right by it; go's driveUntil taps A through whatever it says.
  -- Not required, so not asserted.
  go(52, 27, 75, 48, 36, "map 86 (52,27) -> town (map 75) (48,36)"),
  H.call(function() where("back in occupied town") end),
  -- exit via the x=56 column -> world (87,112)
  H.navTo(56, 34, { maxFrames = 12000, honest = true,
    arrive = function() return H.worldMode() end }),
  H.release(),
  (function()
    local cnt = 0
    return H.advanceStory(function()
      local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
        and bright() >= 15
      cnt = ok and cnt + 1 or 0; return cnt >= 20
    end, 12000, { honest = true })
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "out on the world map, south of the range")
    where("sfigaro_escape (world)")
    H.assertEq(H.worldBfs(75, 102) ~= nil, true,
      "the south cave mouth (75,102) is reachable")
    H.screenshot("sfigaro_escape")
  end),
  H.saveState("sfigaro_escape.mss"),
  H.logStep(function()
    return string.format("sfigaro_escape minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- PHASE 3: THE FIGARO CAVE, walked into from the SOUTH.  world (75,102)
  -- is a world EVENT TRIGGER, not an entrance record (event_trigger.asm:38):
  -- _ca5ee3 with $001A=1 loads map 69 (the TunnelArmr side), where $001A=0
  -- would load map 72.  From map 69, (10,2)/(4,4) -> map 70, and (47,38) on
  -- map 70 is the TunnelArmr trigger _ca89af.
  -- ===================================================================== --
  -- issue #75: honest=true -- a world encounter on the band south of the
  -- range is FOUGHT by real input (LOCKE and CELES both attack under
  -- tap-A), never kill-bitted; the budget carries the ATB rounds.
  H.worldNavTo(75, 102, { maxFrames = 45000, honest = true,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField(69),
  H.call(function()
    H.assertEq(map(), 69, "world (75,102) -> map 69, the cave (map 70 side)")
    where("cave map 69 (16,42)")
  end),

  -- Map 69 is a warp maze (gen_kolts's map 72, mirrored): the landing does
  -- not reach the map-70 mouths.  Two same-map warps then a crossing, each
  -- verified by re-flooding the far side:
  --   (16,42) --walk--> (14,33) --warp--> (55,56)  [reaches (61,57)]
  --   (55,56) --walk--> (61,57) --warp--> (17,21)  [276 tiles, reaches (10,2)]
  --   (17,21) --walk--> (10,2)  --> map 70 (55,31)
  warpTo(14, 33, 55, 56, 69, "cave warp A (14,33) -> (55,56)"),
  warpTo(61, 57, 17, 21, 69, "cave warp B (61,57) -> (17,21)"),
  go(10, 2, 70, 55, 31, "cave (10,2) -> map 70 (55,31)"),
  H.call(function()
    H.assertEq(map(), 70, "on map 70 -- the TunnelArmr cave")
    H.assertEq(H.bfsPath(47, 38) ~= nil, true,
      "the TunnelArmr trigger (47,38) is reachable")
    where("map 70")
  end),

  -- ===================================================================== --
  -- PHASE 4: THE DOORSTEP.  (47,38) fires _ca89af (event_main.asm:20990) ->
  -- battle 67.  Mint one tile SOUTH of it: (47,39), the reachable approach.
  -- (47,40) is past one of map 70's same-map warps -- navTo to it lands the
  -- party at (8,3) instead -- so the doorstep is (47,39), which the flood
  -- from the (55,31) landing reaches on foot.
  -- ===================================================================== --
  -- walk to (47,37), one tile NORTH of the (47,38) trigger.  The approach
  -- from the (55,31) landing threads the (50,31) noise dialog; safeWalk taps
  -- through it.  (47,37) is the last tile before the trigger on that path.
  safeWalk(47, 37, "approach the TunnelArmr trigger", 10000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 70, "still on map 70")
    H.assertEq(H.fieldX() == 47 and H.fieldY() == 37, true,
      "at the (47,37) doorstep, one tile above the trigger")
    H.assertEq(H.hasControl(), true, "controllable at the doorstep")
    H.assertEq(sw(0x001E), 0, "$001E clear -- TunnelArmr not fought yet")
    where("tunnelarmr_doorstep")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("tunnelarmr_doorstep")
  end),
  H.saveState("tunnelarmr_doorstep.mss"),
  H.logStep(function()
    return string.format("tunnelarmr_doorstep minted at frame %d", H.frame)
  end),
  -- capture the same doorstep as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "doorstep retry blob")
        armrBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #armrBlob))
      end),
    })
  end)(),

  -- ===================================================================== --
  -- PHASE 5: TUNNELARMR, PLAYED.  Step DOWN onto (47,38) -> _ca89af ->
  -- battle 67 (formation 436, TunnelArmr $0104: hp 1300, 5/5 shields
  -- OT6_PIERCE, plus the OT6 ice element-add on vanilla's bolt|water).
  -- CELES holds RUNIC up, LOCKE breaks the shields with boosted Fights --
  -- see the armrPulse header above -- with the phase-spread retry ladder
  -- around it.  Then ride _ca89af's tail ("Whew!" / switch $001E=1 / fade
  -- / call _caad4c) back to the hub (map 9).  $001E=1 IS the Locke
  -- scenario complete.  Unlike the kill-bit ancestor, an honest win
  -- routes every hit through Ot6ShieldedDmg -- the first minted state in
  -- the chain whose TunnelArmr actually had his shields broken.
  -- ===================================================================== --
  armrAttempt(1),
  armrAttempt(2),
  armrAttempt(3),
  H.call(function()
    H.assertEq(armrWon, true,
      "TunnelArmr beaten honestly within 3 attempts (Runic + boosted Fights)")
  end),

  -- ride the tail to the hub; $001E already flipped on map 70 (the attempt
  -- decided on it), _caad4c warps home.  Honest: nothing on the scripted
  -- warp can draw a battle, and if one ever did, the A-taps would fight it.
  (function()
    local calm = 0
    return H.driveUntil(function()
      local ok = sw(0x001E) == 1 and map() == 9 and H.hasControl()
             and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, 30000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if not H.hasControl() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "ride back to the scenario hub")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x001E), 1, "$001E=1 -- LOCKE's scenario is COMPLETE")
    H.assertEq(map(), 9, "back at the three-way scenario hub (map 9)")
    H.assertEq(H.hasControl(), true, "controllable at the hub")
    where("locke_done")
    H.screenshot("locke_done")
  end),
  H.saveState("locke_done.mss"),
  H.logStep(function()
    return string.format("locke_done minted at frame %d -- scenario complete", H.frame)
  end),
})
