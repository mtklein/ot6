-- ot6_field.lua -- the navigation half of the OT6 test library: the true
-- passability model ported from the engine, BFS pathfinding, and the
-- verified-step walkers (navTo / worldNavTo / advanceStory / route).
-- lib/compose.py inlines lib/ot6.lua and then this file into every
-- composed script, invoking this chunk with the core's module table as
-- its argument (the `local M = ...` below).

local M = ...
assert(type(M) == "table",
  "ot6_field.lua is inlined by lib/compose.py after lib/ot6.lua and " ..
  "receives the core module table; it cannot be loaded on its own")

-- navTo/worldNavTo/advanceStory reach here when a step draws a random
-- encounter without declaring how to handle it (opts.playBattles); it logs
-- once and the battle is then fought by blind A-taps.
M._killbitFired = false
function M.killbit(_slot)
  if not M._killbitFired then
    M.log("[killbit] a nav step drew a random encounter without opts.playBattles "
      .. "-- the kill-bit cheat is removed (#75), so it is fought by blind "
      .. 'A-taps; declare playBattles="flee"/"tactical" on this step')
    M._killbitFired = true
  end
end

-- How long playBattles="flee" holds L+R before it accepts that this
-- formation is not going to release the party and fights the battle out
-- instead; 1800 frames is 30 seconds.  Navigators accept opts.fleeCap to
-- shorten the cap per route.
M.FLEE_CAP = 1800

-- True while a battle is loaded and every party slot with a plausible max HP
-- ($3c1c, nonzero and under 1000) reads 0 current HP ($3bf4).  $1600 (the
-- field's own character table, checked by M.partyWiped) never reports a
-- death that occurs inside a battle: it is synced back from the battle
-- module's own table only at teardown, and a wipe tears down straight into
-- the Game Over.
function M.partyWipedInBattle()
  local sane, alive = 0, 0
  for e = 0, 3 do
    local mx = M.readWord(0x3c1c + e * 2)
    if mx > 0 and mx < 10000 then
      sane = sane + 1
      if M.readWord(0x3bf4 + e * 2) > 0 then alive = alive + 1 end
    end
  end
  if sane == 0 then return false end
  local want = 0
  for c = 0, 15 do
    if (M.readByte(0x1850 + c) & 0x07) ~= 0 then want = want + 1 end
  end
  return want >= 1 and want <= 4 and sane >= math.min(want, 4) and alive == 0
end

function M.partyWiped()
  if M.partyWipedInBattle() then return true end
  local any = false
  for _, c in ipairs(M.partyMembers()) do
    any = true
    if M.charHp(c) > 0 then return false end
  end
  return any
end

-- The canary returns true once a wipe has held for 300 frames.  It normally
-- also raises, since a wipe is the end of the run.  `soft` hands the verdict
-- back to the caller instead, for a retry ladder that reloads and retries on
-- a loss rather than treating it as a failed run.
local function wipeCanary(tag, soft)
  local n, said = 0, false
  return function()
    n = M.partyWiped() and n + 1 or 0
    if n < 300 then return false end
    if not soft then
      error(string.format("%s: THE PARTY IS WIPED -- every member of the " ..
        "party has read 0 hp for 300 consecutive frames.  This is a lost " ..
        "fight, not a stuck navigator; the frames after a wipe are the " ..
        "Game Over screen and whatever the drive presses into it.", tag), 0)
    end
    if not said then
      said = true
      M.log(string.format("%s: the party is wiped (0 hp for 300 frames); " ..
        "ending this ride so the caller's ladder can retry", tag))
    end
    return true
  end
end

-- The corridor flee policy, one driver per navigator call.  L+R is the
-- engine's own run mechanic; at the cap the battle is fought out by the
-- tactical driver instead.  Before the cap, $b1 bit 1 is the engine's own
-- can't-run flag (set for a pincer or a monster that blocks running); while
-- it is held, holding L+R is free damage with no roll behind it, so the
-- fight is handed to the tactical driver early instead.  The periodic log
-- line reports the engine's own run machinery:
--   $2f45  characters-are-running (set while L+R is held and unblocked)
--   $3a3b  run difficulty: 2 per live monster, 6 for a harder-to-run one
--   $3d70  per-character run counter, +rand(run factor)+1 per check; the
--          character escapes once it reaches the difficulty
--   $b1    bit 1 can't-run, bit 2 harder-to-run, bit 5 back attack/pincer
--   $2f4b  bit 0 the formation's own "no running with L+R"
--   $7EE9EF / $7E629A  battle time stopped / menus force-closed, either of
--          which suppresses $2f45 outright
local CANT_RUN = 0x02           -- $b1 bit 1
local REFUSAL_FRAMES = 60       -- consecutive frames of it before believing it

local function newFlee(opts, tactical)
  local cap = opts.fleeCap or M.FLEE_CAP
  local refusedN, said = 0, false
  -- battN is the caller's per-battle counter and it is 3 on the first frame
  -- that reaches here, so that value is the new-battle edge.
  return function(battN)
    if battN <= 3 then refusedN, said = 0, false end
    refusedN = ((M.readByte(0x00b1) & CANT_RUN) ~= 0) and refusedN + 1 or 0
    if battN % 600 == 3 then
      M.log(string.format(
        "flee: held %d of %d frames -- running=%d difficulty=%d " ..
        "counters=%d,%d,%d,%d $b1=%02X $2f4b=%02X timeStopped=%d menusShut=%d",
        battN, cap, M.readByte(0x2f45), M.readByte(0x3a3b),
        M.readByte(0x3d70), M.readByte(0x3d72), M.readByte(0x3d74),
        M.readByte(0x3d76), M.readByte(0x00b1), M.readByte(0x2f4b),
        M.readByte(0x7EE9EF), M.readByte(0x7E629A)))
    end
    if refusedN >= REFUSAL_FRAMES then
      if not said then
        said = true
        M.log(string.format("flee: this formation refuses the run ($b1 bit 1 " ..
          "held %d frames -- a pincer, or a monster nobody runs from) after " ..
          "%d frames; fighting it out instead of standing still for the cap",
          refusedN, battN))
      end
      tactical.frame()
      return
    end
    if battN <= cap then
      M.setPad({ l = true, r = true })
      return
    end
    if battN == cap + 1 then
      M.log(string.format("flee: no release after %d frames; " ..
        "fighting this formation out", cap))
    end
    tactical.frame()
  end
end


-- Field navigation, so routes are coordinate-aware instead of blind
-- timed holds (which desync on any map).  Movement is grid-oriented, one
-- tile per step: up=-Y down=+Y left=-X right=+X, plus the four diagonals
-- a left/right press produces on a diagonal-movement tile (every Figaro
-- staircase).  Passability is computed from RAM by porting both of the
-- engine's movement branches (the "true passability model" below), so
-- routes are found by BFS rather than discovered by playing.

-- ----------------------------------------------- true passability model --
-- Port of the engine's own step check (UpdatePlayerMovement), which takes
-- one of two branches.  Tile id at (x,y) is the BG1 tilemap byte at
-- $7f0000[y*256+x]; its properties are p1 = $7e7600[id] (the party's own
-- tile prop, kept in $b8) and p2 = $7e7700[id] (directional exits, $b9).
--
-- Cardinal branch: a step toward dir is allowed iff p2(cur) has the
-- direction's exit bit, p1(dst)&7 ~= 7 (not a counter/wall tile), the
-- bridge/z-level rules pass (party z-level is $b2's low bits, bit0 upper /
-- bit1 lower), and no object occupies dst ($7e2000[dst] bit7 set means
-- free).
--
-- Diagonal branch: on a tile with p1 bit6 or bit7 set (and not a bridge
-- tile the party is on the lower z-level of), a left/right press moves the
-- party diagonally instead of cardinally, one tile in each axis.  bit7
-- ("\" tiles) sends right to down-right and left to up-left; bit6 ("/"
-- tiles) sends right to up-right and left to down-left; bit7 wins if both
-- are set.  The destination tile must carry the same diagonal bit and must
-- not be exactly $f7; nothing else is checked (no exit bits, no z-level
-- rule, no object map).  Up/down presses never take this branch, nor does
-- a left/right press whose diagonal destination fails -- those fall
-- through to the cardinal path.  So on a diagonal tile the diagonal is
-- tried first, and stepAllowed says "no" to a cardinal left/right that the
-- engine would turn into a diagonal instead.
--
-- The four cardinal names double as press names; the four diagonal names
-- are moves the model plans and verifies but never presses directly.
-- DIRS/DIRIDX stay cardinal: the world map has no diagonal branch, so only
-- the field walks diagonals.
local DIRS   = { "up", "right", "down", "left" }
local DIRIDX = { up = 0, right = 1, down = 2, left = 3 }
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 },
                 down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
-- the field's move set: the four presses plus the four diagonals they can
-- turn into.  PRESS is the button a move is executed with.
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local MOVEIDX = { up = 0, right = 1, down = 2, left = 3,
                  upright = 4, downright = 5, downleft = 6, upleft = 7 }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }

-- BG1 tilemap byte for a tile.  The tilemap's row stride is 256
-- ($7f0000 + row*256 + col), but the coordinates wrap at the map's own
-- size masks $86/$87, not at 256; those masks are never zero, so no
-- guard is needed.
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

-- whether the party can make `move` from tile (x,y) at the live z-level.
-- `move` is any of MOVES: the four presses, or one of the four diagonals
-- (true only where the engine would turn that press into that diagonal).
function M.canStep(x, y, move)
  return stepAllowed(x, y, move, M.readByte(0x00b2) & 0x03)
end

-- the button that executes `move` (diagonals are pressed left/right)
function M.movePress(move) return PRESS[move] end

-- party z-level after stepping off (x,y): kept on a bridge/both tile,
-- otherwise taken from the tile being left (player.asm @4eef, :1196-1201).
-- The diagonal branch spells the same rule out longhand, keeping z if the
-- tile is a bridge ($04) or is both-z-levels ($03) and otherwise taking
-- $b8&3 (player.asm:432-439), so one function serves both branches.
local function zAfter(x, y, z)
  local c = M.readByte(0x7E7600 + M.maptile(x, y))
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end

local function edgeKey(x, y, move)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 8 + MOVEIDX[move]
end

-- BFS a path from the party's current tile to (tx,ty) over stepAllowed
-- edges, tracking the z-level a walker would carry along each candidate
-- path (nodes are (x,y,z) triples).  `blockedEdges` (optional, keys from
-- edgeKey) prunes edges the executor has proven wrong empirically.
-- `avoid` (optional) is a set of tile keys ((y<<8)|x) BFS must never route
-- through, for tiles that are walkable but must not be stepped on (a
-- one-way entrance row inside an otherwise ordinary region).  The target
-- tile itself is exempt, so a route can still aim at an avoided tile
-- deliberately.
-- Returns a list of MOVES names (four cardinals plus the four diagonals a
-- press turns into on a diagonal tile), or nil (unreachable / >4096 nodes).
function M.bfsPath(tx, ty, blockedEdges, avoid)
  blockedEdges = blockedEdges or {}
  avoid = avoid or {}
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
    if qi > 4096 then return nil end      -- radius cap: give up, do not hang
    local zn = zAfter(x, y, z)
    for _, dir in ipairs(MOVES) do
      if not blockedEdges[edgeKey(x, y, dir)] and stepAllowed(x, y, dir, z) then
        local d = DELTA[dir]
        local nx, ny = x + d[1], y + d[2]
        local k = nkey(nx, ny, zn)
        if avoid[((ny & 0xFF) << 8) | (nx & 0xFF)]
           and not (nx == tx and ny == ty) then
          k = nil                          -- routed through a forbidden tile
        end
        if k and not seen[k] then
          seen[k] = true
          parent[k] = { nkey(x, y, z), dir }
          q[#q + 1] = { nx, ny, zn }
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
function M.navDump()   -- debugging one-liner
  return string.format("bfs plan=%d idx=%d blocked=%d",
    NAV.plan or 0, NAV.idx or 0, NAV.nblocked or 0)
end

-- targets may be numbers or thunks (resolved each tick, so a route can
-- aim at a coord it only knows at runtime)
local function resolve(v) return type(v) == "function" and v() or v end

-- Walk to tile (tx,ty) on the current map: BFS a plan over the true
-- passability model, then execute it one verified step at a time.  Each
-- iteration (only when user-controlled and tile-aligned): press the step's
-- direction until the party is moving, release (a begun 16px step
-- always completes), wait for tile-alignment, and check the landing
-- against the plan.  A press that never moves us proves the model wrong
-- for that edge, so blocklist it (the entry persists across re-plans
-- within this navTo) and re-BFS.  Any deviation from the plan (event
-- force-moves, post-battle drift) also re-plans, because BFS is cheap.
-- Encounters that fire mid-walk are cleared inline by writing the
-- battle-clearing flag unless the formation matches opts.spare (the goal
-- fight, which is left alone so opts.arrive can see it).  Dialogs are
-- advanced with edge-pressed A; other control losses (events walking the
-- party) get a neutral pad.
--   opts.avoid     list of {x,y} the plan must never route through (a
--                  one-way entrance inside a walkable region); the goal
--                  tile itself is exempt
--   opts.arrive    extra terminator predicate (checked before everything)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     list of formation species words never to clear by a
--                  flag write
--   opts.playBattles  clear mid-route battles by real play instead of the
--                  flag write.  Three spellings, with the same contract
--                  worldNavTo carries:
--                  true    auto-fight by edge-tapped A (opens the command
--                          list, confirms its first entry, default target);
--                  "tactical"  read the live command table and use Edgar's
--                          Tools, Sabin's Blitz, and Fight for everyone else,
--                          with the driver's own item medic line.  Tool is
--                          opts.tool (default H.AUTOCROSSBOW); heals at
--                          opts.healPercent (default 55);
--                  "flee"  hold L+R, the engine's own run mechanic.  A
--                          formation that has not released the party after
--                          M.FLEE_CAP consecutive battle frames is fought
--                          out by edge-tapped A instead of hanging the step.
--   opts.calmFrames  consecutive settled frames on the goal tile the
--                  terminator requires (default 16)
--   opts.noPathRetries  BFS-no-path retries, 45 idle frames apart, before
--                  erroring (default 20)
--
-- A step is held only until the party starts moving (the first frame
-- tileAligned() goes false), then released, rather than until the tile
-- coordinate changes -- the coordinate flips only on the final frame of a
-- rightward/downward step, one input poll too late, which would overshoot
-- by a tile.  The terminator requires calmFrames consecutive aligned frames
-- on the goal tile rather than hasControl(), since some goal tiles retrigger
-- control loss immediately on arrival (a step-on trigger, a scene); without
-- control the run required is three times calmFrames.  Battle and dialog
-- frames are excluded from the run.
-- Human players FIGHT.  The route beelined by fleeing every encounter
-- (playBattles="flee"), which pays ZERO xp and left the party badly
-- under-leveled -- the level gap the chart documents, and the root cause
-- of the fights that "needed" in-combat healing to scrape through.  With
-- this true (the default), a "flee" navigation FIGHTS the encounter
-- tactically instead -- leveling the party the way a person playing would
-- -- while the tactical driver the flee mode already builds wins it.  A
-- genuinely unwinnable encounter (a scripted set-piece that must be run)
-- opts back out with playBattles="mustflee".
M.FIGHT_NOT_FLEE = true
local function wantsFlee(mode)
  if mode == "mustflee" then return true end
  return mode == "flee" and not M.FIGHT_NOT_FLEE
end

function M.navTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  -- The walk budget pays for WALKING.  A mid-walk battle's frames are the
  -- battle's own cost: measured (thamlab deadboard probe, the P5 Fire Rod
  -- spur), one 20000-frame walk drew three full Balloon fights -- ~18900
  -- battle frames -- and timed out ~110 frames AFTER the killing blow of
  -- a fight it had already won.  Battle frames and between-battles care
  -- frames no longer charge the walk budget; the driveUntil cap keeps a
  -- hard backstop (walk budget + 80000, everything included) so a
  -- genuinely hung battle still ends the ride.
  local walked = 0
  local arrive = opts.arrive
  local calmWant = opts.calmFrames or 16
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  -- opts.avoid = { {x,y}, ... }: walkable tiles the plan must never route
  -- through (one-way entrances mid-region); see M.bfsPath
  local avoidSet = {}
  for _, t in ipairs(opts.avoid or {}) do
    avoidSet[((t[2] & 0xFF) << 8) | (t[1] & 0xFF)] = true
  end
  M.navReset()
  local plan, idx = nil, 1
  local pend = nil          -- the in-flight/unverified step
  local aPhase = 0          -- edge-press phasing for A (4 on / 4 off)
  local calm = 0            -- consecutive settled frames on the goal tile
  local battN, dlgN, lostN = 0, 0, 0   -- debounce counters (see below)
  local noPathN, pause = 0, 0          -- no-path retry state
  -- built for "tactical" and for "flee": the flee branch falls back to it
  -- once M.FLEE_CAP frames pass without the formation releasing the party
  --
  -- opts.wipeEndsRide: a party wipe ends this ride instead of raising, for a
  -- caller whose retry ladder reloads and retries.  Off by default.
  local wipeSeen = false
  local wipeCheck = wipeCanary("navTo", opts.wipeEndsRide)
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee" or opts.playBattles == "mustflee")
      and M.newFightDriver("navTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool, blitz = opts.blitz }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  -- the heal-after-every-battle directive: once a mid-walk battle
  -- resolves, run a between-battles care stop (M.newCareDriver, soft)
  -- before walking on, so the next fight starts whole.  opts.care=false
  -- opts out; a live event timer opts the scene out automatically.
  local careD, sawBattle = nil, false
  local function drop(why)  -- discard the plan, logging why once, not per frame
    if plan or pend then
      M.log(string.format("nav: %s at (%d,%d); plan dropped", why,
        M.fieldX(), M.fieldY()))
    end
    plan, pend = nil, nil
    NAV.plan, NAV.idx = 0, 0
  end
  return M.driveUntil(function()
    -- never complete mid-care: arrive() can be map-based and go true while
    -- the care menu is still open (see advanceStory's identical guard)
    if careD then return false end
    local done
    if wipeSeen then
      done = true
    elseif arrive and arrive() then
      done = true
    else
      -- stopped on the goal tile, not passing through it.
      calm = (M.fieldX() == resolve(txIn) and M.fieldY() == resolve(tyIn)
          and M.tileAligned() and not M.battleLoadStarted()
          and not M.dialogWaiting()) and calm + 1 or 0
      done = calm >= calmWant and (M.hasControl() or calm >= calmWant * 3)
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames + 80000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if not M.battleLoadStarted() and careD == nil then
        walked = walked + 1
        if walked > maxFrames then
          error(string.format("navTo: timeout after %d walk frames " ..
            "(battle and care frames excluded)%s", maxFrames,
            M.timeoutContext()), 0)
        end
      end
      if M.frame - NAV.hb >= 600 then
        NAV.hb = M.frame
        M.log(string.format("nav f%d (%d,%d) %s", M.frame, M.fieldX(),
          M.fieldY(), M.navDump()))
      end
      -- classify the frame, debounced: the battle/dialog signals live in
      -- RAM the field module also writes to, so require 3 consecutive
      -- frames before acting; a real battle or dialog persists for hundreds.
      -- Acting on a 1-frame ghost would tap A on the open field.
      if wipeCheck() then wipeSeen = true; M.setPad({}); return end
      -- a between-battles care stop in progress owns the pad
      if careD then
        if careD.done() then careD = nil; drop("cared")
        else careD.frame(); return end
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      lostN = M.hasControl() and 0 or lostN + 1
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it, but never the goal formation
      if battN >= 3 then
        sawBattle = true
        drop("battle")
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})                 -- goal fight: left alone for arrive()
          return
        end
        if wantsFlee(opts.playBattles) then
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.killbit(slot)
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
      --    yet-undebounced battle/dialog): neutral pad and wait, because
      --    jamming directions or A only corrupts state
      if lostN > 0 or battN > 0 or dlgN > 0 then
        if lostN >= 3 then drop("control lost") end
        M.setPad({})
        return
      end
      -- 3b. a battle just resolved and the field is back: recover OUTSIDE
      --     combat before walking on (the heal-after-every-battle
      --     directive).  Costs nothing when nobody needs care.
      if sawBattle then
        sawBattle = false
        if opts.care ~= false and not M.eventTimerLive() then
          careD = M.newCareDriver({
            threshold = opts.careThreshold or 0.65, reserve = opts.reserve,
            tag = "care after battle (navTo)" })
          careD.frame()
          if not careD.done() then return end
          careD = nil
        end
      end
      -- 4. a step is in flight: hold only until the party is moving (the
      --    first frame it is off tile-alignment), then release -- the tile
      --    coord changing is one input poll too late for right/down.
      if pend and pend.holding then
        -- the coord test is kept as a backstop rather than the primary rule:
        -- it is the only signal left if a map ever moved a full 16px in one
        -- frame (no unaligned frame to see), and it can only fire later than
        -- the alignment test, never earlier.
        if not M.tileAligned()
           or M.fieldX() ~= pend.x or M.fieldY() ~= pend.y then
          pend.holding = false         -- committed; it'll glide to rest
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
          -- Landed off-plan.  A slide further along the same move (the
          -- engine can carry more than one tile) leaves the edge itself
          -- proven good; anything else condemns it.  The test is that the
          -- displacement is a positive whole multiple of the move's
          -- delta, which holds for the diagonals too.  The old
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
        plan = M.bfsPath(resolve(txIn), resolve(tyIn), NAV.blocked, avoidSet)
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
        -- An empty plan means we are already standing on the goal and are
        -- only waiting out the terminator's calm frames, so idle without
        -- logging: logging (and re-BFSing) every frame buried the real
        -- plan lines under many "planned 0 steps" lines once the
        -- terminator started requiring the party to be stopped.
        if #plan == 0 then plan = nil; pause = 8; M.setPad({}); return end
        M.log(string.format("nav: planned %d steps from (%d,%d)", #plan, x, y))
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

-- Ride out a non-interactive story stretch: long automatic events with
-- intermittent dialogs and scripted battles (the esper-scene class).  It is
-- the companion to navTo for stretches with no walking and no plan; it
-- keeps the story unstuck until pred() is truthy (checked every frame;
-- raises after maxFrames).
--   battle  -> flag-clear everything present + edge-tap A through the text
--              (with opts.playBattles, no flag write: the same edge-tapped A
--              auto-fights the encounter for real).  A formation matching
--              opts.spare is a scripted set-piece: never cleared by a flag
--              write, left alone for its first 300 frames, edge-tapped
--              after that;
--   dialog  -> edge-tap A;
--   anything else -> neutral pad.
function M.advanceStory(pred, maxFrames, opts)
  opts = opts or {}
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local aPhase = 0
  local battN, dlgN = 0, 0
  -- opts.wipeEndsRide: a wipe ends this ride instead of raising, for a
  -- caller that reloads and tries again.
  local wipeSeen = false
  local wipeCheck = wipeCanary("advanceStory", opts.wipeEndsRide)
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee" or opts.playBattles == "mustflee")
      and M.newFightDriver("advanceStory",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool, blitz = opts.blitz }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  -- heal-after-every-battle: see navTo's care block; same contract here
  local careD, sawBattle = nil, false
  local hb = -600                      -- heartbeat: log immediately, then every 600
  return M.driveUntil(function()
    -- never complete mid-care: pred() can be map/switch-based and go true
    -- while the care menu is still open, which would end the step with
    -- the menu up and the next step pressing into it
    local done = careD == nil and (wipeSeen or pred())
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
      if wipeCheck() then wipeSeen = true; M.setPad({}); return end
      if careD then
        if careD.done() then careD = nil else careD.frame(); return end
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
      if battN >= 3 then
        sawBattle = true
        if battN == 3 then             -- rising edge: name the fight once
          local w = M.formationWords()
          M.log(string.format("story: battle up (%04X %04X %04X %04X %04X %04X)",
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad(battN > 300 and aPhase < 4 and { "a" } or {})
          return
        end
        -- same contract as navTo's, cap included.
        if wantsFlee(opts.playBattles) then
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.killbit(slot)
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
      -- a battle resolved earlier in the ride and control is back:
      -- recover OUTSIDE combat before riding on.  A ride whose scene
      -- never returns control simply leaves the latch armed; the caller's
      -- own care stop then owns it.
      if sawBattle and M.hasControl() and M.tileAligned() then
        sawBattle = false
        if opts.care ~= false and not M.eventTimerLive() then
          careD = M.newCareDriver({
            threshold = opts.careThreshold or 0.65, reserve = opts.reserve,
            tag = "care after battle (advanceStory)" })
          careD.frame()
          if not careD.done() then return end
          careD = nil
        end
      end
      M.setPad({})
    end),
  }, "advanceStory")
end

-- ------------------------------------------------------- world map nav --
-- The overworld is a separate engine (ff6/src/world/) with its own
-- position registers and a 1-bit passability rule; every field predicate
-- above is meaningless there.  The world module keeps DP=$0000, so these
-- are absolute zero-page addresses:
--   $E0/$E2  tile x/y, the high bytes of the 16-bit position words at
--            $DF/$E1 (word = tile*256 + fraction)
--   $DF/$E1  low bytes = sub-tile fraction; both zero <=> at rest.
--            Moving down/right the tile byte flips at step completion;
--            moving up/left it borrows through on the first frame, so
--            position samples gate on worldAligned()
--   $E3/$E5  16-bit velocity; GetPlayerInput zeroes both every aligned
--            frame, then sets +-$10 for a held passable direction
--   $F6     facing 0=up 1=right 2=down 3=left
--   $E7     bit0 = world event script running (Figaro/Narshe triggers)
--   $19     fade/exit trigger (nonzero = leaving the world map)
--   $E8     bit0 = menu opening, bit3 = once-per-tile event/battle
--            latch, bit4 = reload-world (battle return, zone eater)
--
-- Movement is latched to the step: input is gated on both fractions being
-- zero, so a begun step always continues to the next tile boundary; the
-- executor holds the planned direction whenever it is aligned, and
-- releases are never needed mid-step.

-- On the world map iff (word $1F64 & $3FF) < 3.  Raw compares are wrong
-- there, because entrance/parent records carry flag bits in the high byte.
function M.worldMode() return (M.readWord(0x1f64) & 0x3FF) < 3 end
-- which world: 0=WoB 1=WoR 2=Serpent Trench
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

-- A step onto (x,y) is legal on foot iff bit4 ($0010) of the destination
-- tile's property word is clear.  The engine checks nothing else: no
-- exit bits, no z-levels, no object map.  Other bits, informational: $20
-- forest (legal, sets the hidden flag), $40 random battles enabled here.
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

-- BFS a path from the party's current world tile to (tx,ty).  The map
-- wraps at 256 in both axes.  `blockedEdges` (keys from worldEdgeKey)
-- prunes edges the executor has proven wrong, same contract as the
-- field bfsPath.  The node cap is 60000 rather than the field's 4096,
-- since world segments can run over 100 tiles.
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
    if qi > 60000 then return nil end
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
-- map, no world event script ($E7 bit0, which the Figaro/Narshe gate
-- events run through), not fading out to a field map ($19), and none of
-- $E8's takeover bits: bit0 menu opening, bit5 battle pending/running (set
-- as soon as the encounter roll wins, well before battleLoadStarted's
-- HP-table signal), bit4 reload-world (the post-battle fade/init).
-- battleLoadStarted is still checked for the battle interior itself.
function M.worldHasControl()
  return M.worldMode()
     and M.readByte(0x0019) == 0
     and (M.readByte(0x00e7) & 0x01) == 0
     and (M.readByte(0x00e8) & 0x31) == 0
     and not M.battleLoadStarted()
end

-- Walk to world tile (tx,ty): the field navTo's verified-step loop on
-- the world engine.  Differences:
--  * hold-through: input is read only at tile boundaries, so the walker
--    holds the planned direction continuously; a landing is verified
--    when the fractions return to zero, and only then is the next
--    direction chosen (re-plan on any mismatch, blocklist an edge whose
--    press provably never moved us)
--  * battles reload the world: the walker clears non-spared battles
--    inline (flag write + edge-A) and stalls until the reload finishes
--    (aligned + full brightness) before planning again
--  * no dialog branch: world triggers run world event scripts, not the
--    field dialog engine
--   opts.arrive    extra terminator (checked first, every frame)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     formation species words never to clear by a flag write
--   opts.playBattles  end mid-walk battles by real play instead of the
--                  flag write, the same opt-in contract navTo/advanceStory
--                  carry.
--                  true    = auto-fight by edge-tapped A;
--                  "tactical" = read the live command table and use Edgar's
--                            Tools (opts.tool, default H.AUTOCROSSBOW),
--                            Sabin's Blitz, and Fight for everyone else;
--                  "flee"  = hold L+R, the engine's own run mechanic; times
--                            out on unrunnable formations.  In both cases
--                            the post-battle world reload restores the
--                            pre-battle tile with the danger counter
--                            zeroed, and the walker re-plans from it.
function M.worldNavTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  -- opts.fleeSpecies: a set of formation species words (M.formationHas's
  -- own convention) to FLEE specifically while otherwise fighting
  -- tactically.  Reuses newFlee's own cap + can't-run/pincer-refusal
  -- fallback, built below whenever `tactical` is.
  local fleeSet = {}
  for _, w in ipairs(opts.fleeSpecies or {}) do fleeSet[w] = true end
  local blocked, nblocked = {}, 0
  local plan, idx = nil, 1
  local pend = nil
  local aPhase = 0
  local battN = 0
  -- opts.wipeEndsRide: a party wipe ends this ride instead of raising, for
  -- a caller that reloads and retries.  Off by default.
  local wipeSeen = false
  local wipeCheck = wipeCanary("worldNavTo", opts.wipeEndsRide)
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee" or opts.playBattles == "mustflee")
      and M.newFightDriver("worldNavTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool, blitz = opts.blitz }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  -- heal-after-every-battle: see navTo's care block; same contract here,
  -- run once the post-battle world reload has fully settled
  local careD, sawBattle = nil, false
  -- walk-budget semantics shared with navTo: battle and care frames do
  -- not charge maxFrames (see navTo's measured note); the driveUntil cap
  -- is the hard backstop.
  local walked = 0
  local hb = -600
  local function resolveT(v) return type(v) == "function" and v() or v end
  return M.driveUntil(function()
    if careD then return false end
    local done
    if wipeSeen then
      done = true
    elseif arrive and arrive() then
      done = true
    else
      done = M.worldX() == resolveT(txIn) and M.worldY() == resolveT(tyIn)
         and M.worldHasControl() and M.worldAligned()
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames + 80000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if not M.battleLoadStarted() and careD == nil then
        walked = walked + 1
        if walked > maxFrames then
          error(string.format("worldNavTo: timeout after %d walk frames " ..
            "(battle and care frames excluded)%s", maxFrames,
            M.timeoutContext()), 0)
        end
      end
      if M.frame - hb >= 600 then
        hb = M.frame
        M.log(string.format("wnav f%d (%d,%d) plan=%s idx=%d blocked=%d",
          M.frame, M.worldX(), M.worldY(),
          plan and tostring(#plan) or "-", idx, nblocked))
      end
      if wipeCheck() then wipeSeen = true; M.setPad({}); return end
      -- a between-battles care stop in progress owns the pad
      if careD then
        if careD.done() then careD = nil; plan, pend = nil, nil
        else careD.frame(); return end
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it (never a spared formation), then let the
      --    world reload run out before touching the plan again
      if battN >= 3 then
        sawBattle = true
        plan, pend = nil, nil
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})
          return
        end
        if wantsFlee(opts.playBattles)
           or (flee and next(fleeSet) and M.formationHas(fleeSet)) then
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.killbit(slot)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 2. anything that is not plain walkable control: no input (the
      --    post-battle reload, world event scripts, fades)
      if battN > 0 or not M.worldHasControl() then M.setPad({}); return end
      -- 3. mid-step: the engine's latch drives it; keep the pad as-is
      if not M.worldAligned() then return end
      -- 4. the reload's own fade ends before brightness is back; a step
      --    launched into the fade works but leaves position samples one
      --    frame stale, so wait it out (getState only runs
      --    at rest, not per frame)
      if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then
        M.setPad({})
        return
      end
      -- 4b. a battle just resolved and the reload has settled: recover
      --     OUTSIDE combat before walking on (heal-after-every-battle).
      --     The world menu is safe here -- careClose's world-mode
      --     debounce owns the teardown.
      if sawBattle then
        sawBattle = false
        if opts.care ~= false and not M.eventTimerLive() then
          careD = M.newCareDriver({
            threshold = opts.careThreshold or 0.65, reserve = opts.reserve,
            tag = "care after battle (worldNavTo)" })
          careD.frame()
          if not careD.done() then return end
          careD = nil
        end
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
      -- forgive it once and re-search before giving up: some world
      -- corridors run one tile wide, so a single falsely-condemned edge
      -- there would otherwise be unrecoverable, while an edge that is
      -- actually dead is re-condemned on the next pass.
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

-- --------------------------------------- timed-tilemap (phase) rooms --
-- Some rooms are two complementary tilemaps swapped on an event timer,
-- and the reachable set inside either phase alone is a dead end; the
-- crossing exists only across the swaps.  navTo cannot drive such a room
-- (every edge is legitimately dead half the time and would be
-- condemned), so this walker plans over the union graph instead.
--
-- Each swap callback rewrites the tilemap before flipping the phase
-- switches, so there is a brief window where the next phase's floor is
-- in place while its hurt triggers still read the old phase; a step taken
-- during the window lands mid-step when the switches flip and so never
-- fires the trigger.  Hurt tiles are ordinary event triggers that
-- re-enter every frame, so every press there is unconditional.  Random
-- encounters preserve the phase switches and timers across the battle
-- round-trip but rebase the dead cycle's tilemap, so the walker
-- re-snapshots and re-plans afterward.
--
-- M.phaseWalk(tx, ty, spec) returns a step that walks the party to
-- (tx,ty) across the swaps.  spec (all fields required unless noted):
--   switches   = { a = 0x01F5, b = 0x01F6 }  -- the two phase switches;
--                edges on `b` are the clock (on 385 only the four timer
--                callbacks touch $01F6, so its edges are the swap
--                instants; pick the switch with that property)
--   period     = 158            -- frames between swaps
--   region     = { w = 17, h = 16 }
--   hurt       = { a = {{x,y},...},   -- tiles that hurt while switch a
--                  b = {{x,y},...},   -- ... while switch b is on
--                  always = {{x,y},...} }
--   avoid      = { {x,y}, ... } -- optional; tiles BFS must never use
--                (e.g. the other cycle's arming triggers, which would
--                re-arm it and freeze the half being crossed)
--   windowHold = 132            -- optional; fsf to start the window hold
--   segMargin  = 24             -- optional; frames of slack a k-step
--                               -- in-phase lane needs beyond 16k
--   maxFrames, what             -- optional; driveUntil plumbing
function M.phaseWalk(tx, ty, spec)
  local swA, swB = spec.switches.a, spec.switches.b
  local PERIOD = spec.period
  local WINDOW_HOLD = spec.windowHold or (PERIOD - 26)
  local SEG_MARGIN = spec.segMargin or 24
  local W, Hh = spec.region.w, spec.region.h
  local PDIRS = { "up", "right", "down", "left" }
  local PDX = { 0, 1, 0, -1 }
  local PDY = { -1, 0, 1, 0 }

  local function swv(id)
    return (M.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
  end
  local function tkey(x, y) return y * 256 + x end
  local hurt = { a = {}, b = {} }
  local hurtAlways = {}
  for _, t in ipairs(spec.hurt.a or {}) do hurt.a[tkey(t[1], t[2])] = true end
  for _, t in ipairs(spec.hurt.b or {}) do hurt.b[tkey(t[1], t[2])] = true end
  for _, t in ipairs(spec.hurt.always or {}) do
    hurtAlways[tkey(t[1], t[2])] = true
  end
  local avoid = {}
  for _, t in ipairs(spec.avoid or {}) do avoid[tkey(t[1], t[2])] = true end

  local function prop(x, y) return M.readByte(0x7E7600 + M.maptile(x, y)) end
  local function hpsum()
    return M.readWord(0x1609) + M.readWord(0x1609 + 37)
         + M.readWord(0x1609 + 74) + M.readWord(0x1609 + 111)
  end

  local lastB, lastFlip = nil, nil
  local grids = {}                -- ["a"|"b"] = { step = {}, walk = {} }
  local plan, idx = nil, 1
  local begunSeg = -1
  local hp0, obsStart = nil, nil
  local hb = -300
  local battN, aPhase = 0, 0

  -- Encounters are fled with the shared corridor policy (the same driver
  -- navTo's playBattles="flee" runs), and a wipe is named a wipe.
  local wipeCheck = wipeCanary("phaseWalk")
  local tactical = M.newFightDriver("phaseWalk",
    { tactical = true, boost = true, items = true,
      healPercent = spec.healPercent or 55 })
  local flee = newFlee(spec, tactical)

  local function curPhase() return swv(swB) == 1 and "b" or "a" end
  local function otherOf(p) return p == "a" and "b" or "a" end
  local function fsf() return lastFlip and (M.frame - lastFlip) or -1 end
  local function skey(x, y, di) return tkey(x, y) * 4 + di end

  local function clockTick()
    local cur = swv(swB)
    if lastB ~= nil and cur ~= lastB then lastFlip = M.frame end
    lastB = cur
  end

  local function capture(p)
    local g = { step = {}, walk = {} }
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if (prop(x, y) & 7) ~= 7 then g.walk[tkey(x, y)] = true end
        for di = 1, 4 do
          if M.canStep(x, y, PDIRS[di]) then g.step[skey(x, y, di)] = true end
        end
      end
    end
    grids[p] = g
    M.log(string.format("[phaseWalk] captured phase-%s grid at f%d (fsf=%d)",
      p, M.frame, fsf()))
  end

  local function buildPlan(sx, sy, sp)
    local function nk(x, y, p)
      return (p == "b" and 0x10000 or 0) + tkey(x, y)
    end
    local start = nk(sx, sy, sp)
    local seen = { [start] = true }
    local parent = {}
    local q, qi = { { sx, sy, sp } }, 1
    local goal = nil
    while qi <= #q do
      local x, y, p = q[qi][1], q[qi][2], q[qi][3]
      qi = qi + 1
      if x == tx and y == ty then goal = nk(x, y, p); break end
      local o = otherOf(p)
      local function push(nx, ny, np, item)
        if nx < 0 or nx >= W or ny < 0 or ny >= Hh then return end
        if avoid[tkey(nx, ny)] then return end
        local k = nk(nx, ny, np)
        if seen[k] then return end
        seen[k] = true
        item.tox, item.toy = nx, ny
        parent[k] = { nk(x, y, p), item }
        q[#q + 1] = { nx, ny, np }
      end
      for di = 1, 4 do                                      -- move edges
        if grids[p].step[skey(x, y, di)] then
          push(x + PDX[di], y + PDY[di], p,
            { kind = "move", dir = PDIRS[di], phase = p })
        end
      end
      local k = tkey(x, y)                                  -- flip edge
      if grids[o].walk[k] and not hurt[o][k] and not hurtAlways[k] then
        push(x, y, o, { kind = "flip", phase = o })
      end
      for di = 1, 4 do                                      -- window edges
        if grids[o].step[skey(x, y, di)] then
          push(x + PDX[di], y + PDY[di], o,
            { kind = "window", dir = PDIRS[di], phase = o })
        end
      end
    end
    if not goal then
      error(string.format("phaseWalk: no union-graph path (%d,%d,%s) -> "
        .. "(%d,%d)", sx, sy, sp, tx, ty), 0)
    end
    local items, k2 = {}, goal
    while parent[k2] do
      table.insert(items, 1, parent[k2][2])
      k2 = parent[k2][1]
    end
    local i, seg = 1, 0
    while i <= #items do
      if items[i].kind == "move" then
        seg = seg + 1
        local j = i
        while j <= #items and items[j].kind == "move"
              and items[j].phase == items[i].phase do j = j + 1 end
        for m = i, j - 1 do
          items[m].seg = seg
          items[m].segHead = (m == i)
          items[m].segLen = j - i
        end
        i = j
      else
        i = i + 1
      end
    end
    local desc = {}
    for _, it in ipairs(items) do
      desc[#desc + 1] = string.format("%s%s->(%d,%d)%s", it.kind,
        it.dir and ("[" .. it.dir .. "]") or "", it.tox, it.toy, it.phase)
    end
    M.log(string.format("[phaseWalk] plan (%d items): %s", #items,
      table.concat(desc, " ")))
    plan = items
    idx = 1
  end

  return M.driveUntil(function()
    return not M.battleLoadStarted()
       and M.fieldX() == tx and M.fieldY() == ty and M.tileAligned()
  end, spec.maxFrames or 30000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      wipeCheck()
      battN = M.battleLoadStarted() and battN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
      if battN >= 3 then
        if plan or lastFlip then
          M.log(string.format("[phaseWalk] encounter at f%d -- flee, "
            .. "then re-observe", M.frame))
        end
        plan, grids, lastFlip, lastB = nil, {}, nil, nil
        begunSeg, hp0, obsStart = -1, nil, nil
        flee(battN)
        return
      end
      if battN > 0 then M.setPad({}); return end
      clockTick()
      if hp0 == nil then hp0 = hpsum(); obsStart = M.frame end
      if hpsum() < hp0 then
        error(string.format("phaseWalk: HURT fired at (%d,%d) fsf=%d -- "
          .. "hp %d -> %d", M.fieldX(), M.fieldY(), fsf(), hp0, hpsum()), 0)
      end
      if not plan then
        -- parked on a hurt-list tile (a battle return can leave the party
        -- there): step off before observing, because a swap would hurt
        local hk = tkey(M.fieldX(), M.fieldY())
        if hurt.a[hk] or hurt.b[hk] or hurtAlways[hk] then
          local x, y = M.fieldX(), M.fieldY()
          for pass = 1, 2 do
            for di = 1, 4 do
              local nk2 = tkey(x + PDX[di], y + PDY[di])
              local safe = not hurtAlways[nk2] and not avoid[nk2]
                and (pass == 2 or (not hurt.a[nk2] and not hurt.b[nk2]))
              if safe and M.canStep(x, y, PDIRS[di]) then
                M.setPad({ [PDIRS[di]] = true })
                return
              end
            end
          end
        end
        M.setPad({})
        if lastFlip and fsf() >= 25 and fsf() <= PERIOD - 38 then
          local p = curPhase()
          if not grids[p] then capture(p) end
          if grids.a and grids.b then
            buildPlan(M.fieldX(), M.fieldY(), p)
          end
        elseif not lastFlip and M.frame - obsStart > 3 * PERIOD + 30 then
          error("phaseWalk: no clock edge observed -- is a cycle armed?", 0)
        end
        return
      end
      while plan[idx] and plan[idx].kind ~= "flip"
            and M.fieldX() == plan[idx].tox
            and M.fieldY() == plan[idx].toy do
        idx = idx + 1
      end
      local item = plan[idx]
      if not item then M.setPad({}); return end
      if M.frame - hb >= 300 then
        hb = M.frame
        M.log(string.format("[phaseWalk] f%d (%d,%d) p%s fsf=%d item %d/%d "
          .. "%s%s", M.frame, M.fieldX(), M.fieldY(), curPhase(), fsf(),
          idx, #plan, item.kind, item.dir and ("[" .. item.dir .. "]") or ""))
      end
      if item.kind == "flip" then
        if curPhase() == item.phase then idx = idx + 1 end
        M.setPad({})
        return
      end
      if item.kind == "window" then
        if fsf() >= WINDOW_HOLD
           or M.canStep(M.fieldX(), M.fieldY(), item.dir) then
          M.setPad({ [item.dir] = true })
        else
          M.setPad({})
        end
        return
      end
      if item.segHead and begunSeg ~= item.seg then
        if curPhase() ~= item.phase or fsf() < 0
           or fsf() + 16 * item.segLen + SEG_MARGIN > PERIOD then
          M.setPad({})
          return
        end
        begunSeg = item.seg
      end
      M.setPad({ [item.dir] = true })
    end),
  }, spec.what or string.format("phaseWalk (%d,%d)", tx, ty))
end

-- --------------------------------------------------- NPC chase-talk --
-- Talk to a wandering NPC: re-plan the approach every aligned frame
-- (BFS one step toward any neighbor of the object's live tile), face it,
-- edge A+direction; plain dialogs advanced with edge-A; stops as soon as
-- a choice list is up ($056F >= 2) so a blind A can never answer it.
--   objIdx: the NPC's object index ($10 + record order in npc_prop)
--   opts.done (optional): custom terminator; the default is
--     "a choice dialog is up and waiting"
--   opts.avoid (optional): a tile set (keys ((y<<8)|x)) the approach must
--     never route through, for one-way entrances near the chase area
function M.chaseTalk(objIdx, maxFrames, what, opts)
  opts = opts or {}
  local ph = 0
  local done = opts.done or function()
    return M.readByte(0x056f) >= 2 and M.dialogWaiting()
  end
  local function objAt(idx)
    local off = 0x29 * idx
    return M.readWord(0x086a + off) >> 4, M.readWord(0x086d + off) >> 4
  end
  return M.driveUntil(done, maxFrames or 9000, {
    M.call(function()
      ph = (ph + 1) % 8
      if M.battleLoadStarted() then
        for s = 0, 5 do
          if M.readByte(0x3aa8 + s * 2) % 2 == 1 then
            M.killbit(s)
          end
        end
        M.setPad(ph < 4 and { "a" } or {})
        return
      end
      if M.readByte(0x056f) >= 2 then M.setPad({}); return end
      if M.dialogWaiting() then M.setPad(ph < 4 and { "a" } or {}); return end
      if not (M.hasControl() and M.tileAligned()) then M.setPad({}); return end
      local ox, oy = objAt(objIdx)
      local px, py = M.fieldX(), M.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        M.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = M.bfsPath(c[1], c[2], nil, opts.avoid)
        if p and (not best or #p < #best) then best = p end
      end
      if best and #best > 0 then
        M.setPad({ [M.movePress(best[1])] = true })
      else
        M.setPad({})
      end
    end),
  }, what or string.format("chaseTalk obj %02X", objIdx))
end

-- ------------------------------------------- levers and re-entry escapes --
-- A lever tile: one 8-frame up+A tap fires the event and the switch flips
-- at the end of it (~70 frames); holding up with A released never
-- re-fires; a second A press on a toggle tile flips it back.  So tap
-- once, hold up, and wait for the flip.  Dialogs opened by the event are
-- advanced with edge-A; a battle that fires on the tile is cleared by a
-- flag write.
function M.tapLever(swId, maxFrames, what)
  local n = 0
  local function swv(id)
    return (M.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
  end
  return M.driveUntil(function() return swv(swId) == 1 end, maxFrames, {
    M.call(function()
      n = n + 1
      if M.battleLoadStarted() then
        for s = 0, 5 do
          if M.readByte(0x3aa8 + s * 2) % 2 == 1 then
            M.killbit(s)
          end
        end
        M.setPad({ "a" }); return
      end
      if M.dialogWaiting() then M.setPad(n % 8 < 4 and { "a" } or {}); return end
      M.setPad(n <= 8 and { up = true, a = true } or { up = true })
    end),
  }, what)
end

-- Escape a stood-on re-entry trigger tile (the re-entry-trap class: the
-- trigger re-enters every frame, hasControl never settles, and only an
-- unconditional held press leaves).  Cycles dirs 40 frames each until the
-- party tile changes and settles 10 aligned quiet frames.
function M.stepOff(dirs, maxFrames, what)
  local x0, y0, moved, calm, n = nil, nil, false, 0, 0
  return M.driveUntil(function()
    if not x0 then return false end
    if M.fieldX() ~= x0 or M.fieldY() ~= y0 then moved = true end
    calm = (moved and M.tileAligned() and not M.dialogWaiting()
            and not M.battleLoadStarted()) and calm + 1 or 0
    return calm >= 10
  end, maxFrames, {
    M.call(function()
      if not x0 then x0, y0 = M.fieldX(), M.fieldY() end
      if M.battleLoadStarted() then
        for s = 0, 5 do
          if M.readByte(0x3aa8 + s * 2) % 2 == 1 then
            M.killbit(s)
          end
        end
        M.setPad({ "a" }); return
      end
      if M.dialogWaiting() then M.setPad({ "a" }); return end
      if moved then M.setPad({}); return end
      n = n + 1
      M.setPad({ [dirs[((n // 40) % #dirs) + 1]] = true })
    end),
  }, what)
end

-- --------------------------------------------------------- field care --
-- M.fieldCare: open the field menu and revive, cure and heal the party with
-- real presses, then close it again.  The status pass is CARE_STATUS_CURES
-- below, and it is one bit today: poison, because poison is the only status
-- that walking makes worse.
--
-- ZMENUSTATE = DP $26, and the shared list cursor is DP $4B.
-- Item path: $05 main menu (Item row 0) -A-> $08 item list ($4B is the
-- inventory slot) -A-> $19 slot picked up (A on a different slot swaps
-- them, A on the same slot uses it) -A-> $70 target select ($4B is the
-- menu slot 0..3, battle order, moved by up/down only) -A-> item applied,
-- window stays on $70.  B from $08 lands on the item options window $17,
-- then $04, then out.  Refusals start the mosaic task, which writes DP $B5
-- for eight frames without clearing it; the driver watches that byte's
-- high nibble and drops the plan rather than pressing into a refusal.
--
-- OT6 restores HP and MP in full on every level up, so MP spent walking a
-- corridor is refunded by the next level while a Tonic drunk there is gone
-- for good; casting is therefore tried before the bag.
--
-- Magic path: $05 (Skills row 1) -A-> $06 character select ($4B copies
-- into zSelIndex $28) -A-> $0A skills options (Magic row 1, enabled only
-- when gate byte $7A reads $20) -A-> $1A spell list ($4B = 2*row+column;
-- a spell is castable when its colour byte at $7E9E09+i reads $20) -A->
-- $3B target select (up/down only) -A-> spell lands, window stays on $3B,
-- so the driver holds a caster until they hit their MP floor rather than
-- spreading the casts around.
--
-- opts.threshold  heal a living member below this fraction of max HP
--                 (default 0.55)
-- opts.magic      cast a cure spell when someone can, and reach for the bag
--                 only when nobody can, the MP is short, or the target is
--                 KO'd and needs a Fenix Down (default true).  Set false on
--                 a step that wants its MP kept for the fight it is walking
--                 toward.
-- opts.mpFloor    MP a caster keeps back: a fraction of their maximum below
--                 1, an absolute number at or above it (default 0.25).  A
--                 caster drained to zero in a corridor walks into the next
--                 fight with no Cure and no attack spell, and the fight
--                 driver's own in-battle heal has nothing to spend, so the
--                 floor is not zero.
-- opts.reserve    { [itemId] = n } -- keep n of that item unspent, so a step
--                 can hold Potions back for the fight it is walking toward
-- opts.maxFrames  budget for the whole visit (default 24000)
-- opts.maxTries   plans to attempt before giving up (default 48)
-- opts.tag        log prefix
--
-- It is a no-op, and does not even open the menu, when nobody needs
-- anything, so a route can call it after every step and pay only where
-- something is needed.
-- Both M.fieldCare and M.setRows can be called on a field map or on the
-- overworld, and "the menu is closed and the party has control again" is a
-- different question on each: the world module has its own position and
-- control registers and every field predicate is meaningless there.
--
-- On the world map the world control/alignment registers can hold
-- stale-live values during the menu module's teardown, so a single
-- satisfying frame can be a coincidence mid-handoff; the world close is
-- therefore debounced, requiring 30 consecutive frames before it is
-- believed.  On a field map hasControl() reads false for the entire menu
-- lifetime and becomes true only once the field module is back, so the
-- first true frame is correct there and debouncing it would hang instead
-- (every B tap the close driver sends drops control for that frame).
-- careClose() below carries that split; careBackOnMap() is the raw
-- predicate it and the setRows first stage build on.
local CARE_ZM, CARE_CUR, CARE_REFUSE = 0x26, 0x4b, 0xb5
local CARE_SEL, CARE_MAGIC_SEL = 0x28, 0x99   -- zSelIndex, chosen list index
local CARE_MAGIC_GATE = 0x7a                  -- zSkillsTextColor[1] = Magic
local CARE_TONIC, CARE_POTION, CARE_FENIX = 0xE8, 0xE9, 0xF0
local CARE_ANTIDOTE, CARE_SOFT, CARE_REMEDY = 0xF2, 0xF4, 0xF5
local CARE_CURES = { 0x2D, 0x2E, 0x2F }       -- Cure, Cure 2, Cure 3

-- ---- clearing a status ----
--
-- Status byte 1: $80 wound, $40 petrify, $20 imp, $10 clear, $08 magitek,
-- $04 poison, $02 zombie, $01 dark.  Soft clears petrify, Green Cherry
-- imp, Antidote poison, Revivify zombie, Eyedrop dark, Remedy any of
-- petrify/imp/poison/dark at once; each item is refused on a target not
-- carrying its bit.  Poison is the only status that walking makes worse
-- (it drains max HP/32 every step, floored at 1).
--
-- Each row is an ORDERED list of items, tried in order and skipped when
-- the bag has none of that one: the single-purpose item first, Remedy as
-- the fallback, since without it a party holding Remedies and no Antidote
-- would carry the bit for the rest of the route.
local CARE_STATUS_CURES = {
  { bit = 0x40, items = { CARE_SOFT, CARE_REMEDY }, what = "petrify" },
  { bit = 0x04, items = { CARE_ANTIDOTE, CARE_REMEDY }, what = "poison" },
}
local MAGIC_LIST, MAGIC_COLOUR = 0x7E9D89, 0x7E9E09

-- The menu screens the drive can be parked on.  Every other value of $26 is
-- a fade ($00/$01/$02) or a one-frame init ($03/$04/$07/$09/$3A/$3C/$6F/$77)
-- that resolves on its own, and pressing anything during one is how a drive
-- loses a button.  Two things read this: the router presses B on any
-- screen that is not on the current plan's path, and the close predicate
-- treats "not on any of these" as the menu no longer being up.
local CARE_SCREENS = {
  [0x05] = "main", [0x06] = "char select", [0x08] = "item list",
  [0x0A] = "skills", [0x17] = "item options", [0x18] = "rare items",
  [0x19] = "item picked up", [0x1A] = "spell list",
  [0x3B] = "magic target", [0x3D] = "magic target (all)",
  [0x64] = "item details", [0x70] = "item target",
}

local function careBackOnMap()
  if M.worldMode() then return M.worldHasControl() and M.worldAligned() end
  return M.hasControl() and M.tileAligned()
end

-- careClose: the close predicate a care/rows drive waits on.  One
-- closure, deciding world vs field at runtime every frame (the step
-- table is built before H.run starts, so the mode cannot be resolved
-- when this is called).
--
--   World -> debounced (30 consecutive true frames) plus the
--   ZMENUSTATE-still-a-menu guard: the world menu module keeps $26 at
--   05 through the half-close, so a single satisfying frame can be a
--   stale-live coincidence mid-handoff, which is the bug this guard
--   exists for.
--   Field -> raw single frame plus the caller's own ZM guard: on the
--   field hasControl() reads false for the entire menu lifetime and
--   becomes true only when the field module is back, so the
--   first true frame is correct.  Debouncing it hangs instead (every
--   B tap the close driver sends drops control for a frame; 4-of-12
--   tapping never leaves 30 clean frames in a row).
local function careClose(zmExtra)
  local calm = 0
  return function()
    if M.worldMode() then
      local zm = M.readByte(0x26)
      local ok = M.worldHasControl() and M.worldAligned()
             and not CARE_SCREENS[zm]
      calm = ok and calm + 1 or 0
      return calm >= 30
    end
    return M.hasControl() and M.tileAligned()
       and (zmExtra == nil or zmExtra())
  end
end

function M.charHp(c) return M.readWord(0x1600 + 37 * c + 9) end

-- M.calcMaxHpMp: unpack one of the two `bbnnnnnn nnnnnnnn` words in a
-- character record into the effective maximum the menu draws and every
-- can-I-use-this check compares against.  The top two bits are a boost
-- code (0 +0%, 1 +25%, 2 +50%, 3 +12.5%) and the rest is the base.
-- `cap` is 9999 for max HP, 999 for max MP.
function M.calcMaxHpMp(w, cap)
  local base, code = w & 0x3fff, w >> 14
  local add = ({ [0] = 0, [1] = base // 4, [2] = base // 2,
                 [3] = base // 8 })[code]
  local v = base + add
  return v > cap and cap or v
end

function M.charMaxHp(c)
  return M.calcMaxHpMp(M.readWord(0x1600 + 37 * c + 11), 9999)
end

function M.charMp(c) return M.readWord(0x1600 + 37 * c + 13) end
function M.charMaxMp(c)
  return M.calcMaxHpMp(M.readWord(0x1600 + 37 * c + 15), 999)
end

-- Status byte 1: $80 wound, $40 petrify, $02 zombie (item.asm:2244,
-- ff6/notes/field-ram.txt:901-909).  `& $C2 == 0` is the gate both
-- CheckCanUseItem (item.asm:2249-2258) and CheckSkillValid
-- (field_menu.asm:722-731) apply, so it decides both "can be healed" and
-- "can be picked for Skills".
function M.charStatus1(c) return M.readByte(0x1600 + 37 * c + 20) end

-- The learn array is indexed by ACTOR, the byte at the top of the character
-- record, not by the character id (skills.asm:1030-1044).  They agree for
-- the World of Balance roster and stop agreeing later, so read it.
function M.charActor(c) return M.readByte(0x1600 + 37 * c) end

-- Can this character cast the spell from the field Magic menu?  $FF in the
-- learned table is permanent knowledge; an equipped esper's GenjuProp
-- spell ids are also live while worn, matching the battle list.  Read both
-- sources exactly as the game does so fieldCare will spend that granted MP
-- before drinking from the bag.  Unequipping removes the second source and
-- never writes the first.
function M.knowsSpell(c, spell)
  local actor = M.charActor(c)
  if M.readByte(0x1A6E + 54 * actor + spell) == 0xFF then return true end
  -- `c` selects the roster record; `actor` selects the learned table.  They
  -- agree in the World of Balance and are not an ABI synonym later.
  local esper = M.readByte(0x1600 + 37 * c + 0x1E)
  if esper >= 0x80 then return false end
  local row = (M.sym("GenjuProp") & 0x3FFFFF) + 11 * esper
  for _, off in ipairs({ 1, 3, 5, 7, 9 }) do
    if M.readRomByte(row + off) == spell then return true end
  end
  return false
end

-- MP cost of a spell, read from the ROM's own table (MagicProp+5).  The
-- field menu halves it for a Gold Hairpin or flattens it to 1 for an
-- Economizer; those two relics are not modelled here, so this over-states
-- the price for a character wearing one, which errs toward drinking a
-- Tonic when a cast would have been free.
function M.spellMpCost(spell)
  return M.readRomByte((M.sym("MagicProp") & 0x3fffff) + 14 * spell + 5)
end

function M.partyMembers()
  local out = {}
  for c = 0, 15 do
    if (M.readByte(0x1850 + c) & 0x07) ~= 0 then out[#out + 1] = c end
  end
  return out
end

-- ------------------------------------------------- the exit contract ------
-- A party member is "standing" (fit to ship in a saved fixture) when:
--   dead:       HP 0, or wound in status 1
--   petrified
--   or zombie:  the other two bits of $C2, the mask the game itself
--               applies when it asks whether a character can be healed or
--               picked for Skills
--   near fatal: HP at or below max HP / 8, the game's own threshold for
--               setting near-fatal status
--   poisoned:   $04 in status 1; DoPoisonDmg drains max HP/32 every step,
--               floored at 1, so a poisoned character arrives at any walk's
--               end at 1 HP regardless of what the record reads now
-- This is the FLOOR, not a readiness bar; some generators assert more
-- (e.g. half HP at their exits).
-- $C6, not $C2: the game's own can-be-healed mask is $C2 (wound, petrify,
-- zombie), and stays $C2 everywhere this file asks the game's own
-- question, because the menu serves a poisoned character perfectly well.
-- The exit contract asks a different question and poison fails it.
function M.standing(c)
  local hp, mx = M.charHp(c), M.charMaxHp(c)
  return hp > 0 and (M.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)
end

-- Assert it for everyone assigned to a party, with the numbers in the
-- message so a failure names the casualty instead of just failing.  During
-- the three-scenario split that is all three parties at once rather than
-- only the one being steered, which is intended: a party queued behind the
-- same fight ships in the same fixture.
function M.assertPartyStanding(tag)
  for _, c in ipairs(M.partyMembers()) do
    M.assertEq(M.standing(c), true, string.format(
      "%s: char %d is on their feet (%d/%d hp, near fatal at or below %d, "
      .. "status1 %02X%s)", tag, c, M.charHp(c), M.charMaxHp(c),
      M.charMaxHp(c) >> 3, M.charStatus1(c),
      (M.charStatus1(c) & 0x04) ~= 0
        and " -- POISONED, and every step drains max/32" or ""))
  end
end

function M.invSlotOf(id)
  for i = 0, 255 do
    if M.readByte(0x1869 + i) == id and M.readByte(0x1969 + i) > 0 then
      return i
    end
  end
  return nil
end

function M.invCountOf(id)
  local s = M.invSlotOf(id)
  return s and M.readByte(0x1969 + s) or 0
end

-- Is treasure bit N (0..511, the global index audit_chests reports) set?
-- $1E40 is the 64-byte treasure bitfield (field-ram.txt:1035); the bit is
-- the unit the game tracks, so duplicate map copies share one.
function M.chestOpen(bit)
  return (M.readByte(0x1E40 + (bit >> 3)) & (1 << (bit & 7))) ~= 0
end

-- M.openChest: open one treasure chest through the real field interaction.
-- navTo the stand tile, face the chest (a short held press against its
-- solid tile turns without stepping), edge-A until the "Received!" dialog
-- answers (held directions starve CheckNPCs, so edge presses only),
-- dismiss it, and assert the game's own record -- the treasure bit.
--
-- Idempotent on the bit: duplicate map copies share one bit and different
-- contents, so a chest already opened -- including its twin on a copy map
-- -- is a logged no-op rather than a timeout against a chest that will
-- never answer.
--
--   H.openChest{ stand = {65,29}, face = "up", bit = 11,
--                what = "Fenix Down", item = 0xF0,     -- item: optional
--                nav = { playBattles = "flee" } }      -- navTo overrides
--
-- `item` adds a bag-delta assertion; gil and empty chests assert the bit
-- alone (the gil counter and the empty dialog are logged, not asserted).
function M.openChest(o)
  local tag = string.format("chest bit %d (%s)", o.bit, o.what or "?")
  local before
  local aPh = 0
  local nav = { maxFrames = 15000, playBattles = "tactical" }
  for k, v in pairs(o.nav or {}) do nav[k] = v end
  -- The turn is closed-loop: hold the direction until the facing byte
  -- ($087F,y) reads back the wanted value (a short fixed press can fail to
  -- set the byte at all).  The facing tile is the chest, which is solid,
  -- so the held direction can press but never step.
  local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
  return M.cond(function()
    if M.chestOpen(o.bit) then
      M.log(string.format("[chest] %s: already open (shared bit or rerun), "
        .. "skipping", tag))
      return false
    end
    return true
  end, {
    M.navTo(o.stand[1], o.stand[2], nav),
    M.call(function()
      before = o.item and M.invCountOf(o.item) or nil
    end),
    M.driveUntil(function()
      return M.readByte(0x087f + M.readWord(0x0803)) == FACE_VAL[o.face]
    end, 300, {
      M.call(function() M.setPad({ [o.face] = true }) end),
    }, tag .. ": faced " .. o.face),
    M.release(), M.waitFrames(4),
    -- The answer is the BIT, not the dialog.  CheckTreasure sets the
    -- treasure bit and gives the item BEFORE it launches the "Received!"
    -- dialog event, and an A press still held when that dialog opens
    -- confirms it the same frame it appears -- this loop's own 4-on/8-off
    -- cadence can flash the dialog through faster than any per-frame
    -- dialogWaiting() sample can see it.  So accept either signal.
    M.driveUntil(function()
      return M.dialogWaiting() or M.chestOpen(o.bit)
    end, 6000, {
      M.call(function()
        aPh = (aPh + 1) % 12
        M.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": the chest answered"),
    -- The bit lands BEFORE the dialog event launches, so when the
    -- bit ended the wait above, the Received! window may still be a
    -- few frames out.  Linger at least 90 frames, dismissing whatever
    -- appears -- returning with a dialog pending starves the next step.
    (function()
      local dt = 0
      return M.driveUntil(function()
        dt = dt + 1
        return dt >= 90 and not M.dialogWaiting()
      end, 600, {
        M.call(function()
          aPh = (aPh + 1) % 8
          M.setPad(M.dialogWaiting() and aPh < 4 and { a = true } or {})
        end),
      }, tag .. ": dialog dismissed")
    end)(),
    M.call(function()
      M.setPad({})
      M.assertEq(M.chestOpen(o.bit), true, tag .. ": treasure bit set")
      if o.item then
        local now = M.invCountOf(o.item)
        M.assertEq(now, before + 1,
          string.format("%s: bag %d -> %d of item $%02X", tag, before, now,
            o.item))
      end
      M.log(string.format("[chest] %s: OPENED", tag))
    end),
  }, {})
end

-- M.buyItem: buy `qtyFn()` more of shop row `row`, closed-loop,
-- with the shop already open at its options window (menu state $25).
--
--  * The list cursor row (DP $4E) and the quantity (zSelIndex, DP $28) are
--    read and steered, never press-counted, because menu direction holds
--    auto-repeat.  Widget deltas: right +1, left -1, up +10, down -10,
--    gil-clamped by the handler.
--  * The clamp reports how much gil is available: steering toward a
--    quantity the gil cannot cover pins qty at the affordable maximum.
--    After 240 frames with the quantity unmoving against the clamp, the
--    clamped qty is accepted and logged.  Order the buys so the marginal
--    item comes last and a small purse shorts it rather than the
--    essentials.
--  * Purchases are verified after the shop closes; mid-menu inventory
--    reads are wrong (the field bag does not update until the shop hands
--    RAM back).
function M.buyItem(id, row, qtyFn, name)
  local phase = 0
  local seen27, bought = false, false
  local want = nil
  local lastQty, stall = nil, 0
  return M.driveUntil(function() return bought end, 20000, {
    M.call(function()
      phase = (phase + 1) % 8
      local st = M.readByte(0x0026)
      if want == nil then
        want = qtyFn()
        if want < 1 then want = 1 end
        M.log(string.format("[shop] %s: buying %d", name, want))
      end
      if st == 0x27 then
        seen27 = true
        local qty = M.readByte(0x0028)
        if qty == lastQty and qty < want then
          stall = stall + 1
          if stall > 240 then
            M.log(string.format(
              "[shop] %s: purse-clamped at %d (wanted %d) -- taking it",
              name, qty, want))
            want = qty
          end
        elseif qty ~= lastQty then
          stall = 0
        end
        lastQty = qty
        local btn = nil
        if qty < want then
          btn = (want - qty >= 10) and "up" or "right"
        elseif qty > want then
          btn = (qty - want >= 10) and "down" or "left"
        else
          btn = "a"
        end
        M.setPad(phase < 2 and { [btn] = true } or {})
      elseif seen27 then
        bought = true
        M.setPad({})
      elseif st == 0x25 then
        M.setPad(phase < 2 and { "a" } or {})
      elseif st == 0x26 then
        local cur = M.readByte(0x004E)
        local btn = cur < row and "down" or cur > row and "up" or "a"
        M.setPad(phase < 2 and { [btn] = true } or {})
      else
        M.setPad({})
      end
    end),
  }, "buy " .. name)
end

-- The event timers, $1188-$119F: four 6-byte records, flags at +0 and a
-- 16-bit frame counter at +1 (event.asm EventCmd_a0/a1).  A nonzero
-- counter means the block holds live data: the scene is time-limited
-- (the opera rafter chase, the banquet window, the aria's armed stretch),
-- menus tick the clock 1:1, and leftover menu-state writers corrupt the
-- block (the banquet-decode.md save-drive rule).  Care and every other
-- menu visit stays out while any counter is nonzero.
function M.eventTimerLive()
  for k = 0, 3 do
    if M.readWord(0x1189 + 6 * k) ~= 0 then return true end
  end
  return false
end

-- careKernel: the planning and menu-routing heart shared by M.fieldCare
-- (the step form) and M.newCareDriver (the per-frame form navigators run
-- between battles).  Works on a field map or the overworld alike --
-- careClose above carries the world/field close split, and gen_sabin_gau
-- has cared on the overworld all along.  (An older KNOWN-LIMIT note here
-- claimed world care was broken; careClose's world-mode debounce is what
-- fixed it.)
-- The kernel plans only for the ACTIVE party ($1A6D), not everyone
-- enrolled: during a multi-squad scene (the Moogle defense fields eleven)
-- M.partyMembers() returns every deployed squad, but the field menu shows
-- only the controlled party's four -- a plan for anyone else can never
-- find its menu slot, and each such plan burns its full 1200-frame stall
-- budget before dropping (measured killing moogle_cleared's advanceStory
-- inside its own budget the first day navigator care ran the early chain).
local function careParty()
  local active = M.readByte(0x1A6D) & 0x07
  local out = {}
  for _, c in ipairs(M.partyMembers()) do
    if (M.readByte(0x1850 + c) & 0x07) == active then out[#out + 1] = c end
  end
  return out
end

local function careKernel(opts)
  opts = opts or {}
  local tag = opts.tag or "care"
  local thresh = opts.threshold or 0.55
  local reserve = opts.reserve or {}
  local budget = opts.maxFrames or 24000

  local useMagic = opts.magic ~= false
  local mpFloor = opts.mpFloor or 0.25
  local maxTries = opts.maxTries or 48

  local function avail(id)
    return math.max(0, M.invCountOf(id) - (reserve[id] or 0))
  end

  -- MP a caster keeps back.  Below 1 the option is a fraction of their own
  -- maximum, so one number suits a level 7 TERRA and a level 30 one; at or
  -- above 1 it is an absolute MP count.
  local function floorOf(c)
    if mpFloor < 1 then return math.floor(M.charMaxMp(c) * mpFloor) end
    return mpFloor
  end

  local failed = {}         -- plans the game refused, so they are not retried
  local function key(w)
    if w.kind == "cast" then
      return string.format("%d:cast:%d:%d", w.char, w.caster, w.spell)
    end
    return string.format("%d:item:%d", w.char, w.item)
  end

  local function planText(w)
    if w.kind == "cast" then
      return string.format("%s char %d by casting $%02X from char %d " ..
        "(%d/%d hp, caster %d/%d mp)", w.why, w.char, w.spell, w.caster,
        M.charHp(w.char), M.charMaxHp(w.char),
        M.charMp(w.caster), M.charMaxMp(w.caster))
    end
    return string.format("%s char %d with $%02X (%d/%d hp, status1 %02X)",
      w.why, w.char, w.item, M.charHp(w.char), M.charMaxHp(w.char),
      M.charStatus1(w.char))
  end

  -- Whoever the drive last set the Skills screens up for stays the caster
  -- until they hit their floor.  Holding one caster is both what a player
  -- does and much the cheaper drive: a second cast for the same caster and
  -- spell never leaves $3B, while switching casters unwinds to $05 and
  -- walks $06/$0A/$1A again.
  local activeCaster = nil

  -- Can this character cast this spell on somebody right now?  Every clause
  -- is a gate the game itself applies, so failing one is a guaranteed
  -- refusal rather than a guess: alive and not petrified or zombie
  -- (CheckSkillValid, field_menu.asm:722-731), knows the spell outright,
  -- and has the MP with the floor still intact.
  local function canCast(c, spell)
    return M.charHp(c) > 0 and (M.charStatus1(c) & 0xC2) == 0
       and M.knowsSpell(c, spell)
       and M.charMp(c) - M.spellMpCost(spell) >= floorOf(c)
  end

  -- The cheapest cure the party can put on this target.  Cheapest rather
  -- than biggest: MP is the resource being rationed and the loop simply
  -- casts again if the target is still short, so two Cures beat one Cure 2
  -- wherever the prices are vanilla's.  Overshoot is wasted MP.
  local function pickCast(target)
    local order = {}
    for _, s in ipairs(CARE_CURES) do order[#order + 1] = s end
    table.sort(order, function(a, b)
      return M.spellMpCost(a) < M.spellMpCost(b)
    end)
    local casters = {}
    if activeCaster ~= nil then casters[1] = activeCaster end
    for _, c in ipairs(careParty()) do
      if c ~= activeCaster then casters[#casters + 1] = c end
    end
    for _, c in ipairs(casters) do
      for _, s in ipairs(order) do
        local w = { kind = "cast", char = target, caster = c, spell = s,
                    why = "heal" }
        if canCast(c, s) and not failed[key(w)] then return w end
      end
    end
    return nil
  end

  -- Everything the bag can do for this target.
  local function pickItem(target)
    local hole = M.charMaxHp(target) - M.charHp(target)
    local order = hole >= 120
      and { CARE_POTION, CARE_TONIC } or { CARE_TONIC, CARE_POTION }
    for _, id in ipairs(order) do
      local w = { kind = "item", char = target, item = id, why = "heal" }
      if avail(id) > 0 and not failed[key(w)] then return w end
    end
    return nil
  end

  -- Everything the bag can do about a status this character is carrying.
  -- Ordered before healing rather than after it, because poison drains on
  -- every step (player.asm:593-613): HP restored while the bit is still set
  -- starts draining again the moment the menu closes, so curing first is
  -- both what a player does and the cheaper order.  A dead, petrified or
  -- zombie target is skipped, because CheckCanUseItem's own first test is
  -- the wound branch (item.asm:2282-2286) and a Fenix Down is the only
  -- thing it accepts there; the revive pass above is what serves them.
  local function pickStatusCure(target)
    if M.charHp(target) == 0 or (M.charStatus1(target) & 0xC2) ~= 0 then
      return nil
    end
    for _, cure in ipairs(CARE_STATUS_CURES) do
      if (M.charStatus1(target) & cure.bit) ~= 0 then
        for _, item in ipairs(cure.items) do
          local w = { kind = "item", char = target, item = item,
                      why = "cure " .. cure.what }
          if avail(item) > 0 and not failed[key(w)] then return w end
        end
      end
    end
    return nil
  end

  -- Pick in the order a player would: revive first, then clear a status the
  -- bag can clear, then top up whoever is worst off, casting where the party
  -- can cast and reaching for the bag where it cannot.  Members are tried
  -- worst-first rather than only the worst being tried, so one member nobody
  -- can help does not stop the rest from being served.
  local function pick()
    for _, c in ipairs(careParty()) do
      local w = { kind = "item", char = c, item = CARE_FENIX, why = "revive" }
      if M.charHp(c) == 0 and avail(CARE_FENIX) > 0 and not failed[key(w)] then
        return w
      end
    end
    for _, c in ipairs(careParty()) do
      local w = pickStatusCure(c)
      if w ~= nil then return w end
    end
    local hurt = {}
    for _, c in ipairs(careParty()) do
      local hp, mx = M.charHp(c), M.charMaxHp(c)
      -- A petrified or zombie member is refused by CheckCanUseItem
      -- (item.asm:2249-2258) and by the spell check (field_menu.asm:3076
      -- -3081) alike, so proposing anything for them only burns attempts.
      if hp > 0 and mx > 0 and hp < mx and hp < mx * thresh
         and (M.charStatus1(c) & 0xC2) == 0 then
        hurt[#hurt + 1] = { c = c, r = hp / mx }
      end
    end
    table.sort(hurt, function(a, b) return a.r < b.r end)
    for _, h in ipairs(hurt) do
      local w = useMagic and pickCast(h.c) or nil
      if w == nil then w = pickItem(h.c) end
      if w ~= nil then return w end
    end
    return nil
  end

  local function anyNeed() return pick() ~= nil end

  -- menu slot (the $70 and $3B cursor row) for a character id
  local function slotOf(c)
    for s = 0, 3 do
      if M.readByte(0x69 + s) == c then return s end
    end
    return nil
  end

  -- Who the Skills screens are currently showing, and which spell A in $1A
  -- committed to.  A in $06 copies the cursor into zSelIndex
  -- (field_menu.asm:644) and A in $1A copies it into $99
  -- (field_menu.asm:2836); GetSelMagic is $7E9D89[$99]
  -- (field_menu.asm:3208-3213).  Reading them back is how the router tells
  -- "this screen belongs to my plan" from "this screen belongs to the plan
  -- before it", which is what decides whether to press on or press B.
  local function menuCaster()
    local s = M.readByte(CARE_SEL)
    if s > 3 then return nil end
    local c = M.readByte(0x69 + s)
    return c ~= 0xFF and c or nil
  end
  local function menuSpell()
    return M.readByte(MAGIC_LIST + M.readByte(CARE_MAGIC_SEL))
  end

  -- List index of a spell in the field magic list.  CalcMagicOrder
  -- (skills.asm:734-747) lays every id down once, and only drawing blanks
  -- the ones this character cannot use (skills.asm:914-916), so a spell the
  -- caster knows is always findable here.  The list order is a Config
  -- setting ($1D54 bits 0-2), which is why this searches rather than
  -- assuming Cure is index 0.
  local function magicIndexOf(spell)
    for i = 0, 0x35 do
      if M.readByte(MAGIC_LIST + i) == spell then return i end
    end
    return nil
  end

  local phase, served, want, pending, tries = 0, false, nil, nil, 0
  local refuseArmed = true

  -- Per-plan stall watchdog.  A plan that neither lands nor is abandoned makes
  -- no forward progress, and without a backstop the drive presses at it for
  -- the whole 24000-frame budget.
  -- `stall` counts serveFrame calls since the last real progress -- a landing,
  -- a fresh plan, or an abandon.  Crossing the limit force-abandons the current
  -- plan (marking it failed so pick() moves on); when every plan is exhausted
  -- pick() returns nil and the visit exits cleanly.  A legitimate heal lands in
  -- a few hundred frames, well under this, so working care is never cut short.
  local STALL_LIMIT = 1200
  local stall = 0

  local function steer(cur, wantRow)
    if cur == wantRow then return { "a" } end
    return { [cur < wantRow and "down" or "up"] = true }
  end

  -- give up on this plan and let the next frame pick another
  local function abandon(w, why)
    M.log(string.format("[%s] dropping plan (%s): %s", tag, why, planText(w)))
    failed[key(w)] = true
    want, pending = nil, nil
    stall = 0
  end

  local function serveFrame()
    phase = (phase + 1) % 12
    stall = stall + 1
    local st = M.readByte(CARE_ZM)

    -- Refusal.  zMosaic is not a flag the game clears: MosaicTask writes
    -- the eight bytes $17 $27 $37 $47 $37 $27 $17 $07 and terminates
    -- (field_menu.asm:3820-3844), and nothing re-zeroes it after menu init
    -- (menu_init_2.asm:506).  So `$B5 ~= 0` stays true for the rest of the
    -- visit, and testing it that way reported every plan after the first
    -- refusal as refused too, without pressing anything, until the attempt
    -- cap gave up.  The high nibble is nonzero only while the animation
    -- runs, so that is the edge; re-arming when it clears keeps one
    -- refusal's tail from being charged to the next plan.
    local mosaic = M.readByte(CARE_REFUSE) & 0xF0
    if mosaic == 0 then
      refuseArmed = true
    elseif want and refuseArmed then
      refuseArmed = false
      M.log(string.format("[%s] REFUSED by the game: %s", tag, planText(want)))
      failed[key(want)] = true
      want, pending = nil, nil
      M.setPad({})
      return
    end

    -- check whether the last confirm landed.  An Antidote restores no HP, so
    -- the status byte is watched as well: without it the only evidence a
    -- status cure landed is the bag count, and a plan whose landing is read
    -- off one signal is a plan that hangs the moment that signal is the one
    -- the item does not move.
    if pending then
      local landed
      if pending.kind == "item" then
        landed = M.charHp(pending.char) ~= pending.hp
              or M.charStatus1(pending.char) ~= pending.st1
              or M.invCountOf(pending.item) < pending.qty
      else
        landed = M.charHp(pending.char) ~= pending.hp
              or M.charMp(pending.caster) ~= pending.mp
      end
      if landed then
        if pending.kind == "item" then
          M.log(string.format(
            "[%s] used $%02X on char %d: %d -> %d hp, status1 %02X -> %02X, " ..
            "%d left",
            tag, pending.item, pending.char, pending.hp,
            M.charHp(pending.char), pending.st1,
            M.charStatus1(pending.char), M.invCountOf(pending.item)))
        else
          M.log(string.format(
            "[%s] char %d cast $%02X on char %d: %d -> %d hp, caster %d -> %d mp",
            tag, pending.caster, pending.spell, pending.char, pending.hp,
            M.charHp(pending.char), pending.mp, M.charMp(pending.caster)))
        end
        want, pending = nil, nil
        stall = 0
      end
    end

    if want == nil then
      want = pick()
      if want == nil then served = true; M.setPad({}); return end
      tries = tries + 1
      stall = 0
      if tries > maxTries then
        M.log(string.format("[%s] giving up after %d attempts", tag, tries))
        served = true; M.setPad({}); return
      end
      if want.kind == "cast" then activeCaster = want.caster end
      M.log(string.format("[%s] plan: %s", tag, planText(want)))
    end

    -- Stall backstop: this plan has made no progress for STALL_LIMIT frames
    -- (a target/caster window that never populated, a confirm that never
    -- lands).  Abandon it so pick() can try another; the visit exits once
    -- every plan is exhausted rather than burning the whole budget.
    if stall > STALL_LIMIT then
      abandon(want, string.format("stalled %d frames without progress", stall))
      M.setPad({}); return
    end

    -- Route by state.  A screen that is not on the current plan's path gets
    -- a B, which unwinds to $05 from anywhere: B in $70 goes to $77 -> $08,
    -- in $08 to $17, in $17 to $05, in $1A to $0A, and in $0A straight to
    -- $05.
    local held = nil
    if want.kind == "item" then
      if st == 0x05 then
        held = steer(M.readByte(CARE_CUR), 0)          -- Item is row 0
      elseif st == 0x08 then
        local slot = M.invSlotOf(want.item)
        if slot == nil then abandon(want, "not in the bag"); M.setPad({}); return end
        held = steer(M.readByte(CARE_CUR), slot)
      elseif st == 0x19 then
        -- A here only uses the item if the cursor is still on the slot it
        -- was picked up from; anywhere else it swaps two items instead
        local slot = M.invSlotOf(want.item)
        held = (slot and M.readByte(CARE_CUR) == slot) and { "a" } or { "b" }
      elseif st == 0x70 then
        -- A use leaves this window open holding the same item, so $70 is on
        -- the path only while the item it is holding is the one planned.
        if M.readByte(0x1869 + M.readByte(CARE_SEL)) ~= want.item then
          held = { "b" }
        else
          -- want.char is always a party member, so a nil slot is the target
          -- window not yet populated (a teardown transient), not an
          -- untargetable character.  Wait for it; the stall backstop guards a
          -- window that never fills.
          local slot = slotOf(want.char)
          if slot == nil then M.setPad({}); return end
          local cur = M.readByte(CARE_CUR)
          if cur == slot then
            pending = { kind = "item", char = want.char, item = want.item,
                        hp = M.charHp(want.char),
                        st1 = M.charStatus1(want.char),
                        qty = M.invCountOf(want.item) }
            held = { "a" }
          else
            held = steer(cur, slot)
          end
        end
      elseif CARE_SCREENS[st] then
        held = { "b" }
      else
        M.setPad({}); return            -- fades and transients: hands off
      end
    else
      if st == 0x05 then
        held = steer(M.readByte(CARE_CUR), 1)          -- Skills is row 1
      elseif st == 0x06 then
        -- The caster is always a party member (pickCast only draws from
        -- partyMembers), so a nil slot here is never "not in the party" -- it
        -- is the on-screen list not yet populated, which is exactly what a
        -- battle-victory teardown transient looks like when the menu opens onto
        -- it.  Wait for it rather than permanently failing the plan; the stall
        -- backstop covers a list that never fills.
        local slot = slotOf(want.caster)
        if slot == nil then M.setPad({}); return end
        held = steer(M.readByte(CARE_CUR), slot)
      elseif st == 0x0A then
        if menuCaster() ~= want.caster then
          held = { "b" }
        elseif M.readByte(CARE_MAGIC_GATE) ~= 0x20 then
          abandon(want, "Magic is greyed out"); M.setPad({}); return
        else
          held = steer(M.readByte(CARE_CUR), 1)        -- Magic is row 1
        end
      elseif st == 0x1A then
        if menuCaster() ~= want.caster then
          held = { "b" }
        else
          local i = magicIndexOf(want.spell)
          if i == nil then abandon(want, "not in the spell list"); M.setPad({}); return end
          local cur = M.readByte(CARE_CUR)
          if cur == i then
            -- The colour is the game's own gate and A applies it, so read
            -- it rather than press into a refusal.  It is only current for
            -- rows that have been drawn, which the cursor's own page always
            -- has been.
            if M.readByte(MAGIC_COLOUR + i) ~= 0x20 then
              abandon(want, string.format("row colour $%02X, not castable",
                M.readByte(MAGIC_COLOUR + i)))
              M.setPad({}); return
            end
            held = { "a" }
          elseif (cur & 1) ~= (i & 1) then
            -- two columns: left and right move one entry, up and down two
            held = { [cur < i and "right" or "left"] = true }
          else
            held = { [cur < i and "down" or "up"] = true }
          end
        end
      elseif st == 0x3B then
        if menuCaster() ~= want.caster or menuSpell() ~= want.spell then
          held = { "b" }
        else
          -- want.char is always a party member (pick draws from
          -- partyMembers), so a nil slot is a not-yet-populated target window,
          -- not an untargetable character.  Wait; the stall backstop guards a
          -- window that never fills.
          local slot = slotOf(want.char)
          if slot == nil then M.setPad({}); return end
          local cur = M.readByte(CARE_CUR)
          if cur == slot then
            pending = { kind = "cast", char = want.char, caster = want.caster,
                        spell = want.spell, hp = M.charHp(want.char),
                        mp = M.charMp(want.caster) }
            held = { "a" }
          else
            -- up and down only here: left and right are the all-targets
            -- shortcut into $3D (field_menu.asm:2852-2874)
            held = steer(cur, slot)
          end
        end
      elseif CARE_SCREENS[st] then
        held = { "b" }
      else
        M.setPad({}); return            -- fades and transients: hands off
      end
    end
    -- 4-on / 8-off edges, so auto-repeat never runs the cursor past its row
    -- and the handler's one-frame cursor lag is always settled before the
    -- next read (menu_common.asm:273-283)
    M.setPad(phase < 4 and held or {})
  end

  -- The roster line carries MP as well as HP, since MP is what the policy
  -- spends, and status 1, since a poisoned character otherwise reads as a
  -- healthy one on an HP/MP line.  A zero status prints nothing.
  local function roster(what)
    local out = {}
    for _, c in ipairs(careParty()) do
      local st = M.charStatus1(c)
      out[#out + 1] = string.format("c%d %d/%d hp %d/%d mp%s", c, M.charHp(c),
        M.charMaxHp(c), M.charMp(c), M.charMaxMp(c),
        st ~= 0 and string.format(" status1=%02X", st) or "")
    end
    return string.format(
      "[%s] %s: %s | tonic=%d potion=%d fenix=%d antidote=%d soft=%d remedy=%d",
      tag, what, table.concat(out, "  "), M.invCountOf(CARE_TONIC),
      M.invCountOf(CARE_POTION), M.invCountOf(CARE_FENIX),
      M.invCountOf(CARE_ANTIDOTE), M.invCountOf(CARE_SOFT),
      M.invCountOf(CARE_REMEDY))
  end

  return {
    tag = tag, budget = budget,
    anyNeed = anyNeed,
    serveFrame = serveFrame,
    served = function() return served end,
    roster = roster,
  }
end

-- M.fieldCare: the step form -- behaviorally what it has always been
-- (open the menu, serve the plans, close, settle), built on careKernel.
-- A live event timer skips the visit outright (see M.eventTimerLive):
-- the three timed scenes are the one standing exemption to the
-- heal-after-every-battle directive, and the guard enforces it centrally
-- rather than trusting every call site to remember.
function M.fieldCare(opts)
  opts = opts or {}
  -- The reserve floor applies to EXPLICIT care too, not just the automatic
  -- post-battle path: a bare fieldCare() with no reserve spent the last
  -- Tonics to zero (measured: the pre-gate-cave care shipped an empty bag
  -- and a member the party then could not revive).  A caller that truly
  -- means to spend everything before a boss passes reserve = {}.
  if opts.reserve == nil then opts.reserve = M.CARE_RESERVE end
  local K = careKernel(opts)
  local phase = 0
  return M.cond(function() return not M.eventTimerLive() end, {
    M.cond(K.anyNeed, {
      M.logStep(function() return K.roster("opening the menu") end),
      M.driveUntil(function() return M.readByte(CARE_ZM) == 0x05 end, 1800, {
        M.call(function()
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { "x" } or {})
        end),
      }, K.tag .. ": field menu open"),
      M.release(),
      M.waitFrames(10),
      M.driveUntil(K.served, K.budget, {
        M.call(K.serveFrame),
      }, K.tag .. ": heal/revive through the field menu"),
      M.release(),
      M.driveUntil(careClose(function()
        return not CARE_SCREENS[M.readByte(CARE_ZM)]
      end), 2400, {
        M.call(function()
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { "b" } or {})
        end),
      }, K.tag .. ": back to the field"),
      M.release(),
      M.waitFrames(30),
      M.logStep(function() return K.roster("done") end),
    }, {
      -- A care stop that does nothing still logs, so "no log" and "nothing
      -- needed" do not look the same.
      M.logStep(function() return K.roster("nothing to do") end),
    }),
  }, {
    M.logStep(function()
      return K.roster("an event timer is live: no menu care here")
    end),
  })
end

-- M.newCareDriver: fieldCare's whole visit as a per-frame driver, for a
-- navigator to run between battles without leaving its own drive.  Soft
-- wherever the step form raises: a menu that will not open or close
-- inside its budget logs and gives up, because a mid-walk care stop must
-- never be the thing that kills a generator in an odd room.  Call
-- frame() every frame; done() reports completion (instantly true when
-- nobody needs care).
-- The default reserve for AUTOMATIC post-battle care (the navigator hooks
-- and M.careStop, which build their care through here): never spend the
-- last few healing consumables.  A human tops off after a fight but keeps
-- a cushion; without a floor, care at a 0.9 threshold in a no-healer
-- segment drank Tonics and Potions to ZERO, and every downstream fixture
-- and item-dependent test inherited an empty bag (measured 2026-08-27:
-- figaro_cleared shipped 0/0, reddening battle_steal/thief/stealmp).
-- Revival is deliberately NOT reserved (a dead member outweighs a thin
-- bag), so CARE_FENIX is absent here.  The floor is the between-shops
-- safety net; the route's shop restocks (owner directive) are what keep
-- the bag actually stocked for the 0.9 top-off.
M.CARE_RESERVE = { [CARE_TONIC] = 4, [CARE_POTION] = 4 }

function M.newCareDriver(opts)
  opts = opts or {}
  if opts.reserve == nil then opts.reserve = M.CARE_RESERVE end
  -- Owner directive: outside-battle care heals with TONICS (items), not by
  -- casting -- Tonics are cheap and everywhere, and casting cures drained
  -- MP over a grind badly enough to wipe (zozo_arrival, MP-starved with a
  -- full Tonic bag).  Field healing therefore spends no MP; MP is reserved
  -- for battle.  An explicit fieldCare that wants to cast passes
  -- magic=true; here (the automatic post-battle path) it stays off.
  if opts.magic == nil then opts.magic = false end
  local K = careKernel(opts)
  local mode, ph, n = "start", 0, 0
  local closed = careClose(function()
    return not CARE_SCREENS[M.readByte(CARE_ZM)]
  end)
  local D = {}
  function D.done() return mode == "done" end
  function D.frame()
    ph = (ph + 1) % 12
    n = n + 1
    if mode == "start" then
      if not K.anyNeed() then
        M.log(K.roster("nothing to do"))
        mode = "done"; M.setPad({}); return
      end
      M.log(K.roster("opening the menu"))
      mode, n = "open", 0
    end
    if mode == "open" then
      if M.readByte(CARE_ZM) == 0x05 then mode, n = "gap", 0; M.setPad({}); return end
      if n > 1800 then
        M.log(string.format("[%s] the menu never opened; giving up on this care stop", K.tag))
        mode = "done"; M.setPad({}); return
      end
      M.setPad(ph < 4 and { "x" } or {})
      return
    end
    if mode == "gap" then                -- the step form's 10-frame settle
      if n >= 10 then mode, n = "serve", 0 end
      M.setPad({})
      return
    end
    if mode == "serve" then
      if K.served() or n > K.budget then mode, n = "close", 0; M.setPad({}); return end
      K.serveFrame()
      return
    end
    if mode == "close" then
      if closed() then mode, n = "settle", 0; M.setPad({}); return end
      if n > 2400 then
        M.log(string.format("[%s] the menu never closed; pressing on regardless", K.tag))
        mode = "settle"; n = 0; M.setPad({}); return
      end
      M.setPad(ph < 4 and { "b" } or {})
      return
    end
    if mode == "settle" then             -- the step form's 30-frame settle
      if n >= 30 then
        M.log(K.roster("done"))
        mode = "done"
      end
      M.setPad({})
      return
    end
    M.setPad({})
  end
  return D
end

-- M.careStop: the between-battles care stop as one reusable step -- the
-- driver above wrapped for a step list, timer-guarded and soft.  This is
-- what the battle-resolving steps append, and what a script drops after
-- its own hand-rolled battle handling.
function M.careStop(tag, opts)
  opts = opts or {}
  opts.tag = opts.tag or tag or "care after battle"
  -- 0.65, not 0.9: the fighting lineage meets several times the battles the
  -- flee route did, and topping to 90% after every one of them drank ~96
  -- Tonics by the Imperial Camp (measured; the bag hit the reserve floor
  -- with two scenarios still to go).  A person walks a little hurt and
  -- tops up before dangers -- the gens' explicit pre-boss cares at
  -- 0.9-0.95 are that, and they stay.
  if opts.threshold == nil then opts.threshold = 0.65 end
  local D
  return M.cond(function() return not M.eventTimerLive() end, {
    M.call(function() D = M.newCareDriver(opts) end),
    M.driveUntil(function() return D.done() end, 40000, {
      M.call(function() D.frame() end),
    }, opts.tag),
  }, {
    M.logStep(function()
      return string.format("[%s] an event timer is live: no menu care here",
        opts.tag)
    end),
  })
end

-- ---------------------------------------------------------------- rows --
-- M.setRows: put characters in the front or back row through the real Order
-- screen.  Reads and pad presses only.
--
-- ExecCmd sets $B3 = $FF at the top of every command, and bit $20 there
-- means "ignore attacker row", so no row penalty is the default; only the
-- weapon-swing setup clears it, and only when the main-hand weapon lacks
-- WEAPON_FLAG::BACK_ROW.  So a back-row character loses damage only on a
-- Fight; EDGAR's Tools, TERRA's Magic and SABIN's Blitz never reach that
-- code and cost nothing.  Damage taken is halved for physical attacks
-- either way.
--
-- The UI, including the two parts that are easy to get wrong:
--   * the Order screen has no main-menu row.  It is reached by pressing
--     left on the main menu ($05); the menu scrolls sideways ($65) to
--     reveal the word "Order", drawn off the visible edge.
--   * the toggle is A twice on the same slot.  MenuState_10 compares
--     zSelIndex ($28) to the cursor ($4B); a second A on a different slot
--     reorders the party instead of flipping a row.  So the cursor must
--     not move between the two presses, and this driver verifies $28
--     before the second press and treats state $11 (the swap) as an
--     error rather than something to recover from.
--   * the row bit is at $1850 + charIdx, bit $20, in the party/order byte
--     rather than the $1600 stat block.  The menu's working copy is
--     $75 + slot.
--
-- spec: { [charIdx] = true (back row) | false (front row) }
-- A no-op, with the menu never opened, when every listed character is
-- already in the right row.
function M.setRows(spec, opts)
  opts = opts or {}
  local tag = opts.tag or "rows"
  local ZM, CUR, SEL, ROWBIT = 0x26, 0x4b, 0x28, 0x20

  local function inParty(c) return (M.readByte(0x1850 + c) & 0x07) ~= 0 end
  local function isBack(c) return (M.readByte(0x1850 + c) & ROWBIT) ~= 0 end
  local function slotOf(c)
    for s = 0, 3 do
      if M.readByte(0x69 + s) == c then return s end
    end
    return nil
  end

  local skip = {}
  local function pick()
    for c, back in pairs(spec) do
      if inParty(c) and isBack(c) ~= back and not skip[c] then return c end
    end
    return nil
  end
  local function anyNeed() return pick() ~= nil end

  local function rowLine()
    local out = {}
    for _, c in ipairs(M.partyMembers()) do
      out[#out + 1] = string.format("c%d=%s", c, isBack(c) and "back" or "front")
    end
    return table.concat(out, " ")
  end

  local phase, done, want, before, tries = 0, false, nil, nil, 0

  local function serveFrame()
    phase = (phase + 1) % 12
    local st = M.readByte(ZM)

    if st == 0x11 then
      error(string.format("setRows: state $11 -- the second A landed on a " ..
        "DIFFERENT slot and reordered the party instead of flipping a row " ..
        "(%s)", rowLine()), 0)
    end

    if want ~= nil and isBack(want) ~= before then
      M.log(string.format("[%s] char %d -> %s row", tag, want,
        isBack(want) and "back" or "front"))
      want = nil
    end

    if want == nil then
      want = pick()
      if want == nil then done = true; M.setPad({}); return end
      tries = tries + 1
      if tries > 8 then
        M.log(string.format("[%s] giving up after %d toggles", tag, tries))
        done = true; M.setPad({}); return
      end
      before = isBack(want)
    end

    local slot = slotOf(want)
    if slot == nil then
      M.log(string.format("[%s] char %d has no order-screen slot " ..
        "(slots %d,%d,%d,%d) -- skipping", tag, want, M.readByte(0x69),
        M.readByte(0x6a), M.readByte(0x6b), M.readByte(0x6c)))
      skip[want] = true; want = nil; M.setPad({}); return
    end

    local held
    if st == 0x0f then
      local cur = M.readByte(CUR)
      held = (cur == slot) and { "a" }
          or { [cur < slot and "down" or "up"] = true }
    elseif st == 0x10 then
      -- if the pick-up did not land on the slot we aimed at, back out,
      -- because pressing A here would reorder the party
      held = (M.readByte(SEL) == slot) and { "a" } or { "b" }
    else
      M.setPad({}); return              -- $65 scroll, $12 portrait slide
    end
    M.setPad(phase < 4 and held or {})
  end

  return M.cond(anyNeed, {
    M.logStep(function()
      return string.format("[%s] opening the Order screen: %s", tag, rowLine())
    end),
    M.driveUntil(function() return M.readByte(ZM) == 0x05 end, 1800, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "x" } or {})
      end),
    }, tag .. ": field menu open"),
    M.release(), M.waitFrames(10),
    M.driveUntil(function() return M.readByte(ZM) == 0x0f end, 1800, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "left" } or {})
      end),
    }, tag .. ": LEFT scrolls to the Order screen"),
    M.release(), M.waitFrames(10),
    M.driveUntil(function() return done end, opts.maxFrames or 12000, {
      M.call(serveFrame),
    }, tag .. ": flip the rows that need flipping"),
    M.release(),
    M.driveUntil(function()
      return M.readByte(ZM) == 0x05 or careBackOnMap()
    end, 2400, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "b" } or {})
      end),
    }, tag .. ": back to the main menu"),
    M.release(),
    M.driveUntil(careClose(function() return M.readByte(ZM) ~= 0x05 end),
      2400, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "b" } or {})
      end),
    }, tag .. ": back to the field"),
    M.release(), M.waitFrames(30),
    M.logStep(function()
      return string.format("[%s] done: %s", tag, rowLine())
    end),
    M.call(function()
      for c, back in pairs(spec) do
        if inParty(c) then
          M.assertEq(isBack(c), back, string.format(
            "char %d is in the %s row", c, back and "back" or "front"))
        end
      end
    end),
  }, {
    M.logStep(function()
      return string.format("[%s] already set: %s", tag, rowLine())
    end),
  })
end

-- M.equipEsper: equip a specific magicite on the character at char-select
-- position `pos`, through the real Skills -> Espers -> detail -> A walk.
-- Reads and pad presses only.  The list seek is against the live
-- $7e9d89 row->esper table; an esper the save does not own never appears
-- there, so the seek times out instead of equipping the wrong row.
-- `pos` may be a literal char-select row or a function returning one,
-- resolved live at the point the row is actually needed, for a caller
-- whose party order isn't pinned down until runtime.
function M.equipEsper(pos, esperIdx, opts)
  opts = opts or {}
  local tag = opts.tag or ("equip esper " .. esperIdx)
  local ZM, CUR = 0x26, 0x4b
  local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL =
    0x05, 0x06, 0x0a, 0x1e, 0x4d
  local GENJULIST = 0x9d89
  local function st() return M.readByte(ZM) end
  local function targetPos()
    return type(pos) == "function" and pos() or pos
  end
  local seek_ph = 0
  return M.seqStep({
    M.driveUntil(function() return st() == ST_MAIN end, 1200,
      { M.pressButtons({ "x" }, 4), M.waitFrames(30) }, tag .. ": main menu"),
    M.waitFrames(20),
    M.driveUntil(function()
      return st() == ST_MAIN and M.readByte(CUR) == 1
    end, 900, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": cursor on Skills"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_CHAR end, 300,
      tag .. ": character select", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_CHAR and M.readByte(CUR) == targetPos()
    end, 600, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": character cursor"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_SKILLS end, 300,
      tag .. ": skills submenu", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_SKILLS and M.readByte(CUR) == 0
    end, 600, { M.pressButtons({ "up" }, 2), M.waitFrames(6) },
      tag .. ": cursor to Espers"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_LIST end, 300,
      tag .. ": esper list", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_LIST
         and M.readByte(GENJULIST + M.readByte(CUR)) == esperIdx
    end, 3000, {
      M.call(function()
        seek_ph = (seek_ph + 1) % 8
        if seek_ph >= 4 then M.setPad({}); return end
        local target
        for r = 0, 26 do
          if M.readByte(GENJULIST + r) == esperIdx then target = r; break end
        end
        if not target then M.setPad({}); return end
        local row = M.readByte(CUR)
        local d = target - row
        if d % 2 ~= 0 then
          if row % 2 == 0 then
            M.setPad(row >= 26 and { up = true } or { right = true })
          else
            M.setPad({ left = true })
          end
        else
          M.setPad(d > 0 and { down = true } or { up = true })
        end
      end),
      M.waitFrames(1),
    }, tag .. ": list cursor on the stone"),
    M.waitFrames(20),
    M.driveUntil(function() return st() == ST_DETAIL end, 600,
      { M.pressButtons({ "a" }, 3), M.waitFrames(12) }, tag .. ": detail"),
    M.waitFrames(20),
    M.pressButtons({ "a" }, 3),          -- MenuState_4d @5902: equip esper
    M.waitUntil(function() return st() == ST_LIST end, 300,
      tag .. ": equipped, back on the list", 5),
    M.driveUntil(function() return M.hasControl() end, 1200,
      { M.pressButtons({ "b" }, 3), M.waitFrames(20) }, tag .. ": back out"),
    M.waitFrames(20),
  })
end

-- M.equipWeapon: put a specific item in one gear slot of the character
-- at char-select position `pos`, through the real Equip menu.  States
-- (equip.asm): $36 options (cursor 0 = Equip) -> $55 slot select (default
-- slot 0 = R-Hand) -> $57 item select, whose list rows at $7e9d8a are bag
-- indexes into $1869 (MenuState_57 @992d reads that), so the seek
-- compares the item id under the cursor rather than guessing a row.  The
-- list is pre-filtered by GetValidEquip, so an un-equippable item makes
-- the seek time out rather than equip something else.
--
-- opts.slot names the slot, 0..5 = R-Hand, L-Hand, Helmet, Armor, Relic 1,
-- Relic 2, and it defaults to 0.  The slot list is one vertical column and
-- the cursor lands on row 0, so the seek is that many DOWN presses, read
-- back off the same cursor byte the character and item seeks use rather
-- than counted blind.  The name still says weapon because that is what it
-- is nearly always used for; the slot is the exception.
--
-- One hazard the slot opens up: equipping a Genji Glove, Gauntlet or Merit
-- Award into a relic row makes the game run Optimum on its own when the
-- Relic screen is backed out of.  Those three are the whole list, so any
-- other relic is safe here; a caller that wants one of them owes the
-- deliberate re-equips afterwards.
--
-- The game's own Optimum picks by attack power alone, with no element
-- awareness, so it can arm a character with a weapon whose element the
-- target absorbs.  An element-aware weapon swap is ordinary fight
-- preparation, and this function is where an input-driven route makes it.
function M.equipWeapon(pos, itemId, opts)
  opts = opts or {}
  local slot = opts.slot or 0
  local tag = opts.tag or string.format("equip %02X slot %d", itemId, slot)
  -- Two cursors, not one.  $4b carries the main menu, the character list and
  -- the item list; the SLOT list is its own cursor at $4e (MenuState_55 and
  -- MenuState_5a both save z4e into z5f, equip.asm:1758, :3005).  Reading
  -- $4b for the slot row is a seek that never arrives.
  local ZM, CUR, SLOTCUR = 0x26, 0x4b, 0x4e
  local ST_MAIN, ST_CHAR = 0x05, 0x06
  -- The Equip menu holds four slots and the two relic rows are a different
  -- menu with its own states, so which menu this walks is decided by the
  -- slot number.  EquipSlotCursorPos has exactly four entries
  -- (equip.asm:79-84) -- R-Hand, L-Hand, Helmet, Armor -- and the relics are
  -- main-menu row 3 (SelectMainMenuOptionTbl, field_menu.asm:3420-3428:
  -- Item, Skills, Equip, Relic, Status, Config, Save), whose Equip option is
  -- likewise cursor 0 (SelectRelicOptionTbl, equip.asm:2910-2912).  Past
  -- that the two walks are the same shape: options -> slot -> item, and the
  -- item list rows are bag indexes at $7e9d8a either way.
  local relic = slot >= 4
  local MAINROW = relic and 3 or 2
  local ST_OPT = relic and 0x59 or 0x36
  local ST_SLOT = relic and 0x5a or 0x55
  local ST_ITEM = relic and 0x5b or 0x57
  local slotRow = relic and (slot - 4) or slot
  local function st() return M.readByte(ZM) end
  local function targetPos()
    return type(pos) == "function" and pos() or pos
  end
  return M.seqStep({
    M.driveUntil(function() return st() == ST_MAIN end, 1200,
      { M.pressButtons({ "x" }, 4), M.waitFrames(30) }, tag .. ": main menu"),
    M.waitFrames(20),
    M.driveUntil(function()
      return st() == ST_MAIN and M.readByte(CUR) == MAINROW
    end, 900, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": cursor on the menu row"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_CHAR end, 300,
      tag .. ": character select", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_CHAR and M.readByte(CUR) == targetPos()
    end, 600, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": character cursor"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_OPT end, 600,
      tag .. ": equip options", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_OPT and M.readByte(CUR) == 0
    end, 600, { M.pressButtons({ "left" }, 2), M.waitFrames(10) },
      tag .. ": cursor on the Equip option"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_SLOT end, 300,
      tag .. ": slot select", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_SLOT and M.readByte(SLOTCUR) == slotRow
    end, 600, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": slot cursor"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_ITEM end, 300,
      tag .. ": item list", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_ITEM
         and M.readByte(0x1869 + M.readByte(0x9d8a + M.readByte(CUR)))
             == itemId
    end, 1800, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": list cursor on the item"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_SLOT end, 300,
      tag .. ": equipped, back on slots", 5),
    M.driveUntil(function() return M.hasControl() end, 1200,
      { M.pressButtons({ "b" }, 3), M.waitFrames(20) }, tag .. ": back out"),
    M.waitFrames(20),
  })
end

-- M.equipLoadout: equip one named character by item, never by Optimum.
-- `items` is an ordered list of `{ slot, item }` pairs, where slot 0..5 is
-- R-Hand, L-Hand, Helmet, Armor, Relic 1, Relic 2.  The character-select
-- row is read from the live party record after the run starts, so callers
-- name the character rather than assuming a party order.  An item already
-- in its intended slot is a no-op; every other item must be in the bag or
-- the run fails before opening a menu whose list can never find it.
--
-- This is the deliberate counterpart to the game's own Equip -> Optimum.
-- A route states the loadout it wants and why at the call site; this helper
-- only makes that decision resilient to an upstream step having already
-- equipped part of it.
function M.equipLoadout(charId, items, opts)
  opts = opts or {}
  local tag = opts.tag or string.format("character %d loadout", charId)
  local base = 0x1600 + 37 * charId
  local pos
  local steps = {
    M.call(function()
      local partyByte = M.readByte(0x1850 + charId)
      local active = M.readByte(0x1A6D) & 0x07
      M.assertEq(partyByte & 0x07, active,
        tag .. ": character is in the active party")
      pos = (partyByte >> 3) & 0x03
      M.log(string.format("[%s] char=%d row=%d before=%02X %02X %02X %02X %02X %02X",
        tag, charId, pos, M.readByte(base + 0x1F), M.readByte(base + 0x20),
        M.readByte(base + 0x21), M.readByte(base + 0x22),
        M.readByte(base + 0x23), M.readByte(base + 0x24)))
    end),
  }
  for _, spec in ipairs(items) do
    local slot, item = spec[1], spec[2]
    steps[#steps + 1] = M.cond(function()
      if M.readByte(base + 0x1F + slot) == item then return false end
      M.assertEq(M.invCountOf(item) > 0, true, string.format(
        "%s: item $%02X for slot %d is in the bag", tag, item, slot))
      return true
    end, {
      M.equipWeapon(function() return pos end, item,
        { slot = slot, tag = string.format("%s slot %d item $%02X", tag, slot, item) }),
    }, {})
  end
  steps[#steps + 1] = M.call(function()
    for _, spec in ipairs(items) do
      local slot, item = spec[1], spec[2]
      M.assertEq(M.readByte(base + 0x1F + slot), item, string.format(
        "%s: slot %d holds item $%02X", tag, slot, item))
    end
    M.log(string.format("[%s] char=%d after=%02X %02X %02X %02X %02X %02X",
      tag, charId, M.readByte(base + 0x1F), M.readByte(base + 0x20),
      M.readByte(base + 0x21), M.readByte(base + 0x22),
      M.readByte(base + 0x23), M.readByte(base + 0x24)))
  end)
  return M.seqStep(steps)
end

-- ------------------------------------------- South Figaro shared toolkit --
-- gen_sfigaro and gen_tunnelarmr both walk occupied South Figaro.

-- field object i's live tile (pixel coords >> 4, block stride $29), the
-- same read chaseTalk does internally; public because NPC positions are
-- route inputs (the gate soldier's post is the branch condition below)
function M.objX(i) return M.readWord(0x086a + 0x29 * i) >> 4 end
function M.objY(i) return M.readWord(0x086d + 0x29 * i) >> 4 end

-- party facing, through the party-object offset ($0803)
local function partyFacing() return M.readByte(0x087f + M.readWord(0x0803)) end
local TALK_FACE = { up = 0, right = 1, down = 2, left = 3 }
local TALK_NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function swv(id)
  return (M.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); M.cond with an always-true
-- predicate is the library's public way to wrap a list into one step
local function seq(steps) return M.cond(function() return true end, steps) end

-- Talk to a posted NPC: approach re-resolved from live object coords (NPCs
-- wander), facing computed from the live delta, soft rounds before a hard
-- one.  CheckNPCs activates whatever the object map
-- holds one tile in the party's facing direction while A is held, and a
-- two-frame turn press does not set the facing byte, so the direction is
-- held until it reads back, and only then is A edge-tapped.
-- (M.chaseTalk above is the wandering-NPC variant with a choice-prompt
-- terminator; this one is for posted NPCs and terminates on engagement.)
function M.talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return M.objX(obj), M.objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - M.fieldX()) + math.abs(oy - M.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if M.frame - apFrame >= 30 then
      apFrame = M.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(TALK_NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if M.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return M.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000, playBattles = true,
      arrive = function()
        return engaged or (adjacent() and M.hasControl() and M.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return M.driveUntil(function()
      started = (M.eventRunning() or M.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      M.call(function()
        aPh = (aPh + 1) % 8
        if not (M.hasControl() and M.tileAligned() and adjacent()) then
          M.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - M.fieldX(), oy - M.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if partyFacing() ~= TALK_FACE[dir] then
          M.setPad({ [dir] = true }); return
        end
        M.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    M.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    -- flat, not repeatN: it cannot replay navTo/driveUntil bodies
    M.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    M.release(),
  })
end

-- Ride a scene out to a settled, controllable field, edge-tapping A on
-- every frame the party is not in control and fighting anything that comes
-- up by real input.  Battle frames drive gen_moogle's Marshal cycle: R
-- raises the active character's pending boost (Ot6InitBP; the R does
-- nothing on an empty bank), then three edge-tapped A's confirm the
-- boosted Fight and page victory text.
--
-- advanceStory does not work here: it taps A only while a battle is up or
-- M.dialogWaiting() is true, and holds the pad empty otherwise, but the
-- tail of a scripted battle can leave a menu module owning the CPU with
-- neither signal set, which advanceStory cannot see.  Tapping A whenever
-- there is no control clears it, and it cannot misfire on the open field
-- because the tap is gated on not having control.  (This must never meet
-- a choice prompt, because an A press always takes option 0, so every
-- prompt on a route is answered by a choice-steering rider instead.)
--
-- The fight itself reads the live command table (M.newFightDriver) rather
-- than driving a fixed button pattern, so it can boost, use items, and
-- decide per-turn whether a heal is worth the turn it costs
-- (M.healDecision) instead of always drinking.
function M.rideOut(what, budget, dstMap)
  local phase, calm = 0, 0
  local F = M.newFightDriver(what or "rideOut",
    -- bank = 3: unboosted Fights until the actor has three BP, then spend
    -- them.  Shielded damage is halved and a broken monster takes 4x
    -- (Ot6ShieldedMulW, ot6_break.asm:1487-1497), so the fight is won by
    -- breaking the shield rather than by chipping, and a boosted Fight is
    -- what chips.
    { tactical = true, boost = true, bank = 3, items = true,
      healPercent = 60, cadence = 12 })
  return seq({
    M.driveUntil(function()
      local ok = M.hasControl() and M.tileAligned()
             and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
             and not M.battleLoadStarted() and not M.dialogWaiting()
             and (dstMap == nil or (M.mapId() & 0x1ff) == dstMap)
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, budget or 30000, {
      M.call(function()
        phase = (phase + 1) % 8
        if M.battleLoadStarted() then
          F.frame()
          return
        end
        F.idle()
        if M.hasControl() then M.setPad({}); return end
        M.setPad(phase < 4 and { "a" } or {})
      end),
    }, what),
    M.release(),
    M.waitFrames(30),
    -- heal-after-every-battle: rideOut exists to ride scripted battles, so
    -- its settle is the canonical place to recover before the next beat
    M.careStop("care after battle (" .. (what or "rideOut") .. ")"),
  })
end

-- The gate soldier comes back every time map 75 reloads: leaving town for
-- an interior and coming back re-runs InitNPCs and re-creates every npc
-- whose spawn switch still holds (his is $030C, and nothing in the
-- scenario clears it).  So (30,42), the only tile joining the SE quarter
-- to the rest of town, is blocked again on every return.  The branch is
-- gated on a symptom (a BFS probe to a tile on the far side) rather than
-- assumed, so if the respawn ever stops happening this reports it instead
-- of walking into a fight that is not there.
--
-- Every engagement is a retry sequence.  A lost battle 11 revives LOCKE on
-- (47,43) and clears both disguise switches, so each fight captures a blob
-- first, and a loss reloads it and re-engages on a different battle RNG
-- phase.  The seed is the game-time frame counter at battle init, so the
-- ladder is spread on that counter and reads back what each attempt drew
-- rather than trusting a frame offset to land somewhere new.  Success
-- means the party is not on the opening tile and the probe tile is
-- reachable; three losses fail generation.
--
-- The ladder is per call, not per run: gen_sfigaro crosses this boundary
-- three times and each crossing is its own three fights.
function M.clearGateSoldier(probeX, probeY, tag)
  local blob, won = nil, false
  local L = M.newSeedLadder((tag or "gate soldier") .. " battle 11")
  local function fightOnce(n)
    local loadReq
    return M.cond(function() return won end, {}, {
      M.logStep(function()
        return string.format("%s: battle 11 attempt %d at f%d", tag, n, M.frame)
      end),
      n > 1 and seq({
        M.call(function() loadReq = M.requestLoadState(blob) end),
        M.waitFrames(2),
        M.call(function() M.checkReq(loadReq, tag .. ": pre-fight reload") end),
        M.waitFrames(90),
      }) or seq({}),
      -- attempt 1 needs a phase of its own too, or it can land on attempt
      -- 2's seed
      L.spread(n),                       -- spread the battle RNG phase
      M.talkToObj(26, tag .. ": the gate soldier (battle 11)"),
      M.rideOut(tag .. ": ride battle 11 out", 30000, 75),
      M.call(function()
        -- The battle's own verdict, read directly.  Field byte $1DD1 bit 0
        -- = 1 means THIS battle was lost; position and the reachability
        -- probe are logged for the record but decide nothing.
        won = (M.readByte(0x1DD1) & 1) == 0
        M.log(string.format(
          "%s: attempt %d %s ($1DD1.0=%d) at (%d,%d) f%d, probe=%s",
          tag, n, won and "WON" or "LOST (scenario reset)",
          M.readByte(0x1DD1) & 1, M.fieldX(), M.fieldY(), M.frame,
          tostring(M.bfsPath(probeX, probeY) ~= nil)))
      end),
    })
  end
  -- He does not step off the choke point, so the fight is mandatory.
  --
  -- He blocks exactly one tile: npc 10 / obj 26 sits at {30,42},
  -- spawn switch $030C, and (30,42) is the only tile joining the starting
  -- pocket to the rest of town.  So the branch reads where he is.  Once
  -- beaten, the object is gone and this reads something other than his
  -- post; while he is standing there it reads {30,42} whatever the object
  -- map happens to be doing that frame.
  return M.cond(function() return M.objX(26) == 30 and M.objY(26) == 42 end, {
    M.logStep(function()
      return string.format("%s: the gate soldier is on his post (%d,%d) " ..
        "at f%d; fighting him", tag, M.objX(26), M.objY(26), M.frame)
    end),
    -- Heal first.  He respawns on every map-75 reload, so a route can
    -- fight him more than once, arriving at a later one with whatever HP
    -- the earlier fights left.  A no-op when he is already at full HP, and
    -- it never spends below the Potion floor the later beats need.
    M.fieldCare({ tag = "care before " .. tag, threshold = 0.95 }),
    (function()
      local req
      return seq({
        M.call(function() req = M.requestSaveState() end),
        M.waitFrames(2),
        M.call(function()
          M.checkReq(req, tag .. ": retry blob")
          blob = req.blob
        end),
      })
    end)(),
    L.watch(),
    fightOnce(1), fightOnce(2), fightOnce(3),
    -- ...and they were three DIFFERENT fights: distinct battle RNG seeds,
    -- read off the seeder itself.  "Three losses fail generation" only
    -- means something if the three were not one fight replayed.
    L.report(),
    M.call(function()
      M.assertEq(won, true,
        tag .. ": battle 11 won within 3 attempts (boosted Fights)")
      M.assertEq(M.bfsPath(probeX, probeY) ~= nil, true,
        tag .. ": the lane is open again")
    end),
  }, {
    M.logStep(function() return tag .. ": the lane is already open" end),
  })
end

-- ---------------------------------------------------------------- saveGame --
-- Save the game through the real Save UI, as a step: open the menu (X),
-- cursor to the Save row, pick a slot, confirm, verify with the
-- CopyGameDataToSRAM exec hook plus SRAM $307ff0, and close back out.
-- Works anywhere the game itself allows saving -- a save-point tile
-- ($01BF set by the shared SavePoint script) or the world map -- and
-- asserts $0201 bit7 (the menu's own save-enable) rather than guessing.
--
-- This exists so story generators can save at the save points they pass,
-- the way a person plays.  Battery SRAM rides inside .mss savestates, so
-- a later `gen_seed_*` cutter can boot the segment's state and let
-- run.sh's OT6_CAPTURE_SRM lift the battery -- the seed is the save made
-- here, with no replay and no navigation in the cutter.
--
-- opts: slot (1-3, default 3), tag, maxFrames (whole drive, default 4000).
function M.saveGame(opts)
  opts = opts or {}
  local slot = opts.slot or 3
  local tag = opts.tag or ("save slot " .. slot)
  local ZMENUSTATE, SAVE_SELECT = 0x26, 0x14
  local saveArg = nil
  local function menuOpen() return M.readByte(0x59) ~= 0 end
  return M.seqStep({
    -- open the menu; on the world map $59 rides the same flow
    (function() local calm, ph = 0, 0
      return M.driveUntil(function()
        calm = (menuOpen() and M.readByte(ZMENUSTATE) == 0x05) and calm + 1 or 0
        return calm >= 20
      end, opts.maxFrames or 4000, {
        M.call(function()
          ph = (ph + 1) % 48
          -- the first save point a save ever meets runs the SavePoint
          -- tutorial dialog ($0133); page it before pressing X, or the
          -- press lands in a dialog and the menu never opens
          if M.dialogWaiting() then
            M.setPad(ph % 8 < 4 and { "a" } or {}); return
          end
          if menuOpen() then M.setPad({}); return end
          M.setPad(ph < 6 and { "x" } or {})
        end),
      }, tag .. ": main menu open")
    end)(),
    M.waitFrames(20),
    M.call(function()
      M.assertEq((M.readByte(0x0201) & 0x80) ~= 0, true,
        tag .. ": $0201 bit7 SET -- the game allows saving here")
      local entry = M.sym("CopyGameDataToSRAM")
      emu.addMemoryCallback(function()
        saveArg = emu.getState()["cpu.a"] & 0xff
      end, emu.callbackType.exec, entry, entry)
    end),
    M.driveUntil(function()
      return M.readByte(ZMENUSTATE) == 0x05 and M.readByte(0x4b) == 6
    end, 600, {
      M.pressButtons({ "up" }, 4), M.waitFrames(16),
    }, tag .. ": cursor on Save"),
    M.pressButtons({ "a" }, 4),
    M.waitUntil(function() return M.readByte(ZMENUSTATE) == SAVE_SELECT end,
      600, tag .. ": save-slot selection", 5),
    M.driveUntil(function()
      return M.readByte(ZMENUSTATE) == SAVE_SELECT
         and M.readByte(0x4b) == slot - 1
    end, 600, {
      M.pressButtons({ "down" }, 4), M.waitFrames(16),
    }, tag .. ": cursor on the slot"),
    M.driveUntil(function()
      return saveArg == slot
         and emu.read(0x307ff0, emu.memType.snesMemory) == slot
    end, 1800, {
      M.pressButtons({ "a" }, 4), M.waitFrames(20),
    }, tag .. ": CopyGameDataToSRAM ran (exec hook + $307ff0)"),
    M.waitFrames(90),
    M.call(function()
      M.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), slot,
        tag .. ": SRAM $307ff0 records the slot")
      M.assertEq(emu.read(0x316800 - 0xb00 * (3 - slot), emu.memType.snesMemory)
        ~= nil, true, tag .. ": slot region readable")
      M.log(string.format("[%s] real Save UI wrote slot %d", tag, slot))
    end),
    -- close the menu; field and world settle differently, so accept either
    (function() local calm = 0
      return M.driveUntil(function()
        local closed = not menuOpen()
        local settled = M.worldMode() and M.worldHasControl()
            or (M.hasControl() and M.tileAligned())
        calm = (closed and settled) and calm + 1 or 0
        return calm >= 20
      end, 1200, {
        M.pressButtons({ "b" }, 4), M.waitFrames(20),
      }, tag .. ": menu closed")
    end)(),
    M.waitFrames(30),
  })
end
