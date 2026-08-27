-- probe_rafterlab_navline.lua -- rafter-crossing lab: the "navline"
-- strategy.  Fight-through baseline (same battle handling as the shared
-- template, measured-correct) with the field walker rebuilt on the
-- repo's verified-step navigation discipline (navTo's executor):
--
--   * each BFS step is pressed only until the party starts moving, then
--     RELEASED -- a begun 16px step glides to completion on a neutral
--     pad.  This is the fix for the diagnosed fightline stall: the
--     template held each press until the next aligned frame, so at the
--     (19,12) junction the still-held vertical press was polled one
--     frame before the westward turn could be set, chaining the party
--     past the junction ((19,11)/(19,13) are both walkable -- the only
--     turn on the route whose overshoot doesn't hit a wall), and the
--     replan marched it right back: a permanent (19,11)<->(19,13)
--     oscillation through (19,12) that only a battle's neutral-pad
--     reset could break (navdiag_h0.log f14391-f14459 shows the cycle
--     with all five rats dead).
--   * a press that never moves the party within 24 aligned frames
--     condemns that edge (navTo's blocked-edge learning) and re-plans;
--     the blocklist is forgiven when no path remains (a condemned edge
--     may be the only corridor once a blocker moves off).
--   * bfsPath(14,7)==nil almost always means a live rat is standing on
--     one of the map's one-tile necks (objects are walls to
--     stepAllowed).  Fallback is non-thrashing: press into an adjacent
--     rat if one is already beside us, else wait briefly (rat wander
--     clears necks fast and waiting is far cheaper than a ~2300-frame
--     fight), else commit to ONE rat and walk at it until the path
--     clears or adjacency fires the fight.  No per-frame retargeting.
--
-- [result] line format identical to the template's, strategy=navline.

local H = dofile("tools/tests/lib/ot6.lua")

local STRATEGY = "@STRATEGY@"
local HOLD     = tonumber("@HOLD@")     or 0
local RUNTRY   = tonumber("@RUNTRY@")   or 0
local RADIUS   = tonumber("@RADIUS@")   or 2
local STUCKCAP = tonumber("@STUCKCAP@") or 600
local PANIC    = tonumber("@PANIC@")    or 6000
if STRATEGY:find("@") then STRATEGY = "navline" end

local GX, GY = 14, 7                    -- the Ultros entry tile
local MAXF = 20000
local WAITCAP = 240   -- aligned frames to wait out a rat-plugged neck
local PRESSCAP = 24   -- held aligned frames before an edge is condemned

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
local function allStanding()
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
      return false
    end
  end
  return true
end

-- move geometry, mirrored from lib/ot6_field.lua so blocked-edge keys
-- match the table H.bfsPath consumes
local DELTA = { up = { 0, -1 }, right = { 1, 0 },
                down = { 0, 1 }, left = { -1, 0 },
                upright = { 1, -1 }, downright = { 1, 1 },
                downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVEIDX = { up = 0, right = 1, down = 2, left = 3,
                  upright = 4, downright = 5, downleft = 6, upleft = 7 }
local function edgeKey(x, y, move)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 8 + MOVEIDX[move]
end

-- one crossing attempt; fills `res`
local function cross(res)
  local hb, battN, wipeN, notBattN = 0, 0, 0, 0
  local held, lost = 0, nil
  local battleUp, wasInBattle, fightStart = false, false, 0
  -- fight config per the lab coordinator's measured-best (2026-08-27):
  -- boost off, cadence 12 -- faster and safer than the template default.
  -- (The navline_h* hold batch predates this and ran boost=true, default
  -- cadence; the fixture-seeded navline-s* batch runs this config.)
  local fight = H.newFightDriver("lab",
    { tactical = true, boost = false, cure = false, items = false,
      cadence = 12 })

  -- navline walker state
  local blocked, nblocked = {}, 0
  local plan, idx = nil, 1
  local pend = nil              -- the in-flight/unverified step
  local waitN, chaseK = 0, nil  -- no-path fallback state
  local function navDrop()      -- position may have shifted under us:
    plan, pend = nil, nil       -- forget the plan, keep the blocklist
  end

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

  -- launch `dir` from (x,y) as a verified step
  local function launch(x, y, dir)
    local d = DELTA[dir]
    pend = { x = x, y = y, dir = dir, tx = x + d[1], ty = y + d[2],
             held = 0, holding = true }
    H.setPad({ [H.movePress(dir)] = true })
  end

  -- the navline field policy, called every non-battle non-dialog
  -- controlled frame; owns alignment handling itself.
  local function navlineStep()
    -- 1. a step is in flight: hold only until the party starts moving,
    --    then release -- the begun step glides to rest on a neutral pad,
    --    and a stale press can never chain us past a junction.
    if pend and pend.holding then
      if not H.tileAligned()
         or H.fieldX() ~= pend.x or H.fieldY() ~= pend.y then
        pend.holding = false
        H.setPad({})
        return
      end
      pend.held = pend.held + 1
      if pend.held > PRESSCAP then    -- never moved: the model was wrong
        blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
        nblocked = nblocked + 1
        H.log(string.format("lab: edge (%d,%d)->%s blocked in reality; re-plan",
          pend.x, pend.y, pend.dir))
        plan, pend = nil, nil
        H.setPad({})
        return
      end
      H.setPad({ [H.movePress(pend.dir)] = true })
      return
    end
    -- 2. gliding between tiles: neutral pad until at rest
    if not H.tileAligned() then H.setPad({}); return end
    local x, y = H.fieldX(), H.fieldY()
    -- 3. verify the landing of the last step
    if pend then
      if x == pend.tx and y == pend.ty then
        pend = nil                    -- clean step, plan still on track
      else
        local d = DELTA[pend.dir]
        local dx, dy = x - pend.x, y - pend.y
        local k = math.max(math.abs(dx), math.abs(dy))
        if not (k > 0 and dx == d[1] * k and dy == d[2] * k) then
          blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
          nblocked = nblocked + 1
        end                           -- (same-direction slide: edge was fine)
        H.log(string.format("lab: step (%d,%d)->%s landed (%d,%d); re-plan",
          pend.x, pend.y, pend.dir, x, y))
        plan, pend = nil, nil
      end
    end
    -- 4. the RNG stagger: stand still HOLD aligned frames before setting off
    if held < HOLD then held = held + 1; H.setPad({}); return end
    -- 5. (re)plan
    if plan and idx > #plan then plan = nil end
    if not plan then
      plan = H.bfsPath(GX, GY, blocked)
      idx = 1
      if not plan and nblocked > 0 then
        -- forgive the blocklist: a condemned edge may be the only
        -- corridor once its blocker moves off
        blocked, nblocked = {}, 0
        plan = H.bfsPath(GX, GY, blocked)
      end
      if plan then waitN, chaseK = 0, nil end
    end
    -- 6. follow the plan
    if plan then
      if #plan == 0 then plan = nil; H.setPad({}); return end
      local dir = plan[idx]
      idx = idx + 1
      launch(x, y, dir)
      return
    end
    -- 7. no path: a live rat is plugging a neck.  Press into an adjacent
    --    rat (adjacency has already doomed us to the fight -- commit),
    --    else wait a while (rats wander off necks fast), else commit to
    --    one rat and walk at it.
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
    waitN = waitN + 1
    if waitN <= WAITCAP then H.setPad({}); return end
    if chaseK ~= nil and sw(RAT_GATE0 + chaseK) ~= 1 then chaseK = nil end
    local bestPlan, bestK
    for _, r in ipairs(rats) do
      if chaseK == nil or r.k == chaseK then
        for _, d in ipairs({ {0,-1}, {1,0}, {0,1}, {-1,0} }) do
          local pl = H.bfsPath(r.x + d[1], r.y + d[2], blocked)
          if pl and #pl > 0 and (not bestPlan or #pl < #bestPlan) then
            bestPlan, bestK = pl, r.k
          end
        end
      end
    end
    if bestPlan then
      if chaseK == nil then
        chaseK = bestK
        H.log(string.format("lab: no path; committing to rat %d at f%d",
          chaseK, H.frame))
      end
      launch(x, y, bestPlan[1])
      return
    end
    -- committed rat unreachable right now (or no rats live): stand
    H.setPad({})
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
    if hb % 600 == 0 then
      H.log(string.format("lab f%d (%d,%d) timer=%d batt=%d wait=%d rats: %s",
        H.frame, H.fieldX(), H.fieldY(), H.readWord(0x1189), battN,
        waitN, ratLine()))
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
      navDrop()
      res.fights = (res.fights or 0) + 1
      fightStart = hb
      H.log(string.format("lab: fight %d fired at (%d,%d) timer=%d rats: %s",
        res.fights, H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
    end
    if wasInBattle and notBattN >= 10 then
      wasInBattle = false
      battleUp = false
      navDrop()
      waitN, chaseK = 0, nil
      res.bframes = (res.bframes or 0) + (hb - fightStart)
      H.log(string.format("lab: fight %d done after %d frames, timer=%d, %s standing, rats: %s",
        res.fights, hb - fightStart, H.readWord(0x1189),
        allStanding() and "all" or "NOT all", ratLine()))
    end
    if battN >= 3 then battleFrame(); return end
    if notBattN < 10 then H.setPad({}); return end
    fight.idle()
    if H.dialogWaiting() then navDrop(); H.setPad(hb % 8 < 4 and { "a" } or {}); return end
    if not H.hasControl() then navDrop(); H.setPad({}); return end
    navlineStep()
  end) }, "rafterlab cross: " .. STRATEGY)
end

local res = { arrived = false, fights = 0, bframes = 0 }
H.run({ maxFrames = 40000 }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS,
  -- so the fixture must stay one literal; the batch wrapper seds this
  -- line's path directly when FIXTURE=rafterlab_catwalk_s<k> is set.
  H.loadState("build/states/rafterlab_catwalk.mss.lua"),
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
