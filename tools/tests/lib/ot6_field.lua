-- ot6_field.lua -- the NAVIGATION half of the OT6 test library: the true
-- passability model ported from the engine, BFS pathfinding, and the
-- verified-step walkers (navTo / worldNavTo / advanceStory / route).
--
-- lib/ot6.lua is the battle core every test uses; this file is everything
-- a ROUTE needs to walk the game world, and only the gen_* route
-- generators and field probes call it.  It is NOT a standalone module:
-- lib/compose.py inlines lib/ot6.lua and then this file into every
-- composed script -- a battle test simply carries nav code it never
-- calls -- invoking this chunk with the core's module table as its
-- argument (the `local M = ...` below).  Test scripts keep their one-line
-- contract
--
--   local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
--
-- and see ONE merged H; nothing anywhere references this file's path at
-- runtime.  Everything here installs onto that shared table through the
-- core's public M.* API plus M.seqStep (exported for route()); the shared
-- field-state reads both halves stand on (fieldX/hasControl/formation...)
-- stay in the core because suite battle tests use them too.
--
-- Freshness: a minted route fixture is a function of BOTH halves, so
-- lib/frontier_stamp.sh hashes generator ++ ot6.lua ++ ot6_field.lua
-- (that fixed order) into the mint signature.

local M = ...
assert(type(M) == "table",
  "ot6_field.lua is inlined by lib/compose.py after lib/ot6.lua and " ..
  "receives the core module table; it cannot be loaded on its own")

-- Field navigation, so routes are coordinate-aware instead of blind
-- timed holds (which desync on any map).  Movement is grid-oriented, one
-- tile per step: up=-Y down=+Y left=-X right=+X, PLUS the four diagonals
-- a left/right press produces on a diagonal-movement tile (every Figaro
-- staircase).  Passability is computed from RAM by porting both of the
-- engine's movement branches (the "true passability model" below), so
-- routes are found by BFS, not discovered by playing.

-- ----------------------------------------------- true passability model --
-- Port of the engine's own step check.  UpdatePlayerMovement
-- (src/field/player.asm:325) reads the d-pad and takes ONE of two branches;
-- both are modelled here, because Figaro Castle is built out of the second.
--
-- Tile id at (x,y) = the BG1 tilemap byte $7f0000[y*256+x]; its properties
-- are p1 = $7e7600[id] (the prop byte the engine keeps for the party's own
-- tile in $b8) and p2 = $7e7700[id] (directional exits, in $b9).
--
-- CARDINAL branch (@4978, player.asm:456-507 -> CheckPlayerMove @4e16,
-- player.asm:1072).  A step from cur=(x,y) toward dir is allowed iff ALL of:
--   1. p2(cur) has the direction's exit bit (up=$08 right=$01 down=$04
--      left=$02 -- player.asm DirectionBitTbl:1210);
--   2. p1(dst)&7 ~= 7 (counter/wall tile);
--   3. the bridge/z-level rules pass (below, transcribed branch for
--      branch; party z-level = $b2 low bits, bit0 upper / bit1 lower);
--   4. no object occupies dst: $7e2000[dstY*256+dstX] bit7 SET means free
--      (the engine allows crossing UNDER an occupied bridge tile; we skip
--      that special case -- conservative, and movement-verify covers it).
--
-- DIAGONAL branch (@48d4, player.asm:379-453).  UpdatePlayerMovement tests
-- the party's OWN tile first (player.asm:368-377): if p1(cur) & $c0 is set
-- -- and it is not a bridge tile the party is standing on the lower z-level
-- of -- a LEFT or RIGHT press moves the party DIAGONALLY instead, one tile
-- in each axis.  Which diagonal is a property of the tile, not the press:
--   p1 bit7 ($80), "\" tiles:  right -> down-right (dir $06, :403)
--                              left  -> up-left    (dir $08, :420)
--   p1 bit6 ($40), "/" tiles:  right -> up-right   (dir $05, :394)
--                              left  -> down-left  (dir $07, :429)
-- bit7 wins when both are set (:385 `bmi`, :410 `bpl`).  The destination
-- tests are the whole of it: p1(dst) must carry the SAME diagonal bit and
-- must not be exactly $f7 (:389-393, :399-402, :416-419, :424-428).  The
-- branch consults NOTHING else -- not p2's exit bits, not the counter rule,
-- not the z-level rules, not the object map (it never touches $7e2000 and
-- never calls GetObjMapAdjacent), and it never calls CheckDoor.  The
-- movement direction it stores in $087e is 5..8, and _c04f8d (player.asm
-- :1286) maps those to exactly the four diagonal neighbours; CalcObjMoveDir
-- (obj.asm:5521) then drives both axes at the cardinal rate, so a diagonal
-- step is one tile in x AND one in y (ObjMoveRateH/V rows for dir 5..8).
-- UP and DOWN presses are not handled by this branch at all (:380/:405 test
-- only $07 bit0/bit1) and fall through to the cardinal path, as does a
-- left/right press whose diagonal destination fails (:396, :400, :417, :426
-- all jump into @4978).  So on a diagonal tile the diagonal is TRIED FIRST
-- and the cardinal move of the same press only happens when it is refused:
-- that is why stepAllowed says "no" to a cardinal left/right that the
-- engine would turn into a diagonal.
--
-- The four cardinal names double as press names; the four diagonal names
-- are moves the model plans and verifies but never presses directly.
-- DIRS/DIRIDX stay CARDINAL: they are the world map's move set too, and the
-- overworld module (ff6/src/world/) has no diagonal branch at all -- its
-- GetPlayerInput tests one passability bit per cardinal direction
-- (move.asm @1ead..@1ff3).  Only the field walks diagonals.
local DIRS   = { "up", "right", "down", "left" }
local DIRIDX = { up = 0, right = 1, down = 2, left = 3 }
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 },
                 down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
-- the FIELD's move set: the four presses plus the four diagonals they can
-- turn into.  PRESS is the button a move is executed with.
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local MOVEIDX = { up = 0, right = 1, down = 2, left = 3,
                  upright = 4, downright = 5, downleft = 6, upleft = 7 }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }

-- BG1 tilemap byte for a tile.  The tilemap's row stride is 256 ($7f0000 +
-- row*256 + col: UpdateLocalTiles builds its row pointers as {lo=0,hi=row},
-- player.asm:1385-1399), but the COORDINATES wrap at the map's own size
-- masks $86/$87, not at 256 (`and $86` / `and $87`, player.asm:1387-1412).
-- Those come from InitScrollClip via ScrollClipTbl = $0f/$1f/$3f/$7f
-- (scroll.asm:298-320, table at :244), so they are never zero and no
-- guard is needed; Figaro's exterior map 55 is $3f/$3f, its interiors
-- $7f/$3f (map_prop.dat record 33*map + 23).
function M.maptile(x, y)
  local xm, ym = M.readByte(0x0086), M.readByte(0x0087)
  return M.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
end

-- The diagonal move a `press` produces standing on the tile whose prop byte
-- is `c` at party z-level `z`, or nil if this press moves cardinally here.
-- Transcribed from player.asm:368-429 (see the branch table above).
local function diagStep(x, y, c, press, z)
  if press ~= "left" and press ~= "right" then return nil end  -- :380/:405
  if (c & 0xC0) == 0 then return nil end                       -- :374-376
  if (c & 0x04) ~= 0 and z == 0x02 then return nil end         -- :368-373
  local bit = (c & 0x80) ~= 0 and 0x80 or 0x40                 -- :385/:410
  local mv
  if bit == 0x80 then mv = press == "right" and "downright" or "upleft"
  else                mv = press == "right" and "upright"   or "downleft" end
  local d = DELTA[mv]
  local t = M.readByte(0x7E7600 + M.maptile(x + d[1], y + d[2]))
  if t == 0xF7 or (t & bit) == 0 then return nil end           -- :389-:428
  return mv
end

-- the step check, parameterized on the party z-level so the pathfinder can
-- track z along a hypothetical path instead of assuming it constant
local function stepAllowed(x, y, move, z)
  local c = M.readByte(0x7E7600 + M.maptile(x, y))     -- p1(cur)
  local press = PRESS[move]
  local diag = diagStep(x, y, c, press, z)
  if move ~= press then return move == diag end  -- asked about a diagonal
  if diag then return false end     -- this press moves diagonally, not here
  local d = DELTA[move]
  local nx, ny = x + d[1], y + d[2]
  local e = M.readByte(0x7E7700 + M.maptile(x, y))     -- p2(cur), exit bits
  local t = M.readByte(0x7E7600 + M.maptile(nx, ny))   -- p1(dst)
  if (e & 0x0F & DIRBIT[move]) == 0 then return false end -- no exit that way
  if (t & 0x07) == 0x07 then return false end            -- counter/wall
  if (c & 0x04) ~= 0 then                 -- cur is a bridge tile:
    if (z & 0x01) ~= 0 then               --   party upper: dst must not be
      if (t & 0x02) ~= 0 then return false end          -- lower-only
    else                                  --   party lower: dst must not be
      if (t & 0x01) ~= 0 then return false end          -- upper-only
    end
  elseif (t & 0x03) == 0x03 then          -- dst walkable on both z-levels
    -- always allowed
  elseif (c & 0x03) == 0x03 then          -- cur on both: any dst EXCEPT a
    if (t & 0x04) ~= 0 then return false end            -- bridge tile
  elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
    return false                          -- z-levels incompatible
  end
  if (M.readByte(0x7E2000 + (ny & 0xFF) * 256 + (nx & 0xFF)) & 0x80) == 0 then
    return false                          -- an NPC/object stands there
  end
  return true
end

-- can the party make `move` from tile (x,y) RIGHT NOW (live z-level)?
-- `move` is any of MOVES: the four presses, or one of the four diagonals
-- (true only where the engine would turn that press into that diagonal).
function M.canStep(x, y, move)
  return stepAllowed(x, y, move, M.readByte(0x00b2) & 0x03)
end

-- the button that executes `move` (diagonals are pressed left/right)
function M.movePress(move) return PRESS[move] end

-- party z-level after stepping OFF (x,y): kept on a bridge/both tile,
-- otherwise taken from the tile being left (player.asm @4eef, :1196-1201).
-- The diagonal branch spells the same rule out longhand -- keep z if the
-- tile is a bridge ($04) or is both-z-levels ($03), else take $b8&3
-- (player.asm:432-439) -- so one function serves both branches.
local function zAfter(x, y, z)
  local c = M.readByte(0x7E7600 + M.maptile(x, y))
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end

local function edgeKey(x, y, move)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 8 + MOVEIDX[move]
end

-- BFS a path from the party's CURRENT tile to (tx,ty) over stepAllowed
-- edges, tracking the z-level a walker would carry along each candidate
-- path (nodes are (x,y,z) triples).  `blockedEdges` (optional, keys from
-- edgeKey) prunes edges the executor has PROVEN wrong empirically.
-- Returns a list of MOVES names (four cardinals plus the four diagonals a
-- press turns into on a diagonal tile), or nil (unreachable / >4096 nodes).
function M.bfsPath(tx, ty, blockedEdges)
  blockedEdges = blockedEdges or {}
  local sx, sy = M.fieldX(), M.fieldY()
  local sz = M.readByte(0x00b2) & 0x03
  local function nkey(x, y, z) return (z << 16) | ((y & 0xFF) << 8) | (x & 0xFF) end
  local seen = { [nkey(sx, sy, sz)] = true }
  local q, qi = { { sx, sy, sz } }, 1
  local parent = {}                       -- nkey -> { parentNkey, dir }
  while qi <= #q do
    local x, y, z = q[qi][1], q[qi][2], q[qi][3]
    qi = qi + 1
    if x == tx and y == ty then           -- collect dirs back to the start
      local dirs, k = {}, nkey(x, y, z)
      while parent[k] do
        table.insert(dirs, 1, parent[k][2])
        k = parent[k][1]
      end
      return dirs
    end
    if qi > 4096 then return nil end      -- sane radius: give up, not hang
    local zn = zAfter(x, y, z)
    for _, dir in ipairs(MOVES) do
      if not blockedEdges[edgeKey(x, y, dir)] and stepAllowed(x, y, dir, z) then
        local d = DELTA[dir]
        local k = nkey(x + d[1], y + d[2], zn)
        if not seen[k] then
          seen[k] = true
          parent[k] = { nkey(x, y, z), dir }
          q[#q + 1] = { x + d[1], y + d[2], zn }
        end
      end
    end
  end
  return nil
end

-- ------------------------------------------------------- BFS navigation --
NAV = {}
function M.navReset()
  NAV = { blocked = {}, nblocked = 0, plan = 0, idx = 0, hb = 0 }
end
M.navReset()
function M.navDump()   -- debugging one-liner (kept from the old navigator)
  return string.format("bfs plan=%d idx=%d blocked=%d",
    NAV.plan or 0, NAV.idx or 0, NAV.nblocked or 0)
end

-- targets may be numbers or thunks (resolved each tick, so a route can
-- aim at a coord it only knows at runtime)
local function resolve(v) return type(v) == "function" and v() or v end

-- Walk to tile (tx,ty) on the current map: BFS a plan over the true
-- passability model, then execute it ONE VERIFIED STEP at a time.  Each
-- iteration (only when user-controlled and tile-aligned): hold the step's
-- direction until the tile coord changes, release (a begun 16px step
-- always completes), wait for tile-alignment, and check the landing
-- against the plan.  A press that never moves us proves the model wrong
-- for that edge: blocklist it (persists across re-plans within this
-- navTo) and re-BFS.  Any deviation from the plan (event force-moves,
-- post-battle drift) also re-plans -- BFS is cheap, guessing isn't.
-- Encounters that fire mid-walk are cleared inline with the kill-bit
-- idiom UNLESS the formation matches opts.spare (the goal fight: hands
-- off, let opts.arrive see it).  Dialogs are advanced with EDGE-pressed
-- A; other control losses (events walking the party) get a neutral pad.
--   opts.arrive    extra terminator predicate (checked before everything)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     list of formation species words never to kill-bit
--   opts.noPathRetries  BFS-no-path retries, 45 idle frames apart, before
--                  erroring (default 20).  A no-path is often TRANSIENT:
--                  an NPC standing in a one-tile corridor blocks the
--                  object map exactly while its scene runs (the Figaro
--                  gate guard, measured), and erroring instantly turned
--                  every such scene into a route failure.
function M.navTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  M.navReset()
  local plan, idx = nil, 1
  local pend = nil          -- the in-flight/unverified step
  local aPhase = 0          -- edge-press phasing for A (4 on / 4 off)
  local battN, dlgN, lostN = 0, 0, 0   -- debounce counters (see below)
  local noPathN, pause = 0, 0          -- no-path retry state
  local function drop(why)  -- discard the plan, saying why (once, not per frame)
    if plan or pend then
      M.log(string.format("nav: %s at (%d,%d); plan dropped", why,
        M.fieldX(), M.fieldY()))
    end
    plan, pend = nil, nil
    NAV.plan, NAV.idx = 0, 0
  end
  return M.driveUntil(function()
    local done
    if arrive and arrive() then
      done = true
    else
      done = M.fieldX() == resolve(txIn) and M.fieldY() == resolve(tyIn)
         and M.hasControl() and M.tileAligned()
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - NAV.hb >= 600 then
        NAV.hb = M.frame
        M.log(string.format("nav f%d (%d,%d) %s", M.frame, M.fieldX(),
          M.fieldY(), M.navDump()))
      end
      -- classify the frame, DEBOUNCED: the battle/dialog signals live in
      -- RAM the field module also scribbles on, so require 3 consecutive
      -- frames before acting -- a real battle/dialog persists for hundreds.
      -- Acting on a 1-frame ghost would tap A on the open field.
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      lostN = M.hasControl() and 0 or lostN + 1
      -- 1. battle: clear it, but NEVER the goal formation
      if battN >= 3 then
        drop("battle")
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})                 -- goal fight: hands off, arrive() sees it
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 2. dialog waiting for a keypress: edge-tap A through it
      if dlgN >= 3 then
        drop("dialog")
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 3. any other control loss (event walking the party, fades, or a
      --    yet-undebounced battle/dialog): neutral pad and wait -- jamming
      --    directions or A only corrupts state
      if lostN > 0 or battN > 0 or dlgN > 0 then
        if lostN >= 3 then drop("control lost") end
        M.setPad({})
        return
      end
      -- 4. a step is in flight: hold until the tile coord changes
      if pend and pend.holding then
        if M.fieldX() ~= pend.x or M.fieldY() ~= pend.y then
          pend.holding = false         -- it'll glide to rest on its own
          M.setPad({})
          return
        end
        pend.held = pend.held + 1
        if pend.held > 30 then         -- never moved: the model was wrong
          NAV.blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
          NAV.nblocked = NAV.nblocked + 1
          M.log(string.format("nav: edge (%d,%d)->%s blocked in reality; re-plan",
            pend.x, pend.y, pend.dir))
          plan, pend = nil, nil
          M.setPad({})
          return
        end
        M.setPad({ [PRESS[pend.dir]] = true })
        return
      end
      -- 5. between steps: position samples are only valid at rest on a tile
      if not M.tileAligned() then M.setPad({}); return end
      if pause > 0 then pause = pause - 1; M.setPad({}); return end
      local x, y = M.fieldX(), M.fieldY()
      -- 6. verify the landing of the last step against the plan
      if pend then
        if x == pend.tx and y == pend.ty then
          pend = nil                   -- clean step, plan still on track
        else
          -- Landed off-plan.  A slide FURTHER along the same move (the
          -- engine can carry more than one tile) leaves the edge itself
          -- proven good; anything else condemns it.  Tested as "the
          -- displacement is a positive whole multiple of the move's
          -- delta", which holds for the diagonals too -- the old
          -- along/perp pair assumed a cardinal unit vector and would have
          -- condemned every correct diagonal step (delta (1,-1) scores
          -- along 2, perp -2).
          local d = DELTA[pend.dir]
          local dx, dy = x - pend.x, y - pend.y
          local k = math.max(math.abs(dx), math.abs(dy))
          if not (k > 0 and dx == d[1] * k and dy == d[2] * k) then
            NAV.blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
            NAV.nblocked = NAV.nblocked + 1
          end                          -- (same-direction slide: edge was fine)
          M.log(string.format("nav: step (%d,%d)->%s landed (%d,%d); re-plan",
            pend.x, pend.y, pend.dir, x, y))
          plan, pend = nil, nil
        end
      end
      -- 7. (re)plan when we have no plan or it ran out
      if plan and idx > #plan then plan = nil end
      if not plan then
        plan = M.bfsPath(resolve(txIn), resolve(tyIn), NAV.blocked)
        idx = 1
        if not plan then
          -- transient blockage patience: idle 45 frames and re-search.
          -- the blocklist is forgiven first (a condemned edge may be the
          -- only corridor once the blocker moves off it).
          noPathN = noPathN + 1
          if noPathN > (opts.noPathRetries or 20) then
            error(string.format(
              "navTo: no path (%d,%d)->(%d,%d) [%d edges blocklisted, %d retries]",
              x, y, resolve(txIn), resolve(tyIn), NAV.nblocked, noPathN - 1), 0)
          end
          if NAV.nblocked > 0 then NAV.blocked, NAV.nblocked = {}, 0 end
          M.log(string.format("nav: no path (%d,%d)->(%d,%d); waiting (retry %d)",
            x, y, resolve(txIn), resolve(tyIn), noPathN))
          pause = 45
          M.setPad({})
          return
        end
        noPathN = 0
        NAV.plan, NAV.idx = #plan, idx
        M.log(string.format("nav: planned %d steps from (%d,%d)", #plan, x, y))
        if #plan == 0 then M.setPad({}); return end  -- pred will notice
      end
      -- 8. launch the next step
      local dir = plan[idx]
      idx = idx + 1
      NAV.idx = idx
      local d = DELTA[dir]
      pend = { x = x, y = y, dir = dir, tx = x + d[1], ty = y + d[2],
               held = 0, holding = true }
      M.setPad({ [PRESS[dir]] = true })   -- a diagonal is pressed left/right
    end),
  }, "navTo")
end

-- Ride out a NON-INTERACTIVE story stretch: long automatic events with
-- intermittent dialogs and scripted battles (the esper-scene class).  The
-- hands-off companion to navTo -- no walking, no plan, just keep the story
-- unstuck until pred() is truthy (checked every frame; raises after
-- maxFrames).  Frames are classified with navTo's 3-frame debounce (the
-- battle/dialog signal bytes live in RAM the field module also scribbles
-- on; acting on a one-frame ghost would tap A on the open field):
--   battle  -> kill-bit everything present + edge-tap A through the text.
--              A formation matching opts.spare is a scripted set-piece:
--              never kill-bitted, and hands OFF for its first 300 frames,
--              THEN edge-tapped.  Both halves are load-bearing (measured,
--              esper zap): the set-piece ends via a monster-turn battle
--              event, and A pressed during the load queues player actions
--              that keep the turn engine busy forever -- but once the
--              event owns the stage (its opening battle dialog is up by
--              ~250 frames), it stalls without A to advance that text;
--   dialog  -> edge-tap A;
--   anything else -> neutral pad.  Control lost means an event is walking
--              the party; control held means the story is between beats.
--              Either way blind A is worse than patience: on the open
--              field it talks to NPCs and re-fires triggers.
function M.advanceStory(pred, maxFrames, opts)
  opts = opts or {}
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local aPhase = 0
  local battN, dlgN = 0, 0
  local hb = -600                      -- heartbeat: log immediately, then every 600
  return M.driveUntil(function()
    local done = pred()
    if done then M.setPad({}) end
    return done
  end, maxFrames or 20000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - hb >= 600 then
        hb = M.frame
        M.log(string.format(
          "story f%d map=%d (%d,%d) ctl=%s algn=%s dlg=%s batt=%s ev=%s",
          M.frame, M.mapId(), M.fieldX(), M.fieldY(),
          tostring(M.hasControl()), tostring(M.tileAligned()),
          tostring(M.dialogWaiting()), tostring(M.battleLoadStarted()),
          tostring(M.eventRunning())))
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        if battN == 3 then             -- rising edge: name the fight once
          local w = M.formationWords()
          M.log(string.format("story: battle up (%04X %04X %04X %04X %04X %04X)",
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad(battN > 300 and aPhase < 4 and { "a" } or {})
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if dlgN >= 3 then
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      M.setPad({})
    end),
  }, "advanceStory")
end

-- ------------------------------------------------------- world map nav --
-- The overworld is a separate engine (ff6/src/world/) with its own
-- position registers and a 1-bit passability rule; every field predicate
-- above is meaningless there.  The world module keeps DP=$0000
-- (world_start.asm has no phd/pld; its menu path reads $e0 plain), so
-- these are absolute zero-page addresses:
--   $E0/$E2  tile x/y -- the high bytes of the 16-bit position words at
--            $DF/$E1 (word = tile*256 + fraction; move.asm integrates
--            velocity into them at @1e56)
--   $DF/$E1  low bytes = sub-tile fraction; both zero <=> at rest.
--            Moving down/right the tile byte flips at step completion;
--            moving up/left it borrows through on the FIRST frame (both
--            measured, probe_world step traces) -- same direction skew
--            as the field, so position samples gate on worldAligned()
--   $E3/$E5  16-bit velocity; GetPlayerInput zeroes both every aligned
--            frame, then sets +-$10 for a held passable direction
--   $F6     facing 0=up 1=right 2=down 3=left
--   $E7     bit0 = world event script running (Figaro/Narshe triggers)
--   $19     fade/exit trigger (nonzero = leaving the world map)
--   $E8     bit0 = menu opening, bit3 = once-per-tile event/battle
--            latch, bit4 = reload-world (battle return, zone eater)
--
-- MOVEMENT IS LATCHED TO THE STEP: MovePlayer gates its whole body,
-- input read included, on both fractions being zero (move.asm:834-841),
-- so a begun step always glides to the next tile boundary -- a 4-frame
-- tap was measured carrying the party a full tile with velocity held at
-- $10 for all 16 frames (probe_world).  The executor therefore just
-- holds the planned direction whenever it is aligned; releases are
-- never needed mid-step.

-- On the world map iff (word $1F64 & $3FF) < 3: the top-level dispatch
-- masks #$03ff (field/reset.asm:66).  Raw compares are wrong there --
-- entrance/parent records ride flag bits in the high byte (measured
-- $2000 on the world after the Narshe exit; $0200|55 entering Figaro).
function M.worldMode() return (M.readWord(0x1f64) & 0x3FF) < 3 end
-- which world: 0=WoB 1=WoR 2=Serpent Trench (GetWorldTileProp masks the
-- LOW BYTE only, move.asm @21d7)
function M.worldId() return M.readWord(0x1f64) & 0xFF end

function M.worldX() return M.readByte(0x00e0) end
function M.worldY() return M.readByte(0x00e2) end
function M.worldAligned()
  return M.readByte(0x00df) == 0 and M.readByte(0x00e1) == 0
end

-- WorldTileProp = $EE9B14 (world/tile_prop.asm:4) -> rom file $2E9B14;
-- 256 words per world, index = worldId*512 + tiletype*2.  Cached per
-- world id on first use (512 rom reads once, not per BFS node).
local WORLD_PROP_FILE = 0x2E9B14
local worldPropCache, worldPropWorld = nil, nil
function M.worldTileProp(x, y)
  local w = M.worldId()
  if worldPropWorld ~= w then
    worldPropCache, worldPropWorld = {}, w
    for t = 0, 255 do
      worldPropCache[t] = M.readRomWord(WORLD_PROP_FILE + w * 512 + t * 2)
    end
  end
  local t = M.readByte(0x7F0000 + (y & 0xFF) * 256 + (x & 0xFF))
  return worldPropCache[t]
end

-- A step onto (x,y) is legal on foot iff bit4 ($0010) of the DESTINATION
-- tile's property word is clear -- the engine checks nothing else, no
-- exit bits / z-levels / object map (GetPlayerInput tests exactly this
-- per direction, move.asm @1ead..@1ff3; verified live: predictions from
-- this rule matched real movement at the Narshe spawn, probe_world).
-- Other bits, informational: $20 forest (legal, sets the hidden flag),
-- $40 random battles enabled here.
function M.worldPassable(x, y)
  return (M.worldTileProp(x, y) & 0x0010) == 0
end
function M.worldCanStep(x, y, dir)
  local d = DELTA[dir]
  return M.worldPassable(x + d[1], y + d[2])
end

local function worldEdgeKey(x, y, dir)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 4 + DIRIDX[dir]
end

-- BFS a path from the party's CURRENT world tile to (tx,ty).  The map
-- wraps at 256 in both axes.  `blockedEdges` (keys from worldEdgeKey)
-- prunes edges the executor has proven wrong, same contract as the
-- field bfsPath.  The node cap is 20000, not the field's 4096: world
-- legs run 60+ tiles (Narshe->Figaro BFS'd 63 steps, probe_world3) and
-- the search disc grows with them.
function M.worldBfs(tx, ty, blockedEdges)
  blockedEdges = blockedEdges or {}
  local sx, sy = M.worldX(), M.worldY()
  local function key(x, y) return (y & 0xFF) * 256 + (x & 0xFF) end
  local seen = { [key(sx, sy)] = true }
  local q, qi = { { sx, sy } }, 1
  local parent = {}
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]
    qi = qi + 1
    if x == tx and y == ty then
      local dirs, k = {}, key(x, y)
      while parent[k] do
        table.insert(dirs, 1, parent[k][2])
        k = parent[k][1]
      end
      return dirs
    end
    if qi > 20000 then return nil end
    for _, dir in ipairs(DIRS) do
      if not blockedEdges[worldEdgeKey(x, y, dir)] then
        local d = DELTA[dir]
        local nx, ny = (x + d[1]) & 0xFF, (y + d[2]) & 0xFF
        local k = key(nx, ny)
        if not seen[k] and M.worldPassable(nx, ny) then
          seen[k] = true
          parent[k] = { key(x, y), dir }
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  return nil
end

-- true when the world engine will accept a step this frame: on the world
-- map, no world event script ($E7 bit0 -- the Figaro/Narshe gate events
-- run through it), not fading out to a field map ($19), and none of
-- $E8's takeover bits: bit0 menu opening, bit5 battle pending/running
-- (set the INSTANT the encounter roll wins, move.asm's `ora #$20`
-- before BattleZoom -- long before battleLoadStarted's HP-table signal,
-- which is what let a battle transition masquerade as a dead edge in
-- gen_figaro run 1), bit4 reload-world (the post-battle fade/init).
-- battleLoadStarted is still checked for the battle interior itself.
-- ($E9 reads $04 during normal control -- measured -- so it is
-- deliberately not gated on.)
function M.worldHasControl()
  return M.worldMode()
     and M.readByte(0x0019) == 0
     and (M.readByte(0x00e7) & 0x01) == 0
     and (M.readByte(0x00e8) & 0x31) == 0
     and not M.battleLoadStarted()
end

-- Walk to world tile (tx,ty): the field navTo's verified-step loop on
-- the world engine.  Differences, each measured (probe_world/3):
--  * hold-through: input is read only at tile boundaries, so the walker
--    holds the planned direction continuously; a landing is verified
--    when the fractions return to zero, and only then is the next
--    direction chosen (re-plan on any mismatch, blocklist an edge whose
--    press provably never moved us)
--  * battles RELOAD THE WORLD: move.asm:916-921 snapshots the tile into
--    $1F60/$1F61 before Battle_ext and world_start.asm:465-482 reruns
--    ReloadMap after -- measured: kill-bit clear, then ~95 frames of
--    fade/init, position and facing back exactly, danger counter zeroed.
--    The walker clears non-spared battles inline (kill-bit + edge-A) and
--    stalls until the reload finishes (aligned + full brightness) before
--    planning again
--  * no dialog branch: world triggers run world event scripts, not the
--    field dialog engine; $BA/$D3 are stale field RAM here
--   opts.arrive    extra terminator (checked first, every frame)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     formation species words never to kill-bit
function M.worldNavTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local blocked, nblocked = {}, 0
  local plan, idx = nil, 1
  local pend = nil
  local aPhase = 0
  local battN = 0
  local hb = -600
  local function resolveT(v) return type(v) == "function" and v() or v end
  return M.driveUntil(function()
    local done
    if arrive and arrive() then
      done = true
    else
      done = M.worldX() == resolveT(txIn) and M.worldY() == resolveT(tyIn)
         and M.worldHasControl() and M.worldAligned()
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - hb >= 600 then
        hb = M.frame
        M.log(string.format("wnav f%d (%d,%d) plan=%s idx=%d blocked=%d",
          M.frame, M.worldX(), M.worldY(),
          plan and tostring(#plan) or "-", idx, nblocked))
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      -- 1. battle: clear it (never a spared formation), then let the
      --    world reload run out before touching the plan again
      if battN >= 3 then
        plan, pend = nil, nil
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 2. anything that is not plain walkable control: hands off (the
      --    post-battle reload, world event scripts, fades)
      if battN > 0 or not M.worldHasControl() then M.setPad({}); return end
      -- 3. mid-step: the latch owns it; keep the pad as-is
      if not M.worldAligned() then return end
      -- 4. the reload's own fade ends before brightness is back; a step
      --    launched into the fade works but leaves position samples one
      --    frame stale -- cheap to just wait it out (getState only runs
      --    at rest, not per frame)
      if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then
        M.setPad({})
        return
      end
      local x, y = M.worldX(), M.worldY()
      -- 5. verify the landing of the last step
      if pend then
        if x == pend.tx and y == pend.ty then
          pend = nil
        elseif x == pend.x and y == pend.y then
          -- still on the start tile.  1-2 aligned frames here are normal
          -- launch latency (the pad applies at the next input poll and
          -- velocity lands the frame after); a press that has not moved
          -- us in 10 is provably refused by the engine.
          pend.stall = pend.stall + 1
          if pend.stall > 10 then
            blocked[worldEdgeKey(pend.x, pend.y, pend.dir)] = true
            nblocked = nblocked + 1
            M.log(string.format("wnav: edge (%d,%d)->%s dead; re-plan",
              pend.x, pend.y, pend.dir))
            plan, pend = nil, nil
            M.setPad({})
            return
          end
          M.setPad({ [pend.dir] = true })
          return
        else
          M.log(string.format("wnav: step (%d,%d)->%s landed (%d,%d); re-plan",
            pend.x, pend.y, pend.dir, x, y))
          plan, pend = nil, nil
        end
      end
      -- 6. (re)plan.  If the blocklist made the target unreachable,
      -- forgive it once and re-search clean before giving up: world
      -- corridors run one tile wide (the desert pass measured so), and
      -- a single falsely-condemned edge there would otherwise be fatal
      -- while a genuinely dead edge just gets re-condemned next lap.
      if plan and idx > #plan then plan = nil end
      if not plan then
        plan = M.worldBfs(resolveT(txIn), resolveT(tyIn), blocked)
        if not plan and nblocked > 0 then
          M.log(string.format(
            "wnav: no path with %d blocked edges; amnesty + re-plan", nblocked))
          blocked, nblocked = {}, 0
          plan = M.worldBfs(resolveT(txIn), resolveT(tyIn), blocked)
        end
        idx = 1
        if not plan then
          error(string.format(
            "worldNavTo: no path (%d,%d)->(%d,%d) [%d edges blocklisted]",
            x, y, resolveT(txIn), resolveT(tyIn), nblocked), 0)
        end
        M.log(string.format("wnav: planned %d steps from (%d,%d)", #plan, x, y))
        if #plan == 0 then M.setPad({}); return end
      end
      -- 7. launch the next step and hold it
      local dir = plan[idx]
      idx = idx + 1
      local d = DELTA[dir]
      pend = { x = x, y = y, dir = dir,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, stall = 0 }
      M.setPad({ [dir] = true })
    end),
  }, "worldNavTo")
end

-- Drive a route that crosses engine modes: legs = { {mode="field", x, y,
-- opts}, {mode="world", x, y, opts}, ... }.  Between legs the engine is
-- expected to change modes on its own (an exit tile fires as the
-- previous leg lands, a world trigger loads a field map); each leg first
-- waits for its declared mode plus the matching settle gates -- control,
-- tile alignment, full screen brightness, then a 30-frame margin, the
-- post-map-load discipline every field fixture uses -- and only then
-- dispatches the mode's navigator.
function M.route(legs)
  local steps = {}
  for _, leg in ipairs(legs) do
    local isWorld = leg.mode == "world"
    steps[#steps + 1] = M.waitUntil(function()
      if isWorld then
        return M.worldHasControl() and M.worldAligned()
      end
      return not M.worldMode() and M.hasControl() and M.tileAligned()
    end, (leg.opts and leg.opts.modeWait) or 1200,
      "route: " .. leg.mode .. " mode + control", 5)
    steps[#steps + 1] = M.waitUntil(function()
      return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 900, "route: " .. leg.mode .. " fade-in", 10)
    steps[#steps + 1] = M.waitFrames(30)
    steps[#steps + 1] = isWorld and M.worldNavTo(leg.x, leg.y, leg.opts)
                        or M.navTo(leg.x, leg.y, leg.opts)
  end
  return M.seqStep(steps)
end
