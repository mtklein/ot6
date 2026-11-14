-- gen_wor_belly.lua -- the Gogo arc's first leg (docs/design/route-wor-gogo.md):
-- Continue the `wor-gau-v1` battery (SABIN, GAU, TERRA and CELES beside the
-- Falcon by Duncan's house), the Falcon's cabin (TERRA, CELES, RELM and
-- STRAGO), Triangle Island, where the Zone Eater (world group 32) engulfs a
-- party that lets it (the walker leaves its battle to the engine), the hunt
-- on the landing until each formation of the belly's pool is won (#486),
-- the belly's bridge (276: its conductors watched, its jumps pressed) and
-- its five chests (a conductor's touch on purpose for the shaft's two) to
-- the door (21,33), and the save point beyond it (279 (24,4)): the
-- `wor-belly-v1` battery, the retry point for the crushing room and GOGO
-- (gen_wor_gogo).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 349, 344, 347
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local SHOP_ITEMS = 74
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, walkInto, regroup, liftOff = K.say, K.kitLine, K.walkInto, K.regroup, K.liftOff
local watches, objLine, doomLine, pace = K.watches, K.objLine, K.doomLine, K.pace

-- ---- the careful walk: the conductors watched ----
-- The bridge's conductors (276 NPC_1..3: random walkers, collision_on, _cb8251) drop the party down the
-- shaft when one touches it.  Each walks a stretch of one row (CONDSEG, measured: x5_cond.txt).  How, read
-- from the field code and measured (build/attempts/wt/v044-esper-rework-4/belly/probe_touch2.log):
-- * a conductor acts on its own update tick, every 4 frames (obj.asm UpdateObjActions: 6 objects a frame), and
--   only while it stands on a tile.  Then, with no event running, it touches a character standing on any of
--   the four tiles beside it (CheckCollosions; the party "stands" on the tile it last stood on at its own tick,
--   $087A/$087B, so mid-step it is still on the tile it left); otherwise it draws a direction (NPCMoveRand,
--   Rand & 3): up and down are walls on its row, so it stays half the time and steps left or right a quarter
--   each, unless the end of its stretch or an object is there.  A step is 16 frames, and the tick that lands it
--   is its next chance to touch.  Probe: $12 landed on (48,30) at f974 and the party on (49,30) was dropped
--   the next frame, its first tick there.
-- * a jump is an event (_cb7e4c...: 34 frames under the Sprint Shoes, f897-f930), so no tick touches the party
--   in the air, wherever the party is registered meanwhile.
-- * the interval between a conductor's moves is 16 frames plus a geometric wait in ticks (0, 4, 8... at
--   1/2, 1/4, 1/8...), matching cond1.txt's 16/20/24/28 counts.  The "flicker" there (a tile and back within
--   1-4 frames) is objX reading the pixel position: a step right shows when it ends and a step left when it
--   begins, so a step right followed at once by one left reads as two changes a frame apart.  Real moves.
-- A person watches them: from where the party stands, a route to the target is planned around their tiles, and
-- of it only the stretch up to the next tile no conductor can reach (a rest) is weighed: the share of
-- CAREFUL_TRIALS simulated walks of the conductors, under the rules above and from where each stands or is
-- stepping now, that touch the party along that stretch.  At or under CAREFUL_RISK the stretch's first move is
-- made; otherwise other routes are tried (the riskiest tile closed, up to five times), then the party stands
-- (on a rest, or where standing is safe enough), or steps or jumps away.  Patience lets the walk take a riskier
-- stretch after a long stand, up to CAREFUL_RISK_CAP and no further.
local CARD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
-- the directions in a fixed order: pairs() over string keys follows the hash seed, which Lua 5.4 draws
-- per run, so the walk's equal-length routes differed between identical runs (#467)
local CARD_DIRS = { "down", "left", "right", "up" }
local FACE = { up = 0, right = 1, down = 2, left = 3 }
CAREFUL_TRIALS, CAREFUL_RISK, CAREFUL_IMPATIENCE, CAREFUL_RISK_CAP = 200, 0.08, 0.002, 0.2
local STEP_F, JUMP_F, DOOR_F = 16, 72, 40
-- the conductors' rules (above): a tick every 4 frames, a step of 16
local COND_TICK, COND_STEP = 4, 16
-- each conductor's tick phase (frame % 4), learned as it starts a step (armTrace)
local CPHASE, CPX = {}, {}
-- the frame the last event (a jump) ended on 276, and the walk's measured pause after a jump before its next
-- move is pressed (logged with the walk's end: DWELL_J's evidence)
local EV_END, EV_ON, DWELLS = nil, false, {}
local CONDSEG = { [276] = { [30] = { { 32, 40 }, { 45, 48 } }, [32] = { { 31, 34 } } } }
-- the longest one stand for the conductors is let sit quiet (the no-progress watchdog stands down for it), from
-- the conductors' cycle (#495): a conductor steps a tile every 16-20 frames either way at even odds, and a
-- random walk on a stretch of L tiles takes about L*L steps to cover it; a stand is let last twice that on the
-- longest stretch at the slowest pace (L = 9, row 30's 32-40: 2 * 81 * 20 = 3240 frames), over the longest
-- stand measured before the walk's tuning, 2304 frames (#486 review of the play at 2db501e2)
CAREFUL_QUIET = (function()
  local L = 0
  for _, rows in pairs(CONDSEG) do
    for _, segs in pairs(rows) do for _, sg in ipairs(segs) do L = math.max(L, sg[2] - sg[1] + 1) end end
  end
  return 2 * L * L * 20
end)()
local function condList(objs)
  local out = {}
  for _, o in ipairs(objs) do
    local ox, oy = H.objX(o), H.objY(o)
    if not (ox == 0 and oy == 0) then out[#out + 1] = { ox, oy, o = o } end
  end
  return out
end
local function condRange(c)
  for _, sg in ipairs((CONDSEG[map()] or {})[c[2]] or {}) do
    if c[1] >= sg[1] - 1 and c[1] <= sg[2] + 1 then return math.min(sg[1], c[1]), math.max(sg[2], c[1]) end
  end
  return c[1], c[1]
end
local function isRest(k, conds)
  local x, y = k & 0xFF, k >> 8
  for _, c in ipairs(conds) do
    local lo, hi = condRange(c)
    if c[2] == y and x >= lo - 1 and x <= hi + 1 then return false end
  end
  return true
end
-- the route to (tx, ty) as moves { kind = "step"|"jump"|"door", dir, link, from, to } (keys (y<<8)|x)
-- around the closed tiles, the cheapest where a move onto a tile a conductor can reach costs 1 + CAREFUL_REACH_W
-- and any other 1: a person crossing the bridge keeps off the conductors' rows where another way is not much
-- longer.  The shortest route to the FakeMustache from row 32's middle (37,32) runs west along conductor $10's row
-- 30 and then $11's row 32 (nine tiles in reach); the one that leaves row 30 at (34,30) for row 28 and comes down
-- at (31,28) has seven, and its first stretch ends on row 28 after four.  Under shortest-first every lab walk
-- stood at (37,32) pricing the long stretch at 0.6-0.9 (n1, build/attempts/wt/v044-esper-rework-4/belly/).
CAREFUL_REACH_W = 2
local function planRoute(tx, ty, lk, closed, conds)
  local sx, sy = H.fieldX(), H.fieldY()
  local byTile, door = {}, {}
  for _, L in ipairs(lk) do
    if L[6] == nil or L[6]() then
      local k = (L[2] << 8) | L[1]
      if L[7] then
        byTile[k] = byTile[k] or {}
        byTile[k][#byTile[k] + 1] = L
      else
        door[k] = (L[5] << 8) | L[4]
      end
    end
  end
  local start, goal = (sy << 8) | sx, (ty << 8) | tx
  -- Dijkstra over small integer costs: a bucket per cost
  local parent, cost, buckets, done, n = { [start] = false }, { [start] = 0 }, { [0] = { start } }, {}, 0
  local c0 = 0
  while n <= 8000 do
    local k
    while c0 <= 4000 do
      local b = buckets[c0]
      if b and #b > 0 then k = table.remove(b); if not done[k] and cost[k] == c0 then break end; k = nil
      else c0 = c0 + 1 end
    end
    if k == nil then break end
    done[k], n = true, n + 1
    if k == goal then
      local out = {}
      while parent[k] do table.insert(out, 1, parent[k].mv); k = parent[k].from end
      return out
    end
    local x, y = k & 0xFF, k >> 8
    local function visit(nk, mv)
      if mv.kind == "step" and door[nk] and nk ~= goal then mv.kind = "door"; nk = door[nk] end
      if closed[nk] or done[nk] then return end
      local nc = c0 + 1 + ((conds and not isRest(nk, conds)) and CAREFUL_REACH_W or 0)
      if cost[nk] == nil or nc < cost[nk] then
        mv.from, mv.to = k, nk
        parent[nk], cost[nk] = { from = k, mv = mv }, nc
        buckets[nc] = buckets[nc] or {}
        table.insert(buckets[nc], 1, nk)
      end
    end
    for _, L in ipairs(byTile[k] or {}) do visit((L[5] << 8) | L[4], { kind = "jump", link = L, dir = L[3] }) end
    for _, dir in ipairs(CARD_DIRS) do local d = CARD[dir]
      if H.canStep(x, y, dir) then visit(((y + d[2]) << 8) | (x + d[1]), { kind = "step", dir = dir }) end
    end
  end
  return nil
end
-- the moves up to and including the first that ends on a rest (or the whole route)
local function toRest(route, conds)
  local out = {}
  for _, m in ipairs(route) do
    out[#out + 1] = m
    if m.kind == "door" or isRest(m.to, conds) then break end
  end
  return out
end
-- where the party stands, over time, along moves: { x, y, from, until }
-- a step's frames at the party's real speed.  The field picks the speed as each step starts (player.asm: 3
-- under the Sprint Shoes' field bit, $11DF bit $20, unless $1EB8 bit $02 turns it off; else 2) and the party
-- object's speed byte reads 2 again at rest, so the bit is read, not the byte (1c8490d1 read the byte at rest:
-- 2 every time, so its halving never applied, which is why it changed nothing).  Measured on wor_belly_in with
-- STRAGO's kept Palidor rank (the Sprint Shoes bit): a step 8 frames, two jumps held (49,32) -> (49,28) 76, so
-- a jump 38, half of JUMP_F like the step, and the door (6,20) entered in 9
-- (build/attempts/wt/v044-esper-rework-3/belly/probe_belly.log).  At the drops of the walk that priced a jump at
-- 72 (belly5), the party landed on the conductors' row (41,30) 41 frames into the stretch against the 72
-- predicted, beside the conductor at (40,30), and jumped on to (41,32) by 83 against 144
-- (build/attempts/wt/v044-esper-rework-3/belly/belly5.log, "[jwalk] drop 31: predicted ... observed ...")
local function stepF()
  if (H.readByte(0x11DF) & 0x20) ~= 0 and (H.readByte(0x1EB8) & 0x02) == 0 then return STEP_F // 2 end
  return STEP_F
end
-- the party's exposure along moves: { x, y, from, until } spans, each a tile the party is registered on with no
-- event running, so a conductor's tick beside it touches.  A step keeps the party on the tile it leaves until it
-- lands (a step of stepF() frames); a jump is an event (JUMP_EV frames), untouchable; a door carries it off.
-- The walk's own pauses between moves (LAT before the first, DWELL_S after a step, DWELL_J after a jump: the
-- landing is waited for, then the next move pressed) are exposure on the tile it stands on.  DWELL_J: the walk
-- decides 4 frames after a jump's event ends (median and minimum of every pause the lab walks logged,
-- "pauses after a jump", n2) and presses within 4 more (jumpStep pulses A four frames in eight).
local LAT, DWELL_S, DWELL_J = 2, 4, 8
local function jumpEv() return (JUMP_F * stepF() // STEP_F) - 2 end
local function spansOf(moves)
  local spans, e = {}, 0
  local sf = stepF()
  local s = LAT
  for _, m in ipairs(moves) do
    local fx, fy = m.from & 0xFF, m.from >> 8
    if m.kind == "step" then
      spans[#spans + 1] = { fx, fy, e, s + sf }
      e = s + sf
      s = e + DWELL_S
    elseif m.kind == "jump" then
      spans[#spans + 1] = { fx, fy, e, s + 1 }
      e = s + jumpEv()
      s = e + DWELL_J
    else
      spans[#spans + 1] = { fx, fy, e, s + 1 }
      e = s + DOOR_F
      s = e + DWELL_S
    end
  end
  local last = moves[#moves]
  local tEnd = e + stepF()
  if last then spans[#spans + 1] = { last.to & 0xFF, last.to >> 8, e, tEnd } end
  return spans, tEnd
end
local seed = 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
-- a conductor as it is now: its tile (where a step under way lands), and the frames to its next tick there
local function condNow(c)
  local b = 0x29 * c.o
  local px, py = H.readWord(0x086a + b), H.readWord(0x086d + b)
  if (px & 15) == 0 and (py & 15) == 0 then
    local ph = CPHASE[c.o]
    return px >> 4, ph and ((ph - H.frame - 1) % COND_TICK) + 1 or nil
  end
  local dir = H.readByte(0x087e + b)
  if dir == 2 then return (px >> 4) + 1, COND_STEP - (px & 15) + 1 end
  if dir == 4 then return px >> 4, (px & 15) + 1 end
  return px >> 4, nil
end
local function simRisk(spans, tEnd, conds)
  local live = {}
  for _, c in ipairs(conds) do
    for _, sp in ipairs(spans) do
      if math.abs(sp[2] - c[2]) <= 1 then
        local x0, t0 = condNow(c)
        local lo, hi = condRange({ x0, c[2] })
        live[#live + 1] = { x0 = x0, y = c[2], t0 = t0, lo = lo, hi = hi }
        break
      end
    end
  end
  if #live == 0 then return 0, nil end
  seed = (H.frame * 7919 + 17) % 2147483648
  local hits, worst = 0, {}
  local function touch(x, y, at)
    for _, sp in ipairs(spans) do
      if at >= sp[3] and at < sp[4] and math.abs(x - sp[1]) + math.abs(y - sp[2]) == 1 then
        local k = (sp[2] << 8) | sp[1]
        worst[k] = (worst[k] or 0) + 1
        return true
      end
    end
    return false
  end
  local function occupied(x, y, at)
    for _, sp in ipairs(spans) do
      if at >= sp[3] and at < sp[4] and x == sp[1] and y == sp[2] then return true end
    end
    return false
  end
  for _ = 1, CAREFUL_TRIALS do
    local hit = false
    for _, c in ipairs(live) do
      local x, t = c.x0, c.t0 or (1 + math.floor(rnd() * COND_TICK))
      while not hit and t < tEnd do
        hit = touch(x, c.y, t)
        if not hit then
          local u, nx = rnd(), nil
          if u < 0.25 then nx = x - 1 elseif u < 0.5 then nx = x + 1 end
          if nx and nx >= c.lo and nx <= c.hi and not occupied(nx, c.y, t) then
            x, t = nx, t + COND_STEP
          else
            t = t + COND_TICK
          end
        end
      end
      if hit then break end
    end
    if hit then hits = hits + 1 end
  end
  local wk, wn = nil, 0
  for k, n in pairs(worst) do if n > wn then wk, wn = k, n end end
  return hits / CAREFUL_TRIALS, wk
end
-- wait for control, fighting a battle that opens meanwhile (one the last step's arrival left loading)
local function waitControl(what)
  local drv = H.fightDriverFor("careful", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local bn = 0
  return H.withReset(H.driveUntil(function()
    return not H.battleLoadStarted() and H.hasControl() and H.tileAligned()
  end, 60000, {
    H.call(function()
      bn = H.battleLoadStarted() and bn + 1 or 0
      if bn >= 3 then drv.frame(); return end
      if bn == 0 then drv.idle() end
      H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {})
    end),
  }, what .. ": control"), function() bn = 0 end)
end
-- a jump from the tile the party stands on: face its way with A pulsed until it lands (on the landing at
-- rest with control) or 600 frames pass without it (logged; the walk plans again from wherever it is)
local function jumpStep(L, what, abort)
  local n, ctl, f0, drv, bn, pf = 0, 0, nil, nil, 0, nil
  drv = H.fightDriverFor("careful jump", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  return H.withReset(H.driveUntil(function()
    f0 = f0 or H.frame
    if abort() then return true end
    -- landed: at rest on the landing with control seen (a landing that is itself a jump's tile re-runs its
    -- script under the party, control one frame in four)
    if H.fieldX() == L[4] and H.fieldY() == L[5] and H.tileAligned() and not H.battleLoadStarted() then
      n = n + 1
      if H.hasControl() then ctl = ctl + 1 end
    else
      n, ctl = 0, 0
    end
    if n >= 6 and ctl >= 1 then return true end
    if H.frame - f0 > 600 and not H.battleLoadStarted() then
      H.log(string.format("[careful] %s: the jump %s from (%d,%d) did not land in 600 frames: at (%d,%d) ctl=%s "
        .. "algn=%s ev=%s dlg=%s facing %d", what, L[3], L[1], L[2], H.fieldX(), H.fieldY(), tostring(H.hasControl()),
        tostring(H.tileAligned()), tostring(H.eventRunning()), tostring(H.dialogWaiting()), H.readByte(0x0743)))
      return true
    end
    return false
  end, 100000, {
    H.call(function()
      bn = H.battleLoadStarted() and bn + 1 or 0
      if bn >= 3 then drv.frame(); return end
      if bn == 0 then drv.idle() end
      local on = H.fieldX() == L[1] and H.fieldY() == L[2] and H.tileAligned() and not H.dialogWaiting()
      local pad = {}
      -- A only once the party faces the jump's way: the "either way" tiles (_cb7ea8) jump the way it faces, and A
      -- pressed with the turn jumped a party just landed facing down back down (n6, (31,30): "jump up" went to
      -- (31,32) and $11 touched it).  Facing: the party object's $087F, 0 up 1 right 2 down 3 left
      local face = H.readByte(0x087f + H.readWord(0x0803))
      if on then
        pf = pf or H.frame
        pad[L[3]] = true
        if face == FACE[L[3]] and (H.frame - pf) % 8 < 4 then pad.a = true end
      end
      H.setPad(pad)
    end),
  }, what .. ": a jump"), function() n, ctl, f0, bn, pf = 0, 0, nil, 0, nil end)
end
local function doMove(mv, what, abort)
  if mv.kind == "jump" then return jumpStep(mv.link, what, abort) end
  local d = CARD[mv.dir]
  local x0, y0 = H.fieldX(), H.fieldY()
  local nx, ny = x0 + d[1], y0 + d[2]
  local m0 = map()
  -- a door carries the party far: arriving anywhere two or more tiles off is arriving
  return H.navTo(nx, ny, { maxFrames = 600, playBattles = "tactical", fight = FIGHT,
    arrive = function()
      return abort() or (H.fieldX() == nx and H.fieldY() == ny) or map() ~= m0
        or math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) >= 2
    end })
end
local function carefulWalk(tx, ty, lk, objs, what, budget, abort)
  local moves, waits, lastWhy, stood, waitStart, lastJump = 0, 0, nil, 0, nil, false
  local function there() return H.fieldX() == tx and H.fieldY() == ty and H.tileAligned() end
  local function oneMove()
    local conds = condList(objs)
    local here = (H.fieldY() << 8) | H.fieldX()
    -- routes are planned around each conductor's tile and the tiles beside it on its row; when that closes every
    -- way (a conductor's stretch is the only way past it), around its own tile alone, the stretch's risk weighed
    -- the same way, so the walk's patience (CAREFUL_IMPATIENCE) can take a stretch rather than stand on "no
    -- route" (#495: on the main line the walk to the FakeMustache spent its whole step budget standing there,
    -- "BUDGET SPENT -- 3000 steps (31 moves, 2969 waits)", every play)
    local closed, tight = {}, {}
    for _, c in ipairs(conds) do
      tight[(c[2] << 8) | c[1]] = true
      for dx = -1, 1 do closed[(c[2] << 8) | (c[1] + dx)] = true end
    end
    local best, bestR, tried = nil, 2, 0
    local plan = closed
    for _ = 1, 6 do
      local route = planRoute(tx, ty, lk, plan, conds)
      if (not route or #route == 0) and plan == closed and tried == 0 then
        plan = tight
        route = planRoute(tx, ty, lk, plan, conds)
        -- a conductor's tile on the way beyond the next rest (row 32's $11 on (31,32), the only way down to
        -- the FakeMustache) closes every route, though only the stretch to the rest is walked and weighed: plan
        -- through it (n6: landed mid-stretch on row 30, the walk saw "no route" and jumped back)
        if not route or #route == 0 then
          plan = {}
          route = planRoute(tx, ty, lk, plan, conds)
        end
      end
      if not route or #route == 0 then break end
      tried = tried + 1
      local pre = toRest(route, conds)
      local sp, te = spansOf(pre)
      local r, wk = simRisk(sp, te, conds)
      if r < bestR then best, bestR = pre, r end
      if r <= CAREFUL_RISK or wk == nil or wk == here then break end
      plan[wk] = true
    end
    local mv = nil
    -- patience: the risk a person takes grows with the frames stood (four a wait), up to CAREFUL_RISK_CAP
    local thr = math.min(CAREFUL_RISK + stood * CAREFUL_IMPATIENCE, CAREFUL_RISK_CAP)
    local onRest = isRest(here, conds)
    -- standing here a while (none on a rest): off a rest it is a risk of its own
    local rs = onRest and 0 or simRisk({ { H.fieldX(), H.fieldY(), 0, 64 } }, 64, conds)
    -- staging: from a rest, the stretch's first move alone when it and a stand where it lands are safe (a jump onto
    -- row 30 at (31,30) while $10 is away), so the rest of the stretch is weighed from there, with a shorter lead
    -- for the conductors to close in.  The descent (31,28) -> (29,32) priced 0.24-0.66 from row 28 and never
    -- went under the cap in 12000 frames (n7: 19 BUDGET SPENT, all "at (31,28)"); from (31,30) $11 has one jump's
    -- time to come, not two.  A conductor that comes after the party there is met as off any rest (below)
    local stageR = nil
    if best and bestR > thr and onRest and #best > 1 and not isRest(best[1].to, conds) then
      local s2, t2 = spansOf({ best[1] })
      s2[#s2][4] = t2 + 64
      stageR = simRisk(s2, t2 + 64, conds)
    end
    if best and (bestR <= thr or (stageR and stageR <= CAREFUL_RISK)) then
      if bestR > thr then
        H.log(string.format("[careful] %s: f%d staging from (%d,%d): the stretch at risk %.2f, its first move and a "
          .. "stand at %.2f", what, H.frame, H.fieldX(), H.fieldY(), bestR, stageR))
      elseif bestR > CAREFUL_RISK then
        H.log(string.format("[careful] %s: f%d after %d frames' wait, a stretch at risk %.2f from (%d,%d)", what,
          H.frame, stood * 4, bestR, H.fieldX(), H.fieldY()))
      end
      mv = best[1]
    else
      if rs > CAREFUL_RISK then
        -- off a rest with a conductor closing in: the safest of going on with the stretch, a move out of its way
        -- (priced with the stand where it lands), and standing
        local cand = {}
        for _, dir in ipairs(CARD_DIRS) do local d = CARD[dir]
          if H.canStep(H.fieldX(), H.fieldY(), dir) then
            cand[#cand + 1] = { kind = "step", dir = dir, from = here,
              to = ((H.fieldY() + d[2]) << 8) | (H.fieldX() + d[1]) }
          end
        end
        for _, L in ipairs(lk) do
          if L[7] and ((L[2] << 8) | L[1]) == here then
            cand[#cand + 1] = { kind = "jump", link = L, dir = L[3], from = here, to = (L[5] << 8) | L[4] }
          end
        end
        local fb, fr = nil, rs
        for _, c in ipairs(cand) do
          if not closed[c.to] or c.kind == "jump" then
            -- a step along a conductor's row toward it is no way out of its way
            local s2, t2 = spansOf({ c })
            if not isRest(c.to, conds) then s2[#s2][4] = t2 + 64; t2 = t2 + 64 end
            local r2 = simRisk(s2, t2, conds)
            if r2 < fr then fb, fr = c, r2 end
          end
        end
        if best and bestR <= fr then
          mv = best[1]
          H.log(string.format("[careful] %s: f%d on with the stretch from (%d,%d) at risk %.2f (standing %.2f, "
            .. "the best move out of the way %.2f)", what, H.frame, H.fieldX(), H.fieldY(), bestR, rs, fr))
        elseif fb then
          mv = fb
          H.log(string.format("[careful] %s: f%d out of a conductor's way from (%d,%d) (standing %.2f, %s %.2f; "
            .. "%s)", what, H.frame, H.fieldX(), H.fieldY(), rs, fb.kind .. " " .. tostring(fb.dir), fr,
            best and string.format("best of %d route(s) at risk %.2f", tried, bestR) or "no route"))
        end
      end
      if mv == nil then
        local why = best and string.format("best of %d route(s) at risk %.2f (%s %s first)", tried, bestR,
          best[1].kind, tostring(best[1].dir)) or "no route"
        if why ~= lastWhy then
          H.log(string.format("[careful] %s: f%d waiting at (%d,%d): %s; %s", what, H.frame, H.fieldX(), H.fieldY(),
            why, objLine()))
        end
        lastWhy = why
      end
    end
    if mv == nil then
      waits = waits + 1
      stood = stood + 1
      -- a person waiting for the conductors to clear stands still on purpose: the bridge's middle is crossed on
      -- the conductor's own row, and a wait for it outlasted the no-progress watchdog (#486, the graph's play
      -- at ec0ff9aa: "waiting at (49,18): no route" for 1808 frames).  Declared for CAREFUL_QUIET frames of one
      -- stand at most, so a stand past that trips
      if waitStart == nil then
        waitStart = H.frame
        H.log(string.format("[careful] %s: f%d standing at (%d,%d) for the conductors, quiet declared for up to %d "
          .. "frames", what, H.frame, H.fieldX(), H.fieldY(), CAREFUL_QUIET))
      end
      if H.frame - waitStart < CAREFUL_QUIET then H.watchQuiet(120) end
      return H.waitFrames(4)
    end
    moves, waitStart = moves + 1, nil
    if best and mv == best[1] then
      -- the stretch the walk priced, kept for the drop's report (#328 review: predicted against observed)
      local sp = spansOf(best)
      BELLY_PRED = { f0 = H.frame, risk = bestR, spans = sp, step = stepF() }
      -- every stretch begun on a conductor's reach, with its price: the model's calibration (each drop follows
      -- the last of these)
      local r = (bestR > thr and stageR) or bestR
      if r > 0 then
        H.log(string.format("[careful] %s: f%d stretch from (%d,%d) at risk %.3f, %d move(s)", what, H.frame,
          H.fieldX(), H.fieldY(), r, (bestR > thr and stageR) and 1 or #best))
      end
    end
    if lastJump and EV_END and H.frame - EV_END < 200 then DWELLS[#DWELLS + 1] = H.frame - EV_END end
    lastJump = mv.kind == "jump"
    stood = 0
    lastWhy = nil
    if mv.kind == "jump" then
      H.log(string.format("[careful] f%d jump %s from (%d,%d) (risk %.2f); %s", H.frame, mv.link[3], H.fieldX(),
        H.fieldY(), bestR, objLine()))
    end
    return doMove(mv, what, abort)
  end
  local nOut = #H.outcomes
  return H.seqStep({
    H.repeatN(budget or 3000, {
      H.cond(function() return not there() and not abort() end, {
        waitControl(what),
        -- a battle fought on the way: the field care a walk gives after one (the menu stops the field)
        H.cond(function() return #H.outcomes ~= nOut end, {
          -- a battle ends a stand: the next stand's quiet counts from after it (#495)
          H.call(function() nOut, waitStart = #H.outcomes, nil end),
          H.fieldCare({ tag = "care after battle (careful)" }),
        }, {}),
        H.cond(function() return not abort() end, { H.lazy(oneMove) }, {}),
      }, {}),
    }),
    H.call(function()
      table.sort(DWELLS)
      H.log(string.format("[careful] %s: %s after %d moves and %d waits; pauses after a jump (frames) n=%d min %s "
        .. "median %s max %s", what, there() and "there" or "stopped", moves, waits, #DWELLS, tostring(DWELLS[1]),
        tostring(DWELLS[(#DWELLS + 1) // 2]), tostring(DWELLS[#DWELLS])))
      -- the walk's step budget spent short of the target and with no drop to end it: said loud (jwalk tries
      -- again from where the party stands, and asserts after its last try)
      if not there() and not abort() then
        H.log(string.format("[careful] %s: BUDGET SPENT -- %d steps (%d moves, %d waits) at (%d,%d), short of "
          .. "(%d,%d)", what, budget or 3000, moves, waits, H.fieldX(), H.fieldY(), tx, ty))
      end
    end),
  })
end
-- ---- the belly's bridge (276) ----
-- route_data map 276: its same-map doors, and its jump triggers (_cb7e4c up, _cb7e63 down, _cb7ea8 either,
-- _cb7e7a left, _cb7e91 right: facing the way with A held, the party jumps two tiles; jumps.py)
local DOORS276 = { { 6, 20, 60, 26 }, { 60, 25, 6, 19 }, { 59, 33, 52, 14 }, { 52, 13, 59, 32 } }
local function jumps(list, dir, n)
  local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[dir]
  local out = {}
  for _, t in ipairs(list) do out[#out + 1] = { t[1], t[2], dir, t[1] + d[1] * n, t[2] + d[2] * n, nil, true } end
  return out
end
local function cat(...)
  local out = {}
  for _, l in ipairs({ ... }) do for _, v in ipairs(l) do out[#out + 1] = v end end
  return out
end
local J276_UP = { { 48, 32 }, { 49, 32 }, { 47, 30 }, { 46, 30 }, { 44, 32 }, { 45, 32 }, { 41, 32 }, { 40, 32 },
  { 39, 32 }, { 38, 32 }, { 37, 32 }, { 34, 32 }, { 33, 32 }, { 32, 32 }, { 31, 32 } }
local J276_DOWN = { { 44, 28 }, { 45, 28 }, { 46, 28 }, { 47, 28 }, { 48, 28 }, { 49, 28 }, { 40, 28 }, { 41, 28 },
  { 39, 30 }, { 38, 30 }, { 37, 30 }, { 31, 28 }, { 32, 28 }, { 33, 28 }, { 34, 28 } }
local J276_BOTH = { { 49, 30 }, { 48, 30 }, { 45, 30 }, { 44, 30 }, { 40, 30 }, { 41, 30 }, { 34, 30 }, { 33, 30 },
  { 32, 30 }, { 31, 30 } }
local LINKS276 = cat(links(DOORS276), jumps(J276_UP, "up", 2), jumps(J276_DOWN, "down", 2), jumps(J276_BOTH, "up", 2),
  jumps(J276_BOTH, "down", 2), jumps({ { 29, 32 } }, "left", 2), jumps({ { 27, 32 } }, "right", 2))
-- a conductor's touch (_cb8251) drops the party down the shaft at x 37 and sets it on (37,17): counted on
-- the edge of the party's entering that column
local falls, inShaft = 0, false
local function fallCount()
  local s = map() == 276 and H.fieldX() == 37 and H.fieldY() >= 9 and H.fieldY() <= 17
  if s and not inShaft then
    falls = falls + 1
    H.log(string.format("[jwalk] f%d dropped down the shaft (%d); %s", H.frame, falls, objLine()))
    local p = BELLY_PRED
    if p then
      local pr = {}
      for _, sp in ipairs(p.spans) do pr[#pr + 1] = string.format("(%d,%d)@%d-%d", sp[1], sp[2], sp[3], sp[4]) end
      local ob = {}
      for _, r in ipairs(BELLY_TRACE or {}) do
        if r.f >= p.f0 then ob[#ob + 1] = string.format("%d:(%d,%d)%sc%s", r.f - p.f0, r.x, r.y, r.e == 1 and "e" or "", r.c) end
      end
      H.log(string.format("[jwalk] drop %d: predicted (step %d frames, risk %.2f) %s", falls, p.step, p.risk,
        table.concat(pr, " ")))
      H.log(string.format("[jwalk] drop %d: observed since the stretch began %s", falls, table.concat(ob, " ")))
    end
  end
  inShaft = s
  return falls
end
-- the careful walk to (x, y) on the bridge, again from wherever the party stands while it is not there (a
-- conductor's touch drops it to the shaft's foot, where the plate (46,17) opens the way back: _cb8062,
-- $01F0 for this load of the map), at most `tries` times; done() ends it early
-- the party's tile and the conductors' columns each frame on 276, the last 200 frames (a drop's report)
local function armTrace()
  if BELLY_TRACE then return end
  BELLY_TRACE = {}
  emu.addEventCallback(function()
    if map() ~= 276 then return end
    local c = {}
    for _, o in ipairs({ 0x10, 0x11, 0x12 }) do
      c[#c + 1] = string.format("%d/%d", H.objX(o), H.objY(o))
      -- a step begins on the conductor's tick: its phase, for the walk's pricing
      local px = H.readWord(0x086a + 0x29 * o)
      if (px & 15) ~= 0 and (CPX[o] or 0) & 15 == 0 and CPX[o] then CPHASE[o] = H.frame % COND_TICK end
      CPX[o] = px
    end
    local ev = H.eventRunning()
    if EV_ON and not ev then EV_END = H.frame end
    EV_ON = ev
    BELLY_TRACE[#BELLY_TRACE + 1] = { f = H.frame, x = H.fieldX(), y = H.fieldY(), c = table.concat(c, ","),
      e = ev and 1 or 0 }
    if #BELLY_TRACE > 200 then table.remove(BELLY_TRACE, 1) end
  end, emu.eventType.endFrame)
end
local function jwalk(x, y, lk, what, tries, done)
  local n = 0
  armTrace()
  local function there() return (done and done()) or (H.fieldX() == x and H.fieldY() == y and H.tileAligned()) end
  return H.seqStep({
    H.repeatN(tries or 6, {
      H.cond(function() return not there() end, {
        H.call(function()
          n = n + 1
          H.log(string.format("[jwalk] %s: try %d from map %d (%d,%d)", what, n, map(), H.fieldX(), H.fieldY()))
        end),
        waitControl(what),
        H.cond(function()
          return not there() and map() == 276 and sw(0x01F0) == 0 and H.bfsReach(nil, nil, nil, {}, 46, 17) ~= nil
        end, {
          H.navTo(46, 17, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
          H.waitUntil(function() return sw(0x01F0) == 1 and H.hasControl() and H.tileAligned() end, 600,
            "276: the plate (46,17) opens the way", 1),
          H.call(function() say("route", "276: the plate (46,17)") end),
        }, {}),
        H.cond(function() return not there() end, {
          H.lazy(function()
            local f0 = fallCount()
            return carefulWalk(x, y, lk, { 0x10, 0x11, 0x12, 0x13, 0x14 }, what, 3000,
              function() return fallCount() > f0 end)
          end),
        }, {}),
      }, {}),
    }),
    H.call(function()
      H.assertEq(there(), true, string.format("%s: at (%d,%d) on map %d within %d tries", what, x, y, map(), tries or 6))
      H.log(string.format("[jwalk] %s: there after %d tries, %d drop(s) down the shaft", what, n, falls))
      say("route", what)
    end),
  })
end
-- ---- the belly in full (#486): its formations and its chests ----
-- The belly's pool (field group 170, maps 276 and 277: SubBattleGroup) deals Karkass x2 (349), Wart Puck and
-- Ogor (353), Tap Dancer and Covert x2 (350) at 80/256 each and Woolly x2 with Karkass x2 (352) at 16/256.  The
-- party walks the landing until each is won (K.hunt, which asserts this list is the pool the ROM gives the map
-- and bounds the hunt by the worst draws the encounter counters can hold: every slot within 110 picks, a battle
-- within 162 steps; build/attempts/wt/v038-zone-eater/lab/scripts/bounds.py).
local BELLY170 = { [349] = "Karkass x2", [353] = "Wart Puck, Ogor", [350] = "Tap Dancer, Covert x2",
  [352] = "Woolly x2, Karkass x2" }
-- the chests (treasure bits; TreasureProp 276) and the tile each is opened from, facing it: the bridge's two
-- beside the jumps of row 32, the shaft's two (the foot of the conductors' drop), and the one at the bridge's
-- west end
local GENJI_ARMOR = { stand = { 44, 32 }, face = "left", bit = 237, what = "Genji Armor", item = 0x9A }
local MAGICAL_BRSH = { stand = { 41, 32 }, face = "right", bit = 236, what = "Magical Brsh", item = 0x3F }
local ETHER = { stand = { 35, 17 }, face = "up", bit = 194, what = "Ether", item = 0xEC }
local RED_JACKET = { stand = { 40, 14 }, face = "up", bit = 209, what = "Red Jacket", item = 0x93 }
local FAKEMUSTACHE = { stand = { 25, 32 }, face = "up", bit = 208, what = "FakeMustache", item = 0xD7 }
local function chest(o)
  return H.openChest({ stand = o.stand, face = o.face, bit = o.bit, what = o.what, item = o.item,
    nav = { maxFrames = 6000, playBattles = "tactical", fight = FIGHT } })
end
-- the bridge's chests from the tile beside each (the careful walk there; a drop on the way is walked back)
local function bridgeChest(o)
  return H.cond(function() return not H.chestOpen(o.bit) end, {
    jwalk(o.stand[1], o.stand[2], LINKS276, string.format("276: the bridge to the %s (%d,%d)", o.what, o.stand[1],
      o.stand[2]), 30),
    chest(o),
  }, {})
end
-- the shaft's chests: a person who wants them lets a conductor touch the party (_cb8251 drops it to (37,17)):
-- onto the conductors' row 30 west of the gap, then a step at a time toward the conductor there
local function towardConductor()
  local best, bd = nil, 99
  for o = 0x10, 0x12 do
    local ox, oy = H.objX(o), H.objY(o)
    if oy == H.fieldY() and ox >= 31 and ox <= 41 and math.abs(ox - H.fieldX()) < bd then
      best, bd = ox, math.abs(ox - H.fieldX())
    end
  end
  return best
end
local function dropDown()
  local f0, ph = nil, 0
  local function dropped() return fallCount() > f0 end
  return H.cond(function() return not (H.chestOpen(ETHER.bit) and H.chestOpen(RED_JACKET.bit)) end, {
    H.call(function() f0 = fallCount() end),
    H.lazy(function()
      return jwalk(36, 30, LINKS276, "276: onto the conductors' row (36,30)", 30, dropped)
    end),
    H.withReset(H.driveUntil(function()
      return dropped() and map() == 276 and H.hasControl() and H.tileAligned() and H.fieldY() == 17
    end, 6000, {
      H.call(function()
        ph = (ph + 1) % 8
        local cx = towardConductor()
        local pad = {}
        if not dropped() and cx and H.hasControl() and H.tileAligned() and ph < 4 then
          pad[cx < H.fieldX() and "left" or "right"] = true
        end
        H.setPad(pad)
      end),
    }, "276: a conductor's touch drops the party down the shaft"), function() ph = 0 end),
    H.release(),
    H.call(function() say("route", string.format("276: down the shaft, at (%d,%d)", H.fieldX(), H.fieldY())) end),
    chest(ETHER),
    chest(RED_JACKET),
  }, {})
end
local huntWon = {}

-- Triangle Island: the Falcon down on (237,52), a landable tile of world group 32 (the Zone Eater, every
-- slot: route_data pool group 32)
local ISLAND = { 237, 52 }
local ZONE_EATER = 0x171
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-gau-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ SABIN, GAU, TERRA, CELES }))
  end),
  -- @@setup-end

  -- ---- 1. the cabin, Triangle Island: the Zone Eater ------------------------------------------
  -- @@stage island
  -- the four highest for the belly (L43-44 bodies: route-wor-gogo.md section 2); GOGO, met at its end,
  -- waits in the cabin for a party of four
  regroup({ TERRA, CELES, RELM, STRAGO }),
  H.gearDress({ tag = "gear for the four" }),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } },
    { tag = "relics for the four" }),
  H.call(function() H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO })) end),
  liftOff(),
  H.call(function() H.log("[doom] aloft: " .. doomLine()) end),
  H.flyTo(ISLAND[1], ISLAND[2], { what = "the Falcon down on Triangle Island", fight = FIGHT }),
  H.call(function() say("wor", "on Triangle Island") end),
  -- the island's battles are the Zone Eater's, and a party that lets its Engulf take every member is
  -- carried inside (battle_main.asm @4807: $3EBC bit 7; world_start.asm @042b, VehicleEvent_05)
  pace(function() return not H.worldMode() end, 12, "the island until the Zone Eater engulfs the party",
    { ZONE_EATER }),
  H.waitUntil(function() return map() == 276 and H.hasControl() and settled() end, 6000, "control in the belly", 5),
  H.call(function() say("story", "engulfed: the belly (276)") end),
  H.saveState("wor_belly_in.mss"),

  -- ---- 2. the hunt on the landing ----------------------------------------------------------------------
  -- @@stage hunt
  K.hunt({ what = "the belly's landing (group 170)", lap = { { 10, 12 }, { 10, 13 } }, forms = BELLY170,
    won = huntWon, castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt" }),
  H.call(function() H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO })) end),

  -- ---- 3. the bridge and its chests --------------------------------------------------------------------
  -- @@stage bridge
  -- the landing (10,12), the door (6,20) to the bridge's east end (60,26), the bridge's rows and their
  -- jumps, the conductors watched (careful walk): the Genji Armor and the Magical Brsh beside row 32's jumps,
  -- a conductor's touch on purpose down the shaft for the Ether and the Red Jacket, the plate (46,17) that
  -- opens the way back, the FakeMustache at the west end, and the door (21,33) to the save point's room (279)
  bridgeChest(GENJI_ARMOR),
  bridgeChest(MAGICAL_BRSH),
  dropDown(),
  bridgeChest(FAKEMUSTACHE),
  jwalk(21, 32, LINKS276, "276: across the bridge to the door (21,33)", 30),
  H.call(function()
    for _, o in ipairs({ GENJI_ARMOR, MAGICAL_BRSH, ETHER, RED_JACKET, FAKEMUSTACHE }) do
      H.assertEq(H.chestOpen(o.bit), true, string.format("276: the %s's chest (bit %d) is open", o.what, o.bit))
    end
  end),
  walkInto(21, 33, 279, "276 (21,33) -> 279"),
  H.gearDress({ tag = "gear from the belly's chests" }),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } },
    { tag = "relics from the belly's chests" }),

  -- ---- 4. the save point -------------------------------------------------------------------------------
  -- @@stage save
  H.fieldCare({ threshold = 1.0, tag = "at the belly's save point" }),
  H.call(function()
    say("wor", "at the save point")
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO }))
  end),
  H.saveAtCheckpoint("wor-belly-v1"),
  H.saveState("wor_belly.mss"),
  H.logStep(function()
    return string.format("wor_belly generated: TERRA L%d, CELES L%d, RELM L%d and STRAGO L%d on the belly's save "
      .. "point, map 279 (%d,%d), saved in slot 3", lv(TERRA), lv(CELES), lv(RELM), lv(STRAGO), H.fieldX(), H.fieldY())
  end),
})
