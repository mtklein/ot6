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
      .. 'A-taps; declare playBattles="tactical" (or "mustflee") on this step')
    M._killbitFired = true
  end
end

-- How long playBattles="flee" holds L+R before it accepts that this
-- formation is not going to release the party and fights the battle out
-- instead; 1800 frames is 30 seconds.  Navigators accept opts.fleeCap to
-- shorten the cap per route.
M.FLEE_CAP = 1800

-- True while the battle module's party table is live and it reads as a
-- lost fight (#166).  $1600 (the field's own character table, checked by
-- M.partyWiped) never reports a death that occurs inside a battle: it is
-- synced back from the battle module's own table only at teardown, and a
-- wipe tears down straight into the Game Over.
--
-- Which of the four battle slots seat a party member is the engine's own
-- reading: the actor table, $3ed8 + 2*slot (InitParty writes the actor
-- number there and $ff for an empty seat; the leave paths write $ff back),
-- AND the seat's "target present" bit, $3aa0 + 2*slot bit 0, which
-- InitParty sets only for an actor who is IN the party -- never a head
-- count of $1850.  The old scan counted every slot with a plausible max HP
-- and compared against $1850's count.  Measured (probe_wipe166.lua,
-- 2026-09-07): a Veldt random from falls_done seats SABIN and CYAN in 0/1
-- and, in seat 2, actor 11 -- GAU, the formation's hidden character AI,
-- 394/394 HP, present bit clear, absent from the engine's alive mask
-- ($3a74=$03) -- so the real two-character wipe read [0/363 0/358 394/394
-- 0/0] (gau_joined's, the #163 audit) with the 394 counted as a survivor;
-- and the Narshe descent marks seven members in $1850 for a battle that
-- seats three, which the `want <= 4` clause turned into "never wiped".
--
-- Two readings of the same fact, either one is the verdict (M.wipeVerdict):
-- the present seats' HP words all 0, and LoseBattle's own flag, $3ebc bit 0
-- ("game over after battle ends", battle_main.asm LoseBattle; cleared by
-- InitBattle's `lda #$91 / trb $3ebc`), which CheckBattleEnd sets the
-- moment its alive mask $3a74 reads 0 -- up to a couple of hundred frames
-- after the last HP word does (UpdateDead runs at action resolution;
-- measured +212 on KEFKA), and also for a party that is all petrified or
-- zombied, which no HP scan can see.  The table's shape (actor bytes $ff or
-- 0..15, a plausible max HP behind every present seat) is what says the
-- battle module owns these bytes; other modules write over them.
function M.partyWipedInBattle()
  local rows = {}
  for e = 0, 3 do
    rows[e + 1] = { actor = M.readByte(0x3ed8 + e * 2),
                    present = (M.readByte(0x3aa0 + e * 2) & 1) == 1,
                    hp = M.readWord(0x3bf4 + e * 2),
                    maxhp = M.readWord(0x3c1c + e * 2) }
  end
  return M.wipeVerdict(rows, M.readByte(0x3ebc))
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
-- can't-run flag; while it is held, holding L+R is free damage with no
-- roll behind it, so the fight is handed to the tactical driver early
-- instead.  The periodic log line reports the engine's own run machinery:
--   $2f45  characters-are-running (set while L+R is held and unblocked)
--   $3a3b  run difficulty: 2 per live monster, 6 for a harder-to-run one
--   $3d70  per-character run counter, +rand(run factor)+1 per check; the
--          character escapes once it reaches the difficulty
--   $b1    bit 1 can't-run, bit 2 the smoke-bomb can't-run, bit 5 back
--          attack/pincer, bit 0 the counterattack flag (flickers on)
--   $2f4b  bit 0 the formation's own "no running with L+R"
--   $7EE9EF / $7E629A  battle time stopped / menus force-closed, either of
--          which suppresses $2f45 outright
--
-- Which $b1 bit (#150, read from battle_main.asm and then measured):
-- bit 1 ($02) is the gate the ESCAPE COMMAND itself tests -- Cmd_2a
-- `lda $b1 / bit #$02 / bne` queues battle message $09 "can't run
-- away!!", and GlobalCounter_05 fires that command the moment L+R is
-- seen while the bit is up.  It is set by UpdateMonsterGfxBuf for a
-- pincer with monsters alive on both sides (`lda #$02 / tsb $b1`), for a
-- present monster whose monster_prop +19 bit 3 says no running (`lda
-- #$06 / tsb $b1`, so bit 2 comes up with it), and while enemy
-- characters are alive ($3a42).  Bit 2 ($04) is read only by the smoke
-- bomb (AttackerEffect_4b).  "Harder to run" is not a $b1 bit at all: it
-- is monster_prop +19 bit 0, which adds 6 instead of 2 to $3a3b.  So the
-- 15609 comment "clear can't run flag and harder to run flag" for #$06
-- does not mean bit 1 is the soft one, and CANT_RUN stays $02.
-- Measured (probe_flee_world.lua, camp_escaped, two world-map randoms):
-- $b1 read 00, L+R was held from battle frame 3, $2f45 went 1, $3a38
-- latched "a character just ran away" at frames 243 and 371, and both
-- fights ended with the party gone and the monsters alive.  On the FC
-- escape map 393 the one formation is Naughty ($169, +19 = $8D: bit 3
-- no-run AND bit 0 harder-to-run), so $b1 reads $06 from frame 3 and the
-- helper's refusal there was the engine's own answer, not a wrong bit;
-- Vargas ($3c88 = $DD) refuses the same way (probe_flee_boss.lua).
-- The formation flag $2f4b bit 0 is a refusal as well: btlgfx escape_set
-- never raises $2f45 while it is up, so holding L+R there is the cap's
-- worth of free damage (asm-derived; no fixture on the route carries it).
local CANT_RUN = 0x02           -- $b1 bit 1
local NO_LR_RUN = 0x01          -- $2f4b bit 0
local REFUSAL_FRAMES = 60       -- consecutive frames of it before believing it

local function newFlee(opts, tactical)
  local cap = opts.fleeCap or M.FLEE_CAP
  local refusedN, said = 0, false
  -- battN is the caller's per-battle counter and it is 3 on the first frame
  -- that reaches here, so that value is the new-battle edge.
  return function(battN)
    if battN <= 3 then refusedN, said = 0, false end
    local refused = (M.readByte(0x00b1) & CANT_RUN) ~= 0
                 or (M.readByte(0x2f4b) & NO_LR_RUN) ~= 0
    refusedN = refused and refusedN + 1 or 0
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
        M.log(string.format("flee: this formation refuses the run ($b1=%02X " ..
          "$2f4b=%02X held %d frames -- $b1 bit 1 is the escape command's " ..
          "own can't-run gate: a pincer, enemy characters, or a monster " ..
          "nobody runs from; $2f4b bit 0 the formation's no-L+R flag) after " ..
          "%d frames; fighting it out instead of standing still for the cap",
          M.readByte(0x00b1), M.readByte(0x2f4b), refusedN, battN))
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

-- M.fightDriverFor(tag, base, fight): M.newFightDriver(tag, base merged
-- with fight).  Every walker in this file that builds a fight driver
-- (navTo, advanceStory, worldNavTo, phaseWalk, newWalkFighter, rideOut,
-- and through them crossDoor, the shop walk and fieldCare) takes a
-- `fight = { ... }` table and builds its driver here, so any driver option
-- (focus, keyed, tools, traceTgt, cure, spend, ...) reaches the driver
-- without the walker naming it.
--
-- Precedence: the walker's own named options (healPercent, bank, reserve,
-- healer, magic, summon, nuke, nukeLore, tool, blitz, and their defaults)
-- build `base` exactly as before; a key present in `fight` overrides that
-- key of `base`.  A `fight` that is not a table (fieldCare's own
-- `fight = false` switch) adds nothing.
--
-- A function-valued entry is a live option: it is called as fn(tag, memo)
-- before every F.frame() and its result is written to that key of the
-- options table the driver reads (nil clears it), so the value can follow
-- the stage frame by frame (a kill order recomputed from the live slots).
-- It reads nil until the driver's first frame.  `memo` is a table private
-- to this driver, emptied on every F.idle(), for a caller that wants
-- per-battle state (a log line said once per battle).
function M.fightDriverFor(tag, base, fight)
  local o, live = {}, nil
  for k, v in pairs(base or {}) do o[k] = v end
  if type(fight) == "table" then
    for k, v in pairs(fight) do
      if type(v) == "function" then
        live = live or {}
        live[k] = v
        o[k] = nil
      else
        o[k] = v
      end
    end
  end
  local F = M.newFightDriver(tag, o)
  if live then
    local memo = {}
    local frame, idle = F.frame, F.idle
    F.frame = function(...)
      for k, fn in pairs(live) do o[k] = fn(tag, memo) end
      return frame(...)
    end
    F.idle = function(...)
      for k in pairs(memo) do memo[k] = nil end
      return idle(...)
    end
  end
  return F
end

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
--   opts.fight     a table merged over the tactical driver's options, key
--                  by key, after the named ones above (M.fightDriverFor:
--                  focus, keyed, tools, traceTgt, ...; function entries
--                  are re-read every battle frame)
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
      and M.fightDriverFor("navTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          summon = opts.summon, nuke = opts.nuke, nukeLore = opts.nukeLore,
          tool = opts.tool, blitz = opts.blitz,
          cadence = opts.cadence }, opts.fight) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  -- the heal-after-every-battle directive: once a mid-walk battle
  -- resolves, run a between-battles care stop (M.newCareDriver, soft)
  -- before walking on, so the next fight starts whole.  opts.care=false
  -- opts out; a live event timer opts the scene out automatically.
  local careD, sawBattle, fought = nil, false, nil
  local function drop(why)  -- discard the plan, logging why once, not per frame
    if plan or pend then
      M.log(string.format("nav: %s at (%d,%d); plan dropped", why,
        M.fieldX(), M.fieldY()))
    end
    plan, pend = nil, nil
    NAV.plan, NAV.idx = 0, 0
  end
  return M.withReset(M.driveUntil(function()
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
      -- forensics (once per battle): the tile the party stood on when the
      -- battle came up, its props and its neighbours', and the event script
      -- pointer -- the shape of the $ca0029 stall (a battle starting while a
      -- step is resolving on z-flux tiles) is a black screen with the battle
      -- RAM populated, and these are what decide it (fire_out, run.IgBKYd89)
      if battN == 1 then
        local x, y = M.fieldX(), M.fieldY()
        local function pp(dx, dy)
          local t = M.maptile(x + dx, y + dy)
          return string.format("%02X/%02X", M.readByte(0x7E7600 + t), M.readByte(0x7E7700 + t))
        end
        M.log(string.format("nav: battle up at (%d,%d) $b2=%02X tile=%s N=%s S=%s W=%s E=%s evpc=%02X%02X%02X $57=%02X",
          x, y, M.readByte(0x00b2), pp(0, 0), pp(0, -1), pp(0, 1), pp(-1, 0), pp(1, 0),
          M.readByte(0x00e7), M.readByte(0x00e6), M.readByte(0x00e5), M.readByte(0x0057)))
      end
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      -- diagnostic (once per episode): a dialog with monsters on screen and
      -- the battle detector DOWN is the shape of the regen's fire_out stall
      -- (a Balloon touch-battle A-tapped as a dialog, never fought)
      if dlgN == 3 and battN == 0 and M.monstersPresent() > 0 then
        M.log(string.format("nav: dialog with %d monster(s) present and battleLoadStarted()=false: hp=%d,%d,%d,%d $ba=%02X $d3=%02X",
          M.monstersPresent(), M.readWord(M.BATTLE_HP), M.readWord(M.BATTLE_HP + 2),
          M.readWord(M.BATTLE_HP + 4), M.readWord(M.BATTLE_HP + 6), M.readByte(0x00ba), M.readByte(0x00d3)))
      end
      lostN = M.hasControl() and 0 or lostN + 1
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it, but never the goal formation
      if battN >= 3 then
        sawBattle = true
        fought = M.readByte(0x1A6D) & 0x07
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
            'drags, convert it: playBattles="tactical" (or "mustflee" to run).')
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
            party = fought, tag = "care after battle (navTo)" })
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
  }, "navTo"), function()
    -- back to as-built (#196): a repeated navTo re-plans from where it
    -- stands with its whole walk budget, forgets a wipe or a care stop
    -- the last pass ended on, and starts the blocklist over as a fresh
    -- call would (M.navReset above).  The fight driver is kept: its
    -- per-battle state is its own, cleared through idle() between fights.
    M.navReset()
    walked, plan, idx, pend, aPhase, calm = 0, nil, 1, nil, 0, 0
    battN, dlgN, lostN, noPathN, pause = 0, 0, 0, 0, 0
    wipeSeen, careD, sawBattle, fought = false, nil, false, nil
  end)
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
-- The tactical driver's options are navTo's (healPercent, bank, ..., and
-- opts.fight merged over them: M.fightDriverFor).
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
      and M.fightDriverFor("advanceStory",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          summon = opts.summon, nuke = opts.nuke, nukeLore = opts.nukeLore,
          tool = opts.tool, blitz = opts.blitz }, opts.fight) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  -- heal-after-every-battle: see navTo's care block; same contract here
  local careD, sawBattle, fought = nil, false, nil
  local hb = -600                      -- heartbeat: log immediately, then every 600
  return M.withReset(M.driveUntil(function()
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
          fought = M.readByte(0x1A6D) & 0x07
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
            'drags, convert it: playBattles="tactical" (or "mustflee" to run).')
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
      -- never returns control leaves the latch armed; the caller's
      -- own care stop then owns it.
      if sawBattle and M.hasControl() and M.tileAligned() then
        sawBattle = false
        if opts.care ~= false and not M.eventTimerLive() then
          careD = M.newCareDriver({
            threshold = opts.careThreshold or 0.65, reserve = opts.reserve,
            party = fought, tag = "care after battle (advanceStory)" })
          careD.frame()
          if not careD.done() then return end
          careD = nil
        end
      end
      M.setPad({})
    end),
  }, "advanceStory"), function()
    -- as-built (#196): a wipe or a care stop the last pass ended on must
    -- not end the next pass on its first frame
    aPhase, battN, dlgN, hb = 0, 0, 0, -600
    wipeSeen, careD, sawBattle, fought = false, nil, false, nil
  end)
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
--   opts.fight     the tactical driver's option table, merged over the
--                  named options (M.fightDriverFor), as navTo's.
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
      and M.fightDriverFor("worldNavTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          summon = opts.summon, nuke = opts.nuke, nukeLore = opts.nukeLore,
          tool = opts.tool, blitz = opts.blitz }, opts.fight) or nil
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
  return M.withReset(M.driveUntil(function()
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
            'drags, convert it: playBattles="tactical" (or "mustflee" to run).')
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
  }, "worldNavTo"), function()
    -- as-built (#196): see navTo's reset; the blocklist here is per call
    blocked, nblocked, plan, idx, pend = {}, 0, nil, 1, nil
    aPhase, battN, walked, hb = 0, 0, 0, -600
    wipeSeen, careD, sawBattle = false, nil, false
  end)
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
--   maxFrames, what             -- optional; driveUntil internals
--   healPercent, fight          -- optional; the encounter driver's heal
--                               -- threshold (55) and an option table
--                               -- merged over it (M.fightDriverFor)
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

  -- Encounters are fought by the library fighter (#183: they were fled
  -- with L+R, which the no-effect watchdog now names a stall -- the
  -- gate-cave regen spent two of three attempts on it), the party is
  -- healed outside battle once it stands on a safe tile, and a wipe is
  -- named a wipe.
  local wipeCheck = wipeCanary("phaseWalk")
  local tactical = M.fightDriverFor("phaseWalk",
    { tactical = true, boost = true, items = true,
      healPercent = spec.healPercent or 55 }, spec.fight)
  local sawBattle, careD = false, nil

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

  return M.withReset(M.driveUntil(function()
    return not M.battleLoadStarted()
       and M.fieldX() == tx and M.fieldY() == ty and M.tileAligned()
  end, spec.maxFrames or 30000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      wipeCheck()
      -- a between-battles care stop in progress owns the pad
      if careD then
        if careD.done() then
          careD = nil
          -- the menu stopped the field module: observe the clock afresh
          grids, lastFlip, lastB, hp0, obsStart = {}, nil, nil, nil, nil
        else
          careD.frame(); return
        end
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
      if battN >= 3 then
        if plan or lastFlip then
          M.log(string.format("[phaseWalk] encounter at f%d -- fighting it, "
            .. "then re-observe", M.frame))
        end
        plan, grids, lastFlip, lastB = nil, {}, nil, nil
        begunSeg, hp0, obsStart = -1, nil, nil
        sawBattle = true
        tactical.frame()
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
        -- a battle just ended and the party stands on a safe tile: recover
        -- OUTSIDE combat before re-observing (heal-after-every-battle).
        -- The menu stops the field module, so the tile clock does not run
        -- under it; the clock is observed afresh once the stop is done.
        if sawBattle then
          if not (M.hasControl() and M.tileAligned()) then return end
          sawBattle = false
          if spec.care ~= false and not M.eventTimerLive() then
            careD = M.newCareDriver({
              threshold = spec.careThreshold or 0.65, reserve = spec.reserve,
              tag = "care after battle (phaseWalk)" })
            careD.frame()
            if not careD.done() then return end
            careD = nil
            grids, lastFlip, lastB, hp0, obsStart = {}, nil, nil, nil, nil
            return
          end
        end
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
  }, spec.what or string.format("phaseWalk (%d,%d)", tx, ty)), function()
    -- as-built (#196): observe the clock afresh and re-plan; a repeated
    -- walk must not trust the last pass's grids, flip instant or HP mark
    lastB, lastFlip, grids, plan, idx = nil, nil, {}, nil, 1
    begunSeg, hp0, obsStart, hb = -1, nil, nil, -300
    battN, aPhase, sawBattle, careD = 0, 0, false, nil
  end)
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
  -- the only closure state is the A cadence phase, so the driveUntil's own
  -- reset (its frame count) is all a repeat needs (#196)
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

-- ------------------------------------------------------- dialog choices --
-- A multiple-choice dialog, from the field's own cells (ff6/notes/
-- field-ram.txt:396-401, src/field/text.asm):
--   $056F  option count.  Built up as the text types out (text.asm:684
--          counts the choice indicators as they are drawn), so it is final
--          only once the dialog waits for a keypress ($D3=1, dialogWaiting);
--          zeroed by the A that confirms (text.asm:425).  Battle RAM
--          scribbles it, so it is not read while a battle is up.
--   $056E  cursor row, 0-based.  Moved only while the dialog waits; the
--          $056D latch lets a held direction move it one row, so steering
--          presses are edges.  The confirm leaves it alone; the event's
--          `choice` opcode (event.asm EventCmd_b6) branches on it and only
--          then clears it, which is after the window has closed.
--   $00D0  the dialog index (event.asm EventCmd_48/4b, already & $1FFF).
-- The row the engine took is the cursor on the last frame the window was
-- up: the A that confirms is handled after the direction branch in the
-- same frame (text.asm:368-425), and no steering press lands with an A.
--
-- M.newChoice(want, opts) -> C, the per-frame half, for a rider that
-- already owns its pad (dialog paging, battles, walking):
--   want  number                       every prompt takes that row
--         function(dlg, max, n) -> row decided live (n = 1-based prompt)
--         list                         prompt n takes want[n]: a row, or
--                                      { want = row, max = count, what = }
--                                      whose max is asserted once waiting
--   opts.extra  "error" (default): a prompt past the list raises;
--               "last": it takes the list's last entry
--   opts.ready  when the window owns the pad:
--               "waiting" (default)  from $056F >= min, pad empty until the
--                                    dialog waits, then steer
--               "count"              steer from $056F >= min (presses
--                                    before the wait are ignored by the
--                                    engine; the older generators did this)
--               "pass"               only while the dialog waits
--   opts.min      option count that means a window is up (default 2)
--   opts.inBattle gate predicate (default M.battleLoadStarted); false for
--                 none
--   opts.press(ph, kind) -> bool, kind "steer" or "confirm": the pulse
--                 (default ph < opts.on, on = 4)
--   opts.onUp(n, max, entry)  once per prompt, on its first waiting frame
--   opts.tag      prefix for error messages
-- C.frame(ph) polls and, when a window owns this frame, sets the pad and
-- returns true.  C.poll() is the observation half alone (idempotent per
-- frame): every prompt that was entered and has closed logs
--   [choice] dlg $XXXX: row N of M
-- (N 0-based, M the option count) and raises if N is not the wanted row.
-- C.n (prompts entered), C.resolved, C.last = { dlg, row, max, n }, and
-- C.history, every C.last in order.
function M.newChoice(want, opts)
  opts = opts or {}
  local tag = opts.tag or "choice"
  local ready = opts.ready or "waiting"
  assert(ready == "waiting" or ready == "count" or ready == "pass",
    "newChoice: opts.ready is waiting, count or pass")
  local minRows = opts.min or 2
  local gate = opts.inBattle
  if gate == nil then gate = M.battleLoadStarted end
  local on = opts.on or 4
  local press = opts.press or function(ph) return ph < on end
  local list = type(want) == "table" and want or nil
  local extra = opts.extra or "error"
  local C = { n = 0, resolved = 0, last = nil, history = {} }
  local up, entered, checked, seen = false, false, false, nil
  local cur, max, dlg, target, entry = 0, 0, 0, nil, nil

  local function entryFor(n, m)
    if not list then return nil end
    local e = list[n]
    if e == nil and extra == "last" then e = list[#list] end
    if e == nil then
      error(string.format("%s: unexpected choice prompt #%d (%d options, dlg $%04X) " ..
        "on map %d -- the route knows of only %d", tag, n, m,
        M.readWord(0x00D0), M.mapId() & 0x1ff, #list), 0)
    end
    return type(e) == "table" and e or { want = e }
  end
  local function rowNow()
    if list then return entry.want end
    if type(want) == "function" then return want(dlg, max, C.n) end
    return want
  end

  function C.poll()
    if seen == M.frame then return end
    seen = M.frame
    local m = (gate and gate()) and 0 or M.readByte(0x056F)
    up = m >= minRows
    if up then
      cur, max, dlg = M.readByte(0x056E), m, M.readWord(0x00D0)
      local waiting = M.dialogWaiting()
      if not entered and (ready == "count" or waiting) then
        entered, checked = true, false
        C.n = C.n + 1
        entry = entryFor(C.n, m)
      end
      if entered then
        target = rowNow()
        if waiting and not checked then
          checked = true
          if entry and entry.max then
            M.assertEq(m, entry.max, string.format("%s choice #%d option count (%s)",
              tag, C.n, tostring(entry.what)))
          end
          if target < 0 or target >= m then
            error(string.format("%s: choice #%d (dlg $%04X) wants row %d of %d",
              tag, C.n, dlg, target, m), 0)
          end
          if opts.onUp then opts.onUp(C.n, m, entry) end
        end
      end
    elseif entered then
      entered = false
      C.resolved = C.resolved + 1
      C.last = { dlg = dlg, row = cur, max = max, n = C.n }
      C.history[#C.history + 1] = C.last
      M.log(string.format("[choice] dlg $%04X: row %d of %d", dlg, cur, max))
      if cur ~= target then
        error(string.format("%s: choice #%d (dlg $%04X) landed on row %d of %d, " ..
          "wanted %d", tag, C.n, dlg, cur, max, target), 0)
      end
    end
  end

  function C.frame(ph)
    C.poll()
    if not up then return false end
    if not entered or (ready ~= "count" and not M.dialogWaiting()) then
      if ready == "pass" then return false end
      M.setPad({})
      return true
    end
    if cur < target then M.setPad(press(ph, "steer") and { "down" } or {})
    elseif cur > target then M.setPad(press(ph, "steer") and { "up" } or {})
    else M.setPad(press(ph, "confirm") and { "a" } or {}) end
    return true
  end

  function C.reset()
    C.n, C.resolved, C.last, C.history = 0, 0, nil, {}
    up, entered, checked, seen = false, false, false, nil
    cur, max, dlg, target, entry = 0, 0, 0, nil, nil
  end
  return C
end

-- M.dialogChoice(want, opts): the step.  Drives until opts.done(C) (default:
-- every prompt of `want` -- #want for a list, else one -- has closed and no
-- dialog waits), steering each choice window through M.newChoice (want and
-- the opts above) and, on every other frame:
--   opts.battle(ph)  while M.battleLoadStarted(), when given
--   opts.idle(ph)    otherwise (default: edge-A while a dialog waits)
-- ph is the step's own pulse, (ph + 1) % opts.period (default 8) per frame.
-- opts.maxFrames (default 6000), opts.what.  The step carries its C as
-- step.choice, for a caller that asserts on what landed.
function M.dialogChoice(want, opts)
  opts = opts or {}
  local C = M.newChoice(want, opts)
  local period, on = opts.period or 8, opts.on or 4
  local ph = 0
  local n = type(want) == "table" and #want or 1
  local done = opts.done or function(c)
    return c.resolved >= n and not M.dialogWaiting()
  end
  local idle = opts.idle or function(p)
    M.setPad(M.dialogWaiting() and p < on and { "a" } or {})
  end
  local step = M.withReset(M.driveUntil(function()
    C.poll()
    return done(C)
  end, opts.maxFrames or 6000, {
    M.call(function()
      ph = (ph + 1) % period
      if opts.battle and M.battleLoadStarted() then opts.battle(ph); return end
      if C.frame(ph) then return end
      idle(ph)
    end),
  }, opts.what or "dialog choice"), function()
    ph = 0
    C.reset()
  end)
  step.choice = C
  return step
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
  return M.withReset(M.driveUntil(function() return swv(swId) == 1 end, maxFrames, {
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
  }, what), function()
    n = 0      -- the one A tap lives in frames 1..8 of the drive (#196)
  end)
end

-- Escape a stood-on re-entry trigger tile (the re-entry-trap class: the
-- trigger re-enters every frame, hasControl never settles, and only an
-- unconditional held press leaves).  Cycles dirs 40 frames each until the
-- party tile changes and settles 10 aligned quiet frames.
function M.stepOff(dirs, maxFrames, what)
  local x0, y0, moved, calm, n = nil, nil, false, 0, 0
  return M.withReset(M.driveUntil(function()
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
  }, what), function()
    -- the origin is re-read where the next pass stands (#196): the last
    -- pass's "moved" would otherwise end this one on its first frame
    x0, y0, moved, calm, n = nil, nil, false, 0, 0
  end)
end

-- --------------------------------------------------------- field care --
-- M.fieldCare: open the field menu and revive, cure and heal the party with
-- real presses, then close it again.  The status pass is CARE_STATUS_CURES
-- below.
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
-- Owner guideline (#152): outside battle the party heals from the BAG --
-- Tonics first, then Potions -- and a cure is cast only when the bag has
-- nothing left to offer (every healing item at its reserve floor, or
-- refused for that target).  MP is the fight's resource; a Tonic is what a
-- person drinks between fights.  (An earlier order cast first, reasoning
-- that OT6's level-up refund makes MP the cheaper resource; measured, it
-- cast Cure three times with 84 Tonics in the bag.)
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
-- opts.magic      allow a cure to be CAST as the fallback when the bag has
--                 nothing for a target (default true).  The bag is always
--                 tried first; set false on a step that must keep every
--                 point of MP for the fight it is walking toward, and the
--                 target goes unhealed once the bag is empty.
--                 Revival is always a Fenix Down.
-- opts.mpFloor    MP a caster keeps back: a fraction of their maximum below
--                 1, an absolute number at or above it (default 0.25).  A
--                 caster drained to zero in a corridor walks into the next
--                 fight with no Cure and no attack spell, and the fight
--                 driver's own in-battle heal has nothing to spend, so the
--                 floor is not zero.
-- opts.reserve    { [itemId] = n } -- keep n of that item unspent, so a step
--                 can hold Potions back for the fight it is walking toward
-- opts.mpBand     a living member under this fraction of their max MP
--                 drinks a Tincture, and another if still under (default
--                 0.25; #231, docs/design/supply.md)
-- opts.tincture   false switches the Tincture arm off (default on)
-- opts.tent       false switches the Tent arm off (default on): where the
--                 item list offers a Tent -- a save point or the world map
--                 -- one is pitched instead of the items whenever a
--                 Tincture would be due for anyone or the party's HP hole
--                 is past 24 Tonics' worth, a Tent's own price
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
-- The MP side (#231, docs/design/supply.md).  A Tincture is +50 MP for
-- 1500 and works anywhere; a Tent is the whole party's both pools for
-- 1200 and works only where the item list offers it: on a save point
-- (OpenMainMenu copies the save-enable bit $1EB7.7 into $0201.7,
-- field/menu.asm:229-235, and item.asm @84f8 greys the Tent off that bit)
-- or on the world map (the world module sets the same bit; measured by
-- gen_narshe_mission's Tent stops).  Elixirs, Ethers and X-Ethers are
-- deliberately not named here: they are never the field's to spend (the
-- owner's ruling on #231; a dry caster mid-fight is the fight driver's
-- call, tools/tests/lib/ot6.lua).
local CARE_TINCTURE, CARE_TENT = 0xEB, 0xF7
-- The HP deficit past which a Tent beats the Tonics that would fill it:
-- 1200 gil is 24 Tonics, so 24 x 50 HP.
local TENT_WORTH_HP = 24 * 50

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
local CARE_EYEDROP, CARE_REVIVIFY = 0xF3, 0xF1
local CARE_STATUS_CURES = {
  { bit = 0x40, items = { CARE_SOFT, CARE_REMEDY }, what = "petrify" },
  { bit = 0x04, items = { CARE_ANTIDOTE, CARE_REMEDY }, what = "poison" },
  -- Dark (blind) persists out of battle and halves a fighter's hits; the
  -- FC descent delivered LOCKE to the alcove blind with three Remedies in
  -- the bag and nothing reaching for them
  { bit = 0x01, items = { CARE_EYEDROP, CARE_REMEDY }, what = "dark" },
  { bit = 0x20, items = { CARE_REMEDY }, what = "imp" },
  -- Zombie persists too, and Remedy's mask ($65, item.asm @8bb2) leaves it,
  -- so Revivify is the one field cure.  A zombied member walks into the
  -- next fight attacking the party, and the fight driver's raise rule spent
  -- eight Fenix Downs on two of them at the Vector crash site (#220)
  { bit = 0x02, items = { CARE_REVIVIFY }, what = "zombie" },
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
      return M.withReset(M.driveUntil(function()
        dt = dt + 1
        return dt >= 90 and not M.dialogWaiting()
      end, 600, {
        M.call(function()
          aPh = (aPh + 1) % 8
          M.setPad(M.dialogWaiting() and aPh < 4 and { a = true } or {})
        end),
      }, tag .. ": dialog dismissed"), function() dt = 0 end)   -- the linger is per pass (#196)
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

-- The shop table (#191).  ShopProp is shop_prop.dat spliced at shop.asm:
-- 128 records of 9 bytes, byte 0 = shop type in bits 0-2 (1 Weapon, 2
-- Armor, 3 Item, 4 Relics, 5 Vendor: ShopTypeTextTbl, shop.asm:1816-1822)
-- and the price adjustment in bits 3-5, bytes 1-8 = the eight rows' item
-- ids, $FF = empty.  The shop event command $9b parks the shop number at
-- $0201 (w0201, shop.asm:1794: DrawShopTypeText multiplies it by 9 into the
-- record), and the buy list is drawn from that record, row r's id landing
-- at $7E9D89+r (shop.asm:819-821).  So the ROM table says which row an
-- item is on, and the drawn list says what the menu actually put there.
local SHOP_TYPES = { [1] = "Weapon", [2] = "Armor", [3] = "Item",
                     [4] = "Relics", [5] = "Vendor" }
local SHOP_REC, SHOP_LIST = 9, 0x9D89
local function shopProp() return M.sym("ShopProp") & 0x3FFFFF end

-- the shop number the open counter parked at $0201
function M.shopId() return M.readByte(0x0201) end

-- the shop's type code (byte 0 & 7) and its name
function M.shopType(shop)
  local t = M.readRomByte(shopProp() + shop * SHOP_REC) & 0x07
  return t, SHOP_TYPES[t] or string.format("type %d", t)
end

-- the eight rows' item ids from the ROM table (nil for an empty $FF row)
function M.shopStock(shop)
  local rows = {}
  for r = 0, 7 do
    local id = M.readRomByte(shopProp() + shop * SHOP_REC + 1 + r)
    if id ~= 0xFF then rows[r] = id end
  end
  return rows
end

-- the row (0..7) shop `shop` sells item `id` on, or nil
function M.shopRowOf(shop, id)
  for r = 0, 7 do
    if M.readRomByte(shopProp() + shop * SHOP_REC + 1 + r) == id then return r end
  end
  return nil
end

local function shopStockText(shop)
  local out = {}
  for r = 0, 7 do
    local id = M.readRomByte(shopProp() + shop * SHOP_REC + 1 + r)
    out[#out + 1] = id == 0xFF and "--" or string.format("$%02X", id)
  end
  return table.concat(out, " ")
end

-- M.buyItem: buy `qtyFn()` more of item `id`, closed-loop, with the shop
-- already open at its options window (menu state $25).
--
--  * The row is the ROM shop table's, for the shop the counter opened
--    ($0201), resolved on the first frame; a caller that still passes one
--    (the old signature, kept) has it checked against the table, and a
--    wrong row is a failure before any money moves rather than a silent
--    purchase of whatever sat on that row.  `row` may be nil, or the
--    argument omitted altogether: M.buyItem(id, qtyFn, name).  `qtyFn`
--    may be a plain count.
--  * Before the confirm the drawn list is read too ($7E9D89+row must hold
--    the item), and the purchase line logs shop, type, row and id from
--    both sources.
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
  if type(row) == "function" or type(row) == "string"
     or (type(row) == "number" and type(qtyFn) == "string") then
    -- the (id, qtyFn, name) form: no row asked for
    row, qtyFn, name = nil, row, qtyFn
  end
  if type(qtyFn) == "number" then
    local n = qtyFn
    qtyFn = function() return n end
  end
  name = name or string.format("item $%02X", id)
  local askedRow = row
  local phase = 0
  local seen27, bought = false, false
  local want = nil
  local lastQty, stall = nil, 0
  local shop, typeName, gil0, drawnOk = nil, nil, nil, false
  return M.withReset(M.driveUntil(function() return bought end, 20000, {
    M.call(function()
      phase = (phase + 1) % 8
      local st = M.readByte(0x0026)
      if want == nil then
        -- The row comes from the ROM table for the shop the counter opened
        -- (the shop event parked its number at $0201 before the options
        -- window came up), so a caller cannot buy the wrong thing by
        -- miscounting rows; a row it still passes is checked, not trusted.
        shop = M.shopId()
        local _
        _, typeName = M.shopType(shop)
        local romRow = M.shopRowOf(shop, id)
        if romRow == nil then
          error(string.format("[shop] %s: shop %d (%s) does not sell item $%02X " ..
            "-- its rows are %s", name, shop, typeName, id, shopStockText(shop)), 0)
        end
        if askedRow ~= nil and askedRow ~= romRow then
          error(string.format("[shop] %s: row %d was asked for, but shop %d (%s) " ..
            "sells $%02X on row %d (row %d holds %s) -- its rows are %s", name,
            askedRow, shop, typeName, id, romRow, askedRow,
            (M.shopStock(shop)[askedRow] and string.format("$%02X", M.shopStock(shop)[askedRow])
              or "nothing"), shopStockText(shop)), 0)
        end
        row = romRow
        want = qtyFn()
        gil0 = M.gil()
        if want < 1 then
          -- already at (or over) the target: nothing to buy, and no menu
          -- interaction -- the first cut clamped this to 1 and bought a
          -- Fenix Down the bag did not need (30 on a target of 25)
          M.log(string.format("[shop] %s: shop %d (%s) row %d = $%02X; already there " ..
            "(%d wanted); skipping", name, shop, typeName, row, id, want))
          bought = true; M.setPad({}); return
        end
        M.log(string.format("[shop] %s: shop %d (%s) row %d = $%02X on the ROM table%s; " ..
          "buying %d (gil %d)", name, shop, typeName, row, id,
          askedRow ~= nil and ", as asked" or "", want, gil0))
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
        M.log(string.format("[shop] %s: bought %d x $%02X from shop %d (%s) row %d; " ..
          "gil %d -> %d", name, lastQty or want, id, shop, typeName, row, gil0, M.gil()))
      elseif st == 0x25 then
        M.setPad(phase < 2 and { "a" } or {})
      elseif st == 0x26 then
        local cur = M.readByte(0x004E)
        if cur == row and not drawnOk then
          -- the list the menu drew is the game's own reading of the same
          -- record; check it once, before the A that opens the quantity
          local drawn = M.readByte(SHOP_LIST + row)
          if drawn ~= id then
            error(string.format("[shop] %s: the drawn list's row %d holds $%02X, " ..
              "not $%02X (shop %d, %s; ROM rows %s)", name, row, drawn, id, shop,
              typeName, shopStockText(shop)), 0)
          end
          drawnOk = true
          M.log(string.format("[shop] %s: the drawn list's row %d shows $%02X too", name, row, id))
        end
        local btn = cur < row and "down" or cur > row and "up" or "a"
        M.setPad(phase < 2 and { [btn] = true } or {})
      else
        M.setPad({})
      end
    end),
  }, "buy " .. name), function()
    -- as-built (#196): the row, the quantity and the "bought" latch are
    -- resolved again for the shop the NEXT pass finds open
    phase, seen27, bought, want = 0, false, false, nil
    lastQty, stall = nil, 0
    shop, typeName, gil0, drawnOk = nil, nil, nil, false
  end)
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
  -- The MP band (#231): a living member whose MP is under this fraction of
  -- their maximum drinks a Tincture, and another if still under.  Every
  -- member is a caster in OT6 (every verb but Fight costs MP), so there is
  -- no list of who qualifies.  opts.tincture = false and opts.tent = false
  -- switch each arm off for a step that wants neither.
  local mpBand = opts.mpBand or 0.25
  local useTincture = opts.tincture ~= false
  local useTent = opts.tent ~= false

  local function avail(id)
    return math.max(0, M.invCountOf(id) - (reserve[id] or 0))
  end

  -- alive, not petrified or zombie (the heals' own refusal mask), and
  -- under the MP band
  local function mpShort(c)
    local mp, mx = M.charMp(c), M.charMaxMp(c)
    return M.charHp(c) > 0 and (M.charStatus1(c) & 0xC2) == 0
       and mx > 0 and mp < mx * mpBand
  end

  -- what the whole party is missing, summed over the members a heal can
  -- reach
  local function partyShort()
    local hp, mp = 0, 0
    for _, c in ipairs(careParty()) do
      if M.charHp(c) > 0 and (M.charStatus1(c) & 0xC2) == 0 then
        hp = hp + M.charMaxHp(c) - M.charHp(c)
        mp = mp + M.charMaxMp(c) - M.charMp(c)
      end
    end
    return hp, mp
  end

  -- Where the item list offers a Tent: the world map, or a field map
  -- while the save-enable bit is up (it is set by the SavePoint script's
  -- sparkle and cleared again on the next orthogonal step).
  local function tentUsable()
    return M.worldMode() or (M.readByte(0x1EB7) & 0x80) ~= 0
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
    elseif w.kind == "tent" then
      return "tent"
    end
    return string.format("%d:item:%d", w.char, w.item)
  end

  local function planText(w)
    if w.kind == "cast" then
      return string.format("%s char %d by casting $%02X from char %d " ..
        "(%d/%d hp, caster %d/%d mp)", w.why, w.char, w.spell, w.caster,
        M.charHp(w.char), M.charMaxHp(w.char),
        M.charMp(w.caster), M.charMaxMp(w.caster))
    elseif w.kind == "tent" then
      local hp, mp = partyShort()
      return string.format("%s (the party %d hp and %d mp short, %d in the bag)",
        w.why, hp, mp, M.invCountOf(CARE_TENT))
    end
    return string.format("%s char %d with $%02X (%d/%d hp, %d/%d mp, status1 %02X)",
      w.why, w.char, w.item, M.charHp(w.char), M.charMaxHp(w.char),
      M.charMp(w.char), M.charMaxMp(w.char), M.charStatus1(w.char))
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
  -- than biggest: MP is the resource being rationed and the loop
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
    -- Tonics first, whatever the hole: outside battle the menu pauses the
    -- clock, so a big hole costs Tonics, not turns, and the Potions are
    -- the combat heal (owner doctrine).  The first cut reached for a
    -- Potion at holes >= 120 and the IAF's between-wave care spent seven
    -- of the gauntlet's Potions with 99 Tonics untouched.
    local order = { CARE_TONIC, CARE_POTION }
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
  -- both what a player does and the cheaper order.  A dead target is
  -- skipped, because CheckCanUseItem's own first test is the wound branch
  -- (item.asm:2282-2286) and a Fenix Down is the only thing it accepts
  -- there; the revive pass above is what serves them.  Every other cure
  -- item checks its own bit and nothing else (@8b8e-@8bbb), so a petrified
  -- or zombied member is served here: the $C2 mask belongs to the heals,
  -- which the game refuses on them (@8bc4).
  local function pickStatusCure(target)
    if M.charHp(target) == 0 or (M.charStatus1(target) & 0x80) ~= 0 then
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

  -- A Tent where the item list offers one (a save point, the world map),
  -- when it is the cheaper answer: whenever a Tincture would otherwise be
  -- due for anyone (1200 for everything against 1500 for 50 MP), or the
  -- party's HP hole alone is past the 24 Tonics a Tent costs.  Below that
  -- the Tonics are cheaper and the Tent is kept (supply.md, the rule for
  -- each option).
  local function pickTent()
    if not useTent or not tentUsable() or avail(CARE_TENT) < 1 then return nil end
    local w = { kind = "tent", item = CARE_TENT, why = "pitch a Tent" }
    if failed[key(w)] then return nil end
    local hp = partyShort()
    local due = hp >= TENT_WORTH_HP
    for _, c in ipairs(careParty()) do
      if mpShort(c) then due = true end
    end
    return due and w or nil
  end

  -- A Tincture on the member furthest under the MP band; the loop picks
  -- again if they are still under it, so a deep hole gets two.
  local function pickTincture()
    if not useTincture then return nil end
    local dry = {}
    for _, c in ipairs(careParty()) do
      if mpShort(c) then
        dry[#dry + 1] = { c = c, r = M.charMp(c) / M.charMaxMp(c) }
      end
    end
    table.sort(dry, function(a, b) return a.r < b.r end)
    for _, d in ipairs(dry) do
      local w = { kind = "item", char = d.c, item = CARE_TINCTURE, why = "restore mp" }
      if avail(CARE_TINCTURE) > 0 and not failed[key(w)] then return w end
    end
    return nil
  end

  -- Pick in the order a player would: revive first, then clear a status the
  -- bag can clear, then a Tent if one is offered and worth it, then top up
  -- whoever is worst off, casting where the party can cast and reaching
  -- for the bag where it cannot, then a Tincture on whoever is under the
  -- MP band.  Members are tried worst-first rather than only the worst
  -- being tried, so one member nobody can help does not stop the rest
  -- from being served.
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
    local tent = pickTent()
    if tent ~= nil then return tent end
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
      -- Bag first (owner guideline, #152: outside battle the party heals
      -- with Tonics, not by casting; Potions are the combat heal and MP is
      -- the fight's).  A cure is cast only when the bag has nothing to
      -- offer -- every healing item at its reserve floor or refused for
      -- this target -- and the caller has not switched casting off.
      -- Measured before this order: gen_esper_tubes' "care before battle
      -- 72" cast $2D three times with 84 Tonics in the bag.
      local w = pickItem(h.c)
      if w == nil and useMagic then w = pickCast(h.c) end
      if w ~= nil then return w end
    end
    return pickTincture()
  end

  local function anyNeed() return pick() ~= nil end

  -- Why the members still below the threshold are going unserved, for the
  -- roster line: "nothing to do" with somebody at 60% is a different fact
  -- from "nothing to do" with everyone whole, and #184 was filed reading
  -- the first as a refusal.  One clause per member nobody can help: each
  -- healing item's count against its floor (and whether the game refused
  -- it for this target), then the casters -- off, or each one's reason.
  local ITEM_NAMES = { [CARE_TONIC] = "tonic", [CARE_POTION] = "potion",
                       [CARE_FENIX] = "fenix", [CARE_REVIVIFY] = "revivify",
                       [CARE_ANTIDOTE] = "antidote", [CARE_EYEDROP] = "eyedrop",
                       [CARE_SOFT] = "soft", [CARE_REMEDY] = "remedy",
                       [CARE_TINCTURE] = "tincture", [CARE_TENT] = "tent" }
  local function unserved()
    if pick() ~= nil then return "" end
    local out = {}
    for _, c in ipairs(careParty()) do
      local hp, mx = M.charHp(c), M.charMaxHp(c)
      local why = {}
      if hp == 0 then
        local w = { kind = "item", char = c, item = CARE_FENIX, why = "revive" }
        why[#why + 1] = string.format("down; fenix %d in the bag%s",
          M.invCountOf(CARE_FENIX), failed[key(w)] and ", refused" or "")
      elseif (M.charStatus1(c) & 0x42) ~= 0 then
        -- petrified or zombied: the heals are refused, only the cure's own
        -- row can serve them, and it did not
        for _, cure in ipairs(CARE_STATUS_CURES) do
          if (M.charStatus1(c) & cure.bit) ~= 0 then
            for _, item in ipairs(cure.items) do
              local w = { kind = "item", char = c, item = item,
                          why = "cure " .. cure.what }
              why[#why + 1] = string.format("%s: %s %d in the bag, floor %d%s",
                cure.what, ITEM_NAMES[item], M.invCountOf(item), reserve[item] or 0,
                failed[key(w)] and ", refused" or "")
            end
          end
        end
      elseif mx > 0 and hp < mx * thresh then
        for _, id in ipairs({ CARE_TONIC, CARE_POTION }) do
          local w = { kind = "item", char = c, item = id, why = "heal" }
          why[#why + 1] = string.format("%s %d in the bag, floor %d%s",
            ITEM_NAMES[id], M.invCountOf(id), reserve[id] or 0,
            failed[key(w)] and ", refused" or "")
        end
        if not useMagic then
          why[#why + 1] = "casting off"
        else
          for _, k in ipairs(careParty()) do
            local knows = false
            for _, s in ipairs(CARE_CURES) do
              if M.knowsSpell(k, s) then knows = true end
            end
            if M.charHp(k) == 0 or (M.charStatus1(k) & 0xC2) ~= 0 then
              why[#why + 1] = string.format("c%d cannot cast (hp %d, status1 $%02X)",
                k, M.charHp(k), M.charStatus1(k))
            elseif not knows then
              why[#why + 1] = string.format("c%d knows no cure", k)
            else
              why[#why + 1] = string.format("c%d mp %d, floor %d%s", k,
                M.charMp(k), floorOf(k),
                failed[key({ kind = "cast", char = c, caster = k,
                             spell = CARE_CURES[1] })] and ", refused" or "")
            end
          end
        end
      end
      if mpShort(c) then
        -- under the MP band and still there: the Tincture the bag would
        -- not offer, and the Tent the map would not
        local w = { kind = "item", char = c, item = CARE_TINCTURE, why = "restore mp" }
        why[#why + 1] = string.format("mp %d/%d under the band (%.2f): %s",
          M.charMp(c), M.charMaxMp(c), mpBand,
          not useTincture and "tinctures off"
          or string.format("tincture %d in the bag, floor %d%s",
               M.invCountOf(CARE_TINCTURE), reserve[CARE_TINCTURE] or 0,
               failed[key(w)] and ", refused" or ""))
      end
      if #why > 0 then
        out[#out + 1] = string.format("c%d %d/%d hp: %s", c, hp, mx,
          table.concat(why, "; "))
      end
    end
    if #out > 0 and M.invCountOf(CARE_TENT) > 0 then
      out[#out + 1] = string.format("tent %d in the bag, %s",
        M.invCountOf(CARE_TENT),
        not useTent and "tents off"
        or not tentUsable() and "no save point underfoot"
        or failed["tent"] and "refused"
        or string.format("floor %d", reserve[CARE_TENT] or 0))
    end
    if #out == 0 then return "" end
    return " -- nothing more can be done: " .. table.concat(out, " | ")
  end

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
  local yielded = false

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

    -- A battle can own the screen with every cell this kernel reads
    -- meaning something else: $26 and DP $B5 -- the menu-state byte and
    -- the mosaic byte the refusal test below reads -- are battle RAM
    -- there, and $26 can read 05 in a fight.  Measured (#184,
    -- gen_zozo2_arrival attempt 1, lap 52): a random opened on the world
    -- map under the X presses, "field menu open" was satisfied 129 frames
    -- later by a battle-side 05 in $26, the Potion plan was "REFUSED" one
    -- frame after it was made by $B5's battle value, the cast plan's
    -- presses walked the battle's Item list, and the close drive's B's
    -- went into the fight for 2400 frames.  (probe_care_race.lua, 2026-09-
    -- 16: with the care asked for 0..47 frames before the encounter step
    -- ends, $26 read $00/$01/$4C/$C0 through the fight's first 400
    -- frames; the 05 is not what a battle always shows, only what one
    -- can.)  So the kernel serves nothing while a battle is up: it logs
    -- once, releases the pad and reports itself yielded, and the caller
    -- plays the fight the way a walker plays what it meets.
    if M.battleLoadStarted() then
      if not yielded then
        yielded = true
        M.log(string.format("[%s] a battle owns the screen (menu state $%02X): " ..
          "the care yields to the fight", tag, st))
      end
      M.setPad({}); return
    end

    -- Refusal.  zMosaic is not a flag the game clears: MosaicTask writes
    -- the eight bytes $17 $27 $37 $47 $37 $27 $17 $07 and terminates
    -- (field_menu.asm:3820-3844), and nothing re-zeroes it after menu init
    -- (menu_init_2.asm:506).  So `$B5 ~= 0` stays true for the rest of the
    -- visit, and testing it that way reported every plan after the first
    -- refusal as refused too, without pressing anything, until the attempt
    -- cap gave up.  The high nibble is nonzero only while the animation
    -- runs, so that is the edge; re-arming when it clears keeps one
    -- refusal's tail from being charged to the next plan.
    -- The byte is only a refusal on a menu screen (the refusals come from
    -- $70 and $3B, both in CARE_SCREENS); read anywhere else it is some
    -- other module's cell.
    local mosaic = M.readByte(CARE_REFUSE) & 0xF0
    if mosaic == 0 then
      refuseArmed = true
    elseif want and refuseArmed and CARE_SCREENS[st] then
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
              or M.charMp(pending.char) ~= pending.mp
              or M.charStatus1(pending.char) ~= pending.st1
              or M.invCountOf(pending.item) < pending.qty
      elseif pending.kind == "tent" then
        -- The Tent leaves the menu on its own (the item menu answers it
        -- with return code $02 and terminates after its fade, item.asm
        -- @84f8) and the field or world module then runs the tent event,
        -- which is what restores the party; so the landing is the event's
        -- end -- the bag one lighter AND every reachable member whole --
        -- and the stall clock is held while the game is visibly doing the
        -- work (the count has already dropped).
        local used = M.invCountOf(CARE_TENT) < pending.qty
        if used then stall = 0 end
        local hp, mp = partyShort()
        -- The restore lands early in the event (measured on the Mt Kolts
        -- summit save point, probe_tent_summit: whole within 60 frames of
        -- the confirm) and the jingle plays on with control off, so the
        -- landing also waits for the map to have the party back -- once,
        -- not for a quiet run of frames: a party standing on a save point
        -- has the SavePoint script re-fire under it every ~30 frames
        -- (probe_tent_summit: `move=02 ev=CA:0000 hasControl=true` and
        -- `move=04 ev=CC:9AF3 hasControl=false` alternating for the whole
        -- 1500 frames watched), so control there is a flicker by the
        -- game's own doing and a debounce never lands.  "Whole" is what
        -- keeps the one frame honest: it cannot hold before the event's
        -- restore, so the first controlled frame after it is the tent's
        -- tail letting go.
        landed = used and hp == 0 and mp == 0 and careBackOnMap()
      else
        landed = M.charHp(pending.char) ~= pending.hp
              or M.charMp(pending.caster) ~= pending.mp
      end
      if landed then
        if pending.kind == "item" then
          M.log(string.format(
            "[%s] used $%02X on char %d: %d -> %d hp, %d -> %d mp, status1 %02X -> %02X, " ..
            "%d left",
            tag, pending.item, pending.char, pending.hp,
            M.charHp(pending.char), pending.mp, M.charMp(pending.char), pending.st1,
            M.charStatus1(pending.char), M.invCountOf(pending.item)))
        elseif pending.kind == "tent" then
          M.log(string.format(
            "[%s] pitched a Tent: the party whole in both pools, %d left (%d frames)",
            tag, M.invCountOf(CARE_TENT), M.frame - pending.frame))
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
    if want.kind == "tent" then
      -- $05 -> $08 -> $19 -> A on the same slot, and the menu leaves by
      -- itself; nothing is pressed once the bag count has dropped, and
      -- nothing is pressed on any screen the game shows while the tent
      -- event runs (the pending block above watches for its end).  The
      -- A is pressed on the 4-on/8-off cadence like every other press,
      -- so the confirm stays armed until the count moves.
      if pending and M.invCountOf(CARE_TENT) < pending.qty then M.setPad({}); return end
      if st == 0x05 then
        held = steer(M.readByte(CARE_CUR), 0)          -- Item is row 0
      elseif st == 0x08 then
        local slot = M.invSlotOf(CARE_TENT)
        if slot == nil then abandon(want, "not in the bag"); M.setPad({}); return end
        held = steer(M.readByte(CARE_CUR), slot)
      elseif st == 0x19 then
        local slot = M.invSlotOf(CARE_TENT)
        if slot and M.readByte(CARE_CUR) == slot then
          pending = pending or { kind = "tent", qty = M.invCountOf(CARE_TENT),
                                 frame = M.frame }
          held = { "a" }
        else
          held = { "b" }
        end
      elseif CARE_SCREENS[st] then
        held = { "b" }
      else
        M.setPad({}); return            -- fades and transients: hands off
      end
    elseif want.kind == "item" then
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
                        hp = M.charHp(want.char), mp = M.charMp(want.char),
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
      "[%s] %s: %s | tonic=%d potion=%d fenix=%d antidote=%d soft=%d remedy=%d " ..
      "revivify=%d tincture=%d tent=%d%s",
      tag, what, table.concat(out, "  "), M.invCountOf(CARE_TONIC),
      M.invCountOf(CARE_POTION), M.invCountOf(CARE_FENIX),
      M.invCountOf(CARE_ANTIDOTE), M.invCountOf(CARE_SOFT),
      M.invCountOf(CARE_REMEDY), M.invCountOf(CARE_REVIVIFY),
      M.invCountOf(CARE_TINCTURE), M.invCountOf(CARE_TENT), unserved())
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
  -- A battle can open under the visit: a wandering NPC whose touch is an
  -- encounter (the burning house's flames, npc_prop map 351: RANDOM, SLOW)
  -- reaches the party on the frame the menu is asked for.  The battle
  -- module keeps $26 at 05, the byte the "menu open" read waits on, so
  -- without a guard the kernel drove menu presses into the fight for 5662
  -- frames while two members died, and the close drive's B tripped the
  -- no-effect watchdog (fire_out regeneration 2026-09-16, attempt 3).  So
  -- every drive here also ends on a live battle, the pad is released, and
  -- the fight is played the way a walker plays what it meets
  -- (M.newWalkFighter: boost-Fight, items, its own care stop after) unless
  -- the caller passes fight = false.  A `fight` table fights it too, and
  -- reaches that driver's options (M.newWalkFighter, M.fightDriverFor).
  local function battle() return M.battleLoadStarted() end
  local closed = careClose(function()
    return not CARE_SCREENS[M.readByte(CARE_ZM)]
  end)
  local W
  return M.cond(function() return not M.eventTimerLive() end, {
    M.cond(function() return K.anyNeed() and not battle() end, {
      M.logStep(function() return K.roster("opening the menu") end),
      M.driveUntil(function()
        return battle() or M.readByte(CARE_ZM) == 0x05
      end, 1800, {
        M.call(function()
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { "x" } or {})
        end),
      }, K.tag .. ": field menu open"),
      M.release(),
      M.waitFrames(10),
      M.driveUntil(function() return battle() or K.served() end, K.budget, {
        M.call(K.serveFrame),
      }, K.tag .. ": heal/revive through the field menu"),
      M.release(),
      M.driveUntil(function() return battle() or closed() end, 2400, {
        M.call(function()
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { "b" } or {})
        end),
      }, K.tag .. ": back to the field"),
      M.release(),
      M.waitFrames(30),
      M.logStep(function()
        return K.roster(battle() and "a battle opened under the care" or "done")
      end),
    }, {
      -- A care stop that does nothing still logs, so "no log" and "nothing
      -- needed" do not look the same.
      M.logStep(function() return K.roster("nothing to do") end),
    }),
    M.cond(function() return battle() and opts.fight ~= false end, {
      M.logStep(function()
        return string.format("[%s] a battle is up at the care stop: fighting it", K.tag)
      end),
      M.call(function()
        W = M.newWalkFighter(K.tag .. ": the battle at the care stop", opts)
      end),
      M.driveUntil(function() return not W.frame() end, 40000, {},
        K.tag .. ": the battle at the care stop, and the care after it"),
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
-- safety net; the route's shop restocks (owner guideline) are what keep
-- the bag actually stocked for the 0.9 top-off.  The last Tincture is
-- kept the same way (#231); Tents are not reserved, because the last one
-- at the last save point is the one that matters.
M.CARE_RESERVE = { [CARE_TONIC] = 4, [CARE_POTION] = 4, [CARE_TINCTURE] = 1 }

function M.newCareDriver(opts)
  opts = opts or {}
  if opts.reserve == nil then opts.reserve = M.CARE_RESERVE end
  -- Owner guideline: outside-battle care heals with TONICS (items), not by
  -- casting -- Tonics are cheap and everywhere, and casting cures drained
  -- MP over a grind badly enough to wipe (zozo_arrival, MP-starved with a
  -- full Tonic bag).  careKernel now tries the bag first on every path
  -- (#152); the automatic post-battle path additionally never casts, so a
  -- grind that empties the bag walks on rather than spending the fight's
  -- MP.  An explicit fieldCare keeps the cast fallback unless it passes
  -- magic=false.
  if opts.magic == nil then opts.magic = false end
  local K = careKernel(opts)
  local mode, ph, n, idle = "start", 0, 0, 0
  local closed = careClose(function()
    return not CARE_SCREENS[M.readByte(CARE_ZM)]
  end)
  -- opts.party: the squad the care is for, on a map that holds several
  -- (the Moogle defense: a collision battle engages the squad it hits,
  -- not the one being walked, and the menu shows only the walked one).
  -- Y cycles the walked squad 1 -> 2 -> 3 -> 1 (ChangeParty, obj.asm,
  -- $1A6D), a press the game takes only with control, aligned and no
  -- event running; once the menu has closed the walk goes back to the
  -- squad it started from.
  local walked = M.readByte(0x1A6D) & 0x07
  local wanted = opts.party
  local switching = wanted ~= nil and wanted ~= walked
  if switching then mode = "switch" end
  local D = {}
  function D.done() return mode == "done" end
  function D.frame()
    ph = (ph + 1) % 12
    n = n + 1
    -- A battle under the stop (#184): every mode below reads menu cells
    -- that are battle RAM once a fight owns the screen.  Measured on the
    -- world map (probe_care_race.lua, the encounter step ending 0..47
    -- frames after the stop starts): the open wait pressed X into the
    -- fight until its 240-frame no-control cap gave the stop up, 378-512
    -- frames with the party idle in the battle; had $26 read 05 there,
    -- as it did in gen_zozo2_arrival lap 52, the serve and close modes
    -- would have pressed into the fight for another 2400 -- and the walk
    -- fighter that plays the battle waits on this driver either way.  A
    -- battle is a fight to play, not a menu to close: yield at once and
    -- the caller's own battle handling takes the frame.
    if mode ~= "done" and M.battleLoadStarted() then
      M.log(string.format("[%s] a battle opened under the care stop (while %s, " ..
        "%d frames in): yielding to the fight", K.tag, mode, n))
      mode = "done"; M.setPad({}); return
    end
    if mode == "switch" or mode == "switchback" then
      local p = mode == "switch" and wanted or walked
      if (M.readByte(0x1A6D) & 0x07) == p and M.hasControl() and M.tileAligned() then
        M.log(string.format("[%s] walking squad %d", K.tag, p))
        mode, n = (mode == "switch") and "start" or "done", 0
        M.setPad({}); return
      end
      if n > 1800 then
        M.log(string.format("[%s] the Y-switch to squad %d never landed; giving up on this care stop", K.tag, p))
        mode = "done"; M.setPad({}); return
      end
      M.setPad(n % 46 < 6 and { "y" } or {})
      return
    end
    if mode == "start" then
      if not K.anyNeed() then
        M.log(K.roster("nothing to do"))
        mode, n = switching and "switchback" or "done", 0
        M.setPad({}); return
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
      -- A scene that starts on the battle's last frame (the FlameEater's
      -- "RELM!!! Where are you?!" tail) owns the field: X there is a press
      -- the game never answers, and the no-effect watchdog trips on it
      -- (fire_out regeneration 2026-09-16, attempt 1).  A person cannot
      -- open the menu in a cutscene either; hold the pad empty while
      -- nothing is in control, and give the stop up after 240 such frames
      -- so the caller's own scene-riding step gets the field back.  The
      -- menu's own lifetime reads as no control too, so the wait applies
      -- only while no menu screen is up.
      local ctl = M.worldMode() and (M.worldHasControl() and M.worldAligned())
                  or (not M.worldMode() and M.hasControl())
      if not ctl and not CARE_SCREENS[M.readByte(CARE_ZM)] then
        idle = idle + 1
        if idle > 240 then
          M.log(string.format("[%s] a scene owns the field (no control for %d frames); giving up on this care stop", K.tag, idle))
          mode = "done"
        end
        M.setPad({})
        return
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
        mode, n = switching and "switchback" or "done", 0
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

-- ------------------------------------------------------- doors, shops --
-- Promoted from gen_thamasa_fire.lua so the Floating Continent prep can shop
-- at Thamasa with the same measured mechanics (one implementation, not two).
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- Returns the predicate and a function that restarts its count, for a
-- step that is repeated (#196): the count is only advanced while the
-- predicate is polled, so it would otherwise carry the last pass's
-- settled run into the next.
local function calmFor(n, extra)
  local cnt = 0
  return function()
    local ok = M.hasControl() and M.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end, function() cnt = 0 end
end
local function mapLow() return M.mapId() & 0x1ff end
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local SHOP_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { 0, 2, "up" }, { 0, -2, "down" }, { -2, 0, "right" }, { 2, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }

-- M.crossDoor: walk through the door at (sx,sy) and land on map dm at
-- (dx,dy).  Stages on a reachable neighbour, holds the direction into the
-- door tile through the transition, then waits for far-side control and the
-- fade-in.  opts.healer / opts.avoid / opts.fight pass to the walk.
function M.crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = M.movePress(move)
        if M.bfsPath(cx, cy) and (press == move or M.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      M.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled, settledAgain = calmFor(20)
  local aPhase = 0
  return M.seqStep({
    -- the first step is the reset (#196): the stage, the start map and
    -- the far-side settle count are all re-read where this pass stands
    M.call(function() pick, startMap = nil, mapLow(); settledAgain() end),
    M.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = opts.healer,
        bank = 3, items = true, avoid = opts.avoid, fight = opts.fight,
        arrive = function() return mapLow() ~= startMap end }),
    M.driveUntil(function()
      return mapLow() ~= startMap or (M.fieldX() == dx and M.fieldY() == dy)
    end, 1800, {
      M.call(function()
        aPhase = (aPhase + 1) % 8
        if M.dialogWaiting() then M.setPad(aPhase < 4 and { "a" } or {}); return end
        M.setPad({ [stage()[3]] = true })
      end),
    }, what),
    M.release(),
    M.waitUntil(settled, 1800, what .. ": far-side control"),
    M.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    M.waitFrames(30),
    M.call(function()
      M.assertEq(mapLow(), dm, what .. ": landed on the right map")
      M.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        M.fieldX(), M.fieldY(), M.frame))
    end),
  })
end

local function gilNow()
  return M.readByte(0x1860) + M.readByte(0x1861) * 256 + M.readByte(0x1862) * 65536
end
M.gil = gilNow

-- M.shopTalk: stand beside the shopkeeper at (nx,ny), face them, and A until
-- the shop's options window (menu state $25) is open -- M.buyItem's entry.
-- opts.healer / opts.fight pass to the walk.
function M.shopTalk(nx, ny, what, opts)
  opts = opts or {}
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(SHOP_CAND) do
        local sx, sy = nx + c[1], ny + c[2]
        if M.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { nx, ny + 1, "up" }
      M.log(string.format("[shop] %s: staging (%d,%d) face %s",
        what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local aPh = 0
  return M.seqStep({
    -- the staging tile is picked afresh per pass (#196)
    M.call(function() pick = nil end),
    M.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = opts.healer,
        bank = 3, items = true, fight = opts.fight }),
    M.driveUntil(function()
      return M.readByte(0x087f + M.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      M.call(function() M.setPad({ [stage()[3]] = true }) end),
    }, what .. ": faced"),
    M.release(), M.waitFrames(4),
    M.driveUntil(function() return M.readByte(0x0026) == 0x25 end, 3000, {
      M.call(function()
        aPh = (aPh + 1) % 12
        M.setPad(aPh < 4 and { a = true, [stage()[3]] = true } or {})
      end),
    }, what .. ": shop opens"),
    M.call(function()
      M.log(string.format("[shop] %s: open at f%d, gil=%d", what, M.frame, gilNow()))
    end),
  })
end

-- M.shopClose: B out of the shop until field control returns.
function M.shopClose(what)
  local ph = 0
  return M.seqStep({
    M.driveUntil(function()
      local st = M.readByte(0x0026)
      return M.hasControl() and st ~= 0x25 and st ~= 0x26 and st ~= 0x27
    end, 1800, {
      M.call(function()
        ph = (ph + 1) % 8
        M.setPad(ph < 4 and { b = true } or {})
      end),
    }, what .. ": shop closed"),
    M.release(),
    M.waitFrames(30),
  })
end

-- M.innRest: a night at an inn through the real talk -- the whole party
-- to full HP and full MP with every status cleared, for the price the
-- keeper names (the rest routine _cacd3c; docs/design/supply.md lists the
-- route's inns: 80 at South Figaro up to 350, Thamasa's 1).  Promoted
-- from gen_kolts's innRest with the keeper's talk spot and the price as
-- arguments:
--
--   opts.spot   {x, y}: the tile the party stands on to talk
--   opts.face   the direction the keeper is in (default "up")
--   opts.price  the charge, asserted against the purse before the talk --
--               `take_gil` sets $01BE when the party cannot pay, the
--               keeper says "Not enough money" and nobody rests
--   opts.tag    log prefix
--   opts.nav    navTo overrides for the walk to the spot
--
-- The keeper's Yes/No is taken through M.newChoice (row 0 = Yes), the
-- night is ridden out until the party has control back, and every member
-- is asserted whole afterwards.
function M.innRest(opts)
  opts = opts or {}
  local what = opts.tag or "the inn"
  local face = opts.face or "up"
  local price = opts.price or 0
  local nav = { maxFrames = 20000, playBattles = "tactical" }
  for k, v in pairs(opts.nav or {}) do nav[k] = v end
  local ph, calm = 0, 0
  local C = M.newChoice(0, { tag = what, onUp = function(n, max)
    M.log(string.format("%s: choice #%d up (%d options) -- taking 0 (Yes)",
      what, n, max))
  end })
  local function partyLine(when)
    local t = {}
    for _, c in ipairs(M.partyMembers()) do
      t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, M.charHp(c),
        M.charMaxHp(c), M.charMp(c), M.charMaxMp(c))
    end
    return string.format("[%s] %s: %s | gil=%d", what, when,
      table.concat(t, "  "), M.gil())
  end
  return M.seqStep({
    M.call(function()
      M.assertEq(M.gil() >= price, true,
        string.format("%s: the party can pay the %d GP (gil %d)", what, price, M.gil()))
      M.log(partyLine("before the night"))
    end),
    M.navTo(opts.spot[1], opts.spot[2], nav),
    M.release(), M.waitFrames(20),
    M.call(function()
      M.assertEq(M.fieldX() == opts.spot[1] and M.fieldY() == opts.spot[2], true,
        string.format("%s: on the keeper's talk spot (%d,%d)", what,
          opts.spot[1], opts.spot[2]))
    end),
    M.driveUntil(function()
      return M.eventRunning() or M.dialogWaiting()
    end, 6000, {
      M.call(function()
        if not (M.hasControl() and M.tileAligned()) then M.setPad({}); return end
        if M.readByte(0x087f + M.readWord(0x0803)) ~= FACE_VAL[face] then
          M.setPad({ [face] = true }); return
        end
        M.setPad((M.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": engage the keeper"),
    M.release(),
    M.driveUntil(function()
      local ok = M.hasControl() and M.tileAligned() and bright() >= 15
             and not M.dialogWaiting() and not M.eventRunning()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 30000, {
      M.call(function()
        ph = (ph + 1) % 8
        if C.frame(ph) then return end
        if M.hasControl() and not M.dialogWaiting() then M.setPad({}); return end
        M.setPad(ph < 4 and { "a" } or {})
      end),
    }, what .. ": the night passes"),
    M.release(), M.waitFrames(30),
    M.call(function()
      for _, c in ipairs(M.partyMembers()) do
        M.assertEq(M.charHp(c), M.charMaxHp(c),
          string.format("%s: char %d woke at full hp", what, c))
        M.assertEq(M.charMp(c), M.charMaxMp(c),
          string.format("%s: char %d woke at full mp", what, c))
      end
      M.log(partyLine("after the night"))
    end),
  })
end

-- M.bagArrange: put the listed items at bag slots 0, 1, 2, ... through the
-- real field Item menu, the way a person keeps the combat items on top so a
-- battle heal is one press away, not forty-three (the IAF gauntlet found
-- the Potion at row 43: 1300 frames of active-time menu per heal).
--
-- Mechanics, measured by the care kernel: in the list ($08) the cursor
-- (DP $4B) is the absolute bag slot; A picks the slot up ($19); A on a
-- DIFFERENT slot swaps the two and returns to $08 (A on the same slot would
-- use the item, so this driver never presses it there).  Direction is held,
-- not tapped: the field menu auto-repeats.  Reads and presses only; every
-- swap is verified in the bag ($1869 + slot) before the next.
function M.bagArrange(order, opts)
  opts = opts or {}
  local tag = opts.tag or "bag arrange"
  local ZM, CUR = 0x26, 0x4b
  local mode, n, ph, i = "start", 0, 0, 1
  local job = nil                 -- { id, tgt, from } for the swap in flight
  local swaps = 0
  local function nextJob()
    while i <= #order do
      local id, tgt = order[i], i - 1
      local s = M.invSlotOf(id)
      if s == nil then
        M.log(string.format("[%s] $%02X is not in the bag; skipping its slot", tag, id))
        i = i + 1
      elseif s == tgt then i = i + 1
      else return { id = id, tgt = tgt, from = s } end
    end
    return nil
  end
  local function done() return mode == "done" end
  local function frame()
    ph = (ph + 1) % 12
    n = n + 1
    local st = M.readByte(ZM)
    if mode == "start" then
      job = nextJob()
      if job == nil then
        M.log(string.format("[%s] already in order", tag))
        mode = "done"; M.setPad({}); return
      end
      mode, n = "open", 0
    end
    if mode == "open" then
      if st == 0x05 then mode, n = "item", 0; M.setPad({}); return end
      if n > 1800 then error(string.format("[%s] the menu never opened", tag), 0) end
      M.setPad(ph < 4 and { "x" } or {}); return
    end
    if mode == "item" then                -- main menu row 0 is Item
      if st == 0x08 then mode, n = "pick", 0; M.setPad({}); return end
      if st == 0x05 then
        local cur = M.readByte(CUR)
        if cur == 0 then M.setPad(ph < 4 and { "a" } or {})
        else M.setPad({ [cur > 0 and "up" or "down"] = true }) end
        return
      end
      if n > 1800 then error(string.format("[%s] the Item list never opened (state $%02X)", tag, st), 0) end
      M.setPad(ph < 4 and { "b" } or {}); return
    end
    if mode == "pick" then                -- $08: cursor to the item, A -> $19
      if job == nil then job = nextJob() end
      if job == nil then mode, n = "close", 0; M.setPad({}); return end
      if st == 0x19 then mode, n = "drop", 0; M.setPad({}); return end
      if st ~= 0x08 then M.setPad(ph < 4 and { "b" } or {}); return end
      if n > 2400 then error(string.format("[%s] never picked up $%02X at slot %d", tag, job.id, job.from), 0) end
      local cur = M.readByte(CUR)
      if cur == job.from then M.setPad(ph < 4 and { "a" } or {})
      else M.setPad({ [cur < job.from and "down" or "up"] = true }) end
      return
    end
    if mode == "drop" then                -- $19: cursor to the target, A -> swap
      if st == 0x08 then
        local got = M.readByte(0x1869 + job.tgt)
        M.assertEq(got, job.id, string.format("[%s] $%02X moved to slot %d (from %d)", tag, job.id, job.tgt, job.from))
        swaps = swaps + 1
        job = nil
        mode, n = "pick", 0; M.setPad({}); return
      end
      if st ~= 0x19 then M.setPad({}); return end
      if n > 2400 then error(string.format("[%s] never dropped $%02X at slot %d", tag, job.id, job.tgt), 0) end
      local cur = M.readByte(CUR)
      if cur == job.tgt then M.setPad(ph < 4 and { "a" } or {})
      else M.setPad({ [cur < job.tgt and "down" or "up"] = true }) end
      return
    end
    if mode == "close" then
      if M.hasControl() and not CARE_SCREENS[st] then
        local top = {}
        for k = 0, math.max(#order, 1) - 1 do top[#top + 1] = string.format("$%02X", M.readByte(0x1869 + k)) end
        M.log(string.format("[%s] done: %d swap(s); slots 0..%d = %s", tag, swaps, #order - 1, table.concat(top, " ")))
        mode = "done"; M.setPad({}); return
      end
      if n > 2400 then error(string.format("[%s] the menu never closed", tag), 0) end
      M.setPad(ph < 4 and { "b" } or {}); return
    end
    M.setPad({})
  end
  return M.seqStep({
    M.withReset(
      M.driveUntil(done, opts.maxFrames or 24000, { M.call(frame) }, tag),
      function()   -- as-built (#196): the job list and "done" are per pass
        mode, n, ph, i, job, swaps = "start", 0, 0, 1, nil, 0
      end),
    -- settle the way shopClose does: the field drops a press for a few
    -- frames after the menu closes (gen_sabin_gau's inventory move tapped
    -- X 30 frames after this step and waited 600 for a menu that never
    -- opened, 3/3 seeds)
    M.release(),
    M.waitFrames(30),
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

  return M.withReset(M.cond(anyNeed, {
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
  }), function()
    -- as-built (#196): "done" and the skip list would otherwise let a
    -- repeated pass open the Order screen and flip nothing
    skip, phase, done, want, before, tries = {}, 0, false, nil, nil, 0
  end)
end

-- M.equipEsper: equip a specific magicite on the character at char-select
-- position `pos`, through the real Skills -> Espers -> detail -> A walk.
-- Reads and pad presses only.  The list seek is against the live
-- $7e9d89 row->esper table; an esper the save does not own never appears
-- there, so the seek times out instead of equipping the wrong row.
-- `pos` may be a literal char-select row or a function returning one,
-- resolved live at the point the row is actually needed, for a caller
-- whose party order isn't pinned down until runtime.
--
-- The one-owner rule (#151).  The esper detail's A is refused when ANY
-- character wears the stone: _c35574 (skills.asm) scans all sixteen
-- $161E bytes and paints the row grey ($28), and MenuState_4d's A on a
-- grey row plays the invalid sound and shows the "already equipped"
-- message instead of writing the byte.  The first cut waited only for
-- the list to come back and reported "equipped" either way -- measured
-- on fc_landing: "SHIVA -> EDGAR: equipped, back on the list satisfied
-- after 30 frames" while EDGAR's +$1E stayed $FF and TERRA's stayed $02,
-- and every later fight logged "summon refused for char 4 ... stone=$FF".
-- So the stone is freed from its owner FIRST, in the owner's own list:
-- A on an empty row (a $7e9d89 entry of $FF) is the game's unequip
-- (MenuState_1e @2908 writes $FF to +$1E), and that is verified before
-- the target's walk begins.  After the target's walk the worn byte is
-- read back and a mismatch raises, naming what the byte says.  An owner
-- outside the active party cannot be reached through this menu, so that
-- raises too rather than walking a session that cannot succeed.
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
  local function worn(c) return M.readByte(0x1600 + 37 * c + 0x1E) end
  local function activeParty() return M.readByte(0x1A6D) & 0x07 end
  local function inActiveParty(c)
    local pb = M.readByte(0x1850 + c)
    return (pb & 0x07) ~= 0 and (pb & 0x07) == activeParty()
  end
  local function posOf(c) return (M.readByte(0x1850 + c) >> 3) & 0x03 end
  local function charAt(p)
    for c = 0, 15 do
      if inActiveParty(c) and posOf(c) == p then return c end
    end
    return nil
  end
  local function ownerOf(idx)
    for c = 0, 15 do
      if worn(c) == idx then return c end
    end
    return nil
  end

  -- the walk from the field to one character's esper list
  local function listWalk(what, posFn)
    return {
      M.driveUntil(function() return st() == ST_MAIN end, 1200,
        { M.pressButtons({ "x" }, 4), M.waitFrames(30) }, what .. ": main menu"),
      M.waitFrames(20),
      M.driveUntil(function()
        return st() == ST_MAIN and M.readByte(CUR) == 1
      end, 900, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
        what .. ": cursor on Skills"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_CHAR end, 300,
        what .. ": character select", 5),
      M.waitFrames(10),
      M.driveUntil(function()
        return st() == ST_CHAR and M.readByte(CUR) == posFn()
      end, 600, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
        what .. ": character cursor"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_SKILLS end, 300,
        what .. ": skills submenu", 5),
      M.waitFrames(10),
      M.driveUntil(function()
        return st() == ST_SKILLS and M.readByte(CUR) == 0
      end, 600, { M.pressButtons({ "up" }, 2), M.waitFrames(6) },
        what .. ": cursor to Espers"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_LIST end, 300,
        what .. ": esper list", 5),
      M.waitFrames(10),
    }
  end

  -- put the list cursor on the first row whose $7e9d89 entry is `value`
  -- (two columns: left/right move one row, up/down two)
  local function seekRow(what, value)
    local seek_ph = 0
    return M.driveUntil(function()
      return st() == ST_LIST and M.readByte(GENJULIST + M.readByte(CUR)) == value
    end, 3000, {
      M.call(function()
        seek_ph = (seek_ph + 1) % 8
        if seek_ph >= 4 then M.setPad({}); return end
        local target
        for r = 0, 26 do
          if M.readByte(GENJULIST + r) == value then target = r; break end
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
    }, what)
  end

  local function backOut(what)
    return {
      M.driveUntil(function() return M.hasControl() end, 1200,
        { M.pressButtons({ "b" }, 3), M.waitFrames(20) }, what .. ": back out"),
      M.waitFrames(20),
    }
  end

  local owner, target = nil, nil
  local freeSteps = {
    M.logStep(function()
      return string.format("[%s] stone $%02X is worn by char %d (pos %d); " ..
        "freeing it there first (one-owner rule)", tag, esperIdx, owner, posOf(owner))
    end),
  }
  for _, s in ipairs(listWalk(tag .. " (free)", function() return posOf(owner) end)) do
    freeSteps[#freeSteps + 1] = s
  end
  freeSteps[#freeSteps + 1] = seekRow(tag .. " (free): list cursor on an empty row", 0xFF)
  freeSteps[#freeSteps + 1] = M.waitFrames(20)
  freeSteps[#freeSteps + 1] = M.pressButtons({ "a" }, 3)   -- MenuState_1e @2908: unequip
  freeSteps[#freeSteps + 1] = M.waitFrames(20)
  freeSteps[#freeSteps + 1] = M.call(function()
    if worn(owner) ~= 0xFF then
      error(string.format("%s: freeing stone $%02X from char %d FAILED -- " ..
        "+$1E still reads $%02X after A on an empty row", tag, esperIdx,
        owner, worn(owner)), 0)
    end
    M.log(string.format("[%s] char %d freed: +$1E reads $FF", tag, owner))
  end)
  for _, s in ipairs(backOut(tag .. " (free)")) do freeSteps[#freeSteps + 1] = s end

  local equipSteps = {}
  for _, s in ipairs(listWalk(tag, targetPos)) do equipSteps[#equipSteps + 1] = s end
  equipSteps[#equipSteps + 1] = seekRow(tag .. ": list cursor on the stone", esperIdx)
  equipSteps[#equipSteps + 1] = M.waitFrames(20)
  equipSteps[#equipSteps + 1] = M.driveUntil(function() return st() == ST_DETAIL end, 600,
    { M.pressButtons({ "a" }, 3), M.waitFrames(12) }, tag .. ": detail")
  equipSteps[#equipSteps + 1] = M.waitFrames(20)
  equipSteps[#equipSteps + 1] = M.pressButtons({ "a" }, 3)   -- MenuState_4d @5902: equip esper
  equipSteps[#equipSteps + 1] = M.waitUntil(function() return st() == ST_LIST end, 300,
    tag .. ": back on the list", 5)
  equipSteps[#equipSteps + 1] = M.waitFrames(10)
  equipSteps[#equipSteps + 1] = M.call(function()
    local got = worn(target)
    if got ~= esperIdx then
      local who = ownerOf(esperIdx)
      error(string.format("%s: char %d (pos %d) does NOT wear stone $%02X after " ..
        "the walk -- +$1E reads $%02X; the stone is %s.  The detail's A is " ..
        "refused for a stone anyone wears (skills.asm _c35574), and reports " ..
        "nothing else.", tag, target, targetPos(), esperIdx, got,
        who and ("worn by char " .. who) or "worn by nobody"), 0)
    end
    M.log(string.format("[%s] verified: char %d (pos %d) wears $%02X (+$1E)",
      tag, target, targetPos(), got))
  end)
  for _, s in ipairs(backOut(tag)) do equipSteps[#equipSteps + 1] = s end

  return M.seqStep({
    M.call(function()
      target = charAt(targetPos())
      if target == nil then
        error(string.format("%s: no active-party character at char-select " ..
          "position %d", tag, targetPos()), 0)
      end
      owner = ownerOf(esperIdx)
      if owner ~= nil and owner ~= target and not inActiveParty(owner) then
        error(string.format("%s: stone $%02X is worn by char %d, who is not " ..
          "in the active party; this menu cannot free it", tag, esperIdx, owner), 0)
      end
    end),
    M.cond(function() return owner ~= nil and owner == target end, {
      M.logStep(function()
        return string.format("[%s] char %d (pos %d) already wears $%02X; nothing to do",
          tag, target, targetPos(), esperIdx)
      end),
    }, {
      M.cond(function() return owner ~= nil and owner ~= target end, freeSteps, {}),
      M.seqStep(equipSteps),
    }),
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
  local found, stuck, lastCur, ph = false, 0, nil, 0
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
    -- The list holds only what this character can wear, so walk it until
    -- the item is under the cursor OR the cursor has stopped moving (the
    -- list's end): an item the character cannot equip never appears, and
    -- the old steer timed out on exactly that (EDGAR offered a Shadow-only
    -- blade at the FC landing, 1800 frames).  opts.result.found reports
    -- which it was, for a caller whose ladder may hold such rungs.
    M.call(function() found, stuck, lastCur, ph = false, 0, nil, 0 end),
    M.driveUntil(function()
      if st() ~= ST_ITEM then return false end
      if M.readByte(0x1869 + M.readByte(0x9d8a + M.readByte(CUR))) == itemId then
        found = true; return true
      end
      return stuck >= 8
    end, 1800, {
      M.call(function()
        -- one press per 12-frame cycle, and the cursor is sampled once per
        -- cycle AFTER the press has had its frames to land: "stuck" counts
        -- presses that moved nothing, never frames (the first cut sampled
        -- every frame and called any list exhausted 8 frames in)
        ph = (ph + 1) % 12
        if ph == 8 then
          local cur = M.readByte(CUR)
          stuck = (cur == lastCur) and stuck + 1 or 0
          lastCur = cur
        end
        M.setPad(ph < 2 and { "down" } or {})
      end),
    }, tag .. ": list cursor on the item (or the list's end)"),
    M.release(),
    M.cond(function() return found end, {
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_SLOT end, 300,
        tag .. ": equipped, back on slots", 5),
      M.call(function() if opts.result then opts.result.found = true end end),
    }, {
      M.call(function()
        M.log(string.format("[%s] $%02X is not in this character's list (unequippable); the slot keeps what it had", tag, itemId))
        if opts.result then opts.result.found = false end
      end),
    }),
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
  -- opts.optional: a rung the character cannot wear (the Equip list never
  -- offers it) is logged and left, not asserted -- a kit LADDER names
  -- candidates, and which of them this character can wear is the game's
  -- call, read from its own list.
  local results = {}
  for _, spec in ipairs(items) do
    local slot, item = spec[1], spec[2]
    local res = { found = nil }
    results[#results + 1] = res
    steps[#steps + 1] = M.cond(function()
      if M.readByte(base + 0x1F + slot) == item then return false end
      M.assertEq(M.invCountOf(item) > 0, true, string.format(
        "%s: item $%02X for slot %d is in the bag", tag, item, slot))
      return true
    end, {
      M.equipWeapon(function() return pos end, item,
        { slot = slot, tag = string.format("%s slot %d item $%02X", tag, slot, item),
          result = res }),
    }, {})
  end
  steps[#steps + 1] = M.call(function()
    for i, spec in ipairs(items) do
      local slot, item = spec[1], spec[2]
      if opts.optional and results[i].found == false then
        M.log(string.format("[%s] slot %d: $%02X was not wearable; slot holds $%02X", tag, slot, item, M.readByte(base + 0x1F + slot)))
      else
        M.assertEq(M.readByte(base + 0x1F + slot), item, string.format(
          "%s: slot %d holds item $%02X", tag, slot, item))
      end
    end
    M.log(string.format("[%s] char=%d after=%02X %02X %02X %02X %02X %02X",
      tag, charId, M.readByte(base + 0x1F), M.readByte(base + 0x20),
      M.readByte(base + 0x21), M.readByte(base + 0x22),
      M.readByte(base + 0x23), M.readByte(base + 0x24)))
  end)
  return M.seqStep(steps)
end

-- M.equipKit: dress SEVERAL slots of one character in one Equip session
-- and one Relic session -- open the menu once, walk slot -> item -> back
-- on slots for each entry, B out once -- rather than M.equipLoadout's full
-- open/close per item.  Built for the IAF deck, where the only window a
-- benched-then-selected character can be dressed in is the short field
-- gap between two waves (the wave timers run while the menu is CLOSED and
-- pause while it is open, so what costs is the number of round trips).
--
-- `items` is an ordered list of { slot, item } with slot 0..5 as
-- equipLoadout's.  opts.ladder = true makes entries for the same slot
-- CANDIDATES in order (list the strongest first): once a slot holds one
-- of them, its later entries are skipped.  An item the character cannot
-- wear never appears in the game's list; that is detected as the list's
-- end (the per-press stuck counter, equipWeapon's) and logged, and the
-- slot keeps what it had.  Reads and presses only.
function M.equipKit(charId, items, opts)
  opts = opts or {}
  local tag = opts.tag or string.format("kit char %d", charId)
  local base = 0x1600 + 37 * charId
  local ZM, CUR, SLOTCUR = 0x26, 0x4b, 0x4e
  local ST_MAIN, ST_CHAR = 0x05, 0x06
  local function st() return M.readByte(ZM) end
  local function slotByte(slot) return M.readByte(base + 0x1F + slot) end
  local pos
  local doneSlot = {}
  local function session(relic, list)
    if #list == 0 then return {} end
    local MAINROW = relic and 3 or 2
    local ST_OPT = relic and 0x59 or 0x36
    local ST_SLOT = relic and 0x5a or 0x55
    local ST_ITEM = relic and 0x5b or 0x57
    local stag = tag .. (relic and " (relics)" or " (gear)")
    local function anyToDo()
      for _, it in ipairs(list) do
        local slot, item = it[3], it[2]
        if not doneSlot[slot] and slotByte(slot) ~= item and M.invCountOf(item) > 0 then return true end
      end
      return false
    end
    local steps = {
      -- a session right after another menu (a care stop's close) must not
      -- read the closing menu's $05 as its own: settle in the field first
      -- (the escape's post-Atma kit saw "main menu" in 3 frames and then
      -- steered a cursor that was not there)
      M.waitUntil(function() return M.hasControl() and st() ~= ST_MAIN end, 600,
        stag .. ": field settled before the menu", 5),
      M.waitFrames(20),
      M.driveUntil(function() return st() == ST_MAIN end, 1200,
        { M.pressButtons({ "x" }, 4), M.waitFrames(30) }, stag .. ": main menu"),
      M.waitFrames(20),
      M.driveUntil(function() return st() == ST_MAIN and M.readByte(CUR) == MAINROW end, 900,
        { M.pressButtons({ "down" }, 2), M.waitFrames(10) }, stag .. ": cursor on the menu row"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_CHAR end, 300, stag .. ": character select", 5),
      M.waitFrames(10),
      M.driveUntil(function() return st() == ST_CHAR and M.readByte(CUR) == pos end, 600,
        { M.pressButtons({ "down" }, 2), M.waitFrames(10) }, stag .. ": character cursor"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_OPT end, 600, stag .. ": equip options", 5),
      M.waitFrames(10),
      M.driveUntil(function() return st() == ST_OPT and M.readByte(CUR) == 0 end, 600,
        { M.pressButtons({ "left" }, 2), M.waitFrames(10) }, stag .. ": cursor on the Equip option"),
      M.pressButtons({ "a" }, 2),
      M.waitUntil(function() return st() == ST_SLOT end, 300, stag .. ": slot select", 5),
      M.waitFrames(10),
    }
    for _, it in ipairs(list) do
      local slotRow, item, slot = it[1], it[2], it[3]
      local itag = string.format("%s slot %d item $%02X", stag, slot, item)
      local found, stuck, lastCur, ph = false, 0, nil, 0
      steps[#steps + 1] = M.cond(function()
        if doneSlot[slot] then return false end
        if slotByte(slot) == item then doneSlot[slot] = opts.ladder or nil; return false end
        if M.invCountOf(item) < 1 then
          M.log(string.format("[%s] $%02X is not in the bag; skipped", itag, item)); return false
        end
        return true
      end, {
        M.driveUntil(function() return st() == ST_SLOT and M.readByte(SLOTCUR) == slotRow end, 600,
          { M.pressButtons({ "down" }, 2), M.waitFrames(10) }, itag .. ": slot cursor"),
        M.pressButtons({ "a" }, 2),
        M.waitUntil(function() return st() == ST_ITEM end, 300, itag .. ": item list", 5),
        M.waitFrames(10),
        M.call(function() found, stuck, lastCur, ph = false, 0, nil, 0 end),
        M.driveUntil(function()
          if st() ~= ST_ITEM then return false end
          if M.readByte(0x1869 + M.readByte(0x9d8a + M.readByte(CUR))) == item then
            found = true; return true
          end
          return stuck >= 8
        end, 1800, {
          M.call(function()
            ph = (ph + 1) % 12
            if ph == 8 then
              local cur = M.readByte(CUR)
              stuck = (cur == lastCur) and stuck + 1 or 0
              lastCur = cur
            end
            M.setPad(ph < 2 and { "down" } or {})
          end),
        }, itag .. ": list cursor on the item (or the list's end)"),
        M.release(),
        M.cond(function() return found end, {
          M.pressButtons({ "a" }, 2),
          M.waitUntil(function() return st() == ST_SLOT end, 300, itag .. ": equipped, back on slots", 5),
          M.call(function()
            M.assertEq(slotByte(slot), item, itag .. ": the slot holds it")
            if opts.ladder then doneSlot[slot] = true end
            M.log(string.format("[%s] slot %d <- $%02X", stag, slot, item))
          end),
        }, {
          M.call(function()
            M.log(string.format("[%s] $%02X is not in this character's list (unequippable); slot %d keeps $%02X",
              stag, item, slot, slotByte(slot)))
          end),
          M.driveUntil(function() return st() == ST_SLOT end, 300,
            { M.pressButtons({ "b" }, 2), M.waitFrames(10) }, itag .. ": back to slots"),
        }),
        M.waitFrames(10),
      }, {})
    end
    steps[#steps + 1] = M.driveUntil(function() return M.hasControl() end, 1200,
      { M.pressButtons({ "b" }, 3), M.waitFrames(20) }, stag .. ": back out")
    steps[#steps + 1] = M.waitFrames(20)
    -- the whole session is skipped when nothing in it is left to do
    return { M.cond(anyToDo, steps, { M.logStep(function() return "[" .. stag .. "] nothing to do" end) }) }
  end
  local gear, relics = {}, {}
  for _, spec in ipairs(items) do
    local slot, item = spec[1], spec[2]
    if slot >= 4 then relics[#relics + 1] = { slot - 4, item, slot }
    else gear[#gear + 1] = { slot, item, slot } end
  end
  local function six()
    return string.format("%02X %02X %02X %02X %02X %02X", slotByte(0), slotByte(1),
      slotByte(2), slotByte(3), slotByte(4), slotByte(5))
  end
  local steps = {
    M.call(function()
      local partyByte = M.readByte(0x1850 + charId)
      M.assertEq(partyByte & 0x07, M.readByte(0x1A6D) & 0x07, tag .. ": character is in the active party")
      pos = (partyByte >> 3) & 0x03
      doneSlot = {}
      M.log(string.format("[%s] char=%d row=%d before=%s", tag, charId, pos, six()))
    end),
  }
  for _, s in ipairs(session(false, gear)) do steps[#steps + 1] = s end
  for _, s in ipairs(session(true, relics)) do steps[#steps + 1] = s end
  steps[#steps + 1] = M.call(function()
    M.log(string.format("[%s] char=%d after=%s", tag, charId, six()))
  end)
  return M.seqStep(steps)
end

-- M.emptyEquip: strip one character of the active party through Equip ->
-- Empty, then B out to the field.  Empty is EquipRemoveAll
-- (menu/equip.asm): the weapon, shield, helmet and armor slots go to the
-- bag through IncItemQty, which skips a slot that is already empty;
-- relics are the other menu and stay.  Written for the Moogle defense
-- (#143), where MOG leaves the party with whatever he still wears.  The
-- character's list row is read from $1850 at run time and the row under
-- the cursor is checked against the list's own $69+row before the
-- options open; after the press the four slot bytes are asserted empty,
-- then opts.check (if given) runs, for a caller asserting what the bag
-- gained, before the menu closes.  Reads and presses only.
function M.emptyEquip(charId, opts)
  opts = opts or {}
  local tag = opts.tag or string.format("empty char %d", charId)
  local base = 0x1600 + 37 * charId
  local ZM, CUR = 0x26, 0x4b
  local ST_MAIN, ST_CHAR, ST_OPT = 0x05, 0x06, 0x36
  local EQUIP_ROW, OPT_EMPTY = 2, 3
  local ph = 0
  local function st() return M.readByte(ZM) end
  local function row() return (M.readByte(0x1850 + charId) >> 3) & 0x03 end
  local function four()
    return string.format("%02X %02X %02X %02X", M.readByte(base + 0x1F),
      M.readByte(base + 0x20), M.readByte(base + 0x21), M.readByte(base + 0x22))
  end
  local function tap(btn) ph = (ph + 1) % 12; M.setPad(ph < 4 and { btn } or {}) end
  local function seek(state, want, back, fwd, label)
    return M.driveUntil(function()
      return st() == state and M.readByte(CUR) == want()
    end, 1800, {
      M.call(function()
        if st() ~= state then M.setPad({}); return end
        ph = (ph + 1) % 12
        M.setPad(ph < 4 and { [M.readByte(CUR) < want() and fwd or back] = true } or {})
      end),
    }, tag .. ": " .. label)
  end
  local function press(state, label)
    return M.seqStep({
      M.driveUntil(function() return st() == state end, 1800, {
        M.call(function() tap("a") end),
      }, tag .. ": " .. label),
      M.release(), M.waitFrames(10),
    })
  end
  return M.seqStep({
    M.call(function()
      ph = 0
      M.assertEq(M.readByte(0x1850 + charId) & 0x07, M.readByte(0x1A6D) & 0x07,
        tag .. ": character is in the active party")
      M.log(string.format("[%s] char=%d row=%d before=%s", tag, charId, row(), four()))
    end),
    M.driveUntil(function() return st() == ST_MAIN end, 1800, {
      M.call(function() tap("x") end),
    }, tag .. ": main menu"),
    M.release(), M.waitFrames(10),
    seek(ST_MAIN, function() return EQUIP_ROW end, "up", "down", "cursor on Equip"),
    M.release(), M.waitFrames(10),
    press(ST_CHAR, "character list"),
    seek(ST_CHAR, row, "up", "down", "cursor on the character"),
    M.call(function()
      M.assertEq(M.readByte(0x69 + row()), charId,
        tag .. ": the list row under the cursor is the character")
    end),
    M.release(), M.waitFrames(10),
    press(ST_OPT, "options row"),
    seek(ST_OPT, function() return OPT_EMPTY end, "left", "right", "cursor on Empty"),
    M.release(), M.waitFrames(10),
    M.pressButtons({ "a" }, 4),
    M.waitFrames(20),
    M.call(function()
      M.log(string.format("[%s] char=%d after=%s", tag, charId, four()))
      M.assertEq(four(), "FF FF FF FF", tag .. ": the four slots read empty")
      if opts.check then opts.check() end
    end),
    M.driveUntil(function() return M.hasControl() end, 2400, {
      M.call(function() tap("b") end),
    }, tag .. ": back out to the field"),
    M.release(), M.waitFrames(20),
  })
end

-- ------------------------------------------------- the party select --
-- M.newPartySelect(pick): a driver for the game's multi-party select
-- screen (menu states $2D character grid / $2E group slots), forming ONE
-- group of exactly the characters in `pick`.  Written for the Blackjack's
-- IAF launch (probe_iaf_fight3 / probe_fc_alcove2) and used by both FC
-- gens; the cursor's direction mapping is probed at run time because the
-- grid's row/column order is not the party-record order.  Reads and
-- presses only.  Call pulse() once per frame while a select screen is up.
function M.newPartySelect(pick)
  local ZM = 0x26
  local function rd(a) return emu.read(a, emu.memType.snesMemory) end
  local function midx() return M.readByte(0x4b) + M.readByte(0x4a) + M.readByte(0x5a) end
  local function charAt(i) return rd(0x7e9d89 + i) end
  local function firstEmptyGroupSlot()
    for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
      if charAt(i) == 0xFF then return i end
    end
  end
  local function inGroup(c)
    for i = 0, 3 do if rd(0x7e9d99 + i) == c then return true end end
    return false
  end
  local P = { ph = 0, dir = {}, lastIdx = nil, lastBtn = nil, probe = 0, probeN = 0 }
  function P.ready()
    for i = 0, 0x13 do
      local c = charAt(i)
      if c ~= 0xFF and c > 0x0F then return false end
    end
    return true
  end
  function P.complete()
    for _, c in ipairs(pick) do if not inGroup(c) then return false end end
    return true
  end
  function P.group()
    local g = {}
    for i = 0, 3 do local c = rd(0x7e9d99 + i); if c ~= 0xFF then g[#g + 1] = string.format("$%02x", c) end end
    return table.concat(g, " ")
  end
  function P.pulse()
    local ms = M.readByte(ZM)
    P.ph = (P.ph + 1) % 9
    local function tap(btn) M.setPad(P.ph < 3 and { btn } or {}) end
    if not P.ready() then M.setPad({}); return end
    if ms == 0x2d then
      if P.complete() then tap("start")
      elseif M.readByte(0x4a) ~= 0 then tap("up")
      else
        local tgt = nil
        for i = 0, 15 do
          local c = charAt(i)
          if c ~= 0xFF and not inGroup(c) and rd(0x7eac8d + i) < 0x80 then
            for _, w in ipairs(pick) do if c == w then tgt = i end end
            if tgt then break end
          end
        end
        local cur = midx()
        if not tgt then tap("b")
        elseif cur == tgt then tap("a")
        else
          local want = (cur < tgt) and "inc" or "dec"
          if P.lastIdx ~= nil and cur ~= P.lastIdx and P.lastBtn then
            P.dir[(cur > P.lastIdx) and "inc" or "dec"] = P.lastBtn
          end
          local btn = P.dir[want]
          if not btn then
            btn = ({ "down", "up", "right", "left" })[(P.probe % 4) + 1]
            P.probeN = P.probeN + 1
            if P.probeN % 14 == 0 then P.probe = P.probe + 1 end
          end
          P.lastIdx, P.lastBtn = cur, btn
          tap(btn)
        end
      end
    elseif ms == 0x2e then
      if M.readByte(0x4a) ~= 0x10 then tap("down")
      else
        local tgt = firstEmptyGroupSlot()
        if not tgt then tap("a")
        else
          local cc, cr = (midx() >> 1) & 1, midx() & 1
          local tc, tr = (tgt >> 1) & 1, tgt & 1
          if cc < tc then tap("right") elseif cc > tc then tap("left")
          elseif cr < tr then tap("down") elseif cr > tr then tap("up")
          else tap("a") end
        end
      end
    else tap("b") end
  end
  return P
end

-- M.partySelect(members, opts): the step form, for a party menu that owns
-- the frame (the menu the event's `party_menu` opens: Narshe's defense
-- split, the Blackjack's swap room, Kefka's aftermath, the Zozo gather
-- room).  Promoted from the state-fed driver those four generators each
-- carried.  The menu (field-ram / menu RAM, measured by those generators):
--   $26            pick state: $2D browsing, $2E carrying a character
--                  ($69 is the menu's own fade, no input taken)
--   $7E9D89+cell   the cell's character id, $FF empty.  Cells $00-$0F are
--                  the pool (two rows of eight: col = cell % 8, row = cell
--                  >= 8), cells $10+ the groups' seats, four per group
--                  (group g's seat s is $10 + 4(g-1) + s: col = b >> 1,
--                  row = b & 1 with b = cell - $10)
--   $4B+$4A+$5A    the cursor's cell
-- A is pick-up and drop, START commits.  Each member is found in the pool
-- at the moment it is seated and dropped into its group's lowest empty
-- seat; both cells are asserted afterwards (a cursor that wandered would
-- otherwise commit whoever it stood on).  Reads and presses only.
--   members  a list of character ids (one group), or a list of such lists
--            (group g = members[g]); ids are seated in the order given.
--            A member already seated in its group is left there.
--   opts.tag         log/step prefix (default "party")
--   opts.names       id -> name for the step names (default the cast)
--   opts.menuWait    frames each seat waits for $26=$2D (default 900)
--   opts.commit      false: leave the menu open (default: START, and wait
--                    for $0059 to read closed)
--   opts.commitWait  (default 600), opts.closeWait (default 1200)
-- M.newPartySelect above is the per-frame form for a rider that already
-- owns the pad (the Blackjack's IAF launch).
local PARTY_NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR",
  "SABIN", "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO" }
function M.partySelect(members, opts)
  opts = opts or {}
  local tag = opts.tag or "party"
  local names = opts.names or PARTY_NAMES
  local groups = type(members[1]) == "table" and members or { members }
  local function mst() return M.readByte(0x0026) end
  local function cell(c) return M.readByte(0x7E9D89 + c) end
  local function cursorCell()
    return M.readByte(0x004b) + M.readByte(0x004a) + M.readByte(0x005a)
  end
  local function decode(c)
    if c < 0x10 then
      return { area = "pool", col = c % 8, row = c >= 8 and 1 or 0 }
    end
    local b = c - 0x10
    return { area = "party", col = b >> 1, row = b & 1 }
  end
  local function stepToward(cur, tgt)
    local c, t = decode(cur), decode(tgt)
    if c.area == "pool" and t.area == "party" then return "down"
    elseif c.area == "party" and t.area == "pool" then return "up"
    elseif c.area == "pool" then
      if c.row ~= t.row then return c.row < t.row and "down" or "up" end
      if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    else
      if c.col ~= t.col then return c.col < t.col and "right" or "left" end
      if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    end
    return nil
  end
  -- walk the cursor to tgt() and press btn until the pick state reaches
  -- doneState and holds there 8 frames with the cursor on tgt
  local function menuAct(tgt, btn, doneState, what)
    local phase, settled = 0, 0
    return M.withReset(M.driveUntil(function()
      return mst() == doneState and cursorCell() == tgt() and settled >= 8
    end, 4000, {
      M.call(function()
        phase = (phase + 1) % 10
        if mst() == doneState then settled = settled + 1; M.setPad({}); return end
        settled = 0
        if mst() == 0x69 then M.setPad({}); return end
        local cur = cursorCell()
        if cur ~= tgt() then
          local b = stepToward(cur, tgt())
          if not b then M.setPad({}); return end
          M.setPad(phase < 4 and { [b] = true } or {})
          return
        end
        M.setPad(phase < 4 and { [btn] = true } or {})
      end),
    }, what), function() phase, settled = 0, 0 end)
  end
  local function survey()
    local t = {}
    for c = 0x00, 0x1F do t[#t + 1] = string.format("%02X", cell(c)) end
    return table.concat(t, " ")
  end
  local steps = {
    M.call(function() M.log(string.format("[%s] cells $00-$1F: %s", tag, survey())) end),
  }
  for g, ids in ipairs(groups) do
    local base = 0x10 + 4 * (g - 1)
    for _, id in ipairs(ids) do
      local name = names[id] or string.format("$%02X", id)
      local what = string.format("%s: %s -> group %d", tag, name, g)
      local src, dst, seated
      steps[#steps + 1] = M.waitUntil(function() return mst() == 0x2d end,
        opts.menuWait or 900, what .. ": menu at $2d", 5)
      steps[#steps + 1] = M.call(function()
        src, dst, seated = nil, nil, false
        for c = base, base + 3 do if cell(c) == id then seated = true end end
        if seated then
          M.log(string.format("[%s] %s already seated in group %d", tag, name, g))
          return
        end
        for c = 0x00, 0x0F do if cell(c) == id then src = c; break end end
        for c = base, base + 3 do if cell(c) == 0xFF then dst = c; break end end
        M.assertEq(src ~= nil, true, what .. ": found in the pool")
        M.assertEq(dst ~= nil, true, what .. ": a free seat in the group")
        M.log(string.format("[%s] %s: pool cell $%02X -> seat $%02X", tag, name, src, dst))
      end)
      steps[#steps + 1] = M.cond(function() return not seated end, {
        menuAct(function() return src end, "a", 0x2e, what .. ": pick"),
        menuAct(function() return dst end, "a", 0x2d, what .. ": drop"),
        M.call(function()
          M.assertEq(cell(dst), id, what .. ": landed in the seat it was aimed at")
          M.assertEq(cell(src), 0xFF, what .. ": its pool cell is now empty")
        end),
      }, {})
    end
  end
  steps[#steps + 1] = M.call(function() M.log(string.format("[%s] seated: %s", tag, survey())) end)
  if opts.commit ~= false then
    steps[#steps + 1] = M.waitUntil(function() return mst() == 0x2d end,
      opts.commitWait or 600, tag .. ": menu at $2d for commit", 5)
    steps[#steps + 1] = M.pressButtons({ "start" }, 6)
    steps[#steps + 1] = M.waitUntil(function() return M.readByte(0x0059) == 0 end,
      opts.closeWait or 1200, tag .. ": menu closed", 5)
  end
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
    return M.withReset(M.driveUntil(function()
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
    }, string.format("%s: activation round %d", what, round)), function()
      -- a soft round's own budget is per pass (#196): the last pass's
      -- spent `waited` would end this one on its first frame, unengaged
      started, waited, aPh = 0, 0, 0
    end)
  end
  return seq({
    M.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    -- two distinct rounds (a soft one, then a hard one), so written flat;
    -- since #196 a repeatN could replay these bodies, but they differ
    M.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    M.release(),
  })
end

-- M.newWalkFighter (#183): fight-and-care for a generator's own walker.
-- A custom driveUntil walker (a held press onto a trigger tile, a
-- grind-and-replan world walk, a tap into a save tile) used to hold L+R
-- when a battle opened under it, which runs from the fight: no XP, and on
-- a pincer roll no escape at all (tools/audit_encounters.py).  The route
-- fights what it meets, so a walker asks this first on every frame:
--
--   local W = H.newWalkFighter("pressWalk " .. what)
--   H.call(function()
--     if W.frame() then plan = nil; return end   -- a battle, or its care, owned the frame
--     ...the walker's own pad...
--   end)
--
-- W.frame() sets the pad itself and returns true on every frame it owns:
-- while a battle is up (M.newFightDriver plays it: boost-Fight by default,
-- items, the heal policy), through the post-battle reload, and through the
-- care stop that heals OUTSIDE battle with Tonics/Potions once the field
-- or world is controllable again (M.newCareDriver: the heal-after-every-
-- battle directive; skipped under a live event timer, and given up after
-- 600 uncontrolled frames so a scripted stretch that never hands control
-- back still walks on).  A dialog during the reload is left to the walker,
-- whose own A-tap branch pages it.  A walker whose predicate fires mid-
-- care ends; driveUntil releases the pad.
--
-- opts: healPercent (45), careThreshold (0.7), care = false skips the
-- stop; healer/magic/summon/nuke/nukeLore/tool/blitz/bank/reserve pass to
-- the fight driver as worldNavTo passes them, and a `fight` table merges
-- over them (M.fightDriverFor).  W.fought() counts battles.
function M.newWalkFighter(tag, opts)
  opts = opts or {}
  local F = M.fightDriverFor(tag, {
    tactical = true, boost = true, items = true,
    healPercent = opts.healPercent or 45,
    bank = opts.bank, reserve = opts.reserve, healer = opts.healer,
    magic = opts.magic, summon = opts.summon, nuke = opts.nuke,
    nukeLore = opts.nukeLore, tool = opts.tool, blitz = opts.blitz }, opts.fight)
  local battN, fought, careD, settleN = 0, 0, nil, nil
  local function settled()
    if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then return false end
    if M.worldMode() then return M.worldHasControl() and M.worldAligned() end
    return M.hasControl() and M.tileAligned() and not M.dialogWaiting()
  end
  local W = {}
  function W.fought() return fought end
  function W.frame()
    if careD then
      careD.frame()
      if careD.done() then careD = nil end
      return true
    end
    if M.battleLoadStarted() then
      battN = battN + 1
      if battN == 3 then
        local w = M.formationWords()
        M.log(string.format("[%s] battle up f%d (%04X %04X %04X %04X %04X %04X) -- fighting it",
          tag, M.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
      end
      F.frame()
      return true
    end
    if battN > 0 then
      F.idle()
      battN, fought, settleN = 0, fought + 1, 0
      M.log(string.format("[%s] battle over f%d -- %d fought on this walk",
        tag, M.frame, fought))
    end
    if settleN then
      settleN = settleN + 1
      if not settled() then
        if M.dialogWaiting() then return false end
        if settleN > 600 then
          M.log(string.format("[%s] no control 600 frames after the battle; " ..
            "no care stop here", tag))
          settleN = nil
          return false
        end
        M.setPad({})
        return true
      end
      settleN = nil
      if opts.care ~= false and not M.eventTimerLive() then
        careD = M.newCareDriver({
          threshold = opts.careThreshold or 0.7, reserve = opts.reserve,
          tag = "care after battle (" .. tag .. ")" })
        careD.frame()
        if careD.done() then careD = nil; return false end
        return true
      end
    end
    return false
  end
  return W
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
-- (M.healDecision) instead of always drinking.  opts.fight is merged over
-- the driver options below (M.fightDriverFor).
function M.rideOut(what, budget, dstMap, opts)
  opts = opts or {}
  local phase, calm = 0, 0
  local F = M.fightDriverFor(what or "rideOut",
    -- bank = 3: unboosted Fights until the actor has three BP, then spend
    -- them.  Shielded damage is halved and a broken monster takes 4x
    -- (Ot6ShieldedMulW, ot6_break.asm:1487-1497), so the fight is won by
    -- breaking the shield rather than by chipping, and a boosted Fight is
    -- what chips.
    { tactical = true, boost = true, bank = 3, items = true,
      healPercent = 60, cadence = 12 }, opts.fight)
  return seq({
    M.withReset(M.driveUntil(function()
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
    }, what), function() calm = 0 end),   -- 20 settled frames of THIS pass (#196)
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
  local saveArg, hooked = nil, false
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
      -- the hook's answer is per pass (#196): a repeated save must see
      -- CopyGameDataToSRAM run AGAIN, not the last pass's slot; the hook
      -- itself is installed once
      saveArg = nil
      if not hooked then
        hooked = true
        local entry = M.sym("CopyGameDataToSRAM")
        emu.addMemoryCallback(function()
          saveArg = emu.getState()["cpu.a"] & 0xff
        end, emu.callbackType.exec, entry, entry)
      end
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
