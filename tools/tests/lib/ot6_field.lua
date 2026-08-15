-- ot6_field.lua -- the navigation half of the OT6 test library: the true
-- passability model ported from the engine, BFS pathfinding, and the
-- verified-step walkers (navTo / worldNavTo / advanceStory / route).
--
-- lib/ot6.lua is the battle core every test uses; this file is what a
-- route needs to walk the game world, and only the gen_* route
-- generators and field probes call it.  It is not a standalone module.
-- lib/compose.py inlines lib/ot6.lua and then this file into every
-- composed script, so a battle test carries nav code it never calls, and
-- invokes this chunk with the core's module table as its argument (the
-- `local M = ...` below).  Test scripts keep their one-line contract
--
--   local H = dofile("tools/tests/lib/ot6.lua")
--
-- and see one merged H; nothing anywhere references this file's path at
-- runtime.  Everything here installs onto that shared table through the
-- core's public M.* API plus M.seqStep (exported for route()); the shared
-- field-state reads both halves stand on (fieldX/hasControl/formation...)
-- stay in the core because suite battle tests use them too.
--
-- Freshness: a generated route fixture is a function of both halves, so
-- lib/savestate_stamp.sh hashes generator ++ ot6.lua ++ ot6_field.lua
-- (that fixed order) into the signature it stamps beside the fixture.

local M = ...
assert(type(M) == "table",
  "ot6_field.lua is inlined by lib/compose.py after lib/ot6.lua and " ..
  "receives the core module table; it cannot be loaded on its own")

-- How long playBattles="flee" holds L+R before it accepts that this
-- formation is not going to release the party and fights the battle out
-- instead.  The run mechanic is a per-round roll against level/speed, so a
-- short tail is normal, but holding L+R means standing still while the
-- formation takes free rounds.  Measured 2026-08-09 with this cap at
-- 5400 (90 seconds): a Mt. Kolts cave-97 formation refused to release a
-- full-health party, the flee held for all 5400 frames, the party wiped
-- inside its own escape attempt, and the drive then tapped A through the
-- Game Over and into a brand-new game, reporting eleven maps of intro
-- before the step's budget expired.  1800 frames is 30 seconds, several
-- rounds, long enough for a run that is going to work and short enough
-- that the fallback still has a party to fight with.
-- Navigators accept opts.fleeCap to shorten the cap per route.  Measured
-- 2026-08-09 on the Figaro-cave escape step (LOCKE + CELES, 113+150 hp): a
-- pincer formation (Trilobiter + Primordites, party surrounded) cannot be
-- fled at all, which is FF6's own rule that there is no escape until one
-- side is cleared, so every held frame is free damage, and the full 1800
-- killed the party before the tactical fallback engaged.  A wipe inside
-- the cap also leaves no "flee: no release" line and no fallback log: the
-- battle ends, RandBattle's GameOver holds the event PC, and the step
-- reads as a parked navigator.  A small party on a map with dangerous
-- formations wants a cap of a few hundred frames (two or three failed run
-- rolls) rather than ninety seconds.
M.FLEE_CAP = 1800

-- A party wipe must be reported as one.  Twice a wipe has been reported
-- as something else: at Mt. Kolts cave 97 the drive tapped A through the
-- Game Over into a brand-new game and reported eleven maps of intro, and
-- at terra_clifftop a navigator spent sixty thousand frames planning
-- routes from field position (44,1888), a coordinate that only exists
-- because the field module no longer owned that RAM, and failed as "navTo
-- timeout".  Neither log said the party had died.
--
-- The character table at $1600 is the right field check: it is save
-- state, not module-owned scratch, so it survives the battle module, the
-- menu module and the Game Over screen alike.  It is debounced over 300
-- frames because a module handoff can blank things for a moment and a
-- false wipe would be worse than the timeout it replaces.
--
-- $1600 keeps pre-battle HP while a battle runs: the battle module
-- works on its own table at $3BF4 and syncs back at teardown, and a
-- battle that ends in a wipe tears down into the Game Over, where the
-- sync the field check is waiting on never reports a death.  Two steps
-- found this independently and converged on the same battle-side
-- signature (gen_sabin_gau's staging walk, gen_sabin_trench's dive):
-- every party slot whose battle max HP looks plausible, meaning nonzero
-- and under 1000, where a WoB max is a few hundred and module-transition
-- garbage reads tens of thousands, showing zero HP.  M.partyWipedInBattle
-- is that signature lifted into the library; M.partyWiped consults it
-- first, so the navigators' canary names an in-battle wipe instead of
-- pressing buttons into the Game Over.
--
-- A related problem, documented where the shared check lives because the
-- copies are scattered through gens: the ad-hoc per-gen `inBattle()`
-- (read $3BF4 words, skip entries that are 0 or FFFF, first survivor
-- under 10000 decides) cannot see a dead party in battle, because
-- every slot reads 0, every slot is skipped, and the loop falls through
-- to "not in battle".  gen_sabin_trench's ride held LEFT at a Game Over
-- through three full 60000-frame budgets for that reason.
-- Any driver keying on that pattern needs this check beside it.
-- Corrected 2026-08-13: this could never fire, and had not once since it was
-- written.  It opened with M.battleLoadStarted(), which returns false unless
-- some slot has current HP above zero, and then required every sane slot to
-- read zero.  The two conditions contradict each other, so the function that
-- exists to notice a dead party required a live one.
--
-- Measured cost, twice in one day: gen_zozo4_dadaluma reported "timeout
-- driving toward followPath" when the party had been dead for eleven tiles
-- and the remaining 22000 frames were the Game Over event playing out, and
-- gen_sabin_trench held LEFT through three 60000-frame budgets at a Game
-- Over.  Each cost about an hour to attribute.
--
-- The right test is the max-HP table rather than the current-HP one.  A
-- battle's $3C1C reads sane maxima whether or not anybody is standing, so it
-- says "a battle is loaded"; $3BF4 then says who is alive.  Outside a battle
-- both read garbage and the maxima fail the range check, which is what keeps
-- this from firing on the field.  The signature is the one gen_zozo4 proved
-- in place before it was lifted here.
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
-- also raises, because for a navigator a wipe is the end of the run and the
-- alternative is pressing buttons into the Game Over until a budget expires.
--
-- `soft` is for the one caller whose whole design is built around losing:
-- a retry ladder rides its own fight out and reloads on a loss, so for that
-- ride a wipe is the expected outcome of an attempt rather than a failed
-- run.  Raising there does not report anything the ladder was not about to
-- report itself; it just stops the ladder at its first rung, which is how
-- gen_vargas came to run one attempt while its header and its step list both
-- said four (measured 2026-08-11 on the v0.10 tip: attempt 1 wiped with
-- VARGAS at 11065/11600 and the run ended there, with no "attempt 2 begins"
-- line anywhere in the log).  A soft canary hands the verdict back to the
-- caller, which still has to decide -- and gen_vargas still fails the run if
-- every attempt loses.
--
-- How far this generalises, checked rather than assumed: gen_vargas is the
-- only one of the ten retry ladders in the tree that was in this position.
-- The ten are the list in the commit that moved them onto H.newSeedLadder --
-- battle_brokendeath, gen_esper_tubes, gen_ifrit_magicite, gen_n128,
-- gen_tunnelarmr, gen_sfigaro, gen_terra_returned_checkpoint, gen_vargas,
-- probe_cranes_water, and M.clearGateSoldier below.  Only three library calls
-- arm this canary (M.navTo, M.worldNavTo and M.advanceStory, its three call
-- sites in this file), and in the other nine every step between an attempt's
-- spread and its verdict is a raw M.driveUntil or M.waitUntil, which do not.
-- Two of them reach a navigator through M.talkToObj, but before the fight
-- rather than after it, and a retry reloads a live-party blob before that
-- step runs, so neither can meet a wiped party.  Three -- gen_sfigaro,
-- gen_n128 and probe_cranes_water -- carry comments saying they avoided
-- advanceStory here deliberately, gen_sfigaro's being "a hard timeout here
-- would abort the whole generate instead of letting the ladder reload and
-- retry".  gen_vargas is the one that reached for the shared ride instead,
-- which is why it is the one that lost its rungs.
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

-- The corridor flee policy, one driver per navigator call.  The three
-- navigators below used to carry three byte-for-byte copies of it.
--
-- L+R is the engine's own run mechanic.  At the cap the run has failed and
-- the party is only taking damage, so the battle is fought out instead.  The
-- fallback is the tactical driver rather than a blind A-tap, because a party
-- that has already spent the cap being hit needs its own item menu more than
-- it needs a first command row.
--
-- Before the cap there is a shorter answer, because some formations do not
-- roll for the run at all.  $b1 bit 1 is the engine's own can't-run flag:
-- UpdateMonsterGfxBuf clears bits 1-2 every pass and sets bit 1 back on for a
-- pincer ($201f == 2, both sides occupied) or a live $3a42, and bit 2 with it
-- for a harder-to-run monster (battle_main.asm:15630-15641, :15655-15661,
-- :15696-15699).  Cmd_2a checks that bit before anything else and answers
-- "Can't run away!!" (battle_main.asm:5729-5731), so while it is set the run
-- counters can climb past the difficulty forever and nobody leaves.  Holding
-- L+R into that is free damage with no roll behind it, so this reads the flag
-- and hands the fight to the tactical driver while the party still has its HP.
--
-- Measured on the Phantom Train's front strip (2026-08-11, this is the bug
-- that made train_done stop generating): three Bombs pincered the party at
-- 141 (105,8), $b1 read $22 -- bit 1 can't-run plus bit 5, which the pincer
-- sets by falling into the back attack's tail (battle_main.asm:7904-7913) --
-- and across the full 1800 the run counters went 7,9,3 then 20,21,12 against
-- a difficulty of 6 while nobody escaped.  The party entered that fight at
-- 231/197/254 and the fallback inherited it at 22/0/39.
--
-- The periodic line is the measurement that was missing while all of that was
-- happening: "no release after 1800 frames" says the run failed and nothing
-- about why, and "the roll kept losing" and "the engine was never asked to
-- roll" want different fixes.  Every cell in it is the engine's own run
-- machinery:
--   $2f45  characters-are-running, set only while L+R reads as held and
--          nothing is blocking it (btlgfx_main.asm:1609-1621)
--   $3a3b  run difficulty: 2 per live monster, 6 for a harder-to-run one
--          (battle_main.asm:15642-15667)
--   $3d70  per-character run counter, +rand(run factor)+1 per check; the
--          character escapes once it reaches the difficulty
--          (battle_main.asm:15583-15590)
--   $b1    bit 1 can't-run, bit 2 harder-to-run, bit 5 back attack/pincer
--   $2f4b  bit 0 the formation's own "no running with L+R"
--   $7EE9EF / $7E629A  battle time stopped / menus force-closed, either of
--          which suppresses $2f45 outright (btlgfx_main.asm:1611-1613)
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
-- Port of the engine's own step check.  UpdatePlayerMovement
-- (src/field/player.asm:325) reads the d-pad and takes one of two branches;
-- both are modelled here, because Figaro Castle is built out of the second.
--
-- Tile id at (x,y) = the BG1 tilemap byte $7f0000[y*256+x]; its properties
-- are p1 = $7e7600[id] (the prop byte the engine keeps for the party's own
-- tile in $b8) and p2 = $7e7700[id] (directional exits, in $b9).
--
-- Cardinal branch (@4978, player.asm:456-507 -> CheckPlayerMove @4e16,
-- player.asm:1072).  A step from cur=(x,y) toward dir is allowed iff all of:
--   1. p2(cur) has the direction's exit bit (up=$08 right=$01 down=$04
--      left=$02 -- player.asm DirectionBitTbl:1210);
--   2. p1(dst)&7 ~= 7 (counter/wall tile);
--   3. the bridge/z-level rules pass (below, transcribed branch for
--      branch; party z-level = $b2 low bits, bit0 upper / bit1 lower);
--   4. no object occupies dst: $7e2000[dstY*256+dstX] bit7 set means free
--      (the engine allows crossing under an occupied bridge tile; we skip
--      that special case, which is conservative, and movement-verify
--      covers it).
--
-- Diagonal branch (@48d4, player.asm:379-453).  UpdatePlayerMovement tests
-- the party's own tile first (player.asm:368-377): if p1(cur) & $c0 is set,
-- and the tile is not a bridge tile the party is standing on the lower
-- z-level of, a left or right press moves the party diagonally instead, one
-- tile in each axis.  Which diagonal depends on the tile, not on the press:
--   p1 bit7 ($80), "\" tiles:  right -> down-right (dir $06, :403)
--                              left  -> up-left    (dir $08, :420)
--   p1 bit6 ($40), "/" tiles:  right -> up-right   (dir $05, :394)
--                              left  -> down-left  (dir $07, :429)
-- bit7 wins when both are set (:385 `bmi`, :410 `bpl`).  The only
-- destination tests are that p1(dst) must carry the same diagonal bit and
-- must not be exactly $f7 (:389-393, :399-402, :416-419, :424-428).  The
-- branch consults nothing else: not p2's exit bits, not the counter rule,
-- not the z-level rules, not the object map (it never touches $7e2000 and
-- never calls GetObjMapAdjacent), and it never calls CheckDoor.  The
-- movement direction it stores in $087e is 5..8, and _c04f8d (player.asm
-- :1286) maps those to the four diagonal neighbours; CalcObjMoveDir
-- (obj.asm:5521) then drives both axes at the cardinal rate, so a diagonal
-- step is one tile in x and one in y (ObjMoveRateH/V rows for dir 5..8).
-- Up and down presses are not handled by this branch at all (:380/:405 test
-- only $07 bit0/bit1) and fall through to the cardinal path, as does a
-- left/right press whose diagonal destination fails (:396, :400, :417, :426
-- all jump into @4978).  So on a diagonal tile the diagonal is tried first
-- and the cardinal move of the same press only happens when the diagonal is
-- refused, which is why stepAllowed says "no" to a cardinal left/right that
-- the engine would turn into a diagonal.
--
-- The four cardinal names double as press names; the four diagonal names
-- are moves the model plans and verifies but never presses directly.
-- DIRS/DIRIDX stay cardinal: they are the world map's move set too, and the
-- overworld module (ff6/src/world/) has no diagonal branch; its
-- GetPlayerInput tests one passability bit per cardinal direction
-- (move.asm @1ead..@1ff3).  Only the field walks diagonals.
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

-- BG1 tilemap byte for a tile.  The tilemap's row stride is 256 ($7f0000 +
-- row*256 + col: UpdateLocalTiles builds its row pointers as {lo=0,hi=row},
-- player.asm:1385-1399), but the coordinates wrap at the map's own size
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
-- through, for tiles that are walkable but must not be stepped on.  The
-- motivating case is a one-way entrance row sitting inside an otherwise
-- ordinary region: map 250's (22..24,34) door into 243, which the I->J
-- circuit crossed by accident while walking somewhere else and could not
-- come back from (issue #31).  The target tile itself is exempt, so a
-- route can still aim at an avoided tile deliberately.
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
function M.navDump()   -- debugging one-liner (kept from the old navigator)
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
--                  flag write, which means no state writes on this
--                  navigator (issue #75).  Opt-in while unconverted
--                  generators still use the flag write; it costs real ATB
--                  rounds per encounter, so input-driven steps budget more
--                  frames.  Three spellings, with the same contract
--                  worldNavTo carries:
--                  true    auto-fight by edge-tapped A (the taps that page
--                          the victory text also fight:
--                          A opens the command list, A confirms its first
--                          entry, A takes the default target);
--                  "tactical"  read the live command table and use Edgar's
--                          Tools, Sabin's Blitz, and Fight for everyone else,
--                          with the driver's own item medic line.  Which
--                          Tool is opts.tool (default H.AUTOCROSSBOW); an
--                          area whose shield rows carry no class key wants
--                          the element instead, which for Zozo is
--                          H.BIO_BLASTER.  See newFightDriver's note.
--                            It heals
--                          at opts.healPercent (default 55).  That default
--                          was 35, which was too late: measured on map 98
--                          (Trilium + Tusker + two Cirpius), a party healing
--                          only below a third spent five Fenix Downs on one
--                          step, where healing earlier would have spent
--                          Tonics at fifty gil instead of Fenix Downs at
--                          five hundred;
--                  "flee"  hold L+R, the engine's own run mechanic.  A
--                          fled battle does not count as a win, so win-only
--                          rolls (SHADOW's 1/16 post-battle leave,
--                          battle_main.asm:11976) never happen, which is
--                          why the Sabin chain runs.  A formation
--                          that has not released the party after
--                          M.FLEE_CAP consecutive battle frames is fought
--                          out by edge-tapped A instead of hanging the step,
--                          because unrunnable formations exist and a run
--                          that cannot end would only be a timeout;
--                          callers pick fight vs flee per step and say why.
--   opts.calmFrames  consecutive settled frames on the goal tile the
--                  terminator requires (default 16; see ISSUE #22 below)
--   opts.noPathRetries  BFS-no-path retries, 45 idle frames apart, before
--                  erroring (default 20).  A no-path is often transient:
--                  an NPC standing in a one-tile corridor blocks the
--                  object map exactly while its scene runs (the Figaro
--                  gate guard, measured), and erroring instantly turned
--                  every such scene into a route failure.
--
-- ISSUE #22: why the press ends on "moving" and the terminator on "stopped".
-- Both rules used to key on the tile coord changing, and both were wrong for
-- rightward and downward steps.  Measured per frame on map 242 with
-- probe_step2 (party at {57,34}, 1 px/frame):
--
--   f01..f05  py=544  aligned, not moving yet (the press has not latched)
--   f06..f20  py=545..559          walking; tile coord still 34
--   f21       py=560  aligned, tile coord flips to 35: arrival
--   f22..f37  py=561..576          a second tile, which was not asked for
--
-- Moving up or left the coord flips about 1px in, so releasing on the change
-- was always early enough; moving down or right it flips only at completion,
-- which is the same frame the engine re-reads the pad for the next step, and
-- a setPad only reaches the ROM at the next input poll.  So the release
-- landed one poll late and the engine latched another step whenever the tile
-- beyond was passable.  Two consequences, both measured: every
-- rightward/downward step overshot by one tile, and the terminator ("on the
-- tile, controlled, tile-aligned") fired on the single aligned frame at f21,
-- reporting success from a tile the party then walked off.  End to end on
-- vector_sneak: navTo(57,35) returned at (57,35) and the party was at
-- (57,36) sixty frames later.  (The original report's case:
-- navTo(45,38) returned success with the party at (46,38).)
--
-- The fix is the one the v0.6 generators' local tapWalk already proved:
--   * release as soon as the party is moving, on the first frame
--     tileAligned() goes false.  That is direction-independent (it does not
--     care when pixel>>4 happens to flip), speed-independent (map 41 walks
--     ~1.33 px/frame with jitter, map 242 exactly 1), and it is the earliest
--     release that still proves the step committed.
--   * require the party to be stopped rather than aligned for one frame:
--     opts.calmFrames consecutive settled frames on the goal tile.  While
--     walking, tileAligned() is false for 15 of every 16 frames, so a run of
--     16 aligned frames on one tile cannot happen mid-step, which is why
--     tapWalk's terminator counts them.
--
-- "Stopped" is not spelled "hasControl() for 16 frames" because many goal
-- tiles take the party away the instant it lands: a step-on trigger, a map
-- edge, a scene.  gen_mines_chase is the clearest case: (38,8) on the Narshe
-- clifftop fires the guard scene and leaves the party standing on the
-- trigger, which then re-fires every four frames indefinitely, so
-- hasControl() never holds for more than a frame at a time (that
-- generator's own comment says so).  A control-gated run of 16 hangs there
-- until the frame budget.  So stillness is counted on alignment alone,
-- which is the direct measurement of "not walking" and needs no control
-- flag, and control is only used to decide how long a run has to be: with
-- control, calmFrames is arrival; without it, three times that, because
-- something took the party over while it stood on the goal and the flag
-- cannot corroborate the rest.  Battle and dialog frames are excluded from
-- the run, because clearing those is navTo's own job rather than something
-- to terminate in the middle of.
function M.navTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
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
  local wipeCheck = wipeCanary("navTo")
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee")
      and M.newFightDriver("navTo",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  local function drop(why)  -- discard the plan, logging why once, not per frame
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
      -- stopped on the goal tile, not passing through it (see ISSUE #22).
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
      -- classify the frame, debounced: the battle/dialog signals live in
      -- RAM the field module also writes to, so require 3 consecutive
      -- frames before acting; a real battle or dialog persists for hundreds.
      -- Acting on a 1-frame ghost would tap A on the open field.
      wipeCheck()
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      lostN = M.hasControl() and 0 or lostN + 1
      if tactical and battN == 0 then tactical.idle() end
      -- 1. battle: clear it, but never the goal formation
      if battN >= 3 then
        drop("battle")
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})                 -- goal fight: left alone for arrive()
          return
        end
        if opts.playBattles == "flee" then
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still use it, but it logs a warning
        -- whenever it runs: converted routes want playBattles="flee"
        -- (corridor encounters) or playBattles="tactical" (fights that
        -- matter).
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
      --    yet-undebounced battle/dialog): neutral pad and wait, because
      --    jamming directions or A only corrupts state
      if lostN > 0 or battN > 0 or dlgN > 0 then
        if lostN >= 3 then drop("control lost") end
        M.setPad({})
        return
      end
      -- 4. a step is in flight: hold only until the party is moving (the
      --    first frame it is off tile-alignment), then release.  See the
      --    ISSUE #22 block above for why "until the tile coord changes" is
      --    one input poll too late for right/down.
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
-- raises after maxFrames).  Frames are classified with navTo's 3-frame
-- debounce (the battle/dialog signal bytes live in RAM the field module
-- also writes to; acting on a one-frame ghost would tap A on the open
-- field):
--   battle  -> flag-clear everything present + edge-tap A through the text
--              (with opts.playBattles, no flag write: the same edge-tapped A
--              auto-fights the encounter for real, with no state writes,
--              issue #75, at the price of real ATB rounds).
--              A formation matching opts.spare is a scripted set-piece: it
--              is never cleared by a flag write, is left alone for its
--              first 300 frames, and is edge-tapped after that.  Both
--              halves are needed (measured, esper zap): the set-piece ends
--              via a monster-turn battle event, and A pressed during the
--              load queues player actions that keep the turn engine busy
--              indefinitely, while once the event has taken over (its
--              opening battle dialog is up by ~250 frames), it stalls
--              without A to advance that text;
--   dialog  -> edge-tap A;
--   anything else -> neutral pad.  Control lost means an event is walking
--              the party; control held means the story is between beats.
--              In both cases blind A is worse than waiting: on the open
--              field it talks to NPCs and re-fires triggers.
function M.advanceStory(pred, maxFrames, opts)
  opts = opts or {}
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local aPhase = 0
  local battN, dlgN = 0, 0
  -- opts.wipeEndsRide: a wipe ends this ride instead of failing the run, for
  -- a caller that reloads and tries again.  See wipeCanary's header.
  local wipeSeen = false
  local wipeCheck = wipeCanary("advanceStory", opts.wipeEndsRide)
  local tactical = (opts.playBattles == "tactical" or opts.playBattles == "flee")
      and M.newFightDriver("advanceStory",
        { tactical = true, boost = true, items = true,
          healPercent = opts.healPercent or 55,
          bank = opts.bank, reserve = opts.reserve,
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
  local hb = -600                      -- heartbeat: log immediately, then every 600
  return M.driveUntil(function()
    local done = wipeSeen or pred()
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
        -- playBattles="flee" used to be accepted here and then ignored: every
        -- other navigator had a flee branch and this one did not, so a settle
        -- that rolled an encounter blind-tapped A through a whole fight while
        -- its caller's header said the route runs from them.  Measured on
        -- gen_kolts (2026-08-09): the mountain settles fought Cirpius packs
        -- by tap-A, which is how the party reached VARGAS with TERRA dead and
        -- EDGAR on 1 hp.  Same contract as navTo's, cap included.
        if opts.playBattles == "flee" then
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still use it, but it logs a warning
        -- whenever it runs: converted routes want playBattles="flee"
        -- (corridor encounters) or playBattles="tactical" (fights that
        -- matter).
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
--   $E0/$E2  tile x/y, the high bytes of the 16-bit position words at
--            $DF/$E1 (word = tile*256 + fraction; move.asm integrates
--            velocity into them at @1e56)
--   $DF/$E1  low bytes = sub-tile fraction; both zero <=> at rest.
--            Moving down/right the tile byte flips at step completion;
--            moving up/left it borrows through on the first frame (both
--            measured, probe_world step traces), which is the same
--            direction skew as the field, so position samples gate on
--            worldAligned()
--   $E3/$E5  16-bit velocity; GetPlayerInput zeroes both every aligned
--            frame, then sets +-$10 for a held passable direction
--   $F6     facing 0=up 1=right 2=down 3=left
--   $E7     bit0 = world event script running (Figaro/Narshe triggers)
--   $19     fade/exit trigger (nonzero = leaving the world map)
--   $E8     bit0 = menu opening, bit3 = once-per-tile event/battle
--            latch, bit4 = reload-world (battle return, zone eater)
--
-- Movement is latched to the step: MovePlayer gates its whole body,
-- input read included, on both fractions being zero (move.asm:834-841),
-- so a begun step always continues to the next tile boundary.  A 4-frame
-- tap was measured carrying the party a full tile with velocity held at
-- $10 for all 16 frames (probe_world).  The executor therefore
-- holds the planned direction whenever it is aligned; releases are
-- never needed mid-step.

-- On the world map iff (word $1F64 & $3FF) < 3: the top-level dispatch
-- masks #$03ff (field/reset.asm:66).  Raw compares are wrong there,
-- because entrance/parent records carry flag bits in the high byte (measured
-- $2000 on the world after the Narshe exit; $0200|55 entering Figaro).
function M.worldMode() return (M.readWord(0x1f64) & 0x3FF) < 3 end
-- which world: 0=WoB 1=WoR 2=Serpent Trench (GetWorldTileProp masks the
-- low byte only, move.asm @21d7)
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
-- exit bits, no z-levels, no object map (GetPlayerInput tests this
-- per direction, move.asm @1ead..@1ff3; verified live, where predictions
-- from this rule matched real movement at the Narshe spawn, probe_world).
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

-- BFS a path from the party's current world tile to (tx,ty).  The map
-- wraps at 256 in both axes.  `blockedEdges` (keys from worldEdgeKey)
-- prunes edges the executor has proven wrong, same contract as the
-- field bfsPath.  The node cap is 60000 rather than the field's 4096,
-- because world segments run 60+ tiles (Narshe->Figaro BFS'd 63 steps,
-- probe_world3) and the search disc grows quadratically with them: the
-- I->J crash-site grind is ~117 steps and its disc exceeded the old 20000
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
-- map, no world event script ($E7 bit0, which the Figaro/Narshe gate
-- events run through), not fading out to a field map ($19), and none of
-- $E8's takeover bits: bit0 menu opening, bit5 battle pending/running
-- (set as soon as the encounter roll wins, move.asm's `ora #$20`
-- before BattleZoom, well before battleLoadStarted's HP-table signal,
-- which is what let a battle transition look like a dead edge in
-- gen_figaro run 1), bit4 reload-world (the post-battle fade/init).
-- battleLoadStarted is still checked for the battle interior itself.
-- ($E9 reads $04 during normal control, measured, so it is
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
--  * battles reload the world: move.asm:916-921 snapshots the tile into
--    $1F60/$1F61 before Battle_ext and world_start.asm:465-482 reruns
--    ReloadMap after.  Measured: flag-write clear, then ~95 frames of
--    fade/init, position and facing restored exactly, danger counter zeroed.
--    The walker clears non-spared battles inline (flag write + edge-A) and
--    stalls until the reload finishes (aligned + full brightness) before
--    planning again
--  * no dialog branch: world triggers run world event scripts, not the
--    field dialog engine; $BA/$D3 are stale field RAM here
--   opts.arrive    extra terminator (checked first, every frame)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     formation species words never to clear by a flag write
--   opts.playBattles  end mid-walk battles by real play instead of the
--                  flag write, with no state writes on this navigator (issue
--                  #75), the same opt-in contract navTo/advanceStory carry.
--                  true    = auto-fight by edge-tapped A (A opens the acting
--                            character's command list, A confirms its first
--                            entry, A takes the default target; the same
--                            taps page the victory text);
--                  "tactical" = read the live command table and use Edgar's
--                            Tools (opts.tool, default H.AUTOCROSSBOW),
--                            Sabin's Blitz, and Fight for everyone else;
--                  "flee"  = hold L+R, the engine's own run mechanic.  On a
--                            fixture chain this is often the right
--                            input-driven ending for world encounters,
--                            because it earns no win, so
--                            win-only rolls (SHADOW's 1/16 post-battle
--                            leave, battle_main.asm:11976) never happen.
--                            It times out on unrunnable
--                            formations, so callers pick fight vs flee per
--                            step and say why.  In both cases the
--                            post-battle world reload restores the
--                            pre-battle tile with the danger counter
--                            zeroed (move.asm:916-921 /
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
          healer = opts.healer, magic = opts.magic,
          tool = opts.tool }) or nil
  local flee = tactical and newFlee(opts, tactical) or nil
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
          flee(battN)
          return
        end
        if tactical then tactical.frame(); return end
        -- playBattles=true reaches here: the battle is cleared by blind
        -- A-taps, with no menu awareness, no items and no flee.  This
        -- is the branch that walked BANON's escort into a wipe at
        -- terra_clifftop while its log said "navTo timeout".  It stays
        -- because unconverted steps still use it, but it logs a warning
        -- whenever it runs: converted routes want playBattles="flee"
        -- (corridor encounters) or playBattles="tactical" (fights that
        -- matter).
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
      -- forgive it once and re-search before giving up: world
      -- corridors run one tile wide (measured at the desert pass), so
      -- a single falsely-condemned edge there would otherwise be
      -- unrecoverable, while an edge that is actually dead is re-condemned
      -- on the next pass.
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
-- Some rooms are two complementary tilemaps swapped on an event timer.
-- Basement 2 of the Sealed Gate cave (map 385) swaps every 158 frames
-- once armed, and the reachable set inside either phase is a dead end;
-- the crossing exists only across the swaps.  navTo cannot drive such a
-- room (every edge is legitimately dead half the time and would be
-- condemned), so this walker plans over the union graph instead.
--
-- The mechanism, measured on map 385 (probe_v07_385win, 2026-07-28; the
-- room's scripts are event_main.asm:44634-44905):
--   * every swap callback rewrites the tilemap before it flips the phase
--     switches (`call _cb2b24` then `switch $01F5=0/$01F6=1`, and the
--     same shape in all four callbacks), so there is a ~13-frame window
--     (fsf 145..157 of the 158 cycle) where the next phase's floor is
--     physically in place while the switches, and the hurt triggers
--     keyed on them, still show the old phase;
--   * a held press into a tile the window just opened is taken by the
--     engine at fsf ~148; the party is mid-step when the switches flip,
--     and mid-step does not fire the stood-on tile's hurt trigger
--     (arrival on the far side runs the destination's trigger in the new
--     phase, where it EventReturns);
--   * hurt tiles are ordinary event-trigger tiles, and a stood-on
--     trigger tile re-enters its script every frame, so hasControl()
--     flickers there and every press here is unconditional (the
--     re-entry-trap escape idiom);
--   * random encounters restore state rather than running a LoadMap: the
--     phase switches and timers survive the battle round-trip (measured,
--     probe_v07_385door), but the dead cycle's half of the tilemap is
--     re-based by map-init, so after a battle the walker re-snapshots
--     and re-plans.
--
-- M.phaseWalk(tx, ty, spec) returns a step that walks the party to
-- (tx,ty) across the swaps.  spec (all fields required unless noted):
--   switches   = { a = 0x01F5, b = 0x01F6 }  -- the two phase switches;
--                edges on `b` are the clock (on 385 only the four timer
--                callbacks touch $01F6, so its edges are the swap
--                instants; pick the switch with that property)
--   period     = 158            -- measured frames between swaps
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
-- Written for the Blackjack party-swap room's random-walking TERRA
-- (probe_v07_g2h, 2026-07-28); nothing in it is specific to her.
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

-- The measured lever idiom (probe_v07_384toggle): one 8-frame up+A tap
-- fires the event and the switch flips at the end of it (~70 frames);
-- holding up with A released never re-fires; a second A press on a toggle
-- tile flips it back.  So tap once, hold up, and wait for the flip.
-- Dialogs opened by the event are advanced with edge-A; a battle that
-- fires on the tile is cleared by a flag write (no lever on any route so
-- far draws one, but the branch is kept because unexpected battles have
-- turned up elsewhere).
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
-- M.fieldCare: open the field menu and revive, cure and heal the party with
-- real presses, then close it again.  No state writes (issue #75); every
-- point of HP this restores is restored by the game's own item code,
-- driven the way a player drives it.  The status pass is CARE_STATUS_CURES
-- below, and it is one bit today: poison, because poison is the only status
-- that walking makes worse.
--
-- The input-driven routes run from random encounters, and a run costs HP:
-- the party takes a round or two of hits every time the run roll fails.
-- Measured on gen_kolts (2026-08-09), the mountain crossing took
-- TERRA from 94 to 39 and then the map-98 approach took her to 1 and EDGAR
-- from 106 to 1, at which point four played-out VARGAS attempts in a row
-- wiped, while seven Potions and five Tonics sat unused in the bag the
-- whole way.  The route was not too hard; the item menu was never used.
--
-- The UI, measured by probe_fieldheal.lua / probe_fieldcells.lua against a
-- real vargas_entry and cross-read against src/menu (the full citation
-- trail is docs/research/field-care-menu.md):
--
--   ZMENUSTATE = DP $26, and the shared list cursor is DP $4B.
--   $05 main menu, Item on row 0
--     -A-> $08 the item list itself; there is no options window in front
--          of it, and $4B here is the inventory slot (one column)
--     -A-> $19 "slot picked up".  A on a different slot swaps the two; A on
--          the same slot calls UseItem (field_menu.asm:2331-2336).
--          A first pass tapped A toward $08 and then pressed A again with a
--          moved cursor, which rearranged the bag instead of using
--          anything.
--     -A-> $70 target select: $4B is the menu slot 0..3 (battle order, not
--          party order), moved by up/down only; $69+slot holds that slot's
--          character id, which is how a character maps to a cursor row.
--     -A-> the item is applied and the window stays on $70, so serving a
--          second character with a different item has to back out ($77 ->
--          $08) rather than press on.
--   B from $08 lands on the item options window $17, then $04, then out.
--
--   Refusals are readable.  CheckCanUseItem (item.asm:2243-2330) allows only
--   a Fenix Down on a KO'd target and allows Tonic/Potion only on a living
--   character below full HP; an invalid pick starts the mosaic task, which
--   writes DP $B5 (zMosaic) for eight frames and then stops without clearing
--   it.  This driver watches the high nibble, which is the only part of that
--   cell that goes back to zero, and gives up on the plan instead of
--   pressing A at a window that will never accept it.  See serveFrame.
--
-- ---- casting instead of drinking ----
--
-- Owner, 2026-08-11: *"use tonics.  they're cheap, easy heals.  also early
-- game as we've modded it, healing with magic is pretty economical, given
-- the MP refresh on level up."*
--
-- OT6 restores HP and MP in full on every level up (Ot6LevelUpHeal,
-- ff6/src/battle/ot6_progression.asm:3-6, called from
-- battle_main.asm:16251).  So MP spent walking a corridor is refunded by
-- the next level, while a Tonic drunk in that corridor is gone for good and
-- the Phantom Train's shop is a hard gil budget.  Casting is therefore the
-- cheap move and the bag is the fallback, which is the order this driver
-- picks in.  Cure is 5 MP (MagicProp+5) against pools of 40 to 106 at the
-- fixtures measured, so with the default floor a caster covers six to
-- fifteen heals between level ups.
--
-- The magic path, same sources as above (field-care-menu.md section 5):
--
--   $05 main menu, Skills on row 1
--     -A-> $06 character select: $4B is the menu slot again, and A here
--          copies it into zSelIndex $28, which is how the drive reads back
--          WHO the skills screens are showing (field_menu.asm:644-649)
--     -A-> $0A skills options, Magic on row 1, enabled only when the
--          gate byte $7A reads $20 (field_menu.asm:1091-1104)
--     -A-> $1A the spell list.  $7E9D89+i is the spell id at list index i
--          and $7E9E09+i is its colour; $20 there is the game's own
--          "known, castable outside battle, and the MP is there"
--          (skills.asm:1093-1122), and it is the gate A itself applies
--          (field_menu.asm:2826-2831).  $4B = 2*row + column.
--     -A-> $3B target select, the same cursor as $70.  Left and Right here
--          jump to the all-targets state $3D, so only up and down are used
--          (field_menu.asm:2852-2874).
--     -A-> the spell lands and the window STAYS on $3B, so a second target
--          for the same caster and spell costs nothing but cursor moves.
--          That is why the driver holds a caster until they hit their MP
--          floor rather than spreading the casts around.
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
-- opts.maxTries   plans to attempt before giving up (default 48).  A magic
--                 visit runs more plans than an item one for the same
--                 party, because a Cure restores less than a Potion at
--                 these levels: measured at the battle-70 stop, one Cure
--                 from a level 14 CELES restored 197 HP against a Potion's
--                 246, and a Tonic is a flat 50.  It is still the shorter
--                 visit in frames, because the extra plans stay inside $3B
--                 while each item use pays a full fade round trip.
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
-- On the world map that answer is only trustworthy when it holds for a
-- while.  Measured on the overworld (gen_sabin_gau's staging walk,
-- 2026-08-09): the close drive's exit read one satisfying frame
-- mid-handoff, logging "back to the field satisfied after 58 frames",
-- while the main menu was still open behind it (ZMENUSTATE=05), because
-- the world control/alignment registers held stale-live values during the
-- menu module's teardown.  The caller's walk then parked against an open
-- menu for its whole budget at every care stop, until it gained its own
-- B-tap recovery.  So the world close is debounced: its condition must
-- hold 30 consecutive frames before the close is believed, which a
-- stale-live coincidence cannot survive.
--
-- The debounce is world-mode only, because only the world close was
-- broken.  On a field map hasControl() already reads false for the
-- entire menu lifetime and becomes true only once the field module is
-- back (measured: the pre-dive close sampled ctl=false
-- straight through the menu, then ctl=true stable), so the field exit
-- is correct on the first true frame and needs no wait.  Forcing 30
-- consecutive true frames there hangs it instead: every B tap the close
-- driver sends to shut the menu drops control for that frame, and
-- 4-of-12 tapping never leaves 30 clean frames in a row (measured:
-- 2400-frame timeout with ctl=true on every heartbeat).  careClose()
-- below carries that split; careBackOnMap() is the raw predicate it and
-- the setRows first stage build on.
local CARE_ZM, CARE_CUR, CARE_REFUSE = 0x26, 0x4b, 0xb5
local CARE_SEL, CARE_MAGIC_SEL = 0x28, 0x99   -- zSelIndex, chosen list index
local CARE_MAGIC_GATE = 0x7a                  -- zSkillsTextColor[1] = Magic
local CARE_TONIC, CARE_POTION, CARE_FENIX = 0xE8, 0xE9, 0xF0
local CARE_ANTIDOTE, CARE_SOFT, CARE_REMEDY = 0xF2, 0xF4, 0xF5
local CARE_CURES = { 0x2D, 0x2E, 0x2F }       -- Cure, Cure 2, Cure 3

-- ---- clearing a status, when a fixture proves the route needs it ----
--
-- Status 1 is `weicmpzd` (ff6/notes/field-ram.txt:900-907): $80 wound, $40
-- petrify, $20 imp, $10 clear, $08 magitek, $04 poison, $02 zombie, $01
-- dark.  Five of those bits have a bag item that clears them, and
-- CheckCanUseItem accepts each item only on a target actually carrying its
-- bit (item.asm:2243-2323): Soft on petrify, Green Cherry on imp, Antidote
-- on poison, Revivify on zombie, Eyedrop on dark, Remedy on any of
-- petrify/imp/poison/dark at once.  The antidote arm is :2318-2322, and it
-- is `and #$04 / beq invalid`, so an Antidote offered to a character who is
-- not poisoned is refused rather than wasted.
--
-- Poison was the first row in this table, because it is the only status that
-- walking makes worse.  DoPoisonDmg drains max HP/32
-- from every poisoned character on every step and floors the result at 1
-- (`ff6/src/field/player.asm:593-613`), so a character who leaves a fight
-- poisoned arrives at the end of any walk of length at exactly 1 HP,
-- whatever they had when the fight ended.  That is what banon_joined and
-- lete_river were: TERRA at 1 of 136 after five crossings of a hideout that
-- cannot draw an encounter at all.  Every other curable bit is a combat
-- handicap that costs nothing to carry down a corridor.
--
-- Adding one is one row here, and the drive needs no other change -- the
-- item path already routes $05 -> $08 -> $19 -> $70 for any item id, and
-- the landing check below watches the status byte as well as the bag count,
-- which is the only signal a cure that restores no HP produces.  What is
-- missing for the other four is a fixture that carries the status, so a row
-- for them would be a path nothing in the tree has ever run.  Petrify earned
-- its row on 2026-08-13: a forced Phantom Train corridor fight left SHADOW
-- petrified, the boss was then broken and beaten cleanly, and train_done
-- correctly refused to ship a stone party member.  The South Figaro
-- provision stop now carries Soft for that journey, so fieldCare uses the
-- ordinary item when the bit is present and otherwise leaves it in the bag.
--
-- A row carries an ORDERED list of items rather than one, tried in order and
-- skipped when the bag has none of that one.  The Antidote is first because
-- it is the cheap single-purpose answer; the Remedy is the fallback, and its
-- arm does accept a poisoned target -- `and #$65` isolates petrify, imp,
-- poison and dark (ff6/src/menu/item.asm:2311-2315).  Without the fallback a
-- party holding Remedies and no Antidote carries the bit for the rest of the
-- route, and that is measured rather than hypothetical: CELES took poison in
-- the first fight of gen_zozo2_arrival's crossing on 2026-08-13 with two
-- Remedies and no Antidote in the bag, and all twelve care stops after it
-- spent a Cure undoing damage the bit immediately redid.
--
-- HOW FAR THIS HAS BEEN WATCHED.  The declining half is measured three
-- times: with the bit set and nothing in the bag that clears it,
-- pickStatusCure returns nil and the visit logs `status1 04 -> 04` beside
-- each Tonic it spends, at gen_kolts's stop before VARGAS and at both of
-- gen_returner's.  The succeeding half -- bit set, a cure in the bag, bit
-- cleared -- was unwatched until 2026-08-13, because poison is a rare draw:
-- it landed once in a full chain regeneration and then not at all in eleven
-- targeted re-runs of the two generators that fight the formations which
-- apply it.  The Zozo crossing is the run that finally carried it.
local CARE_STATUS_CURES = {
  { bit = 0x40, items = { CARE_SOFT, CARE_REMEDY }, what = "petrify" },
  { bit = 0x04, items = { CARE_ANTIDOTE, CARE_REMEDY }, what = "poison" },
}
local MAGIC_LIST, MAGIC_COLOUR = 0x7E9D89, 0x7E9E09

-- The menu screens the drive can be parked on.  Every other value of $26 is
-- a fade ($00/$01/$02) or a one-frame init ($03/$04/$07/$09/$3A/$3C/$6F/$77)
-- that resolves on its own, and pressing anything during one is how a drive
-- loses a button (field-care-menu.md section 6, trap 1).  Two things read
-- this: the router presses B on any screen that is not on the current
-- plan's path, and the close predicate treats "not on any of these" as the
-- menu no longer being up.
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
-- can-I-use-this check compares against.  The top two bits are a boost code
-- and the rest is the base.
--
-- CalcMaxHPMP (menu_common.asm:2376-2413) is a four-entry jump table whose
-- arms fall through each other, so the percentages are not in table order:
--
--   MaxHPMP_00 (:2398) clr_a, then falls through all three shifts -> +0
--   MaxHPMP_03 (:2400) lsr, lsr, lsr, adc base                    -> +12.5%
--   MaxHPMP_01 (:2402) lsr, lsr, adc base                         -> +25%
--   MaxHPMP_02 (:2404) lsr, adc base                              -> +50%
--
-- so code 2 is the 50% boost and code 3 is the 12.5% one.  This function
-- had those two swapped, matching neither the source nor
-- research/field-care-menu.md section 4; it is latent rather than observed,
-- because every World of Balance roster dumped so far reads a bare base
-- with no boost bits set, so no fixture has ever taken the wrong branch.
-- M.calcMaxHpMp is exported separately from the two readers so the unpack
-- can be checked against literal words without a fixture that sets a boost
-- (probe_healpolicy.lua).
--
-- `cap` is ValidateMaxHP's 9999 or ValidateMaxMP's 999
-- (menu_common.asm:2424-2447).
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
-- learned table is permanent knowledge; #96 also makes an equipped esper's
-- GenjuProp spell ids live while worn, matching the battle list.  Read both
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

-- MP cost of a spell, read from the ROM's own table.  The field menu prices
-- a spell at MagicProp+5 with no OT6 hook in the path (_c3510d,
-- skills.asm:1056-1060), then halves it for a Gold Hairpin ($11D7 bit $20)
-- or flattens it to 1 for an Economizer (bit $40), skills.asm:1078-1090.
-- Those two relics are not modelled here, so this over-states the price for
-- a character wearing one, which errs toward drinking a Tonic when a cast
-- would have been free.  The in-menu gate below ($7E9E09 == $20) is the
-- game's own answer and catches the difference where it matters.
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
-- Why this is a shared helper rather than four hand-written loops.
--
-- returner_hideout shipped with TERRA at 0/136 and LOCKE at 0/168 and five
-- Fenix Downs unused in the bag.  Two steps later Banon's speech cut the
-- party down to TERRA alone, so a hideout with no encounters in it produced
-- a party wipe, and the wipe was investigated as a bug in the hideout.  A
-- generator that ships a casualty is not saving the story getting
-- somewhere; it is saving the route losing on the way, and every step that
-- boots from that fixture inherits the loss.
--
-- tools/audit_party_hp.py is the tree-wide net for this and it is the same
-- three conditions, deliberately: the net only catches a bad fixture after
-- a `make savestates` measured in hours, while this fails the generator at
-- the moment it was about to save.  If you change one, change the other, or
-- a generator will pass its own exit contract and fail the audit.
--
--   dead:       HP 0, or wound in status 1
--   petrified
--   or zombie:  the other two bits of $C2, which is the mask the game
--               itself applies when it asks whether a character can be
--               healed (CheckCanUseItem, item.asm:2249-2258) or picked for
--               Skills (CheckSkillValid, field_menu.asm:722-731).  A
--               petrified character is not dead and a Fenix Down will not
--               raise them either
--   near fatal: HP at or below max HP / 8, which is the game's own
--               arithmetic and not a number chosen here: `lda $3c1c,y`
--               (max HP), `lsr3`, `cmp $3bf4,y` (current HP), and near
--               fatal goes into the status-to-set when the carry says
--               max/8 >= current (battle_main.asm:11544-11549)
--   poisoned:   $04 in status 1, which is a casualty in slow motion rather
--               than a handicap.  DoPoisonDmg drains max HP/32 from
--               every poisoned character on every step and floors the result
--               at 1 (ff6/src/field/player.asm:593-613), so the walk itself
--               converts the bit into 1 HP and then holds it there.  A
--               fixture that ships poison is a fixture that will hand the
--               next generator a character the next encounter has already
--               claimed, whatever HP the record reads today.  Measured:
--               banon_joined and lete_river shipped TERRA at 1 of 136 with
--               status 04, and the near-fatal clause above is what caught
--               them -- at the end, after the grind, rather than at the
--               fight that applied the bit.
--
-- Near fatal rather than dead-only because a member at 15 of 231 is a
-- casualty the next random encounter has already collected.  Near fatal
-- rather than something stricter because a bar that fires on ordinary wear
-- gets waived away; audit_party_hp.py's header carries the measurement that
-- put the line there.
--
-- This is the FLOOR, not the readiness bar.  A generator walking into a
-- known fight should assert more than this and several do: gen_kolts and
-- gen_returner require half HP at their exits, and gen_kolts additionally
-- rations TERRA's MP to what VARGAS needs.  Passing this helper only means
-- the fixture is not a casualty report.
-- $C6, not $C2: the game's own can-be-healed mask is $C2 (wound, petrify,
-- zombie) and stays $C2 everywhere this file asks the game's own question,
-- because the menu serves a poisoned character perfectly well.  The exit
-- contract asks a different question -- is this fixture safe to hand down --
-- and poison fails that one.
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

-- M.buyItem: buy `qtyFn()` more of shop row `row`, closed-loop,
-- with the shop already open at its options window (menu state $25).
-- Promoted from gen_sabin_train/gen_sabin_gau, where two identical
-- copies had each arrived at these rules:
--
--  * The list cursor row is MoveCursor's own cell (DP $4E,
--    menu_common.asm:1318) and the quantity is zSelIndex (DP $28,
--    menu_ram.inc).  Both are read and steered, never press-counted,
--    because menu direction holds auto-repeat: a counted 4-frame hold
--    measurably bought 25 Tonics instead of 14 and parked the next lap
--    on the wrong row.  Widget deltas (shop.asm MenuState_27): right +1,
--    left -1, up +10, down -10, gil-clamped by the handler.
--  * The clamp reports how much gil is available: steering toward a
--    quantity the gil cannot cover pins qty at the affordable maximum,
--    and a loop that keeps pressing spends its whole budget against that
--    clamp (gen_sabin_gau's "TONIC to 99" on 209 gil failed with a
--    timeout at 20000).  After 240 frames with the quantity unmoving
--    against the clamp, the clamped qty is accepted and logged.  Order
--    the buys so the marginal item comes last and a small purse shorts
--    it rather than the essentials.
--  * Purchases are verified after the shop closes; mid-menu inventory
--    reads are measurably wrong (the field bag does not update until the
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
    for _, c in ipairs(M.partyMembers()) do
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
    for _, c in ipairs(M.partyMembers()) do
      local w = { kind = "item", char = c, item = CARE_FENIX, why = "revive" }
      if M.charHp(c) == 0 and avail(CARE_FENIX) > 0 and not failed[key(w)] then
        return w
      end
    end
    for _, c in ipairs(M.partyMembers()) do
      local w = pickStatusCure(c)
      if w ~= nil then return w end
    end
    local hurt = {}
    for _, c in ipairs(M.partyMembers()) do
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

  local function steer(cur, wantRow)
    if cur == wantRow then return { "a" } end
    return { [cur < wantRow and "down" or "up"] = true }
  end

  -- give up on this plan and let the next frame pick another
  local function abandon(w, why)
    M.log(string.format("[%s] dropping plan (%s): %s", tag, why, planText(w)))
    failed[key(w)] = true
    want, pending = nil, nil
  end

  local function serveFrame()
    phase = (phase + 1) % 12
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
      end
    end

    if want == nil then
      want = pick()
      if want == nil then served = true; M.setPad({}); return end
      tries = tries + 1
      if tries > maxTries then
        M.log(string.format("[%s] giving up after %d attempts", tag, tries))
        served = true; M.setPad({}); return
      end
      if want.kind == "cast" then activeCaster = want.caster end
      M.log(string.format("[%s] plan: %s", tag, planText(want)))
    end

    -- Route by state.  A screen that is not on the current plan's path gets
    -- a B, which unwinds to $05 from anywhere: B in $70 goes to $77 -> $08,
    -- in $08 to $17, in $17 to $05, in $1A to $0A (ReloadSkillsMenu,
    -- field_menu.asm:2855-2860) and in $0A straight to $05
    -- (field_menu.asm:1000-1007).  That replaces the older explicit rewind
    -- flag, which only knew how to get back to the item list.
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
          local slot = slotOf(want.char)
          if slot == nil then
            M.log(string.format("[%s] char %d is not on the target window " ..
              "(slots %d,%d,%d,%d)", tag, want.char, M.readByte(0x69),
              M.readByte(0x6a), M.readByte(0x6b), M.readByte(0x6c)))
            abandon(want, "not a target"); M.setPad({}); return
          end
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
        local slot = slotOf(want.caster)
        if slot == nil then abandon(want, "caster not on screen"); M.setPad({}); return end
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
          local slot = slotOf(want.char)
          if slot == nil then abandon(want, "not a target"); M.setPad({}); return end
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

  -- The roster line carries MP as well as HP now.  MP is what the policy
  -- spends, so a before/after pair that prints only HP cannot show what a
  -- visit cost or what casting saved.  It carries status 1 as well, for the
  -- same reason: a poisoned character reads as a healthy one on an HP/MP
  -- line right up until the walk grinds them to 1, so a stop that could not
  -- clear a status has to say so in its own log rather than leave the next
  -- generator's roster to imply it.  A zero status prints nothing, so the
  -- ordinary line is unchanged.
  local function roster(what)
    local out = {}
    for _, c in ipairs(M.partyMembers()) do
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

  return M.cond(anyNeed, {
    M.logStep(function() return roster("opening the menu") end),
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
    }, tag .. ": heal/revive through the field menu"),
    M.release(),
    M.driveUntil(careClose(function()
      return not CARE_SCREENS[M.readByte(CARE_ZM)]
    end), 2400, {
      M.call(function()
        phase = (phase + 1) % 12
        M.setPad(phase < 4 and { "b" } or {})
      end),
    }, tag .. ": back to the field"),
    M.release(),
    M.waitFrames(30),
    M.logStep(function() return roster("done") end),
  }, {
    -- A care stop that does nothing still logs.  The first run with
    -- this driver skipped its most important stop without logging, and the
    -- roster three lines later was the only evidence, so "no log" and
    -- "nothing needed" must not look the same.
    M.logStep(function() return roster("nothing to do") end),
  })
end

-- ---------------------------------------------------------------- rows --
-- M.setRows: put characters in the front or back row through the real Order
-- screen.  Reads and pad presses only (issue #75).
--
-- Owner note, 2026-08-09: "a lot of ranged attackers can just sit in
-- the back row forever at no cost."  Before this, no fixture in this
-- chain had set a row: every input-driven route walked its whole party
-- into the front row and took full physical damage.
--
-- The exemption was checked in this ROM.  ExecCmd sets
-- $B3 = $FF at the top of every command (battle_main.asm:3131-3133), and
-- bit $20 there means "ignore attacker row", so no row penalty is the
-- default.  One routine clears it: the weapon-swing setup
-- _c2299f (battle_main.asm:7127-7133), and only when the main-hand weapon
-- lacks WEAPON_FLAG::BACK_ROW.  So a back-row character loses damage only
-- on a Fight; EDGAR's Tools, TERRA's Magic and SABIN's Blitz never
-- reach that code and cost nothing.  Damage taken is halved for physical
-- attacks either way.  LOCKE is the one who trades something: Steal deals
-- no damage, so Fight is all he has, and this route leaves him in front.
-- Full citation trail: docs/research/row-menu.md.
--
-- The UI, including the two parts that are easy to get wrong:
--   * the Order screen has no main-menu row.  It is reached by pressing
--     left on the main menu ($05), a handler beside the A handler that
--     never goes through SelectMainMenuOption (field_menu.asm:571-576,
--     :3491-3508); the menu scrolls sideways ($65) to reveal the word
--     "Order", which is drawn off the visible edge.
--   * the toggle is A twice on the same slot.  MenuState_10 compares
--     zSelIndex ($28) to the cursor ($4B); a second A on a different slot
--     reorders the party instead of flipping a row
--     (field_menu.asm:1845-1870).  So the cursor must not move between the
--     two presses, and this driver verifies $28 before the second press
--     and treats state $11 (the swap) as an error rather than something to
--     recover from.
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
-- position `pos`, through the real Skills -> Espers -> detail -> A walk
-- (skills.asm MenuState_4d @5902 is the equip).  Reads and pad presses
-- only (issue #75).  Written for the Cranes re-test (2026-08-10): the
-- fight's designed key is BISMARK's Sea Song, the game's only water
-- attack, and no input-driven route had equipped an esper before.
-- The list seek is menu_esperdetail's two-column idiom against the live
-- $7e9d89 row->esper table; an esper the save does not own never appears
-- there, so the seek times out instead of equipping the wrong row.
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
-- Relic 2, and it defaults to 0, which is what every caller before the Zozo
-- readiness sweep wanted.  The slot list is one vertical column and the
-- cursor lands on row 0, so the seek is that many DOWN presses, read back
-- off the same cursor byte the character and item seeks use rather than
-- counted blind.  The name still says weapon because that is what it is
-- nearly always used for; the slot is the exception.
--
-- One hazard the slot opens up: equipping a Genji Glove, Gauntlet or Merit
-- Award into a relic row makes the game run Optimum on its own when the
-- Relic screen is backed out of (CheckReequipRelics tests exactly those
-- three, equip.asm:2843-2850).  Those three are the whole list, so any
-- other relic is safe here; a caller that wants one of them owes the
-- deliberate re-equips afterwards, as HANDOFF records.
--
-- The slot matters because a bare slot is not a cosmetic gap.  Measured
-- 2026-08-12 at zozo_arrival and again at zozo_clock_solved: CELES walks
-- into Zozo with no body armour and no relics and SABIN with no shield and
-- no relics, while a LeatherArmor, a Buckler, two Star Pendants, a Peace
-- Ring and a Black Belt sit in the bag -- six items for the six empty
-- slots.  CELES's defence is 34 where the rest of the party runs 44 to 55,
-- and she is the only healer.
--
-- equipOptimum is not enough, measured 2026-08-10 on the Cranes:
-- Optimum picks by attack power and armed LOCKE and EDGAR with Thunder
-- Blades ($0F: slash class, lightning element), and the Left Crane
-- absorbs lightning, so every Fight healed the boss (+160/+198 pair
-- heals, +943 boosted) and advanced its Giga Volt charge counter.  An
-- element-aware weapon swap is ordinary fight preparation, and no
-- input-driven route had it until this function.
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
-- This is the deliberate counterpart to equipOptimum.  A route states the
-- loadout it wants and why at the call site; this helper only makes that
-- decision resilient to an upstream step having already equipped part of it.
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

-- --------------------------------------------------------------- equip --
-- M.equipOptimum: put the party's gear back on, through the real field
-- Equip -> Optimum walk.  Reads and pad presses only (issue #75).
--
-- This is a library function because more than one fixture needs it.  The
-- game strips characters and returns their gear to inventory at story
-- beats (`remove_equip` / EventCmd_8d), and the chain of generated
-- savestates never put it back.  battle_brokendeath found this at the
-- Vector infiltration and drove Equip -> Optimum by hand to fix its own
-- fixture.  Measured 2026-08-09, solo LOCKE starts his whole
-- South Figaro scenario with $1600+37*1+$1F..$23 all reading $FF, so no
-- weapon, no armor, no relics, and his own Dirk sitting in the bag, and
-- then fought a level-13, 495-hp HeavyArmor barehanded for eight
-- damage a swing across three lost attempts.  That looks like a
-- balance finding but is not one.  A player opens the Equip
-- menu, and so does this.
--
-- Menu path (battle_brokendeath.lua:118-152, verified live there):
--   $05 main, cursor row 2 = Equip -A-> $06 character select -A-> $36 the
--   option row, which is horizontal: Equip / Optimum / Rmove / Empty, so
--   Optimum is cursor 1, one press right.  A runs EquipOptimum in place.
--
-- A no-op, with the menu never opened, when everyone already holds a
-- weapon, so a route can call it after any story beat and pay only where
-- something was taken away.
--
-- Optimum picks by attack power and knows nothing about elements, which
-- is how the Cranes got armed with ThunderBlades against a boss that
-- absorbs bolt.  That case is caught rather than corrected: the absorb
-- guard in M.run fails the run at battle start when an equipped weapon's
-- element is absorbed by anything in the formation (issue #81; the block
-- above M.ELEM_NAMES in lib/ot6.lua carries the reasoning).  It
-- deliberately says nothing about a merely NULLED element, because on
-- battle 70 the nulled pick is the correct one and the element-aware
-- alternative lost all three attempts.  When the guard fires, the fix is
-- a deliberate M.equipWeapon for that fight, not a change here.
--
-- `opts.slots` names which character-select slots Optimum runs on, in
-- order; the default is every slot, which is what every caller before
-- gen_tunnelarmr wanted.  It exists because power-greedy Optimum and a
-- deliberate M.equipWeapon cannot both have the same slot: measured
-- 2026-08-12 at celes_freed, the bag holds one MithrilBlade (power 38,
-- slash) and one Dirk (power 26, pierce), and running Optimum over both
-- slots gives LOCKE the blade and CELES the Dirk (`[celes kit] done:
-- c1=0A c6=00`) -- the pierce weapon in the hand of the character whose
-- whole drive is Runic, against a boss that is `5, OT6_PIERCE`
-- (ot6_hud.asm:1943).  Equipping LOCKE first and then letting Optimum
-- have his slot back just undoes it, because 38 beats 26.  So the caller
-- equips the slot it cares about with M.equipWeapon and leaves that slot
-- out of this list.
function M.equipOptimum(opts)
  opts = opts or {}
  local tag = opts.tag or "equip"
  local slots = opts.slots or { 0, 1, 2, 3 }
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
  -- member gets one whether or not that member is the bare one, because
  -- Optimum on an already-equipped character is a no-op the game handles
  -- itself
  local function oneSlot(slot)
    -- Guard on the party rather than on zCharID: $69+slot is the menu's own
    -- copy and it is stale on the field, so a solo scenario read "slot 1 =
    -- char 255" as occupied and then hung trying to walk a cursor onto a
    -- slot that is not there.  #M.partyMembers() is answered by $1850 and is
    -- correct whether or not a menu has ever been open.
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
      -- EquipOptimum runs in place: the state does not change, so there is
      -- nothing to drive toward; one edge press is enough.
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

  -- built up rather than written out, because opts.slots decides both which
  -- slots run and in what order
  local walk = {
    M.logStep(function()
      return string.format("[%s] someone is bare-handed (%s) -- opening " ..
        "Equip on slots %s", tag, kitLine(), table.concat(slots, ","))
    end),
  }
  for _, slot in ipairs(slots) do walk[#walk + 1] = oneSlot(slot) end
  walk[#walk + 1] = M.logStep(function()
    return string.format("[%s] done: %s", tag, kitLine())
  end)
  walk[#walk + 1] = M.call(function()
    for _, c in ipairs(M.partyMembers()) do
      M.assertEq(bare(c), false, string.format(
        "char %d is holding a weapon after Optimum", c))
    end
  end)

  return M.cond(anyBare, walk, {
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

-- gen_banon's talkToObj, unchanged in shape: approach re-resolved from live
-- object coords (NPCs wander), facing computed from the live delta, soft
-- rounds before a hard one.  CheckNPCs activates whatever the object map
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

-- Ride a scene out to a settled, controllable field, edge-tapping A on every
-- frame the party is not in control and fighting anything that comes up by
-- real input (issue #75; the HP pin and battle-clearing flag write this
-- branch used to carry are gone).  Battle frames drive gen_moogle's Marshal
-- cycle: R raises the
-- active character's pending boost (1 bp at battle start, Ot6InitBP; the R
-- does nothing on an empty bank), then three edge-tapped A's confirm
-- the boosted Fight and page victory text, so solo LOCKE alternates
-- boosted and plain Fights against battle 11's HeavyArmor.  A loss now has
-- real consequences (the _ca85ba scenario reset), so the callers wrap every
-- engagement in a phase-spread retry sequence rather than pinning HP.
--
-- advanceStory does not work here.  advanceStory taps A only while a battle
-- is up or M.dialogWaiting() is true, and holds the pad empty otherwise.
-- The tail of `battle 11` has a window state that satisfies neither:
-- measured at the third gate-soldier fight, $0059 = $52 (a menu module owns
-- the CPU) with $BA/$D3 both clear, so dialogWaiting() is false, the battle
-- flag is already down, and advanceStory sat with the pad empty for 20000
-- frames while the event PC stayed parked at $CA85B9.  Tapping A whenever
-- there is no control clears it, and it cannot misfire on the open field
-- because the tap is gated on not having control.
-- (This must never meet a choice prompt, because an A press always takes
-- option 0, so every prompt on a route is answered by a choice-steering
-- rider like gen_sfigaro's rideUntil rather than by this.)
-- The fight itself is no longer a fixed button pattern.  The first
-- input-driven version of this drove every battle with a fixed 32-frame
-- cycle (R to boost, then three edge-tapped A's), which pages victory text
-- but does not keep the party alive.  Measured 2026-08-09 on the
-- first end-to-end run that reached this edge: solo LOCKE, level 8 with
-- 168 hp, lost the gate soldier's HeavyArmor three attempts running, while
-- sixteen Tonics sat in the bag.  He used none of them, because
-- the pattern does not read menus.  M.newFightDriver does: it reads
-- the live command table, boosts, and runs its own item medic line.
-- healPercent is the fraction it tops up at, and it is no longer the whole
-- rule: M.healDecision decides whether a heal is worth the turn it costs,
-- and a solo character who cannot out-heal the damage swings instead of
-- drinking.  That matters here more than anywhere, because LOCKE alone is
-- the one party shape opts.healer cannot help.
-- (The field half of this routine is hand-rolled; see the note above on
-- why advanceStory cannot handle the tail of battle 11.)
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
  })
end

-- The gate soldier comes back every time map 75 reloads.  `hide_obj NPC_11`
-- (_ca856a, event_main.asm:20313) sets a runtime bit rather than story
-- state: leaving town for an interior and coming back re-runs InitNPCs
-- (field/init.asm:469 only skips it when reloading the same map) and
-- re-creates every npc whose spawn switch still holds.  His is $030C and
-- nothing in the scenario clears it.  So (30,42), the only tile joining the
-- SE quarter to the rest of town, is blocked again on every return, and
-- gen_sfigaro's route crosses that boundary three times.  The soldier's
-- uniform does not help: `if_switch $0103=1` only swaps his fight for a
-- "Halt!" line (:20296); it does not move him.
-- The branch is gated on a symptom (a BFS probe to a tile on the far side)
-- rather than assumed, so if the respawn ever stops happening this reports
-- it instead of walking into a fight that is not there.
--
-- Every engagement is a retry sequence (issue #75).  With the HP pin
-- gone, a lost battle 11 runs _ca85ba, which revives LOCKE on (47,43) and
-- clears both disguise switches, so each fight captures a blob first, and a
-- loss reloads it and re-engages on a different battle RNG phase.  The seed
-- is the game-time frame counter at battle init (`lda $021e / asl2 / sta $be`,
-- battle_main.asm:6174-6176), so the ladder is spread on $021e itself and
-- reads back what each attempt drew (M.newSeedLadder, issue #83) rather than
-- trusting a frame offset to land somewhere new.  Success means the party is
-- not on the opening tile and the probe tile is reachable; three losses fail
-- generation.
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
      -- outside the n > 1 block, unlike the wait it replaces: attempt 1 needs
      -- a phase of its own too, or it can land on attempt 2's seed (#83)
      L.spread(n),                       -- spread the battle RNG phase (#83)
      M.talkToObj(26, tag .. ": the gate soldier (battle 11)"),
      M.rideOut(tag .. ": ride battle 11 out", 30000, 75),
      M.call(function()
        -- a lost attempt runs the scenario reset (_ca85ba) and puts the
        -- party back on (47,43); being anywhere else with the lane open is
        -- a win.  ($0104 is not this signal; see the branch below.)
        -- The same test does not work after the fight: a beaten
        -- soldier keeps his coordinates, because the scene hides the object
        -- without moving it, so obj 26 still reads {30,42} on a win.
        -- Each question is asked where it is valid: his tile decides whether
        -- to fight (stable at step start, when the object map may not be
        -- populated), and reachability decides whether we won (stable
        -- afterwards, when he is gone from the map even though his record
        -- is not).  A loss puts the party back on (47,43).
        won = not (M.fieldX() == 47 and M.fieldY() == 43)
          and M.bfsPath(probeX, probeY) ~= nil
        M.log(string.format("%s: attempt %d %s at (%d,%d) f%d, $0104=%d",
          tag, n, won and "WON" or "LOST (scenario reset)",
          M.fieldX(), M.fieldY(), M.frame, swv(0x0104)))
      end),
    })
  end
  -- The party cannot walk past him, and that is measured rather than
  -- assumed.  South Figaro is a stealth chapter and the gate soldier
  -- appeared to wander, since the old reachability probe answered "lane
  -- open" often enough to flip this branch by accident, so waiting him out
  -- looked possible.  Measured 2026-08-09: polling M.bfsPath(22,43) every
  -- 60 frames for 7200 frames (two minutes of game time) never found a
  -- path.  He does not step off the choke point.  The fight is mandatory,
  -- which is why the balance finding below is a real one rather than a
  -- routing failure.
  --
  -- An earlier version decided this branch on the story switch instead of
  -- a BFS probe.  It used to ask whether (22,43) was reachable at that
  -- instant, and the answer appeared to depend on where the gate soldier
  -- was standing: if he stepped off the choke point the probe would say
  -- "lane already open", the fight would be skipped, and the next navTo
  -- would walk into him and fail with "no path" twenty retries later.
  -- Measured 2026-08-09: inserting a single menu visit ahead of this cond
  -- was enough to flip it.  $0104 was taken to be the switch the gate
  -- scene sets, it does not wander, and the loss path below already reads
  -- it.
  -- That change was then reverted to the reachability probe.  It had been
  -- switched to $0104 on the theory that the soldier wanders and the probe
  -- is a coin flip.  Both halves of that were wrong: he does not wander
  -- (polled every 60 frames for 7200 frames, the lane never opened once),
  -- and $0104 is not the switch the gate sets, so keyed on it this
  -- reported a loss on a fight LOCKE had won outright, with HeavyArmor at
  -- 0 hp and the party standing clear of the reset tile.
  -- The branch is now the soldier's own tile rather than a path query.
  -- Three readings of this have been wrong.  $0104 is not the switch the
  -- gate sets (it called a won fight a loss).  And the BFS probe, which
  -- was right when this step opened with a walk, reads "open" every time
  -- now that the step opens two menus first, so the party skips the fight,
  -- walks to (31,42) and fails with "no path" twenty retries later.
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
    -- Heal first.  He respawns on every map-75 reload, so gen_sfigaro's
    -- route fights him three times, and LOCKE arrives at the third one
    -- with whatever HP the first two left him.  Measured: B1 won, R1 won
    -- on its second attempt, R2 lost all three, not because that fight is
    -- different but because he entered it with low HP.  A player heals
    -- between rounds with a soldier, and so does this.  A no-op when he is
    -- already at full HP, and it never spends below the Potion floor the
    -- later beats need.
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
    -- read off the seeder itself (#83).  "Three losses fail generation" only
    -- means something if the three were not one fight replayed.
    L.report(),
    M.call(function()
      -- This fight blocks the route today, and the assert below is the
      -- report of that rather than a flaky step.  A note here used to say
      -- it passed once LOCKE was armed, in the back row, healed between
      -- rounds and breaking the armour; that is falsified and removed.
      --
      -- Measured 2026-08-12 by probe_battle11.lua, which hooks the battle
      -- module's own end-of-battle decision: solo LOCKE, level 8, 168 hp,
      -- armed through the real Equip -> Optimum walk and in the back row,
      -- IS KILLED by the level-13 HeavyArmor's second action and the party
      -- is wiped.  168 -> 111 on its first (the halved physical), his one
      -- Fight takes it 495 -> 489 and one shield off three, then 111 -> 0.
      -- CheckBattleEnd sees $3A74 = 0 and calls LoseBattle with battle
      -- message $29 "annihilated" (battle_main.asm:12170, :12822-12830),
      -- which sets $3EBC.0 -- battle switch $40 -- and the event's
      -- `if_b_switch $40` then falls through to the scenario reset.  So the
      -- loss branch below is reading a real, ordinary loss.
      -- One ATB round is about 570 frames at this level, so he gets one
      -- action per fight and three shield chips are four away.  Healing
      -- cannot close it: 111 of 168 is 66%, above the driver's 60% line,
      -- and no Tonic covers a 111-damage hit.  Its weaknesses are bolt and
      -- water (monster_prop +25 = $84) and solo LOCKE can reach neither.
      -- Bare-handed -- how the chain delivered him until H.equipOptimum
      -- landed -- it was eight damage a swing, and front row and back row
      -- measured identically bare-handed, which is why the row setting went
      -- unnoticed for three runs.
      -- Do not widen the attempt sequence until it succeeds by chance; that
      -- is the #74 mistake, and it would be a re-roll of a fight whose
      -- outcome does not depend on the seed.
      M.assertEq(won, true,
        tag .. ": battle 11 won within 3 attempts (boosted Fights)")
      M.assertEq(M.bfsPath(probeX, probeY) ~= nil, true,
        tag .. ": the lane is open again")
    end),
  }, {
    M.logStep(function() return tag .. ": the lane is already open" end),
  })
end
