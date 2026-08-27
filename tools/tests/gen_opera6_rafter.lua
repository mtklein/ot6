-- gen_opera6_rafter.lua -- v0.5 Beat A step 6: opera_dance_done (map 238
-- {98,7}, $0111=1) -> the rafter chase -> generate ultros2_entry one
-- interaction before battle 104 (Ultros②, $012d, 6 shields, slash|pierce).
--
-- The crossing was rebuilt 2026-08-27 against a catwalk lab (the
-- probe_rafterlab_* instruments; per-experiment seconds instead of full
-- replays), which measured, across four strategies and ~90 runs
-- (evidence: build/rafterlab/*.log):
--
--   * the chase clock $1189 ticks 1/frame INCLUDING inside battles; a
--     rat fight costs ~2300 frames, so fight COUNT dominates margin;
--   * rat collisions are adjacency-triggered object-side (obj.asm
--     DoCollision checks the four tiles around the RAT), so standing
--     still is not safe and passing a rat in a 1-wide corridor is
--     impossible without the fight;
--   * these fights refuse the run ($b1=$06 held) -- L+R flee attempts
--     only waste frames; a WIN despawns the rat and clears its switch;
--   * the victory exp/gil boxes are battle-module text pages: the fight
--     driver's own menu==0 branch taps A through them once it is given
--     every battle frame (the old code starved it behind a
--     run-refused counter that victory resets -- the deadlock the owner
--     watched);
--   * rat wander is a pure function of the chase clock, blind to party
--     input, and a savestate reload replays it exactly -- so the retry
--     ladder below samples arrangements with LARGE set-off holds (small
--     staggers collapse into identical runs) and can deterministically
--     REPLAY its best attempt;
--   * measured strategy expectation over 8 arrangement fixtures
--     (failures as 0): old held-pad fight-through and halo-avoidance
--     both 0 (never arrived); verified-step fight-through 4163; the
--     dodge policy used below 6938 with 100% arrival, ~3.0 fights.

-- The facing is produced by input rather than poked: the old generator wrote
-- the object facing byte and $0743 to point the party at Ultros; now the last
-- action at the entry point is a short RIGHT press against his occupied tile
-- {15,7}, which is a blocked press that turns the party in place, and the
-- facing is asserted from RAM afterwards.  This file writes no emulated game
-- state.
--
-- The rat gates are played rather than switched off. The five rat NPCs
-- ({8,11} {11,15} {18,14} {21,7} {13,12}, switches $034C-$0350) wander
-- live; each is a no_react collision NPC whose event is `battle 25`, a
-- win despawns it and clears its switch, and a loss restarts the chase.
-- The catwalk crossing fights whichever rats collide, inside the same
-- 5-minute timer the vanilla scene uses.

-- Note: the WoB story encounter is `_cabf4b` -> battle 104.  Battle 134
-- belongs to the WoR Opera House dragon/weight event (`$0387=1`); older route
-- notes conflated the two.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function key(x,y) return y*256+x end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d ctl=%s | 58=%d 110=%d 111=%d 345=%d 355=%d 366=%d 387=%d 1B0=%d 1B4=%d A4=%d 2BA=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    tostring(H.hasControl()),
    sw(0x0058), sw(0x0110), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366),
    sw(0x0387), sw(0x01B0), sw(0x01B4), sw(0x00A4), sw(0x02BA)))
end

local function ratLine()
  local t = {}
  for k = 0, 4 do
    local obj = 24 + k
    local ox = H.readWord(0x086a + 0x29 * obj) >> 4
    local oy = H.readWord(0x086d + 0x29 * obj) >> 4
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(0x034C + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
end
local function ratNear(x, y, r)
  for k = 0, 4 do
    if sw(0x034C + k) == 1 then
      local obj = 24 + k
      local ox = H.readWord(0x086a + 0x29 * obj) >> 4
      local oy = H.readWord(0x086d + 0x29 * obj) >> 4
      if math.abs(ox - x) + math.abs(oy - y) < r then return true end
    end
  end
  return false
end

-- crossRafters: walk to (tx,ty) on map 235 with the five rats live.

local RAT_GATE0, RAT_OBJ0 = 0x034C, 24
-- the eight moves M.bfsPath can return, and what each does to (x,y)
local DELTA8 = { up = {0,-1}, right = {1,0}, down = {0,1}, left = {-1,0},
                 upright = {1,-1}, downright = {1,1},
                 downleft = {-1,1}, upleft = {-1,-1} }
local function ratXY(k)
  local obj = RAT_OBJ0 + k
  return H.readWord(0x086a + 0x29 * obj) >> 4,
         H.readWord(0x086d + 0x29 * obj) >> 4
end
local function liveRats()
  local t = {}
  for k = 0, 4 do
    if sw(RAT_GATE0 + k) == 1 then
      local ox, oy = ratXY(k)
      t[#t + 1] = { k = k, x = ox, y = oy }
    end
  end
  return t
end
local function minRatDist(x, y)
  local best = 99
  for _, r in ipairs(liveRats()) do
    local d = math.abs(r.x - x) + math.abs(r.y - y)
    if d < best then best = d end
  end
  return best
end
-- `res` is a one-field table the caller reads afterwards: res.ok is true only
-- if the party is standing on the goal.  The two ways to fail -- the chase
-- clock running out, and a lost rat fight, which is a wipe -- both end the
-- drive quietly with res.ok false, because the caller is a retry ladder
-- that reloads and tries again.  `hold` (number or thunk) is that ladder's
-- arrangement seed: aligned frames to stand still before setting off.
--
-- The policy is the lab's measured champion ("dodge-h",
-- probe_rafterlab_dodge.lua; E[margin] 6938 over 8 arrangements, 100%
-- arrival, ~3 fights):
--   * pulsed walking: every press is released on the first unaligned
--     frame (a begun 16px step completes on its own); a press held
--     through a step chains past junctions whose BOTH neighbors are
--     walkable -- (19,12), (11,7) -- into a permanent oscillation, which
--     is how every fight-through run died;
--   * route: bfsPath at the goal, re-planned per tile; on nil (a rat is
--     standing on a route tile -- objects are walls to stepAllowed, and
--     with five roamers on a mostly 1-wide network nil is the NORMAL
--     state) fall back to the furthest still-reachable FORWARD waypoint
--     of the measured route; never target anything behind;
--   * gate: refuse a step only when a live rat is within 2 of the next
--     tile or within 1 of tiles 2..4 of the plan.  Light gating measured
--     strictly better than caution: waiting near a deterministic sweep
--     is how the clock dies;
--   * standoff: stand at rat distance >= 3; closer, retreat greedily but
--     never into a dead end; in the start pocket (x<=7, whose only exit
--     is the (7,12) choke) there is no standoff -- push and fight NOW on
--     a fat clock;
--   * watchdog: 600 frames without reaching a NEW waypoint -> push
--     through (fight the blocker); timer < 6000 -> push permanently;
--   * fights: the driver gets every battle frame from load latch to the
--     field's return -- its own menu==0 branch chews the victory boxes.
--     boost=false, cadence=12: measured 232 frames/fight faster than the
--     boosted default, and safer (zero casualties in ~40 lab fights).
local function crossRafters(tx, ty, maxF, hold, res, what)
  local hb, battN, wipeN, notBattN = 0, 0, 0, 0
  local held, lost = 0, nil
  local battleUp, wasInBattle = false, false
  local panicking = false
  local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, 6000, 4
  local wpts = { {8,12}, {8,16}, {11,16}, {11,18}, {13,18}, {13,15},
                 {19,15}, {19,12}, {11,12}, {11,9}, {11,7}, {tx, ty} }
  local prog = 0                        -- highest waypoint index touched
  local plan, planX, planY, planAge = nil, -1, -1, 0
  local waitN, pushMode, pushSteps, fightsSeen = 0, false, 0, 0
  local moveSameN, wig, lastDir = 0, nil, "right"
  local curMv, curMvN = nil, 0
  local chaseK, chaseN = nil, 0
  local fight = H.newFightDriver("rafters",
    { tactical = true, boost = false, cure = false, items = false,
      cadence = 12 })
  local function holdN()
    local h = type(hold) == "function" and hold() or hold
    return h or 0
  end

  local function battleFrame()
    -- Neutral pad until the battle module shows its first interactive
    -- menu; after that the driver owns every frame -- its menu==0 branch
    -- taps A through the victory text, which is what un-parks the
    -- "Got ... Exp. point(s)" box the old code deadlocked under.
    if not battleUp then
      if H.readByte(0x7BCA) ~= 0 then battleUp = true end
      H.setPad({})
      return
    end
    fight.frame()
  end

  -- unrestricted BFS at the goal; on nil, the furthest reachable forward
  -- waypoint (also advances `prog` when standing on one)
  local function planRoute(x, y)
    for i = #wpts, prog + 1, -1 do
      if x == wpts[i][1] and y == wpts[i][2] then prog = i; break end
    end
    local p = H.bfsPath(tx, ty)
    if p and #p > 0 then return p end
    for i = #wpts - 1, prog + 1, -1 do
      p = H.bfsPath(wpts[i][1], wpts[i][2])
      if p and #p > 0 then return p end
    end
    return nil
  end

  local function gateShut(x, y, p)
    local cx, cy = x, y
    for i = 1, math.min(GATEK, #p) do
      local d = DELTA8[p[i]]
      cx, cy = cx + d[1], cy + d[2]
      for _, r in ipairs(liveRats()) do
        local dist = math.abs(r.x - cx) + math.abs(r.y - cy)
        if dist < ((i == 1) and RADIUS + 1 or RADIUS) then return true end
      end
    end
    return false
  end

  local function degree(x, y)
    local n = 0
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      if H.canStep(x, y, mv) then n = n + 1 end
    end
    return n
  end

  local function standoffStep(x, y)
    if minRatDist(x, y) >= 3 then H.setPad({}); return end
    local bestMv, bestD = nil, minRatDist(x, y)
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      if H.canStep(x, y, mv) then
        local d = DELTA8[mv]
        local nx, ny = x + d[1], y + d[2]
        local nd = minRatDist(nx, ny)
        if nd > bestD and degree(nx, ny) >= 2 then bestMv, bestD = mv, nd end
      end
    end
    if bestMv then H.setPad({ [bestMv] = true }) else H.setPad({}) end
  end

  local function currentPlan(x, y)
    if not plan or x ~= planX or y ~= planY or planAge > 16 then
      plan, planX, planY, planAge = planRoute(x, y), x, y, 0
    else
      planAge = planAge + 1
    end
    return plan
  end

  -- commit a pressed direction for a dozen frames: re-deciding every
  -- frame flip-flops the pad so fast no 16px step ever starts.  A press
  -- that holds ~4s without changing the tile means model and engine
  -- disagree: log the tile bytes and wiggle sideways once.
  local function pressMove(x, y, mv)
    if not curMv or curMvN >= 12 then curMv, curMvN = mv, 0 end
    curMvN = curMvN + 1
    lastDir = H.movePress(curMv)
    moveSameN = moveSameN + 1
    if moveSameN >= 240 then
      for _, m in ipairs({ "up", "down", "left", "right" }) do
        if m ~= lastDir and H.canStep(x, y, m) and not wig then
          wig = { dir = m, n = 30 }
        end
      end
      H.log(string.format("cross: STALL at (%d,%d) pressing %s, timer=%d, wiggling %s",
        x, y, lastDir, H.readWord(0x1189), wig and wig.dir or "nowhere"))
      moveSameN = 0
    end
    H.setPad({ [lastDir] = true })
  end

  -- the rat most plausibly plugging the route: nearest to the next
  -- forward waypoint, committed for 300 frames so the chase does not
  -- retarget to every passer-by
  local function blockingRat()
    chaseN = chaseN + 1
    if chaseK and chaseN < 300 and sw(RAT_GATE0 + chaseK) == 1 then
      return chaseK
    end
    local w = wpts[math.min(prog + 1, #wpts)]
    local bestK, bestD = nil, 999
    for _, r in ipairs(liveRats()) do
      local d = math.abs(r.x - w[1]) + math.abs(r.y - w[2])
      if d < bestD then bestK, bestD = r.k, d end
    end
    chaseK, chaseN = bestK, 0
    return bestK
  end

  -- no geometric route at all: hold a press toward the next waypoint.
  -- The waypoints sit on corners, so every leg between consecutive ones
  -- is a straight line -- the greedy axis press is correct anywhere on
  -- or near the chain, costs nothing, and catches the corridor the first
  -- frame the engine opens it.
  local function goalDrill(x, y)
    local w = wpts[math.min(prog + 1, #wpts)]
    local dx, dy = w[1] - x, w[2] - y
    local mvx = dx ~= 0 and (dx > 0 and "right" or "left") or nil
    local mvy = dy ~= 0 and (dy > 0 and "down" or "up") or nil
    local mv = (math.abs(dx) >= math.abs(dy)) and (mvx or mvy) or (mvy or mvx)
    if not mv then mv = lastDir end
    if not H.canStep(x, y, mv) then
      local alt = (mv == mvx) and mvy or mvx
      if alt and H.canStep(x, y, alt) then mv = alt end
    end
    pressMove(x, y, mv)
  end

  local function pushStep(x, y)
    local p = currentPlan(x, y)
    if p then pressMove(x, y, p[1]); return end
    for _, r in ipairs(liveRats()) do
      local dx, dy = r.x - x, r.y - y
      if math.abs(dx) + math.abs(dy) <= 1 then
        local mv = (math.abs(dx) > math.abs(dy))
          and (dx > 0 and "right" or "left")
          or  (dy > 0 and "down" or "up")
        H.setPad({ [mv] = true })
        return
      end
    end
    local k = blockingRat()
    if k then
      local rx, ry = ratXY(k)
      local bestPlan
      for _, d in ipairs({ {0,-1}, {1,0}, {0,1}, {-1,0} }) do
        local pl = H.bfsPath(rx + d[1], ry + d[2])
        if pl and #pl > 0 and (not bestPlan or #pl < #bestPlan) then
          bestPlan = pl
        end
      end
      if bestPlan and #bestPlan <= 15 then pressMove(x, y, bestPlan[1]); return end
    end
    goalDrill(x, y)
  end

  local function startPush(x, y, why)
    pushMode, pushSteps = true, 0
    H.log(string.format("cross: %s at (%d,%d) timer=%d, pushing",
      why, x, y, H.readWord(0x1189)))
  end

  local function dodgeStep(x, y)
    if H.readWord(0x1189) < PANIC and not panicking then
      panicking = true
      H.log(string.format("cross: PANIC at (%d,%d) timer=%d", x, y,
        H.readWord(0x1189)))
    end
    -- a completed fight invalidates the cached plan (2300 frames passed,
    -- every rat moved), ends the push, and resets the watchdog
    if (res.fights or 0) ~= fightsSeen then
      fightsSeen = res.fights or 0
      plan, chaseK, waitN, pushMode = nil, nil, 0, false
    end
    if x ~= planX or y ~= planY then
      moveSameN, wig, curMv = 0, nil, nil
      if pushMode then pushSteps = pushSteps + 1 end
    end
    if wig then
      wig.n = wig.n - 1
      if wig.n <= 0 then wig = nil else
        H.setPad({ [H.movePress(wig.dir)] = true })
        return
      end
    end
    -- the watchdog counts frames since the last NEW waypoint: only real
    -- progress (or a fight) resets it -- churn must not
    local oldProg = prog
    local p = currentPlan(x, y)          -- updates prog as a side effect
    waitN = (prog > oldProg) and 0 or waitN + 1
    if prog > oldProg then
      H.log(string.format("cross: waypoint %d (%d,%d) timer=%d fights=%d",
        prog, wpts[prog][1], wpts[prog][2], H.readWord(0x1189),
        res.fights or 0))
    end
    -- a push that advanced 6 tiles found the road open: back to dodging
    if pushMode and pushSteps >= 6 then pushMode = false end
    if panicking or pushMode then pushStep(x, y); return end
    if p and not gateShut(x, y, p) then
      pressMove(x, y, p[1])
      return
    end
    -- no route but no rat near either: a transient planner nil, not a
    -- blockage -- drill at the next waypoint instead of parking
    if not p and minRatDist(x, y) >= 4 then
      goalDrill(x, y)
      return
    end
    if waitN >= STUCKCAP then
      startPush(x, y, string.format("no progress for %d frames", waitN))
      pushStep(x, y)
      return
    end
    if x <= 7 and minRatDist(x, y) <= 2 then
      startPush(x, y, "cornered in start pocket")
      pushStep(x, y)
      return
    end
    standoffStep(x, y)
  end

  return H.driveUntil(function()
    if H.fieldX() == tx and H.fieldY() == ty
       and H.hasControl() and H.tileAligned() then
      res.ok = true
      H.setPad({})
      return true
    end
    if lost then H.setPad({}); return true end
    return false
  end, maxF, { H.call(function()
    hb = hb + 1
    if hb % 600 == 0 then
      H.log(string.format("cross f%d (%d,%d) timer=%d wp=%d fights=%d rats: %s",
        H.frame, H.fieldX(), H.fieldY(), H.readWord(0x1189), prog,
        res.fights or 0, ratLine()))
    end
    if H.readWord(0x1189) == 0 and not lost then
      local live = 0
      for k = 0, 4 do if sw(RAT_GATE0 + k) == 1 then live = live + 1 end end
      lost = "the chase clock ran out"
      H.log(string.format("cross: the rafter timer ran out at (%d,%d) with %d " ..
        "rats still live -- the weight drops and the opera restarts, so this " ..
        "attempt is over", H.fieldX(), H.fieldY(), live))
      H.setPad({}); return
    end
    wipeN = H.partyWiped() and wipeN + 1 or 0
    if wipeN >= 300 and not lost then
      lost = "a lost rat fight"
      H.log("cross: THE PARTY IS WIPED for 300 consecutive frames -- a lost " ..
        "rat fight restarts the chase, so this attempt is over.")
      H.setPad({}); return
    end
    if lost then H.setPad({}); return end
    -- battleLoadStarted flickers mid-battle (its RAM is shared with the
    -- field module), so neither edge is trusted raw: battN>=3 latches
    -- "really in a battle", ten consecutive battle-free frames is really
    -- out, and between the two the pad stays neutral -- field reads
    -- taken on flicker frames inject rogue presses into the fight.
    battN = H.battleLoadStarted() and battN + 1 or 0
    notBattN = (not H.battleLoadStarted()) and notBattN + 1 or 0
    if battN >= 3 and not wasInBattle then
      wasInBattle = true
      res.fights = (res.fights or 0) + 1
      H.log(string.format("cross: fight %d fired at (%d,%d) timer=%d rats: %s",
        res.fights, H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
    end
    if wasInBattle and notBattN >= 10 then
      wasInBattle = false
      battleUp = false
      H.log(string.format("cross: fight %d done, timer=%d, rats: %s",
        res.fights, H.readWord(0x1189), ratLine()))
    end
    if battN >= 3 then battleFrame(); return end
    if notBattN < 10 then H.setPad({}); return end
    fight.idle()
    if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    -- release the pad on the first unaligned frame: a begun step glides
    -- to rest, and a stale press can never chain past a junction
    if not H.tileAligned() then H.setPad({}); return end
    if held < holdN() then held = held + 1; H.setPad({}); return end
    dodgeStep(H.fieldX(), H.fieldY())
  end) }, what)
end

local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then H.setPad(aPh<4 and {"a"} or {}); return end
      H.setPad({})
    end) }, what)
end

-- corridor: hand-coded per-tile direction table, canStep-gated on the live z,
-- pulsed so no press outlives its step (gen_opera5_dance's `corridor`).
local function corridor(TBL, tx, ty, maxF, doneFn, what)
  local hb=0
  return H.driveUntil(function()
    if doneFn and doneFn() then return true end
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%120==0 then dumpsw("["..what.."]") end
    if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(TBL[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, what)
end

-- bump an on-contact (no_react) NPC at (tx,ty) from approach tile (sx,sy).
local function bumpInto(sx, sy, dir, pred, maxF, what)
  local ph=0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames=12000, playBattles=true }),
    H.driveUntil(pred, maxF, { H.call(function() ph=(ph+1)%16
      if H.battleLoadStarted() then
        H.setPad(ph % 8 < 4 and { "a" } or {})   -- fought, not write-cleared
        return
      end
      if ph<8 then H.setPad({[dir]=true}) elseif ph<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what),
  })
end

local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx,ty,{maxFrames=18000,playBattles=true,arrive=function() return map()==destMap end}),
    (function() local n=0 return H.driveUntil(function() return map()==destMap end,3000,{
      H.call(function()
        n=n+1
        if H.dialogWaiting() then H.setPad(n%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(n%16<10 and {[bumpDir]=true} or {})
      end)
    },what) end)(),
    H.waitUntil(function() return map()==destMap and settled() end,3000,what.." settled",5),
  })
end

-- The crossing's retry ladder.  Attempt 1 runs from where the walk already
-- stands; later attempts reload the catwalk tile and stand still a
-- DIFFERENT, LARGE number of frames before setting off.  Rat wander is a
-- pure function of the chase clock (measured: blind to party input), so a
-- reload replays the same rat schedule exactly and the hold shifts only
-- the party's phase within it -- small staggers collapse into identical
-- attempts (the old 0/30/60/90/120/150 ladder produced six bit-identical
-- runs), while these large irregular holds land in genuinely different
-- collision patterns.  The same determinism is what makes the final
-- REPLAY step sound: re-running the best recorded hold reproduces its
-- outcome bit-for-bit.
local crossed = { ok = false, fights = 0 }
local attempts = {}                    -- per attempt: hold, margin, standing
local replayHold = nil                 -- set when the replay step picks one
-- Arrival alone is not enough: the generated entry point still needs time to
-- turn toward Ultros and let a nearby rat wander clear before it is safe to
-- bank.  MIN is that floor; TARGET is the margin worth stopping the ladder
-- for (measured E[margin] of this policy is ~6900, and ~3/4 of arrangements
-- clear 6000, so the ladder usually accepts its first attempt).
local MIN_CROSS_TIMER = 900
local TARGET_CROSS_TIMER = 6000
local HOLDS = { 0, 250, 550, 900, 1300, 1750 }
local catwalkBlob = nil                -- captured on the catwalk, below

local function allStanding()
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
      return false
    end
  end
  return true
end
local function hurtLine()
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d", c, H.charHp(c), H.charMaxHp(c))
  end
  return table.concat(t, " ")
end
-- One rung.  `hold` is a number, or a thunk for the replay rung (the value
-- is only known at run time).  `minAccept` is the margin this rung banks
-- at: TARGET for the sampling rungs, MIN for the replay rung.
local function crossAttempt(n, hold, minAccept)
  local loadReq
  return H.cond(function() return not crossed.ok end, {
    H.call(function()
      crossed.fights = 0
      local h = type(hold) == "function" and hold() or hold
      H.log(string.format("[rafters] crossing attempt %d: hold %d, banking a " ..
        "standing arrival with margin >= %d", n, h or -1, minAccept))
    end),
    -- attempts past the first rewind to the tile the walk stepped onto.  The
    -- rewind is gen_vargas's: capture once with H.requestSaveState and reload
    -- the blob in memory, because H.loadState only reaches savestates
    -- compose.py inlined before the run (lib/ot6.lua:293-300).
    H.cond(function() return n > 1 end, {
      H.call(function() loadReq = H.requestLoadState(catwalkBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt " .. n .. ": catwalk reload")
      end),
      H.waitFrames(90),                -- the settle every other reload uses
    }, {}),
    crossRafters(14, 7, 25000, hold, crossed,
      string.format("cross the rafters to Ultros (attempt %d)", n)),
    H.call(function()
      local margin = crossed.ok and H.readWord(0x1189) or 0
      local standing = allStanding()
      local h = type(hold) == "function" and hold() or hold
      attempts[#attempts + 1] = { hold = h, margin = margin,
                                  standing = standing }
      if crossed.ok and margin < minAccept then
        H.log(string.format("[rafters] attempt %d reached Ultros with %d " ..
          "frames left, under this rung's %d bar; recorded, trying the next " ..
          "arrangement", n, margin, minAccept))
        crossed.ok = false
      end
      -- On time but hurt is not good enough: a casualty banked here fails the
      -- exit contract just as an over-clock arrival does, so it spends the
      -- next arrangement too.  (See the allStanding note above.)
      if crossed.ok and not standing then
        H.log(string.format("[rafters] attempt %d reached Ultros on the clock " ..
          "but banked a hurt party (%s); recorded, trying the next " ..
          "arrangement", n, hurtLine()))
        crossed.ok = false
      end
      H.log(string.format("[rafters] attempt %d %s at (%d,%d), timer %d left, " ..
        "%d fights, rats: %s", n, crossed.ok and "ARRIVED" or "did not bank",
        H.fieldX(), H.fieldY(), H.readWord(0x1189), crossed.fights or 0,
        ratLine()))
    end),
  })
end

H.run({ maxFrames = 420000 }, {
  H.loadState("build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    -- Boot invariants (the only lines this file can guarantee until
    -- opera_dance_done can be generated).
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- the aria is solved (opera_dance_done)")
    H.assertEq(sw(0x0058), 0, "$0058 CLEAR -- Ultros has not dropped in yet")
    H.assertEq(sw(0x0345), 1, "$0345 SET -- the ENVELOPE (Ultros) is at 238 {99,20}")
    dumpsw("BOOT"); H.screenshot("rafter_boot")
  end),

  -- The opera field menu exposes only LOCKE even though EDGAR and SABIN join
  -- its battles.  Kirin turns his otherwise idle MP into ~200-HP Cures.
  -- The crossing driver itself fights cure-less for speed (measured safe:
  -- zero casualties in ~40 lab fights, and the ladder re-rolls any hurt
  -- arrival), so this wear is for the fights around the scene, not inside
  -- it.
  H.equipEsper(0, 0x11, { tag = "KIRIN -> LOCKE for the rafters" }),
  H.call(function()
    H.log(string.format("[prep] esper wear: LOCKE=%02X EDGAR=%02X SABIN=%02X CELES=%02X",
      H.readByte(0x1600 + 37 * 0x01 + 0x1E),
      H.readByte(0x1600 + 37 * 0x04 + 0x1E),
      H.readByte(0x1600 + 37 * 0x05 + 0x1E),
      H.readByte(0x1600 + 37 * 0x06 + 0x1E)))
    H.assertEq(H.readByte(0x1600 + 37 * 0x01 + 0x1E), 0x11,
      "LOCKE wears KIRIN for Cure in the rat fights")
  end),

  -- Step 1: walk into the envelope at {99,20} -> _cabf31 -> $0058=1.
  bumpInto(99, 19, "down", function() return sw(0x0058)==1 or map()~=238 end, 6000,
    "touch the envelope -> $0058"),
  rideScene(function() return H.hasControl() and not H.dialogWaiting() end, 4000,
    "ride Ultros's threat dialog"),
  H.call(function()
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros threatened the opera")
    dumpsw("AFTER-ENVELOPE"); H.screenshot("rafter_ultros_dropped")
  end),
  -- Checkpoint: a cheap replay point for the steps below.
  H.saveState("ultros_dropped.mss"),

  toDoor(100,23,"down",237,"stage -> opera house"),
  H.navTo(72,30,{maxFrames=12000,playBattles=true,arrive=function() return map()==233 end}),
  H.waitUntil(function() return map()==233 and settled() end,3000,"active theater settled",5),
  H.navTo(15,45,{maxFrames=12000,playBattles=true}),
  (function() local n=0 return H.driveUntil(function()
    return sw(0x0110)==1 or H.dialogWaiting()
  end,3000,{H.call(function()
    n=n+1
    H.setPad(n%12<6 and {"down","a"} or {})
  end)},"talk active-opera impresario") end)(),
  rideScene(function() return sw(0x0110)==1 and map()==231 and settled() end,18000,
    "ride the 5-minute briefing"),
  H.call(function()
    H.assertEq(map(),231,"briefing lands in the active theater (231)")
    H.assertEq(sw(0x0110),1,"$0110 SET -- rafter timer armed")
    dumpsw("AFTER-BRIEFING")
  end),
  H.saveState("rafter_briefing.mss"),

  H.navTo(28,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"right room",3),
  H.driveUntil(function() return H.fieldY()==35 end,300,{H.hold({"up"})},"leave right landing"),
  H.driveUntil(function() return H.fieldY()==34 end,300,{H.hold({"up"})},"right stair 1"),
  H.driveUntil(function() return H.fieldX()==113 end,300,{H.hold({"left"})},"right stair 2"),
  H.driveUntil(function() return H.fieldY()==32 end,500,{H.hold({"up"})},"right stair 3"),
  H.driveUntil(function() return H.fieldX()==114 end,300,{H.hold({"right"})},"right stair 4"),
  H.driveUntil(function() return H.fieldX()>=117 and H.fieldY()<=29 end,800,{
    H.call(function()
      if H.dialogWaiting() then H.setPad({"a"})
      elseif H.hasControl() then H.setPad({"up","right"})
      else H.setPad({}) end
    end)},"reach stage master"),
  H.driveUntil(function() return sw(0x01B4)==1 end,1000,{
    H.call(function() H.setPad({"right","a"}) end)},"talk stage master"),
  H.navTo(120,28,{maxFrames=1500,playBattles=true}),
  H.driveUntil(function() return sw(0x0355)==0 end,500,{
    H.call(function() H.setPad({"up","a"}) end)},"operate far-right switch"),
  H.navTo(114,37,{maxFrames=3000,playBattles=true,arrive=function() return map()==231 end}),
  H.waitUntil(function() return map()==231 and settled() end,1000,"return theater",3),
  H.navTo(28,27,{maxFrames=500,playBattles=true}),
  H.navTo(4,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"left room",3),
  H.driveUntil(function() return H.fieldY()==13 end,500,{H.hold({"up"})},"leave left landing"),
  H.navTo(117,5,{maxFrames=2500,playBattles=true}),
  -- The five rat gates stay live (see the header).  A rat collision fires
  -- battle 25; crossRafters drives that fight tactically, and a win despawns
  -- the rat and clears its gate.
  H.navTo(117,3,{maxFrames=6000,playBattles=true,arrive=function() return map()==235 end}),
  H.waitUntil(function() return map()==235 and settled() end,1500,"framework",3),
  H.call(function() H.log("[rats] on 235: " .. ratLine()) end),
  H.navTo(6,16,{maxFrames=30000,playBattles=true}),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()<=10 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({up=true}) end) }, "climb framework") end)(),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()>=11 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({down=true}) end) }, "step onto rafters") end)(),

  -- NO menu care inside this scene: from the moment it was added, every
  -- attempt booted with a nil path and impotent presses -- the menu visit
  -- inside an event-timer scene corrupts the room state (the same $1188
  -- block hazard the save-drive rule documents; this scene's clock is
  -- $1189).  Recovery here is the all-out driver keeping fights to one
  -- round; the party crosses on whatever HP the approach left it.
  H.call(function()
    H.log(string.format("[rafters] on the catwalk at (%d,%d), timer %d frames left, rats: %s",
      H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
  end),
  (function() local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "catwalk capture")
        catwalkBlob = req.blob
        H.log(string.format("[rafters] captured the catwalk tile for the ladder (%d bytes)",
          #catwalkBlob))
      end),
    }) end)(),
  crossAttempt(1, HOLDS[1], TARGET_CROSS_TIMER),
  crossAttempt(2, HOLDS[2], TARGET_CROSS_TIMER),
  crossAttempt(3, HOLDS[3], TARGET_CROSS_TIMER),
  crossAttempt(4, HOLDS[4], TARGET_CROSS_TIMER),
  crossAttempt(5, HOLDS[5], TARGET_CROSS_TIMER),
  crossAttempt(6, HOLDS[6], TARGET_CROSS_TIMER),
  -- No sampling rung cleared TARGET: replay the best recorded arrangement.
  -- Reloads replay the rat schedule exactly, so re-running the best hold
  -- reproduces its crossing bit-for-bit; this rung banks at the MIN floor.
  H.cond(function() return not crossed.ok end, {
    H.call(function()
      local best
      for _, a in ipairs(attempts) do
        if a.standing and a.margin >= MIN_CROSS_TIMER
           and (not best or a.margin > best.margin) then
          best = a
        end
      end
      H.assertEq(best ~= nil, true,
        "some sampled arrangement banked a standing arrival worth replaying")
      replayHold = best.hold
      H.log(string.format("[rafters] no rung cleared %d; replaying the best " ..
        "recorded arrangement (hold %d, margin %d)",
        TARGET_CROSS_TIMER, best.hold, best.margin))
    end),
    crossAttempt(7, function() return replayHold end, MIN_CROSS_TIMER),
  }, {}),
  H.call(function()
    H.assertEq(crossed.ok, true,
      "the rafters were crossed on the clock and standing within the ladder")
  end),
  -- No menu care here: the entry point is still inside the event-timer
  -- scene, where a menu visit corrupts the room state (the $1189-block
  -- hazard this file documents above).  Every banked arrival is gated
  -- all-standing by the ladder, which is what the exit contract asserts.
  -- face Ultros by input: his NPC occupies {15,7}, so a short RIGHT press
  -- is a blocked step that turns the party in place
  H.hold({ "right" }), H.waitFrames(6), H.release(), H.waitFrames(6),
  H.call(function()
    H.assertEq(H.fieldX()==14 and H.fieldY()==7, true,
      "still at (14,7) -- the blocked press did not step")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1,
      "facing RIGHT at Ultros (EVENT_DIR 1), earned by the blocked press")
  end),
  -- the banked state must not boot into a rat collision: wait until no
  -- live rat stands within 4 tiles of the entry point (they wander off; the
  -- timer has headroom for this wait, and the log shows the positions)
  (function() local calm=0
    return H.driveUntil(function()
      calm = (settled() and not ratNear(14,7,4)) and calm+1 or 0
      return calm >= 20
    end, 9000, { H.call(function()
      if H.battleLoadStarted() then H.setPad(H.frame%8<4 and {"a"} or {}); return end
      H.setPad({}) end) }, "a rat-free, settled entry point") end)(),
  H.call(function()
    H.assertEq(map(),235,"Ultros entry point is on rafters map 235")
    H.assertEq(sw(0x02BC),1,"rafter timer is active at the entry point")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing RIGHT")
    H.assertEq(H.readWord(0x1189) >= 600, true,
      string.format("the rafter timer has room left at the entry point (%d frames)",
        H.readWord(0x1189)))
    -- and nobody is banked hurt: the crossing's rat fights are real fights,
    -- and the blind-A version of this route shipped LOCKE dead at 0/353.
    H.assertPartyStanding("the Ultros entry point")
    H.log("[rats] at generation: " .. ratLine())
    dumpsw("ULTROS2-ENTRY")
  end),
  H.saveState("ultros2_entry.mss"),
  H.logStep(function()
    return string.format("gen_opera6_rafter: catwalk traversal banked the Ultros 2 entry point at f%d", H.frame)
  end),
})
