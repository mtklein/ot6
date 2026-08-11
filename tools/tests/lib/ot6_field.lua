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
--   local H = dofile("tools/tests/lib/ot6.lua")
--
-- and see ONE merged H; nothing anywhere references this file's path at
-- runtime.  Everything here installs onto that shared table through the
-- core's public M.* API plus M.seqStep (exported for route()); the shared
-- field-state reads both halves stand on (fieldX/hasControl/formation...)
-- stay in the core because suite battle tests use them too.
--
-- Freshness: a generated route fixture is a function of BOTH halves, so
-- lib/frontier_stamp.sh hashes generator ++ ot6.lua ++ ot6_field.lua
-- (that fixed order) into the signature it stamps beside the fixture.

local M = ...
assert(type(M) == "table",
  "ot6_field.lua is inlined by lib/compose.py after lib/ot6.lua and " ..
  "receives the core module table; it cannot be loaded on its own")

-- How long playBattles="flee" holds L+R before it accepts that this
-- formation is not going to release the party and fights the battle out
-- instead.  The run
-- mechanic is a per-round roll against level/speed, so a short tail is
-- normal -- but holding L+R is not a neutral act, it is standing still while
-- the formation takes free rounds.  MEASURED 2026-08-09 with this cap at
-- 5400 (90 seconds): a Mt. Kolts cave-97 formation refused to release a
-- FULL-HEALTH party, the flee held for all 5400 frames, the party WIPED
-- inside its own escape attempt, and the drive then tapped A through the
-- Game Over and into a brand-new game -- eleven maps of intro before the
-- step's budget finally expired.  1800 frames is 30 seconds, several rounds,
-- long enough for a run that is going to work and short enough that the
-- fallback still has a party to fight with.
-- Navigators accept opts.fleeCap to SHORTEN the cap per route.  Measured
-- 2026-08-09 on the Figaro-cave escape step (LOCKE + CELES, 113+150 hp): a
-- PINCER formation (Trilobiter + Primordites, party surrounded) cannot be
-- fled at all -- FF6's own rule, no escape until one side is cleared -- so
-- every held frame is free damage, and the full 1800 killed the party
-- BEFORE the tactical fallback ever engaged.  Worse, a wipe inside the
-- cap leaves no "flee: no release" line and no fallback log: the battle
-- ends, RandBattle's GameOver holds the event PC, and the step reads as a
-- parked navigator.  A small party on a meaty map wants a cap of a few
-- hundred frames (two or three failed run rolls), not ninety seconds.
M.FLEE_CAP = 1800

-- A PARTY WIPE MUST SAY SO.  Twice now a wipe has presented as something
-- else entirely: at Mt. Kolts cave 97 the drive tapped A through the Game
-- Over into a brand-new game and reported eleven maps of intro, and at
-- terra_clifftop a navigator spent SIXTY THOUSAND FRAMES planning routes
-- from field position (44,1888) -- a coordinate that only exists because
-- the field module no longer owned that RAM -- and failed as "navTo
-- timeout".  Neither log contained the word "died".
--
-- The character table at $1600 is the right FIELD check: it is save
-- state, not module-owned scratch, so it survives the battle module, the
-- menu module and the Game Over screen alike.  Debounced hard (300
-- frames) because a module handoff can blank things for a moment and a
-- false wipe would be worse than the timeout it replaces.
--
-- BUT $1600 KEEPS PRE-BATTLE HP WHILE A BATTLE RUNS -- the battle module
-- works on its own table at $3BF4 and syncs back at teardown, and a
-- battle that ends in a wipe tears down into the Game Over, where the
-- sync the field check is waiting on never says "dead".  Two steps
-- found this independently and converged on the same battle-side
-- signature (gen_sabin_gau's staging walk, gen_sabin_trench's dive):
-- every party slot whose battle MAX HP looks SANE -- nonzero and under
-- 1000, where a WoB max is a few hundred and module-transition garbage
-- reads tens of thousands -- showing zero HP.  M.partyWipedInBattle is
-- that signature lifted into the library; M.partyWiped consults it
-- first, so the navigators' canary names an in-battle wipe instead of
-- pressing buttons into the Game Over.
--
-- Related trap, documented where the shared check lives because the
-- copies are scattered through gens: the ad-hoc per-gen `inBattle()`
-- (read $3BF4 words, SKIP entries that are 0 or FFFF, first survivor
-- under 10000 decides) cannot see a DEAD party in battle at all --
-- every slot reads 0, every slot is skipped, the loop falls through to
-- "not in battle".  gen_sabin_trench's ride held LEFT at a Game Over
-- through three full 60000-frame budgets on exactly that blindness.
-- Any driver keying on that pattern needs this check beside it.
function M.partyWipedInBattle()
  if not M.battleLoadStarted() then return false end
  local want = 0
  for c = 0, 15 do
    if (M.readByte(0x1850 + c) & 0x07) ~= 0 then want = want + 1 end
  end
  if want < 1 or want > 4 then return false end
  local sane, alive = 0, 0
  for e = 0, 3 do
    local mx = M.readWord(0x3c1c + e * 2)
    if mx > 0 and mx < 1000 then
      sane = sane + 1
      if M.readWord(0x3bf4 + e * 2) > 0 then alive = alive + 1 end
    end
  end
  return sane >= want and alive == 0
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

local function wipeCanary(tag)
  local n = 0
  return function()
    n = M.partyWiped() and n + 1 or 0
    if n == 300 then
      error(string.format("%s: THE PARTY IS WIPED -- every member of the " ..
        "party has read 0 hp for 300 consecutive frames.  This is a lost " ..
        "fight, not a stuck navigator; the frames after a wipe are the " ..
        "Game Over screen and whatever the drive presses into it.", tag), 0)
    end
  end
end


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
-- `avoid` (optional) is a set of tile keys ((y<<8)|x) BFS must never route
-- THROUGH -- for tiles that are walkable but must not be stepped on: a
-- one-way entrance row sitting inside an otherwise ordinary region is the
-- motivating case (map 250's (22..24,34) door into 243, which the I->J
-- circuit crossed by ACCIDENT while walking somewhere else and could not
-- come back from -- issue #31).  The target tile itself is exempt, so a
-- route can still deliberately aim AT an avoided tile.
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
    if qi > 4096 then return nil end      -- sane radius: give up, not hang
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
function M.navDump()   -- debugging one-liner (kept from the old navigator)
  return string.format("bfs plan=%d idx=%d blocked=%d",
    NAV.plan or 0, NAV.idx or 0, NAV.nblocked or 0)
end

-- targets may be numbers or thunks (resolved each tick, so a route can
-- aim at a coord it only knows at runtime)
local function resolve(v) return type(v) == "function" and v() or v end

-- Walk to tile (tx,ty) on the current map: BFS a plan over the true
-- passability model, then execute it ONE VERIFIED STEP at a time.  Each
-- iteration (only when user-controlled and tile-aligned): press the step's
-- direction until the party is actually MOVING, release (a begun 16px step
-- always completes), wait for tile-alignment, and check the landing
-- against the plan.  A press that never moves us proves the model wrong
-- for that edge: blocklist it (persists across re-plans within this
-- navTo) and re-BFS.  Any deviation from the plan (event force-moves,
-- post-battle drift) also re-plans -- BFS is cheap, guessing isn't.
-- Encounters that fire mid-walk are cleared inline by writing the
-- battle-clearing flag UNLESS the formation matches opts.spare (the goal
-- fight: hands off, let opts.arrive see it).  Dialogs are advanced with
-- EDGE-pressed A; other control losses (events walking the party) get a
-- neutral pad.
--   opts.avoid     list of {x,y} the plan must never route THROUGH (a
--                  one-way entrance inside a walkable region); the goal
--                  tile itself is exempt
--   opts.arrive    extra terminator predicate (checked before everything)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     list of formation species words never to clear by a
--                  flag write
--   opts.playBattles  clear mid-route battles by REAL PLAY instead of the
--                  flag write -- ZERO state writes on this navigator (issue
--                  #75).  Opt-in while unconverted generators still lean on
--                  the flag write; costs real ATB rounds per encounter, so
--                  input-driven steps budget more frames.  Three spellings,
--                  the same contract worldNavTo carries:
--                  true    auto-fight by edge-tapped A (the taps already
--                          driving the victory text double as a fighter:
--                          A opens the command list, A confirms its first
--                          entry, A takes the default target);
--                  "tactical"  read the live command table and use Edgar's
--                          Tools, Sabin's Blitz, and Fight for everyone else,
--                          with the driver's own item medic line.  It heals
--                          at opts.healPercent (default 55).  That default
--                          was 35 and 35 was too late: measured on map 98
--                          (Trilium + Tusker + two Cirpius), a party healing
--                          only below a third spent FIVE Fenix Downs on one
--                          step -- reviving is what healing late costs, and a
--                          Tonic is fifty gil against five hundred;
--                  "flee"  hold L+R, the engine's own run mechanic.  A
--                          fled battle is not a WIN, so win-only rolls
--                          (SHADOW's 1/16 post-battle leave,
--                          battle_main.asm:11976) never happen -- the
--                          Sabin chain's whole reason to run.  A formation
--                          that has not released the party after
--                          M.FLEE_CAP consecutive battle frames is fought
--                          out by edge-tapped A instead of hanging the step
--                          (unrunnable formations exist and a run that
--                          cannot end is not real play, it is a timeout);
--                          callers pick fight vs flee per step and say why.
--   opts.calmFrames  consecutive settled frames on the goal tile the
--                  terminator requires (default 16; see ISSUE #22 below)
--   opts.noPathRetries  BFS-no-path retries, 45 idle frames apart, before
--                  erroring (default 20).  A no-path is often TRANSIENT:
--                  an NPC standing in a one-tile corridor blocks the
--                  object map exactly while its scene runs (the Figaro
--                  gate guard, measured), and erroring instantly turned
--                  every such scene into a route failure.
--
-- ISSUE #22 -- WHY THE PRESS ENDS ON "MOVING" AND THE TERMINATOR ON "STOPPED".
-- Both rules used to key on the TILE COORD changing, and both were wrong for
-- rightward and downward steps.  Measured per frame on map 242 with
-- probe_step2 (party at {57,34}, 1 px/frame):
--
--   f01..f05  py=544  aligned, not moving yet (the press has not latched)
--   f06..f20  py=545..559          walking; tile coord still 34
--   f21       py=560  ALIGNED, tile coord flips to 35 -- arrival
--   f22..f37  py=561..576          a SECOND tile, unasked for
--
-- Moving up or left the coord flips ~1px in, so releasing on the change was
-- always early enough; moving down or right it flips only AT completion --
-- the same frame the engine re-reads the pad for the next step, and a
-- setPad only reaches the ROM at the NEXT input poll.  So the release landed
-- one poll late and the engine latched another step whenever the tile beyond
-- was passable.  Two consequences, both measured: every rightward/downward
-- step overshot by one tile, and the terminator ("on the tile, controlled,
-- tile-aligned") fired on the single aligned frame at f21 -- reporting
-- success from a tile the party then walked straight off.  End to end on
-- vector_sneak: navTo(57,35) returned at (57,35) and the party was at
-- (57,36) sixty frames later.  (The original report's case:
-- navTo(45,38) returned success with the party at (46,38).)
--
-- The fix is the one the v0.6 generators' local tapWalk already proved:
--   * release as soon as the party is DEMONSTRABLY MOVING -- the first frame
--     tileAligned() goes false.  That is direction-independent (it does not
--     care when pixel>>4 happens to flip), speed-independent (map 41 walks
--     ~1.33 px/frame with jitter, map 242 exactly 1), and it is as early as
--     a release can possibly be while still proving the step committed.
--   * require the party to be STOPPED, not merely aligned for one frame:
--     opts.calmFrames consecutive settled frames on the goal tile.  While
--     walking, tileAligned() is false for 15 of every 16 frames, so a run of
--     16 aligned frames on one tile cannot happen mid-step -- which is
--     exactly why tapWalk's terminator counts them.
--
-- WHY "STOPPED" IS NOT SPELLED "hasControl() FOR 16 FRAMES".  Plenty of goal
-- tiles take the party away the instant it lands: a step-on trigger, a map
-- edge, a scene.  gen_mines_chase's is the sharpest -- (38,8) on the Narshe
-- clifftop fires the guard scene and leaves the party STANDING ON the
-- trigger, which then re-fires every four frames forever, so hasControl()
-- never holds for more than a frame at a time (that generator's own comment
-- says so).  A control-gated run of 16 hangs there until the frame budget.
-- So stillness is counted on ALIGNMENT ALONE -- which is the direct
-- measurement of "not walking" and needs no control flag -- and control is
-- only used to decide HOW LONG a run has to be: with control, calmFrames is
-- arrival; without it, three times that, because something took the party
-- over while it stood on the goal and the flag cannot corroborate the rest.
-- Battle and dialog frames are excluded from the run outright: clearing
-- those is navTo's own job, not something to terminate in the middle of.
function M.navTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local calmWant = opts.calmFrames or 16
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  -- opts.avoid = { {x,y}, ... }: walkable tiles the plan must never route
  -- THROUGH (one-way entrances mid-region); see M.bfsPath
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
  -- built for "tactical" AND for "flee": the flee branch falls back to it
  -- once M.FLEE_CAP says this formation is not letting go
  local wipeCheck = wipeCanary("navTo")
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee")
      and M.newFightDriver("navTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic }) or nil
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
      -- STOPPED on the goal tile, not passing through it (see ISSUE #22).
      calm = (M.fieldX() == resolve(txIn) and M.fieldY() == resolve(tyIn)
          and M.tileAligned() and not M.battleLoadStarted()
          and not M.dialogWaiting()) and calm + 1 or 0
      done = calm >= calmWant and (M.hasControl() or calm >= calmWant * 3)
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
      wipeCheck()
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      lostN = M.hasControl() and 0 or lostN + 1
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it, but NEVER the goal formation
      if battN >= 3 then
        drop("battle")
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})                 -- goal fight: hands off, arrive() sees it
          return
        end
        if opts.playBattles == "flee" then
          -- L+R is the engine's own run mechanic; M.FLEE_CAP is the point
          -- at which "still holding" stops being a run and starts being a
          -- slow death, and the battle is fought out instead.  The fallback
          -- is the TACTICAL driver, not a blind A-tap: a party that has
          -- already spent M.FLEE_CAP frames being hit needs its own item
          -- menu more than it needs a first command row.
          if battN <= (opts.fleeCap or M.FLEE_CAP) then
            M.setPad({ l = true, r = true })
            return
          end
          if battN == (opts.fleeCap or M.FLEE_CAP) + 1 then
            M.log(string.format("flee: no release after %d frames; " ..
              "fighting this formation out", opts.fleeCap or M.FLEE_CAP))
          end
          tactical.frame()
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is about to be "cleared"
        -- by BLIND A-TAPS -- no menu awareness, no items, no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still ride it, but it must never be
        -- ridden SILENTLY: converted routes want playBattles="flee" (corridor
        -- trash) or playBattles="tactical" (fights that matter).
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
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
      -- 4. a step is in flight: hold only until the party is MOVING (the
      --    first frame it is off tile-alignment), then release -- see the
      --    ISSUE #22 block above for why "until the tile coord changes" is
      --    one input poll too late for right/down.
      if pend and pend.holding then
        -- the coord test is kept as a BACKSTOP, never as the primary rule:
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
        -- An EMPTY plan means we are already standing on the goal and are
        -- only waiting out the terminator's calm frames.  Say nothing and
        -- idle: logging (and re-BFSing) that every frame buried the real
        -- plan lines under a screenful of "planned 0 steps" once the
        -- terminator started insisting the party be stopped.
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

-- Ride out a NON-INTERACTIVE story stretch: long automatic events with
-- intermittent dialogs and scripted battles (the esper-scene class).  The
-- hands-off companion to navTo -- no walking, no plan, just keep the story
-- unstuck until pred() is truthy (checked every frame; raises after
-- maxFrames).  Frames are classified with navTo's 3-frame debounce (the
-- battle/dialog signal bytes live in RAM the field module also scribbles
-- on; acting on a one-frame ghost would tap A on the open field):
--   battle  -> flag-clear everything present + edge-tap A through the text
--              (with opts.playBattles, NO flag write: the same edge-tapped A
--              auto-fights the encounter for real -- zero state writes,
--              issue #75 -- at the price of real ATB rounds).
--              A formation matching opts.spare is a scripted set-piece:
--              never cleared by a flag write, and hands OFF for its first
--              300 frames,
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
  local wipeCheck = wipeCanary("advanceStory")
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee")
      and M.newFightDriver("advanceStory",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic }) or nil
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
      wipeCheck()
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
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
        -- playBattles="flee" was accepted here and then IGNORED: every navigator
        -- had a flee branch and this one did not, so a settle that rolled an
        -- encounter blind-tapped A through a whole fight while its caller's
        -- header said the route runs from them.  Measured on gen_kolts
        -- (2026-08-09): the mountain settles fought Cirpius packs by tap-A,
        -- which is how the party reached VARGAS with TERRA dead and EDGAR on
        -- 1 hp.  Same contract as navTo's, cap included.
        if opts.playBattles == "flee" then
          if battN <= (opts.fleeCap or M.FLEE_CAP) then
            M.setPad({ l = true, r = true })
            return
          end
          if battN == (opts.fleeCap or M.FLEE_CAP) + 1 then
            M.log(string.format("flee: no release after %d frames; " ..
              "fighting this formation out", opts.fleeCap or M.FLEE_CAP))
          end
          tactical.frame()
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is about to be "cleared"
        -- by BLIND A-TAPS -- no menu awareness, no items, no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still ride it, but it must never be
        -- ridden SILENTLY: converted routes want playBattles="flee" (corridor
        -- trash) or playBattles="tactical" (fights that matter).
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
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
-- field bfsPath.  The node cap is 60000, not the field's 4096: world
-- segments run 60+ tiles (Narshe->Figaro BFS'd 63 steps, probe_world3) and
-- the search disc grows quadratically with them -- the I->J crash-site
-- grind is ~117 steps and its disc blew straight through the old 20000
-- cap, which returned nil and left worldGrind idling to its frame
-- budget (measured, probe_banquet_stage run 2, 2026-07-28).
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
--    ReloadMap after -- measured: flag-write clear, then ~95 frames of
--    fade/init, position and facing back exactly, danger counter zeroed.
--    The walker clears non-spared battles inline (flag write + edge-A) and
--    stalls until the reload finishes (aligned + full brightness) before
--    planning again
--  * no dialog branch: world triggers run world event scripts, not the
--    field dialog engine; $BA/$D3 are stale field RAM here
--   opts.arrive    extra terminator (checked first, every frame)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     formation species words never to clear by a flag write
--   opts.playBattles  end mid-walk battles by REAL PLAY instead of the
--                  flag write -- ZERO state writes on this navigator (issue
--                  #75), the same opt-in contract navTo/advanceStory carry.
--                  true    = auto-fight by edge-tapped A (A opens the acting
--                            character's command list, A confirms its first
--                            entry, A takes the default target; the same
--                            taps page the victory text);
--                  "tactical" = read the live command table and use Edgar's
--                            Tools, Sabin's Blitz, and Fight for everyone else;
--                  "flee"  = hold L+R, the engine's own run mechanic.  On a
--                            fixture chain this is often the RIGHT
--                            input-driven ending for world trash: it earns
--                            no win, so
--                            win-only rolls (SHADOW's 1/16 post-battle
--                            leave, battle_main.asm:11976) never happen --
--                            but it FAILS (times out) on unrunnable
--                            formations, so callers pick fight vs flee per
--                            step and say why.  Either way the post-battle
--                            world reload restores the pre-battle tile with
--                            the danger counter zeroed (move.asm:916-921 /
--                            world_start.asm:465-482), and the walker
--                            re-plans from it.  Input-driven endings cost
--                            real ATB rounds; budget frames accordingly.
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
  local wipeCheck = wipeCanary("worldNavTo")
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee")
      and M.newFightDriver("worldNavTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic }) or nil
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
      wipeCheck()
      battN = M.battleLoadStarted() and battN + 1 or 0
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it (never a spared formation), then let the
      --    world reload run out before touching the plan again
      if battN >= 3 then
        plan, pend = nil, nil
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})
          return
        end
        if opts.playBattles == "flee" then
          -- L+R is the engine's own run mechanic; M.FLEE_CAP is the point
          -- at which "still holding" stops being a run and starts being a
          -- slow death, and the battle is fought out instead.  The fallback
          -- is the TACTICAL driver, not a blind A-tap: a party that has
          -- already spent M.FLEE_CAP frames being hit needs its own item
          -- menu more than it needs a first command row.
          if battN <= (opts.fleeCap or M.FLEE_CAP) then
            M.setPad({ l = true, r = true })
            return
          end
          if battN == (opts.fleeCap or M.FLEE_CAP) + 1 then
            M.log(string.format("flee: no release after %d frames; " ..
              "fighting this formation out", opts.fleeCap or M.FLEE_CAP))
          end
          tactical.frame()
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is about to be "cleared"
        -- by BLIND A-TAPS -- no menu awareness, no items, no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still ride it, but it must never be
        -- ridden SILENTLY: converted routes want playBattles="flee" (corridor
        -- trash) or playBattles="tactical" (fights that matter).
        if opts.playBattles == true and battN % 3600 == 3 then
          M.log('playBattles=true IS FIGHTING THIS BATTLE BY BLIND A-TAPS -- ' ..
            'no menus, no items, no flee.  If this step loses parties or ' ..
            'drags, convert it: playBattles="flee" or playBattles="tactical".')
        end
        if M.monstersPresent() > 0 and not opts.playBattles then
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

-- Drive a route that crosses engine modes: `legs` = { {mode="field", x, y,
-- opts}, {mode="world", x, y, opts}, ... }.  Between steps the engine is
-- expected to change modes on its own (an exit tile fires as the
-- previous step lands, a world trigger loads a field map); each step first
-- waits for its declared mode plus the matching settle checks -- control,
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

-- --------------------------------------- timed-tilemap (phase) rooms --
-- Some rooms are TWO complementary tilemaps swapped on an event timer:
-- BASEMENT 2 of the Sealed Gate cave (map 385) swaps every 158 frames
-- once armed, and the reachable set inside either phase is a dead end --
-- the crossing exists only ACROSS the swaps.  navTo cannot drive such a
-- room (every edge is legitimately dead half the time and would be
-- condemned), so this walker plans over the UNION graph instead.
--
-- The mechanism, measured on map 385 (probe_v07_385win, 2026-07-28; the
-- room's scripts are event_main.asm:44634-44905):
--   * every swap callback rewrites the tilemap BEFORE it flips the phase
--     switches (`call _cb2b24` then `switch $01F5=0/$01F6=1`, and the
--     same shape in all four callbacks), so there is a ~13-frame WINDOW
--     (fsf 145..157 of the 158 cycle) where the NEXT phase's floor is
--     physically in place while the switches -- and the hurt triggers
--     keyed on them -- still show the OLD phase;
--   * a held press into a tile the window just opened is taken by the
--     engine at fsf ~148; the party is MID-STEP when the switches flip,
--     and mid-step does not fire the stood-on tile's hurt trigger
--     (arrival on the far side runs the destination's trigger in the NEW
--     phase, where it EventReturns);
--   * hurt tiles are ordinary event-trigger tiles, and a stood-on
--     trigger tile re-enters its script every frame -- hasControl()
--     flickers there, so every press here is UNCONDITIONAL (the
--     re-entry-trap escape idiom);
--   * random encounters are a state RESTORE, not a LoadMap: the phase
--     switches and timers SURVIVE the battle round-trip (measured,
--     probe_v07_385door), but the dead cycle's half of the tilemap is
--     re-based by map-init, so after a battle the walker re-snapshots
--     and re-plans.
--
-- M.phaseWalk(tx, ty, spec) returns a step that walks the party to
-- (tx,ty) across the swaps.  spec (all fields required unless noted):
--   switches   = { a = 0x01F5, b = 0x01F6 }  -- the two phase switches;
--                edges on `b` are the clock (on 385 only the four timer
--                callbacks touch $01F6, so its edges are exactly the
--                swap instants -- pick the switch with that property)
--   period     = 158            -- measured frames between swaps
--   region     = { w = 17, h = 16 }
--   hurt       = { a = {{x,y},...},   -- tiles that hurt while switch a
--                  b = {{x,y},...},   -- ... while switch b is on
--                  always = {{x,y},...} }
--   avoid      = { {x,y}, ... } -- optional; tiles BFS must never use
--                (e.g. the OTHER cycle's arming triggers, which would
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
      battN = M.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        if plan or lastFlip then
          M.log(string.format("[phaseWalk] encounter at f%d -- battle-clear write, "
            .. "then re-observe", M.frame))
        end
        plan, grids, lastFlip, lastB = nil, {}, nil, nil
        begunSeg, hp0, obsStart = -1, nil, nil
        for s = 0, 5 do
          if M.readByte(0x3aa8 + s * 2) % 2 == 1 then
            M.writeByte(0x3eec + s * 2, M.readByte(0x3eec + s * 2) | 0x80)
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
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
        -- there): step off before observing -- a swap would hurt
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
-- Talk to a WANDERING NPC: re-plan the approach every aligned frame
-- (BFS one step toward any neighbor of the object's live tile), face it,
-- edge A+direction; plain dialogs advanced with edge-A; STOPS the moment
-- a CHOICE list is up ($056F >= 2) so a blind A can never answer it.
-- Written for the Blackjack party-swap room's random-walking TERRA
-- (probe_v07_g2h, 2026-07-28); nothing in it is specific to her.
--   objIdx: the NPC's object index ($10 + record order in npc_prop)
--   opts.done (optional): custom terminator; the default is
--     "a choice dialog is up and waiting"
--   opts.avoid (optional): a tile SET (keys ((y<<8)|x)) the approach must
--     never route through -- one-way entrances near the chase area
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
            M.writeByte(0x3eec + s * 2, M.readByte(0x3eec + s * 2) | 0x80)
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
-- Promoted from gen_vector_crash (2026-07-28, pre-approved in the I->J
-- dispatch) the moment a second step needed both: the banquet's dais is the
-- same face-UP+A trigger class as 384's levers, and its boot/exit tiles are
-- the same stood-on re-entry class as the SavePoint boot.

-- The measured lever idiom (probe_v07_384toggle): ONE 8-frame up+A tap
-- fires the event and the switch flips at its END (~70 frames); holding UP
-- with A released never re-fires; a SECOND A press on a TOGGLE tile flips
-- it back.  So: tap once, hold up, wait for the flip.  Dialogs opened by
-- the event are advanced with edge-A; a battle that fires on the tile is
-- cleared by a flag write (no lever on any route so far draws one, but the
-- world module has surprised this harness before).
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
            M.writeByte(0x3eec + s * 2, M.readByte(0x3eec + s * 2) | 0x80)
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
-- UNCONDITIONAL held press leaves).  Cycles dirs 40 frames each until the
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
            M.writeByte(0x3eec + s * 2, M.readByte(0x3eec + s * 2) | 0x80)
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
-- M.fieldCare: open the FIELD MENU and heal or revive the party with real
-- presses, then close it again.  Zero state writes (issue #75) -- every
-- point of HP this restores is restored by the game's own item code,
-- driven the way a player drives it.
--
-- WHY THIS EXISTS.  The input-driven routes run from random encounters, and
-- a run is not free: the party takes a round or two of hits every time the dice
-- say no.  Measured on gen_kolts (2026-08-09), the mountain crossing spent
-- TERRA from 94 to 39 and then the map-98 approach took her to 1 and EDGAR
-- from 106 to 1, at which point four straight played-out VARGAS attempts wiped
-- -- while SEVEN POTIONS AND FIVE TONICS sat unused in the bag the whole
-- way.  The route was not too hard; nobody was playing the item menu.
--
-- THE UI, measured by probe_fieldheal.lua / probe_fieldcells.lua against a
-- real vargas_doorstep and cross-read against src/menu (the full citation
-- trail is docs/research/field-care-menu.md):
--
--   ZMENUSTATE = DP $26, and the shared list cursor is DP $4B.
--   $05 main menu, Item on row 0
--     -A-> $08 the item list itself -- there is NO options window in front
--          of it, and $4B here IS the inventory slot (one column)
--     -A-> $19 "slot picked up".  A on a DIFFERENT slot SWAPS the two; A on
--          the SAME slot is what calls UseItem (field_menu.asm:2331-2336).
--          A first pass tapped A toward $08 and then pressed A again with a
--          moved cursor, and quietly rearranged the bag instead of using
--          anything.
--     -A-> $70 target select: $4B is the MENU slot 0..3 (battle order, not
--          party order), moved by up/down only; $69+slot holds that slot's
--          character id, which is how a character maps to a cursor row.
--     -A-> the item is applied and the window STAYS on $70, so serving a
--          second character with a different item has to back out ($77 ->
--          $08) rather than press on.
--   B from $08 lands on the item options window $17, then $04, then out.
--
--   REFUSALS ARE READABLE.  CheckCanUseItem (item.asm:2243-2330) allows only
--   a Fenix Down on a KO'd target and allows Tonic/Potion only on a living
--   character below full HP; an invalid pick sets DP $B5 (zMosaic) nonzero
--   for about eight frames.  This driver watches that cell and gives up on
--   that (character, item) pair instead of mashing A at a window that will
--   never accept it.
--
-- opts.threshold  heal a living member below this fraction of max HP
--                 (default 0.55)
-- opts.reserve    { [itemId] = n } -- keep n of that item unspent, so a step
--                 can hold Potions back for the fight it is walking toward
-- opts.maxFrames  budget for the whole visit (default 24000)
-- opts.tag        log prefix
--
-- It is a no-op -- not even a menu open -- when nobody needs anything, so a
-- route can call it after every step and pay only where it matters.
-- Both M.fieldCare and M.setRows can be called on a field map or on the
-- overworld, and "the menu is closed and the party has control again" is a
-- different question on each: the world module has its own position and
-- control registers and every field predicate is meaningless there.
--
-- AND THE ANSWER IS ONLY TRUSTWORTHY HELD, not glimpsed.  Measured on
-- the overworld (gen_sabin_gau's staging walk, 2026-08-09): the close
-- drive's exit read one satisfying frame mid-handoff -- "back to the
-- field satisfied after 58 frames" -- while the MAIN MENU was still
-- open behind it (ZMENUSTATE=05), because the world control/alignment
-- registers held stale-live values during the menu module's teardown.
-- The caller's walk then parked against an invisible open menu for its
-- whole budget, every single care stop, until it grew its own B-tap
-- recovery.  So the WORLD close is now DEBOUNCED: its condition must
-- hold 30 consecutive frames before the close is believed, a stale-live
-- coincidence cannot survive that.
--
-- BUT THE DEBOUNCE IS WORLD-MODE ONLY, because only the world close was
-- ever broken.  On a FIELD map hasControl() already reads false for the
-- entire menu lifetime and snaps true only once the field module is
-- genuinely back (measured: the pre-dive close sampled ctl=false
-- straight through the menu, then ctl=true stable) -- so the field exit
-- is correct on the FIRST true frame and needs no wait, and forcing 30
-- CONSECUTIVE true frames there instead HANGS it: every B tap the close
-- driver sends to shut the menu drops control for that frame, and
-- 4-of-12 tapping never leaves 30 clean frames in a row (measured:
-- 2400-frame timeout with ctl=true on every heartbeat).  careClose()
-- below carries that split; careBackOnMap() is the raw predicate it and
-- the setRows first stage build on.
local function careBackOnMap()
  if M.worldMode() then return M.worldHasControl() and M.worldAligned() end
  return M.hasControl() and M.tileAligned()
end

-- careClose: the close predicate a care/rows drive waits on.  ONE
-- closure, deciding world vs field at RUNTIME every frame (the step
-- table is built before H.run starts, so the mode cannot be resolved
-- when this is called).
--
--   WORLD -> debounced (30 consecutive true frames) AND the
--   ZMENUSTATE-still-a-menu guard: the world menu module keeps $26 at
--   05 through the half-close, so a single satisfying frame is a
--   stale-live coincidence mid-handoff -- the bug this whole change
--   exists for.
--   FIELD -> raw single frame plus the caller's own ZM guard: on the
--   field hasControl() reads false for the entire menu lifetime and
--   snaps true only when the field module is genuinely back, so the
--   first true frame is correct.  Debouncing it instead HANGS (every
--   B tap the close driver sends drops control for a frame; 4-of-12
--   tapping never leaves 30 clean frames in a row).
local function careClose(zmExtra)
  local calm = 0
  return function()
    if M.worldMode() then
      local zm = M.readByte(0x26)
      local ok = M.worldHasControl() and M.worldAligned()
             and zm ~= 0x05 and zm ~= 0x08
      calm = ok and calm + 1 or 0
      return calm >= 30
    end
    return M.hasControl() and M.tileAligned()
       and (zmExtra == nil or zmExtra())
  end
end

local CARE_ZM, CARE_CUR, CARE_REFUSE = 0x26, 0x4b, 0xb5
local CARE_TONIC, CARE_POTION, CARE_FENIX = 0xE8, 0xE9, 0xF0

function M.charHp(c) return M.readWord(0x1600 + 37 * c + 9) end

-- Max HP is NOT a plain word: the top two bits carry an HP-boost code and
-- the effective maximum is the base plus a percentage of it, clamped to
-- 9999 (menu_common.asm:2377-2436).  Nothing in the World of Balance chain
-- has a boost set yet -- every roster dump so far reads a bare base -- so
-- the percentages below are transcribed from the source, not measured, and
-- are marked as such deliberately.
function M.charMaxHp(c)
  local w = M.readWord(0x1600 + 37 * c + 11)
  local base, code = w & 0x3fff, w >> 14
  local add = ({ [0] = 0, [1] = base // 4, [2] = base // 8,
                 [3] = base // 2 })[code]
  local v = base + add
  return v > 9999 and 9999 or v
end

function M.partyMembers()
  local out = {}
  for c = 0, 15 do
    if (M.readByte(0x1850 + c) & 0x07) ~= 0 then out[#out + 1] = c end
  end
  return out
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

-- M.buyItem: buy `qtyFn()` MORE of shop row `row`, fully CLOSED-LOOP,
-- with the shop ALREADY OPEN at its options window (menu state $25).
-- Promoted from gen_sabin_train/gen_sabin_gau, where two identical
-- copies had earned every line the hard way:
--
--  * The list cursor row is MoveCursor's own cell (DP $4E,
--    menu_common.asm:1318) and the quantity is zSelIndex (DP $28,
--    menu_ram.inc) -- both READ and STEERED, never press-counted (menu
--    direction holds auto-repeat: a counted 4-frame hold measurably
--    bought 25 Tonics instead of 14 and parked the next lap on the
--    wrong row).  Widget deltas (shop.asm MenuState_27): RIGHT +1,
--    LEFT -1, UP +10, DOWN -10, gil-clamped by the handler.
--  * THE CLAMP IS THE PURSE'S ANSWER: steering toward a want the gil
--    cannot cover pins qty at the affordable maximum, and a loop that
--    keeps pressing burns its whole budget against that wall
--    (gen_sabin_gau's "TONIC to 99" on 209 gil -- FAIL, timeout at
--    20000).  A player buys what the purse covers; 240 unmoving frames
--    against the clamp accept the clamped qty, loudly.  Order the buys
--    so the marginal item comes LAST and a poor purse shorts it, never
--    the essentials.
--  * Purchases are verified AFTER the shop closes; mid-menu inventory
--    reads measurably lie (the field bag does not update until the
--    shop hands RAM back).
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

function M.fieldCare(opts)
  opts = opts or {}
  local tag = opts.tag or "care"
  local thresh = opts.threshold or 0.55
  local reserve = opts.reserve or {}
  local budget = opts.maxFrames or 24000

  local function avail(id)
    return math.max(0, M.invCountOf(id) - (reserve[id] or 0))
  end

  local failed = {}                    -- "char:item" pairs the game refused
  local function key(w) return w.char .. ":" .. w.item end

  -- What a player would do, in the order they would do it: raise the dead
  -- first, then top up whoever is worst off, spending the cheap item when
  -- the cheap item covers the hole.
  local function pick()
    for _, c in ipairs(M.partyMembers()) do
      if M.charHp(c) == 0 and avail(CARE_FENIX) > 0
         and not failed[c .. ":" .. CARE_FENIX] then
        return { char = c, item = CARE_FENIX, why = "revive" }
      end
    end
    local best, bestR = nil, 1.0
    for _, c in ipairs(M.partyMembers()) do
      local hp, mx = M.charHp(c), M.charMaxHp(c)
      if hp > 0 and mx > 0 and hp < mx then
        local r = hp / mx
        if r < thresh and r < bestR then best, bestR = c, r end
      end
    end
    if best == nil then return nil end
    local hole = M.charMaxHp(best) - M.charHp(best)
    local order = hole >= 120
      and { CARE_POTION, CARE_TONIC } or { CARE_TONIC, CARE_POTION }
    for _, id in ipairs(order) do
      if avail(id) > 0 and not failed[best .. ":" .. id] then
        return { char = best, item = id, why = "heal" }
      end
    end
    return nil
  end

  local function anyNeed() return pick() ~= nil end

  -- menu slot (the $70 cursor row) for a character id
  local function slotOf(c)
    for s = 0, 3 do
      if M.readByte(0x69 + s) == c then return s end
    end
    return nil
  end

  local phase, served, want, pending, rewind, tries = 0, false, nil, nil, false, 0

  local function steer(cur, wantRow)
    if cur == wantRow then return { "a" } end
    return { [cur < wantRow and "down" or "up"] = true }
  end

  local function serveFrame()
    phase = (phase + 1) % 12
    local st = M.readByte(CARE_ZM)

    -- a refusal is the game telling us this pair is illegal; believe it
    if want and M.readByte(CARE_REFUSE) ~= 0 then
      M.log(string.format("[%s] REFUSED: char %d / item $%02X (zMosaic set)",
        tag, want.char, want.item))
      failed[key(want)] = true
      want, pending, rewind = nil, nil, true
      M.setPad({})
      return
    end

    -- did the last confirm land?
    if pending then
      if M.charHp(pending.char) ~= pending.hp
         or M.invCountOf(pending.item) < pending.qty then
        M.log(string.format("[%s] used $%02X on char %d: %d -> %d hp, %d left",
          tag, pending.item, pending.char, pending.hp,
          M.charHp(pending.char), M.invCountOf(pending.item)))
        want, pending, rewind = nil, nil, true
      end
    end

    if want == nil then
      want = pick()
      if want == nil then served = true; M.setPad({}); return end
      tries = tries + 1
      if tries > 16 then
        M.log(string.format("[%s] giving up after %d attempts", tag, tries))
        served = true; M.setPad({}); return
      end
      M.log(string.format("[%s] plan: %s char %d with $%02X (%d/%d hp)",
        tag, want.why, want.char, want.item,
        M.charHp(want.char), M.charMaxHp(want.char)))
    end

    local held = nil
    if rewind then
      -- back out to the item list before selecting a different item
      if st == 0x08 then rewind = false else held = { "b" } end
    end
    if held == nil then
      if st == 0x05 then
        held = steer(M.readByte(CARE_CUR), 0)
      elseif st == 0x08 then
        local slot = M.invSlotOf(want.item)
        if slot == nil then
          failed[key(want)] = true; want = nil; M.setPad({}); return
        end
        held = steer(M.readByte(CARE_CUR), slot)
      elseif st == 0x19 then
        -- A here only USES the item if the cursor is still on the slot it
        -- was picked up from; anywhere else it swaps two items instead
        local slot = M.invSlotOf(want.item)
        held = (slot and M.readByte(CARE_CUR) == slot) and { "a" } or { "b" }
      elseif st == 0x70 then
        local slot = slotOf(want.char)
        if slot == nil then
          M.log(string.format("[%s] char %d is not on the target window " ..
            "(slots %d,%d,%d,%d)", tag, want.char, M.readByte(0x69),
            M.readByte(0x6a), M.readByte(0x6b), M.readByte(0x6c)))
          failed[key(want)] = true; want = nil; M.setPad({}); return
        end
        local cur = M.readByte(CARE_CUR)
        if cur == slot then
          pending = { char = want.char, item = want.item,
                      hp = M.charHp(want.char),
                      qty = M.invCountOf(want.item) }
          held = { "a" }
        else
          held = steer(cur, slot)
        end
      elseif st == 0x17 or st == 0x77 then
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

  return M.cond(anyNeed, {
    M.logStep(function()
      local out = {}
      for _, c in ipairs(M.partyMembers()) do
        out[#out + 1] = string.format("c%d %d/%d", c, M.charHp(c),
          M.charMaxHp(c))
      end
      return string.format("[%s] opening the menu: %s | tonic=%d potion=%d " ..
        "fenix=%d", tag, table.concat(out, " "), M.invCountOf(CARE_TONIC),
        M.invCountOf(CARE_POTION), M.invCountOf(CARE_FENIX))
    end),
    M.driveUntil(function() return M.readByte(CARE_ZM) == 0x05 end, 1800, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "x" } or {})
      end),
    }, tag .. ": field menu open"),
    M.release(),
    M.waitFrames(10),
    M.driveUntil(function() return served end, budget, {
      M.call(serveFrame),
    }, tag .. ": heal/revive through the item menu"),
    M.release(),
    M.driveUntil(careClose(function()
      local zm = M.readByte(CARE_ZM)
      return zm ~= 0x05 and zm ~= 0x08
    end), 2400, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "b" } or {})
      end),
    }, tag .. ": back to the field"),
    M.release(),
    M.waitFrames(30),
    M.logStep(function()
      local out = {}
      for _, c in ipairs(M.partyMembers()) do
        out[#out + 1] = string.format("c%d %d/%d", c, M.charHp(c),
          M.charMaxHp(c))
      end
      return string.format("[%s] done: %s | tonic=%d potion=%d fenix=%d",
        tag, table.concat(out, " "), M.invCountOf(CARE_TONIC),
        M.invCountOf(CARE_POTION), M.invCountOf(CARE_FENIX))
    end),
  }, {
    -- A care stop that does nothing must still SAY so.  The first run with
    -- this driver silently skipped its most important stop and the roster
    -- three lines later was the only evidence; "no log" and "nothing needed"
    -- are not allowed to look the same.
    M.logStep(function()
      local out = {}
      for _, c in ipairs(M.partyMembers()) do
        out[#out + 1] = string.format("c%d %d/%d", c, M.charHp(c),
          M.charMaxHp(c))
      end
      return string.format("[%s] nothing to do: %s | tonic=%d potion=%d " ..
        "fenix=%d", tag, table.concat(out, " "), M.invCountOf(CARE_TONIC),
        M.invCountOf(CARE_POTION), M.invCountOf(CARE_FENIX))
    end),
  })
end

-- ---------------------------------------------------------------- rows --
-- M.setRows: put characters in the FRONT or BACK row through the real Order
-- screen.  Reads and pad presses only (issue #75).
--
-- WHY.  Owner note, 2026-08-09: "a lot of ranged attackers can just sit in
-- the back row forever at no cost."  He is right, and no fixture in this
-- chain had ever set a row -- every input-driven route walked its whole party
-- into the front rank and paid full physical damage for it.
--
-- THE EXEMPTION IS REAL IN THIS ROM, not inherited lore.  ExecCmd sets
-- $B3 = $FF at the top of EVERY command (battle_main.asm:3131-3133), and
-- bit $20 there means "ignore attacker row" -- so no row penalty is the
-- DEFAULT.  Exactly one routine clears it: the weapon-swing setup
-- _c2299f (battle_main.asm:7127-7133), and only when the main-hand weapon
-- lacks WEAPON_FLAG::BACK_ROW.  So a back-row character loses damage only
-- on a Fight; EDGAR's Tools and TERRA's Magic and SABIN's Blitz never
-- reach that code and cost nothing.  Damage TAKEN is halved for physical
-- either way.  LOCKE is the one who genuinely trades -- Steal deals no
-- damage, so Fight is all he has -- and this route leaves him in front.
-- Full citation trail: docs/research/row-menu.md.
--
-- THE UI, and the two things that make it not-obvious:
--   * the Order screen has NO main-menu row.  It is reached by pressing
--     LEFT on the main menu ($05), a handler beside the A handler that
--     never goes through SelectMainMenuOption (field_menu.asm:571-576,
--     :3491-3508); the menu SCROLLS sideways ($65) to reveal the word
--     "Order", which is drawn off the visible edge.
--   * the toggle is A TWICE ON THE SAME SLOT.  MenuState_10 compares
--     zSelIndex ($28) to the cursor ($4B); a second A on a DIFFERENT slot
--     is a party REORDER, not a row flip (field_menu.asm:1845-1870).  So
--     the cursor must not move between the two presses, and this driver
--     verifies $28 before the second press and treats state $11 (the
--     swap) as a hard error rather than something to recover from.
--   * the row bit is at $1850 + charIdx, bit $20 -- the party/order byte,
--     NOT the $1600 stat block.  The menu's working copy is $75 + slot.
--
-- spec: { [charIdx] = true (back row) | false (front row) }
-- A no-op, menu never opened, when every listed character is already right.
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
      -- the pick-up landed on the slot we aimed at?  if not, back out --
      -- pressing A here would reorder the party
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

-- M.equipEsper: equip a SPECIFIC magicite on the character at char-select
-- position `pos`, through the real Skills -> Espers -> detail -> A walk
-- (skills.asm MenuState_4d @5902 is the equip).  Reads and pad presses
-- only (issue #75).  Written for the Cranes re-test (2026-08-10): the
-- fight's designed key is BISMARK's Sea Song -- the game's only water
-- verb -- and no input-driven route had ever worn a stone on purpose.
-- The list seek is menu_esperdetail's two-column idiom against the live
-- $7e9d89 row->esper table; an esper the save does not own never appears
-- there, so the seek times out loudly instead of equipping the wrong row.
function M.equipEsper(pos, esperIdx, opts)
  opts = opts or {}
  local tag = opts.tag or ("equip esper " .. esperIdx)
  local ZM, CUR = 0x26, 0x4b
  local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL =
    0x05, 0x06, 0x0a, 0x1e, 0x4d
  local GENJULIST = 0x9d89
  local function st() return M.readByte(ZM) end
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
      return st() == ST_CHAR and M.readByte(CUR) == pos
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

-- M.equipWeapon: put a SPECIFIC weapon in the main hand of the character
-- at char-select position `pos`, through the real Equip menu.  States
-- (equip.asm): $36 options (cursor 0 = Equip) -> $55 slot select (default
-- slot 0 = R-Hand) -> $57 item select, whose list rows at $7e9d8a are BAG
-- INDEXES into $1869 (MenuState_57 @992d reads exactly that), so the seek
-- compares the item id under the cursor rather than guessing a row.  The
-- list is pre-filtered by GetValidEquip, so an un-equippable weapon makes
-- the seek time out loudly rather than equip something else.
--
-- WHY equipOptimum IS NOT ENOUGH, measured 2026-08-10 on the Cranes:
-- Optimum picks by attack power and armed LOCKE and EDGAR with THUNDER
-- BLADES ($0F: slash class, LIGHTNING element) -- and the Left Crane
-- ABSORBS lightning, so every Fight healed the boss (+160/+198 pair
-- heals, +943 boosted) and walked its Giga Volt charge counter.  The
-- element-aware weapon swap is a fight-prep verb a player uses all the
-- time, and no input-driven route had it until this function.
function M.equipWeapon(pos, itemId, opts)
  opts = opts or {}
  local tag = opts.tag or string.format("equip weapon %02X", itemId)
  local ZM, CUR = 0x26, 0x4b
  local ST_MAIN, ST_CHAR = 0x05, 0x06
  local ST_EQOPT, ST_EQSLOT, ST_EQITEM = 0x36, 0x55, 0x57
  local function st() return M.readByte(ZM) end
  return M.seqStep({
    M.driveUntil(function() return st() == ST_MAIN end, 1200,
      { M.pressButtons({ "x" }, 4), M.waitFrames(30) }, tag .. ": main menu"),
    M.waitFrames(20),
    M.driveUntil(function()
      return st() == ST_MAIN and M.readByte(CUR) == 2
    end, 900, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": cursor on Equip"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_CHAR end, 300,
      tag .. ": character select", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_CHAR and M.readByte(CUR) == pos
    end, 600, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": character cursor"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_EQOPT end, 300,
      tag .. ": equip options", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_EQOPT and M.readByte(CUR) == 0
    end, 600, { M.pressButtons({ "left" }, 2), M.waitFrames(10) },
      tag .. ": cursor on Equip option"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_EQSLOT end, 300,
      tag .. ": slot select (R-Hand)", 5),
    M.waitFrames(10),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_EQITEM end, 300,
      tag .. ": item list", 5),
    M.waitFrames(10),
    M.driveUntil(function()
      return st() == ST_EQITEM
         and M.readByte(0x1869 + M.readByte(0x9d8a + M.readByte(CUR)))
             == itemId
    end, 1800, { M.pressButtons({ "down" }, 2), M.waitFrames(10) },
      tag .. ": list cursor on the weapon"),
    M.pressButtons({ "a" }, 2),
    M.waitUntil(function() return st() == ST_EQSLOT end, 300,
      tag .. ": equipped, back on slots", 5),
    M.driveUntil(function() return M.hasControl() end, 1200,
      { M.pressButtons({ "b" }, 3), M.waitFrames(20) }, tag .. ": back out"),
    M.waitFrames(20),
  })
end

-- --------------------------------------------------------------- equip --
-- M.equipOptimum: put the party's gear back ON, through the real field
-- Equip -> Optimum walk.  Reads and pad presses only (issue #75).
--
-- WHY THIS IS A LIBRARY FUNCTION AND NOT A ONE-OFF.  The game strips
-- characters and returns their gear TO INVENTORY at story beats --
-- `remove_equip` / EventCmd_8d -- and the chain of generated savestates has
-- never once put it back.  battle_brokendeath found this at the Vector
-- infiltration and drove Equip -> Optimum by hand to fix its own fixture.
-- It is not one
-- fixture's problem: measured 2026-08-09, solo LOCKE starts his whole
-- South Figaro scenario with $1600+37*1+$1F..$23 all reading $FF -- no
-- weapon, no armor, no relics, his own Dirk sitting in the bag -- and
-- proceeded to punch a level-13, 495-hp HeavyArmor BAREHANDED for EIGHT
-- damage a swing across three lost attempts.  That reads exactly like a
-- balance finding and is nothing of the sort.  A player opens the Equip
-- menu; so does this.
--
-- Menu path (battle_brokendeath.lua:118-152, verified live there):
--   $05 main, cursor row 2 = Equip -A-> $06 character select -A-> $36 the
--   option row, which is HORIZONTAL: Equip / Optimum / Rmove / Empty, so
--   Optimum is cursor 1, one RIGHT.  A runs EquipOptimum in place.
--
-- No-op -- the menu is never opened -- when everyone already holds a
-- weapon, so a route can call it after any story beat and pay only where
-- something was actually taken away.
function M.equipOptimum(opts)
  opts = opts or {}
  local tag = opts.tag or "equip"
  local ZM, CUR = 0x26, 0x4b
  local ST_MAIN, ST_CHAR, ST_OPT = 0x05, 0x06, 0x36

  local function weapon(c) return M.readByte(0x1600 + 37 * c + 0x1f) end
  local function bare(c) return weapon(c) == 0xFF end
  local function anyBare()
    for _, c in ipairs(M.partyMembers()) do
      if bare(c) then return true end
    end
    return false
  end
  local function kitLine()
    local out = {}
    for _, c in ipairs(M.partyMembers()) do
      out[#out + 1] = string.format("c%d=%02X", c, weapon(c))
    end
    return table.concat(out, " ")
  end

  local phase = 0
  local function tap(btn)
    phase = (phase + 1) % 12
    M.setPad(phase < 4 and { btn } or {})
  end

  -- one slot, start to finish; slots are the menu's 0..3, and every party
  -- member gets one whether or not that member is the bare one -- Optimum
  -- on an already-equipped character is a no-op the game handles itself
  local function oneSlot(slot)
    -- Guard on the PARTY, not on zCharID: $69+slot is the menu's own copy
    -- and it is stale on the field, so a solo scenario read "slot 1 = char
    -- 255" as occupied and then hung trying to walk a cursor onto a slot
    -- that is not there.  #M.partyMembers() is answered by $1850 and is
    -- true whether or not a menu has ever been open.
    return M.cond(function() return #M.partyMembers() > slot end, {
      M.driveUntil(function() return M.readByte(ZM) == ST_MAIN end, 1800, {
        M.call(function() tap("x") end),
      }, tag .. ": main menu"),
      M.release(), M.waitFrames(10),
      M.driveUntil(function()
        return M.readByte(ZM) == ST_MAIN and M.readByte(CUR) == 2
      end, 1200, {
        M.call(function()
          local cur = M.readByte(CUR)
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { [cur < 2 and "down" or "up"] = true } or {})
        end),
      }, tag .. ": main cursor on Equip"),
      M.release(), M.waitFrames(10),
      M.driveUntil(function() return M.readByte(ZM) == ST_CHAR end, 1200, {
        M.call(function() tap("a") end),
      }, tag .. ": character select"),
      M.release(), M.waitFrames(10),
      M.driveUntil(function()
        return M.readByte(ZM) == ST_CHAR and M.readByte(CUR) == slot
      end, 1200, {
        M.call(function()
          local cur = M.readByte(CUR)
          phase = (phase + 1) % 12
          M.setPad(phase < 4
            and { [cur < slot and "down" or "up"] = true } or {})
        end),
      }, tag .. ": cursor on slot " .. slot),
      M.release(), M.waitFrames(10),
      M.driveUntil(function() return M.readByte(ZM) == ST_OPT end, 1200, {
        M.call(function() tap("a") end),
      }, tag .. ": equip options"),
      M.release(), M.waitFrames(10),
      M.driveUntil(function()
        return M.readByte(ZM) == ST_OPT and M.readByte(CUR) == 1
      end, 1200, {
        M.call(function()
          local cur = M.readByte(CUR)
          phase = (phase + 1) % 12
          M.setPad(phase < 4 and { [cur < 1 and "right" or "left"] = true } or {})
        end),
      }, tag .. ": cursor on Optimum"),
      M.release(), M.waitFrames(10),
      -- EquipOptimum runs IN PLACE: the state does not change, so there is
      -- nothing to drive toward -- one edge press and let it work.
      M.pressButtons({ "a" }, 4),
      M.release(), M.waitFrames(60),
      M.logStep(function()
        return string.format("[%s] slot %d (char %d): %s", tag, slot,
          M.readByte(0x69 + slot), kitLine())
      end),
      -- back to the field before the next slot, so every pass starts from
      -- the same place rather than from wherever the last one stopped
      M.driveUntil(careClose(function()
        local zm = M.readByte(ZM)
        return zm ~= ST_MAIN and zm ~= ST_CHAR and zm ~= ST_OPT
      end), 2400, {
        M.call(function() tap("b") end),
      }, tag .. ": back to the field"),
      M.release(), M.waitFrames(20),
    }, {})
  end

  return M.cond(anyBare, {
    M.logStep(function()
      return string.format("[%s] someone is bare-handed (%s) -- opening " ..
        "Equip", tag, kitLine())
    end),
    oneSlot(0), oneSlot(1), oneSlot(2), oneSlot(3),
    M.logStep(function()
      return string.format("[%s] done: %s", tag, kitLine())
    end),
    M.call(function()
      for _, c in ipairs(M.partyMembers()) do
        M.assertEq(bare(c), false, string.format(
          "char %d is holding a weapon after Optimum", c))
      end
    end),
  }, {
    M.logStep(function()
      return string.format("[%s] everyone is already armed: %s", tag,
        kitLine())
    end),
  })
end

-- ------------------------------------------- South Figaro shared toolkit --
-- Promoted from gen_sfigaro.lua (2026-08-09, the sfigaro_escape dispatch):
-- gen_sfigaro and gen_tunnelarmr both walk occupied South Figaro, and the
-- gate-soldier helper below was already flagged in HANDOFF as "wants
-- promoting into the library rather than copying".  Everything in this
-- section keeps gen_sfigaro's measured behavior line for line; the header
-- comments are the original findings and travel with the code.

-- field object i's live tile (pixel coords >> 4, block stride $29) -- the
-- same read chaseTalk does internally; public because NPC positions are
-- route inputs (the gate soldier's post IS the branch condition below)
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
-- predicate is the library's public way to wrap a list into ONE step
local function seq(steps) return M.cond(function() return true end, steps) end

-- gen_banon's talkToObj, unchanged in shape: approach re-resolved from live
-- object coords (NPCs wander), facing computed from the live delta, soft
-- rounds before a hard one.  CheckNPCs activates whatever the object map
-- holds ONE TILE IN THE PARTY'S FACING DIRECTION while A is held, and a
-- two-frame turn press does not set the facing byte -- so the direction is
-- HELD until it reads back, and only then is A edge-tapped.
-- (M.chaseTalk above is the WANDERING-NPC variant with a choice-prompt
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

-- Ride a scene out to a settled, controllable field, edge-tapping A on EVERY
-- frame the party is not in control and FIGHTING anything that comes up --
-- by real input (issue #75; the HP pin + battle-clearing flag write this
-- branch used to carry are gone).  Battle frames drive gen_moogle's Marshal
-- cycle: R raises the
-- active character's pending boost (1 bp at battle start, Ot6InitBP; the R
-- buzzes harmlessly on an empty bank), then three edge-tapped A's confirm
-- the boosted Fight and page victory text -- so solo LOCKE alternates
-- boosted and plain Fights against battle 11's HeavyArmor.  A LOSS is real
-- now (the _ca85ba scenario reset); the callers wrap every engagement in a
-- phase-spread retry ladder rather than pinning it away.
--
-- WHY NOT advanceStory HERE.  advanceStory taps A only while a battle is up
-- or M.dialogWaiting() is true, and holds the pad empty otherwise.  The tail
-- of `battle 11` has a window state that satisfies NEITHER: measured at the
-- third gate-soldier fight, $0059 = $52 (a menu module owns the CPU) with
-- $BA/$D3 both clear, so dialogWaiting() is false, the battle flag is
-- already down, and advanceStory sat with the pad empty for 20000 frames
-- while the event PC stayed parked at $CA85B9.  Tapping A on "no control"
-- rather than on "a signal I recognise" clears it, and it cannot misfire on
-- the open field because the tap is gated on NOT having control.
-- (Choice prompts are the one thing this must never meet -- an A press
-- always takes option 0 -- so every prompt on a route is answered by a
-- choice-steering rider like gen_sfigaro's rideUntil, never by this.)
-- ...AND WHY THE FIGHT ITSELF IS NOT A BUTTON PATTERN ANY MORE.  The first
-- input-driven version of this drove every battle with a fixed 32-frame
-- cycle -- R to boost, then three edge-tapped A's -- which is a fine way to
-- page victory text and a poor way to survive.  Measured 2026-08-09 on the
-- first end-to-end run that ever reached this edge: solo LOCKE, level 8 with
-- 168 hp, LOST the gate soldier's HeavyArmor three attempts running, while
-- sixteen Tonics sat in the bag.  He never pressed a single one, because
-- the pattern has no idea what a menu is.  M.newFightDriver does: it reads
-- the live command table, boosts, and runs its own item medic line -- so
-- LOCKE now drinks a Tonic when he is under 60%, which is what a player
-- fighting a soldier alone in an occupied town would obviously do.
-- (The FIELD half of this routine is hand-rolled; see the note above on
-- why advanceStory cannot own the tail of battle 11.)
function M.rideOut(what, budget, dstMap)
  local phase, calm = 0, 0
  local F = M.newFightDriver(what or "rideOut",
    -- bank = 3: unboosted Fights until the actor has three BP, then unload.
    -- Shielded damage is HALVED and a broken monster takes 4x
    -- (Ot6ShieldedMulW, ot6_break.asm:1487-1497), so the fight is won by
    -- breaking, not by chipping -- and a boosted Fight is what chips.
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
  })
end

-- THE GATE SOLDIER COMES BACK EVERY TIME MAP 75 RELOADS.  `hide_obj NPC_11`
-- (_ca856a, event_main.asm:20313) is a RUNTIME bit, not story state: leaving
-- town for an interior and coming back re-runs InitNPCs (field/init.asm:469
-- only skips it when reloading the SAME map) and re-creates every npc whose
-- spawn switch still holds.  His is $030C and nothing in the scenario clears
-- it.  So (30,42) -- the ONE tile joining the SE quarter to the rest of town
-- -- is plugged again on every return, and gen_sfigaro's route crosses that
-- boundary three times.  The soldier's uniform is no answer: `if_switch
-- $0103=1` only swaps his fight for a bare "Halt!" (:20296); it does not
-- move him.
-- Gated on the SYMPTOM (a BFS probe to a tile on the far side) rather than
-- assumed, so the day the respawn stops happening this says so instead of
-- walking into a fight that is not there.
--
-- EVERY ENGAGEMENT IS A RETRY LADDER NOW (issue #75).  With the HP pin
-- gone a lost battle 11 runs _ca85ba -- LOCKE revived on (47,43), both
-- disguise switches cleared -- so each fight captures a blob first, and a
-- loss reloads it and re-engages with a different frame offset (the
-- battle RNG seed is the frame phase at init, so each retry plays a
-- genuinely different fight).  Success = not dumped on the opening tile
-- AND the probe tile reachable; three losses fail generation loudly.
function M.clearGateSoldier(probeX, probeY, tag)
  local blob, won = nil, false
  local function fightOnce(n)
    local loadReq
    return M.cond(function() return won end, {}, {
      M.logStep(function()
        return string.format("%s: battle 11 attempt %d (offset %d) at f%d",
          tag, n, (n - 1) * 37, M.frame)
      end),
      n > 1 and seq({
        M.call(function() loadReq = M.requestLoadState(blob) end),
        M.waitFrames(2),
        M.call(function() M.checkReq(loadReq, tag .. ": pre-fight reload") end),
        M.waitFrames(90),
        M.waitFrames((n - 1) * 37),      -- vary the battle RNG seed
      }) or seq({}),
      M.talkToObj(26, tag .. ": the gate soldier (battle 11)"),
      M.rideOut(tag .. ": ride battle 11 out", 30000, 75),
      M.call(function()
        -- a LOST attempt runs the scenario reset (_ca85ba) and dumps the
        -- party back on (47,43); being anywhere else with the lane open is
        -- the win.  ($0104 is NOT this signal -- see the branch below.)
        -- ...but the SAME test does not work AFTER the fight: a beaten
        -- soldier keeps his coordinates -- the scene hides the object, it
        -- does not move it -- so obj 26 still reads {30,42} on a win.
        -- Each question in the place it is valid: his TILE decides whether
        -- to fight (stable at step start, when the object map may not be
        -- populated), and REACHABILITY decides whether we won (stable
        -- afterwards, when he is gone from the map even though his record
        -- is not).  A loss dumps the party back on (47,43).
        won = not (M.fieldX() == 47 and M.fieldY() == 43)
          and M.bfsPath(probeX, probeY) ~= nil
        M.log(string.format("%s: attempt %d %s at (%d,%d) f%d, $0104=%d",
          tag, n, won and "WON" or "LOST (scenario reset)",
          M.fieldX(), M.fieldY(), M.frame, swv(0x0104)))
      end),
    })
  end
  -- CAN HE JUST WALK PAST HIM?  No, and that is measured, not assumed.
  -- South Figaro is a stealth chapter and the gate soldier looked like he
  -- wandered -- the old reachability probe answered "lane open" often
  -- enough to flip this branch by accident -- so the obvious move is to
  -- wait him out.  Measured 2026-08-09: polling M.bfsPath(22,43) every 60
  -- frames for 7200 frames (two minutes of game time) NEVER once found a
  -- path.  He does not step off the choke.  The fight is mandatory, which
  -- is what makes the balance finding below a real one and not a routing
  -- failure.
  --
  -- WHICH BRANCH, decided on the STORY SWITCH and not on a BFS probe.
  -- This used to ask "is (22,43) reachable this instant?", and the answer
  -- depends on where the gate soldier happens to be standing: he WANDERS,
  -- and when he steps off the choke the probe says "lane already open",
  -- the fight is skipped, and the next navTo walks into him and dies of
  -- "no path" twenty retries later.  Measured 2026-08-09 -- inserting a
  -- single menu visit ahead of this cond was enough to flip it.  $0104 is
  -- the switch the gate scene itself sets, it does not wander, and the
  -- loss path below already reads it.
  -- BACK TO THE ORIGINAL REACHABILITY PROBE.  I swapped this to $0104 on
  -- the theory that the soldier wanders and the probe is a coin flip.  Both
  -- halves of that were wrong: he does NOT wander (polled every 60 frames
  -- for 7200 frames, the lane never opened once), and $0104 is not the
  -- switch the gate sets -- keyed on it, this reported a LOSS on a fight
  -- LOCKE had just won outright, HeavyArmor at 0 hp and the party standing
  -- clear of the reset tile.  The symptom probe was right all along.
  -- THE BRANCH IS THE SOLDIER'S OWN TILE, not a path query.  Three
  -- readings of this have now been wrong.  $0104 is not the switch the
  -- gate sets (it called a won fight a loss).  And the BFS probe -- right
  -- when this step opened with a walk -- reads "open" every time now that
  -- the step opens two MENUS first, so the party skips the fight, walks to
  -- (31,42) and dies of "no path" twenty retries later.
  --
  -- He is a PLUG on exactly one tile: npc 10 / obj 26 sits at {30,42},
  -- spawn switch $030C, and (30,42) is the only tile joining the starting
  -- pocket to the rest of town.  So ask where he is.  Beaten, the object
  -- is gone and this reads anything but his post; on his feet it reads
  -- {30,42} whatever the object map happens to be doing that frame.
  return M.cond(function() return M.objX(26) == 30 and M.objY(26) == 42 end, {
    M.logStep(function()
      return string.format("%s: the gate soldier is on his post (%d,%d) " ..
        "at f%d; fighting him", tag, M.objX(26), M.objY(26), M.frame)
    end),
    -- TOP UP FIRST.  He respawns on every map-75 reload, so gen_sfigaro's
    -- route fights him THREE times, and LOCKE arrives at the third one
    -- carrying whatever the first two left him.  Measured: B1 won, R1 won
    -- on its second attempt, R2 lost all three -- not because that fight is
    -- different but because he walked into it worn down.  A player heals
    -- between rounds with a soldier; so does this.  A no-op when he is
    -- already full, and it never spends below the Potion floor the later
    -- beats need.
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
    fightOnce(1), fightOnce(2), fightOnce(3),
    M.call(function()
      -- THIS WAS THE WALL, and the record of it stays (2026-08-09
      -- correction: sfigaro_town is GREEN now -- the fight opened up once
      -- LOCKE was ARMED, in the BACK ROW, topped up between rounds, and
      -- BREAKING the armour, one shield chip per boosted Fight and 4x once
      -- broken).  The original measurement, kept because its numbers keep
      -- being asked for: solo LOCKE, level 8, 168 hp, correctly equipped
      -- through the real Equip -> Optimum walk, healing himself with
      -- Tonics, dealt ~21 damage per 300 frames to a level-13 HeavyArmor
      -- with 495 hp and took ~117 back.  Bare-handed -- which is how the
      -- chain delivered him until H.equipOptimum landed -- it was eight
      -- damage a swing, and front row and back row measured identically
      -- BARE, which is why the row lever went unnoticed for three runs.
      -- Its weaknesses are bolt and water (monster_prop +25 = $84) and
      -- solo LOCKE can reach neither.  Do not widen the attempt ladder
      -- until it gets lucky; that is the #74 mistake.
      M.assertEq(won, true,
        tag .. ": battle 11 won within 3 attempts (boosted Fights)")
      M.assertEq(M.bfsPath(probeX, probeY) ~= nil, true,
        tag .. ": the lane is open again")
    end),
  }, {
    M.logStep(function() return tag .. ": the lane is already open" end),
  })
end
