-- probe_rafterlab_dodge.lua -- rafter-crossing lab, dodge experiment.
--
-- Copied from probe_rafterlab_template.lua; adds the "dodge-*" strategy
-- family: walk the unrestricted BFS route, but gate each step on LOCAL
-- safety only (rat distance to the next 1-2 route tiles), hold at a
-- standoff tile (rat distance >= 3, backing away when a rat closes),
-- and give up dodging (push into the blocker, fight) when the gate has
-- been shut longer than a wait budget or the clock falls below a panic
-- floor.  The whole-path keep-away halo ("avoid") is measured-broken --
-- halos of five roaming rats cover every route, the party freezes, and
-- the rats come to it -- so nothing here ever avoids globally.
--
-- Hand-run instrument (probe_): boots build/states/rafterlab_catwalk.mss
-- (banked by probe_rafterlab_catwalk.lua: catwalk tile (6,11), chase clock
-- live at ~14760) and runs ONE crossing attempt under one strategy and one
-- RNG stagger, then reports a machine-readable [result] line and PASSes
-- either way -- this file measures, it does not assert.
--
-- The batch runner substitutes the @TOKEN@ defaults below (sed) and runs
-- many staggers per strategy; the stagger (standing still HOLD aligned
-- frames before setting off) advances the field RNG, which is what moves
-- the rats into a different arrangement per seed.
--
--   STRATEGY  fightline | avoid | hybrid | dodge-<variant>
--   HOLD      aligned frames to stand still before setting off
--   RUNTRY    frames of L+R to try fleeing before the driver fights
--             (the 2026-08-26 logs show $b1=$06 held: these fights refuse
--             the run, so the default goes straight to the driver)
--   RADIUS    avoid/hybrid: manhattan keep-away radius from live rats
--             dodge: gate distance -- the step is refused while a live rat
--             is within RADIUS of the NEXT route tile (or RADIUS-1 of the
--             tile after it)
--   STUCKCAP  hybrid: aligned frames without progress before fighting
--             dodge: wait budget W -- consecutive gated frames before the
--             party stops dodging this blockage and pushes through it
--   PANIC     timer floor; below it, stop dodging and fight (both)
--
-- Measured mechanics this file leans on (build/states/rafterlab_*.log):
--   * the chase clock $1189 ticks during battle, 1 per frame;
--   * a rat collision is ADJACENCY-triggered, object-side (obj.asm
--     DoCollision: the four tiles around the object), so a fight fires
--     with no press the moment a rat closes to manhattan 1;
--   * a WON fight's exp/gil boxes are battle-module text pages (menu==0),
--     which newFightDriver taps A through; monstersPresent() stays >0 for
--     dead-but-present rats, so it is NOT a victory signal;
--   * the win despawns the rat and clears its $034C+k switch.

local H = dofile("tools/tests/lib/ot6.lua")

local FIXTURE  = "@FIXTURE@"            -- which catwalk state to boot
local STRATEGY = "@STRATEGY@"
local HOLD     = tonumber("@HOLD@")     or 0
local RUNTRY   = tonumber("@RUNTRY@")   or 0
local RADIUS   = tonumber("@RADIUS@")   or 2
local STUCKCAP = tonumber("@STUCKCAP@") or 600
local PANIC    = tonumber("@PANIC@")    or 6000
if STRATEGY:find("@") then STRATEGY = "fightline" end
if FIXTURE:find("@") then FIXTURE = "rafterlab_catwalk" end

local GX, GY = 14, 7                    -- the Ultros entry tile
local MAXF = 20000
local DIAG = false                      -- temporary heartbeat diagnostics

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local RAT_GATE0, RAT_OBJ0 = 0x034C, 24
local function ratXY(k)
  local obj = RAT_OBJ0 + k
  return H.readWord(0x086a + 0x29 * obj) >> 4,
         H.readWord(0x086d + 0x29 * obj) >> 4
end
local function ratLine()
  local t = {}
  for k = 0, 4 do
    local ox, oy = ratXY(k)
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(RAT_GATE0 + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
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
local function allStanding()
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
      return false
    end
  end
  return true
end

-- one crossing attempt; fills `res`
local function cross(res)
  local hb, battN, wipeN, notBattN = 0, 0, 0, 0
  local held, lost = 0, nil
  local battleUp, wasInBattle, fightStart = false, false, 0
  local stuckN, panicking, lastDistToGoal = 0, false, 999
  -- dodge state
  local waitN, pushMode, fightsAtPush, lastDir = 0, false, 0, "right"
  local DXY = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0},
                upleft = {-1,-1}, upright = {1,-1},
                downleft = {-1,1}, downright = {1,1} }
  -- Junction waypoints of the (measured) route, in crossing order.  With
  -- five rats roaming a mostly 1-wide network, bfsPath(goal) is nil at
  -- MOST instants -- some rat is nearly always standing on a route tile
  -- (measured: 1 non-nil in 15 samples of a stationary run) -- and the
  -- blockage is transient.  So a nil is never "wait here": walk to the
  -- FURTHEST waypoint still reachable and stand off there (junctions
  -- beat corridors: more exits), re-planning as the rat wanders off.
  local wpts = { {8,12}, {8,16}, {11,16}, {11,18}, {13,18}, {13,15},
                 {19,15}, {19,12}, {11,12}, {11,9}, {11,7}, {GX, GY} }
  local prog = 0                        -- highest waypoint index touched
  local plan, planX, planY, planAge = nil, -1, -1, 0
  local moveSameN, wig = 0, nil         -- anti-stall wiggle state
  local pushSteps = 0                   -- tiles advanced during this push
  -- fight config per the 2026-08-27 fightsmart measurements: boost off,
  -- cadence 12 -- 232 frames/fight faster than the template's, and safer
  local fight = H.newFightDriver("lab",
    { tactical = true, boost = false, cure = false, items = false,
      cadence = 12 })

  local function battleFrame()
    -- Neutral pad until the battle module shows its first interactive menu
    -- ($7BCA ~= 0): before that the module is loading, and an A queued
    -- during load is the suspected event-starvation hazard from the
    -- 2026-08-26 header.  After the first menu the driver owns every
    -- frame; its own menu==0 branch taps A through victory text, which is
    -- what un-parks the "Got ... Exp. point(s)" box.
    if not battleUp then
      if H.readByte(0x7BCA) ~= 0 then battleUp = true end
      H.setPad({})
      return
    end
    if battN < RUNTRY then H.setPad({ l = true, r = true }); return end
    fight.frame()
  end

  -- press one step of `plan` (a bfsPath list); true if it pressed
  local function pressStep(plan)
    if plan and #plan > 0 then
      H.setPad({ [H.movePress(plan[1])] = true })
      return true
    end
    return false
  end

  -- fightline's field policy: straight at the goal, push into whatever
  -- stands in the way, let adjacency fire the fight.
  local function fightlineStep(x, y)
    local plan = H.bfsPath(GX, GY)
    if pressStep(plan) then return end
    -- no geometric route: a rat plugs a corridor tile.  If one is already
    -- adjacent, press into it; otherwise walk to the nearest live rat's
    -- side and let adjacency fire.
    local rats = liveRats()
    for _, r in ipairs(rats) do
      local dx, dy = r.x - x, r.y - y
      if math.abs(dx) + math.abs(dy) <= 1 then
        local mv = (math.abs(dx) > math.abs(dy))
          and (dx > 0 and "right" or "left")
          or  (dy > 0 and "down" or "up")
        H.setPad({ [mv] = true })
        return
      end
    end
    local bestPlan
    for _, r in ipairs(rats) do
      for _, d in ipairs({ {0,-1}, {1,0}, {0,1}, {-1,0} }) do
        local pl = H.bfsPath(r.x + d[1], r.y + d[2])
        if pl and (not bestPlan or #pl < #bestPlan) then bestPlan = pl end
      end
    end
    if not pressStep(bestPlan) then H.setPad({}) end
  end

  -- avoid's field policy: BFS with a keep-away halo around every live rat;
  -- no safe route means wait (or back away when a rat closes in).
  local function avoidStep(x, y)
    local avoid = {}
    for _, r in ipairs(liveRats()) do
      for dx = -RADIUS, RADIUS do
        for dy = -(RADIUS - math.abs(dx)), RADIUS - math.abs(dx) do
          avoid[(((r.y + dy) & 0xFF) << 8) | ((r.x + dx) & 0xFF)] = true
        end
      end
    end
    local plan = H.bfsPath(GX, GY, nil, avoid)
    if plan and #plan > 0 then
      stuckN = 0
      H.setPad({ [H.movePress(plan[1])] = true })
      return
    end
    stuckN = stuckN + 1
    -- no safe route right now.  If a rat is closing in, greedily step to
    -- the neighbor that maximizes rat distance; otherwise stand still and
    -- let the wander open a gap.
    if minRatDist(x, y) <= 2 then
      local bestMv, bestD = nil, minRatDist(x, y)
      for _, mv in ipairs({ "up", "down", "left", "right" }) do
        if H.canStep(x, y, mv) then
          local d = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0} }
          local nd = minRatDist(x + d[mv][1], y + d[mv][2])
          if nd > bestD then bestMv, bestD = mv, nd end
        end
      end
      if bestMv then H.setPad({ [bestMv] = true }); return end
    end
    H.setPad({})
  end

  -- dodge's route planner: unrestricted BFS at the goal; when that is nil
  -- (a rat is standing on a route tile -- stepAllowed treats occupied
  -- tiles as walls), fall back to the furthest FORWARD waypoint still
  -- reachable, so the party keeps closing distance while the blocker
  -- wanders off.  Backward waypoints are never targets: routing the long
  -- way around to a tile behind us is how thrash starts.
  local function planRoute(x, y)
    for i = #wpts, prog + 1, -1 do
      if x == wpts[i][1] and y == wpts[i][2] then prog = i; break end
    end
    local p = H.bfsPath(GX, GY)
    if p and #p > 0 then return p end
    for i = #wpts - 1, prog + 1, -1 do
      p = H.bfsPath(wpts[i][1], wpts[i][2])
      if p and #p > 0 then return p end
    end
    return nil
  end

  -- Rat velocity memory: positions sampled every 12 frames by the main
  -- loop (rats move ~1 tile per 12-16 frames, deterministically, and
  -- never chase).  ratPrev[k] is where rat k was one sample ago.
  local ratPrev = {}
  local function sampleRats()
    for _, r in ipairs(liveRats()) do
      local pv = ratPrev[r.k]
      if not pv then ratPrev[r.k] = { x = r.x, y = r.y, px = r.x, py = r.y }
      else pv.px, pv.py, pv.x, pv.y = pv.x, pv.y, r.x, r.y end
    end
  end

  -- the gate: refuse the step while a live rat threatens any of the next
  -- K route tiles (the next corridor segment, roughly -- junctions are
  -- 3-6 tiles apart).  The gate re-runs every aligned frame, so tiles
  -- further than K are left to the next junction.
  --
  -- Two gate flavors, picked by the strategy name:
  --   dodge-f (distance-only):    tile 1 needs rat-dist >= RADIUS+1,
  --                               tiles 2..K need >= RADIUS
  --   dodge-g (velocity-aware):   a rat RECEDING from the tile only
  --                               shuts at < RADIUS (tile 1: RADIUS+1);
  --                               approaching or camped shuts at < 4 for
  --                               tiles 1-2, < 3 further out.  Measured
  --                               motivation: every fight 2 fired as a
  --                               2-step race loss against a rat the
  --                               distance gate had just approved at
  --                               dist 3 -- worst-case closure is ~1
  --                               tile per party step.
  local GATEK = 4
  local VGATE = STRATEGY:find("dodge%-g") ~= nil
  local function gateShut(x, y, p)
    local cx, cy = x, y
    for i = 1, math.min(GATEK, #p) do
      local d = DXY[p[i]]
      cx, cy = cx + d[1], cy + d[2]
      for _, r in ipairs(liveRats()) do
        local dist = math.abs(r.x - cx) + math.abs(r.y - cy)
        local need
        if not VGATE then
          need = (i == 1) and RADIUS + 1 or RADIUS
        else
          local pv = ratPrev[r.k]
          local prevd = pv and (math.abs(pv.px - cx) + math.abs(pv.py - cy))
                        or dist
          if dist > prevd then                    -- receding
            need = (i == 1) and RADIUS + 1 or RADIUS
          else                                    -- approaching or camped
            need = (i <= 2) and RADIUS + 2 or RADIUS + 1
          end
        end
        if dist < need then return true end
      end
    end
    return false
  end

  -- how many ways out of a tile (dead ends read 0-1)
  local function degree(x, y)
    local n = 0
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      if H.canStep(x, y, mv) then n = n + 1 end
    end
    return n
  end

  -- gated: hold at a standoff.  Standing is fine at rat distance >= 3;
  -- closer than that, step to the neighbor that gains rat distance --
  -- but never retreat into a dead end (measured: greedy retreat walked
  -- the party into the (8,17) and (6,10) pockets, where the rat cornered
  -- it anyway, later and poorer).  With no improving non-dead-end
  -- retreat, stand and let the rat decide: it wanders randomly, it is
  -- not chasing (pushing here instead bought v3 five fights by timer
  -- 3093 -- measured worse than waiting out the coin flip).
  local function standoffStep(x, y)
    if minRatDist(x, y) >= 3 then H.setPad({}); return end
    local bestMv, bestD = nil, minRatDist(x, y)
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      if H.canStep(x, y, mv) then
        local d = DXY[mv]
        local nx, ny = x + d[1], y + d[2]
        local nd = minRatDist(nx, ny)
        if nd > bestD and degree(nx, ny) >= 2 then bestMv, bestD = mv, nd end
      end
    end
    if bestMv then H.setPad({ [bestMv] = true }) else H.setPad({}) end
  end

  -- the cached plan: re-plan when the party lands on a new tile, when the
  -- cache goes stale (rats move ~1 tile in well under a second), or when
  -- there is no plan at all.  plan[1] stays the correct next step as long
  -- as the party has not left (planX,planY).
  local function currentPlan(x, y)
    if not plan or x ~= planX or y ~= planY or planAge > 16 then
      plan, planX, planY, planAge = planRoute(x, y), x, y, 0
    else
      planAge = planAge + 1
    end
    return plan
  end

  -- Commit to a pressed direction for a dozen frames (or until the tile
  -- changes): re-deciding every frame flip-flopped the pad so fast that
  -- no 16px step ever STARTED (measured: 1800 frames of panic-pushing
  -- that moved two tiles).  Also the anti-stall watchdog: a direction
  -- held ~4s that never changes the tile means the model and the engine
  -- disagree (the open (11,7) problem) -- log it and wiggle sideways.
  local curMv, curMvN = nil, 0
  local function pressMove(x, y, mv)
    if not curMv or curMvN >= 12 then curMv, curMvN = mv, 0 end
    curMvN = curMvN + 1
    lastDir = H.movePress(curMv)
    moveSameN = moveSameN + 1
    if moveSameN >= 240 then
      local cs = {}
      for _, m in ipairs({ "up", "down", "left", "right" }) do
        cs[#cs + 1] = m .. "=" .. tostring(H.canStep(x, y, m))
        if m ~= lastDir and H.canStep(x, y, m) and not wig then
          wig = { dir = m, n = 30 }
        end
      end
      local d = DXY[curMv]
      local nx, ny = x + d[1], y + d[2]
      H.log(string.format("dodge: STALL at (%d,%d) pressing %s, timer=%d, " ..
        "%s, occ(next)=%02X p1(next)=%02X p2(next)=%02X p2(cur)=%02X, " ..
        "wiggling %s", x, y, lastDir, H.readWord(0x1189),
        table.concat(cs, " "), H.readByte(0x7E2000 + (ny & 0xFF) * 256 + nx),
        H.readByte(0x7E7600 + H.maptile(nx, ny)),
        H.readByte(0x7E7700 + H.maptile(nx, ny)),
        H.readByte(0x7E7700 + H.maptile(x, y)),
        wig and wig.dir or "nowhere"))
      moveSameN = 0
    end
    H.setPad({ [lastDir] = true })
  end

  -- the rat most likely to be the one plugging the route: nearest by
  -- manhattan to the next forward waypoint (committed for 300 frames so
  -- the chase does not retarget to every passer-by -- measured: an
  -- uncommitted chase followed roamers to (21,17), three junctions off
  -- route)
  local chaseK, chaseN = nil, 0
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

  -- The drill: with no geometric route at all, hold a press toward the
  -- NEXT waypoint.  The waypoints sit on corners, so every leg between
  -- consecutive ones is a straight line -- the greedy axis press is the
  -- correct move anywhere on or near the chain.  Every measured endgame
  -- died with bfsPath(14,7) nil, no rat anywhere on the route, and the
  -- party parked at (19,11) or (11,7) -- an open problem another agent
  -- is chasing (phase/exit-bit suspicion).  A held press costs nothing
  -- and catches the corridor the first frame the engine opens it.
  local function goalDrill(x, y)
    local w = wpts[math.min(prog + 1, #wpts)]
    local dx, dy = w[1] - x, w[2] - y
    local mvx = dx ~= 0 and (dx > 0 and "right" or "left") or nil
    local mvy = dy ~= 0 and (dy > 0 and "down" or "up") or nil
    local mv = (math.abs(dx) >= math.abs(dy)) and (mvx or mvy) or (mvy or mvx)
    if not mv then mv = lastDir end
    -- off the chain the greedy axis can face a wall: fall back to the
    -- other axis when the engine agrees it is walkable
    if not H.canStep(x, y, mv) then
      local alt = (mv == mvx) and mvy or mvx
      if alt and H.canStep(x, y, alt) then mv = alt end
    end
    pressMove(x, y, mv)
  end

  -- pushing through: take the route step regardless of rats; with no
  -- route, press into an adjacent rat, else walk to the blocking rat's
  -- side (unless that walk is a trek -- a chase >15 steps means the rat
  -- is not what blocks us, and chasing roamers three junctions off the
  -- route is a measured failure mode), else drill at the goal.
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

  local fightsSeen = 0
  local function startPush(x, y, why)
    pushMode, fightsAtPush, pushSteps = true, res.fights or 0, 0
    res.pushes = (res.pushes or 0) + 1
    H.log(string.format("dodge: %s at (%d,%d) timer=%d, pushing",
      why, x, y, H.readWord(0x1189)))
  end
  local function dodgeStep(x, y)
    if H.readWord(0x1189) < PANIC and not panicking then
      panicking = true
      H.log(string.format("dodge: PANIC at (%d,%d) timer=%d", x, y,
        H.readWord(0x1189)))
    end
    -- any completed fight invalidates the cached plan outright (2300
    -- frames passed, every rat moved), ends the current push (the
    -- blocker is despawned), and resets the progress watchdog
    if (res.fights or 0) ~= fightsSeen then
      fightsSeen = res.fights or 0
      plan, chaseK, waitN = nil, nil, 0
      if pushMode then
        pushMode = false
        H.log(string.format("dodge: push resolved by fight at (%d,%d) timer=%d",
          x, y, H.readWord(0x1189)))
      end
    end
    -- landing on a new tile clears the stall counter, the committed
    -- press, and any wiggle
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
    -- waypoint-progress watchdog: waitN counts every frame since the last
    -- waypoint was reached.  The old consecutive-standoff budget never
    -- fired: churn (advance a tile, retreat a tile) reset it while 2500
    -- frames burned.  Progress is the thing the clock buys, so progress
    -- is the thing the budget watches.
    local oldProg = prog
    local p = currentPlan(x, y)          -- updates prog as a side effect
    waitN = (prog > oldProg) and 0 or waitN + 1
    if prog > oldProg then
      -- milestone: the (11,7) waypoint is the mouth of the final east leg
      -- (the leg every measured run so far has failed to cross); the
      -- timer here is the de-facto margin while that problem stays open
      H.log(string.format("dodge: waypoint %d (%d,%d) timer=%d fights=%d",
        prog, wpts[prog][1], wpts[prog][2], H.readWord(0x1189),
        res.fights or 0))
    end
    -- a push that has advanced 6 tiles without needing its fight found
    -- the road open (the blocker wandered off): go back to dodging.
    -- waitN is NOT reset here -- only real progress (a new waypoint) or
    -- a fight resets the watchdog, otherwise a ping-pong between pushes
    -- and standoffs starves it forever (measured: 5000+ frames bouncing
    -- (8,15)<->(8,17) with the watchdog never firing).
    if pushMode and pushSteps >= 6 then
      pushMode = false
      H.log(string.format("dodge: push resolved by movement at (%d,%d)", x, y))
    end
    if panicking or pushMode then pushStep(x, y); return end
    if p and not gateShut(x, y, p) then
      pressMove(x, y, p[1])
      return
    end
    -- no geometric route but no rat anywhere near either: that is the
    -- phantom-nil (open problem), not a blockage -- drill at the next
    -- waypoint instead of parking (a rat 4+ away cannot collide this
    -- step, and this branch re-checks every frame)
    if not p and minRatDist(x, y) >= 4 then
      goalDrill(x, y)
      return
    end
    -- gated (or a rat really is plugging the corridor): hold at a standoff
    res.waits = (res.waits or 0) + 1
    if waitN >= STUCKCAP then
      startPush(x, y, string.format("no progress for %d frames", waitN))
      pushStep(x, y)
      return
    end
    -- In the start pocket (x<=7: a 1-wide dead-end column whose only
    -- exit is the (7,12) choke) there is no standoff -- backing away
    -- just gets the party cornered (measured), so a close rat there is
    -- fought NOW, on a fat clock, by pushing into it.
    if x <= 7 and minRatDist(x, y) <= 2 then
      startPush(x, y, "cornered in start pocket")
      pushStep(x, y)
      return
    end
    standoffStep(x, y)
  end

  local function fieldStep(x, y)
    if STRATEGY:find("^dodge") then dodgeStep(x, y); return end
    if STRATEGY == "fightline" then fightlineStep(x, y); return end
    if STRATEGY == "avoid" then avoidStep(x, y); return end
    -- hybrid: dodge while it is making progress and the clock is fat;
    -- fight the moment dodging stalls or the clock thins.
    local d = math.abs(GX - x) + math.abs(GY - y)
    if d < lastDistToGoal then lastDistToGoal = d; stuckN = 0 end
    if H.readWord(0x1189) < PANIC then panicking = true end
    if stuckN >= STUCKCAP then panicking = true end
    if panicking then fightlineStep(x, y) else avoidStep(x, y) end
  end

  return H.driveUntil(function()
    if H.fieldX() == GX and H.fieldY() == GY
       and H.hasControl() and H.tileAligned() then
      res.arrived = true
      H.setPad({})
      return true
    end
    if lost then H.setPad({}); return true end
    return false
  end, MAXF, { H.call(function()
    hb = hb + 1
    if hb % 12 == 0 and battN == 0 then sampleRats() end
    if hb % 600 == 0 then
      H.log(string.format("lab f%d (%d,%d) timer=%d batt=%d panic=%s rats: %s",
        H.frame, H.fieldX(), H.fieldY(), H.readWord(0x1189), battN,
        tostring(panicking), ratLine()))
      if DIAG and battN == 0 then
        local occ = {}
        for _, t in ipairs({ {7,12}, {8,12}, {8,13}, {11,7}, {12,7}, {13,7},
                             {14,7}, {15,7}, {16,7}, {19,10} }) do
          occ[#occ + 1] = string.format("(%d,%d)=%02X", t[1], t[2],
            H.readByte(0x7E2000 + t[2] * 256 + t[1]))
        end
        local p = H.bfsPath(GX, GY)
        H.log(string.format("diag bfs(14,7)=%s occ: %s",
          p and #p or "nil", table.concat(occ, " ")))
      end
    end
    if H.readWord(0x1189) == 0 and not lost then
      lost = "timeout"
      H.setPad({}); return
    end
    if map() ~= 235 and not lost then
      lost = "left map 235"
      H.setPad({}); return
    end
    wipeN = H.partyWiped() and wipeN + 1 or 0
    if wipeN >= 300 and not lost then
      lost = "wipe"
      H.setPad({}); return
    end
    if lost then H.setPad({}); return end
    -- battleLoadStarted flickers mid-battle (its RAM is shared with the
    -- field module), so neither edge is trusted raw: battN>=3 latches
    -- "really in a battle", and only ten consecutive battle-free frames
    -- count as really out.  Between the two, the pad stays neutral --
    -- field reads (dialogWaiting, hasControl) taken on flicker frames
    -- inject rogue presses into the fight's menus.
    battN = H.battleLoadStarted() and battN + 1 or 0
    notBattN = (not H.battleLoadStarted()) and notBattN + 1 or 0
    if battN >= 3 and not wasInBattle then
      wasInBattle = true
      res.fights = (res.fights or 0) + 1
      fightStart = hb
      H.log(string.format("lab: fight %d fired at (%d,%d) timer=%d rats: %s",
        res.fights, H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
    end
    if wasInBattle and notBattN >= 10 then
      wasInBattle = false
      battleUp = false
      res.bframes = (res.bframes or 0) + (hb - fightStart)
      H.log(string.format("lab: fight %d done after %d frames, timer=%d, %s standing, rats: %s",
        res.fights, hb - fightStart, H.readWord(0x1189),
        allStanding() and "all" or "NOT all", ratLine()))
    end
    if battN >= 3 then battleFrame(); return end
    if notBattN < 10 then H.setPad({}); return end
    fight.idle()
    if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    -- release the pad on the first unaligned frame: a begun 16px step
    -- always completes on its own, and a press held through the step
    -- overshoots junctions whose both neighbors are walkable ((19,12),
    -- (11,7)) into a forever-oscillation -- the navline agent's diagnosis
    -- of every measured endgame parking
    if not H.tileAligned() then H.setPad({}); return end
    if held < HOLD then held = held + 1; H.setPad({}); return end
    fieldStep(H.fieldX(), H.fieldY())
  end) }, "rafterlab cross: " .. STRATEGY)
end

local res = { arrived = false, fights = 0, bframes = 0, waits = 0, pushes = 0 }
H.run({ maxFrames = 40000 }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS,
  -- so every fixture is spelled out and FIXTURE picks at runtime.
  (function()
    local fixtures = {
      rafterlab_catwalk      = H.loadState("build/states/rafterlab_catwalk.mss.lua"),
      rafterlab_catwalk_fast = H.loadState("build/states/rafterlab_catwalk_fast.mss.lua"),
      rafterlab_catwalk_s0   = H.loadState("build/states/rafterlab_catwalk_s0.mss.lua"),
      rafterlab_catwalk_s1   = H.loadState("build/states/rafterlab_catwalk_s1.mss.lua"),
      rafterlab_catwalk_s2   = H.loadState("build/states/rafterlab_catwalk_s2.mss.lua"),
      rafterlab_catwalk_s3   = H.loadState("build/states/rafterlab_catwalk_s3.mss.lua"),
      rafterlab_catwalk_s4   = H.loadState("build/states/rafterlab_catwalk_s4.mss.lua"),
      rafterlab_catwalk_s5   = H.loadState("build/states/rafterlab_catwalk_s5.mss.lua"),
      rafterlab_catwalk_s6   = H.loadState("build/states/rafterlab_catwalk_s6.mss.lua"),
      rafterlab_catwalk_s7   = H.loadState("build/states/rafterlab_catwalk_s7.mss.lua"),
    }
    return assert(fixtures[FIXTURE], "unknown FIXTURE " .. FIXTURE)
  end)(),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 235, "lab fixture boots on the rafters (map 235)")
    res.start = H.readWord(0x1189)
    H.log(string.format("[lab] set-off strategy=%s hold=%d runtry=%d radius=%d " ..
      "stuckcap=%d panic=%d timer=%d rats: %s",
      STRATEGY, HOLD, RUNTRY, RADIUS, STUCKCAP, PANIC, res.start, ratLine()))
  end),
  cross(res),
  H.call(function()
    H.log(string.format("[dodge] waits=%d pushes=%d",
      res.waits or 0, res.pushes or 0))
    local margin = res.arrived and H.readWord(0x1189) or 0
    local live = 0
    for k = 0, 4 do if sw(RAT_GATE0 + k) == 1 then live = live + 1 end end
    H.log(string.format("[result] strategy=%s hold=%d runtry=%d radius=%d " ..
      "stuckcap=%d panic=%d start=%d margin=%d arrived=%d standing=%d " ..
      "fights=%d bframes=%d ratsleft=%d pos=%d,%d",
      STRATEGY, HOLD, RUNTRY, RADIUS, STUCKCAP, PANIC, res.start, margin,
      res.arrived and 1 or 0, allStanding() and 1 or 0,
      res.fights or 0, res.bframes or 0, live, H.fieldX(), H.fieldY()))
  end),
})
