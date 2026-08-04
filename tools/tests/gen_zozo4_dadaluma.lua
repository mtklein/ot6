-- gen_zozo4_dadaluma.lua -- v0.4 leg 3: zozo_arrival (map 221 street) ->
-- the crane maze -> DADALUMA.  Mints dadaluma_doorstep.mss at (30,13),
-- one A-press from the fight, and dadaluma_won.mss on the same tile after
-- battle 69's scripted win clears him off the tower porch.
--
-- THE MAZE (probe_climb5/9/11/15/16 -- every claim below walked):
--  * The city is a DIRECTED graph once door source tiles are modeled as
--    what they are -- walk-on teleports.  Flooding with doors-as-floor
--    fuses regions only a teleport connects (that error hid the route);
--    with doors as walls the islands and their only bridges appear:
--      street --P9(38,57)--> 225 --P10b(47,47)--> roof (35,54)
--      --P11a(34,50)--> the STAIR ROOM --P12b(46,9)--> U1 crane roof
--      --J39 jumps west--> P17a(15,39) --> WEST ROOM --> P18b(104,27)
--      --> W33 strip --J33 jumps east--> U2 --P14a(31,30)--> BRIDGE ROOM
--      --P15b(30,34)--> TOP roof (30,22) --z-loop corridor--> (30,13).
--  * THE STAIR ROOM is a bandit conveyor: init event _caefb8 keeps seven
--    walkers climbing its one-wide stair column (x=53, y=18..29) and the
--    top "\" beam forever, so a snapshot BFS almost never sees a clear
--    path (probe_climb8 starved on 20 straight no-paths).  The engine
--    itself queues a held direction behind a moving body, so that leg is
--    driven as follow-the-queue: press the route direction for the
--    current tile and wait out whoever is standing in it.
--  * THE JUMPS ($01B0-$01B5 = the live $1EB6 control bits, event_trigger
--    _221 + _ca95c6..): {28,y}/{25,y} high pair, {21,y}/{19,y} low pair,
--    rows y=39 and y=33, each side firing only with the facing bit
--    toward the gap set -- so a jump is "walk onto the tile holding the
--    gap direction".  Measured live (probe_climb13/16): westbound fires
--    at $1EB6=C8 (bit3 = facing left), eastbound at $82 (bit1 = right);
--    the obj_script arcs dip a row (25,40 / 28,34) and settle facing up
--    ($1EB6 bit0), which is why the twin trigger never re-fires on
--    landing.  A held direction CHAINS the whole row -- both jumps of a
--    row fire under one hold, and the row is pure transit.
--  * THE TALK: Dadaluma's tile (30,14) seals the roof from the tower
--    porch, (29,14)/(30,15) are $F7 -- and $F7 is the one prop byte
--    CheckNPCs' talk-across-a-counter extension explicitly rejects
--    (player.asm @478e), so there is no south-side talk.  The authored
--    approach is a Z-LEVEL LOOP (probe_climb15): west along y=16 on the
--    lower level, drop to (30,17), climb the "/" beam at (31,17) (zAfter
--    flips the party to upper), then the SAME tiles again as upright
--    diagonals -- (32,16)/(33,15)/(34,14) carry $44/$49 bridge-diag props
--    that only engage at z=1 -- onto the y=13 strip and west to (30,13),
--    facing DOWN at him.  That loop is the LAST rung of THREE: the whole
--    corridor from the (30,22) landing is a switchback ladder of the same
--    motif (full measured tile dump at corridorDir below), and it is
--    driven SCRIPTED, not pathfound -- the bridge-diag tiles move
--    differently per z, so followPath's all-z-seeded BFS mispredicts the
--    live engine there and oscillates at y=19 forever (measured twice,
--    9000-frame timeouts, x wandering 30..35).  Dadaluma's (30,14) stays
--    object-occupied until the win; the scripted route never aims at it.
--  * THE FIGHT: battle 69 = formation 438 = DADALUMA $0107 + two $006C
--    sidekicks (measured words 0107 006C 006C FFFF FFFF FFFF).  The
--    post-battle event _ca5ea9 gates on battle-switch $40 exactly like
--    Kefka/Vargas: a real win despawns him (hide_obj NPC_14, $034A=0,
--    fade_in, control back on (30,13) -- the porch opens); a loss is
--    `call GameOver`.  Since issue #75 the fight is PLAYED -- see the
--    fighter + retry ladder at the fight site; this file writes no
--    emulated game state anywhere, and every mid-route encounter on the
--    climb is fought by the same edge-tapped A that pages dialogs.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted()
end

-- ----------------------------------------------------- the honest fighter --
-- gen_narshe_battle's menu-episode machine (gen_scenario's cadence) for the
-- DADALUMA fight.  Party here is LOCKE+CELES+SABIN+EDGAR (#21's canonical
-- four); his authored row (Ot6ShieldTbl: 6 shields, PIERCE|BLUDG; ElemAdd:
-- poison-weak; 3270 HP) is exactly what they carry -- LOCKE's dagger and
-- EDGAR's spear are pierce, SABIN's fists are bludgeon, and EDGAR's Tools
-- add poison/pierce volume.  Boost banked to 2 and dumped every turn:
--     EDGAR (4), tier 2+   down A A A   Tools -> AutoCrossbow
--     SABIN (5), tier 3+   down A A A   Blitz -> Pummel (menu-picked,
--                                       battle_vargas's tools-shell list)
--     everyone else        A A          Fight, default target
local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca
local BP = 0x3e9c
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("$%04X hp=%d sh=%d", monSpecies(i),
        monHp(i), monShields(i))
    end
  end
  return table.concat(m, " | ")
end
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 4 and tier >= 2 then
    return push("down", "a", "a", "a")                        -- AutoCrossbow
  end
  if id == 5 and tier >= 3 then
    return push("down", "a", "a", "a")                        -- Pummel
  end
  return push("a", "a")                                       -- Fight
end
local function mkFighter(tier, tag)
  local F = { lost = nil }
  local bt = nil
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  function F.frame(battN)
    phase = (phase + 1) % 8
    if battN == 3 then
      bt = { f0 = H.frame, wiped = 0 }
      local w = H.formationWords()
      H.log(string.format("[%s] battle up f%d (%04X %04X %04X %04X %04X %04X)",
        tag, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    if bt then
      bt.lastParty = partyLine()
      if battN % 300 == 0 then
        H.log(string.format("[%s] f%d party [%s] vs %s",
          tag, H.frame, partyLine(), monsterLine()))
      end
      local wiped, any = true, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) > 0 then wiped = false end
        end
      end
      bt.wiped = (any and wiped) and bt.wiped + 1 or 0
      if bt.wiped >= 90 and not F.lost then
        F.lost = string.format("PARTY WIPED at f%d (started f%d, %d frames " ..
          "in, tier %d) -- party [%s] vs %s", H.frame, bt.f0,
          H.frame - bt.f0, tier, partyLine(), monsterLine())
        H.log("[" .. tag .. "] " .. F.lost)
      end
    end
    if bt == nil or H.readByte(MENU) == 0 then
      mStreak, mSeq = 0, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mStreak = mStreak + 1
    if mStreak < 4 then H.setPad({}); return end
    if mSeq == nil then
      local slot = H.readByte(ACTOR) & 3
      local id = H.readByte(BCHID + slot * 2)
      mSeq, mIdx, mTick, mStall = seqFor(id, tier, slot), 1, 0, 0
      H.log(string.format("[%s] cast f%d slot=%d char=%d bp=%d seq=%s",
        tag, H.frame, slot, id, H.readByte(BP + slot * 2),
        table.concat(mSeq, ",")))
    end
    mTick = mTick + 1
    local ph = mTick % 30
    local btn
    if mIdx <= #mSeq then
      btn = mSeq[mIdx]
    elseif mStall < 2 then
      btn = "a"
    elseif mStall < 4 then
      btn = "b"
    else
      mSeq = nil
      H.setPad({})
      return
    end
    if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
    if ph == 29 then
      if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
    end
  end
  function F.idle()
    if bt then
      H.log(string.format("[%s] battle done at f%d (%d frames) -- party [%s]",
        tag, H.frame, H.frame - bt.f0, bt.lastParty or "?"))
      bt = nil
    end
    mStreak, mSeq = 0, nil
  end
  return F
end

-- ---- door-walled step model (the lib's own rules + door tiles as walls;
-- transcribed from lib/ot6.lua stepAllowed/zAfter, minus the object-map
-- test: bodies here are conveyor walkers, waited out rather than pathed
-- around) --------------------------------------------------------------
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }
local function prop1(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function prop2(x, y) return H.readByte(0x7E7700 + H.maptile(x, y)) end
local function diagStep(x, y, c, press, z)
  if press ~= "left" and press ~= "right" then return nil end
  if (c & 0xC0) == 0 then return nil end
  if (c & 0x04) ~= 0 and z == 0x02 then return nil end
  local bit = (c & 0x80) ~= 0 and 0x80 or 0x40
  local mv
  if bit == 0x80 then mv = press == "right" and "downright" or "upleft"
  else                mv = press == "right" and "upright"   or "downleft" end
  local d = DELTA[mv]
  local t = prop1(x + d[1], y + d[2])
  if t == 0xF7 or (t & bit) == 0 then return nil end
  return mv
end
local function stepAllowed(x, y, move, z)
  local c = prop1(x, y)
  local press = PRESS[move]
  local diag = diagStep(x, y, c, press, z)
  if move ~= press then return move == diag end
  if diag then return false end
  local d = DELTA[move]
  local nx, ny = x + d[1], y + d[2]
  local e = prop2(x, y)
  local t = prop1(nx, ny)
  if (e & 0x0F & DIRBIT[move]) == 0 then return false end
  if (t & 0x07) == 0x07 then return false end
  if (c & 0x04) ~= 0 then
    if (z & 0x01) ~= 0 then
      if (t & 0x02) ~= 0 then return false end
    else
      if (t & 0x01) ~= 0 then return false end
    end
  elseif (t & 0x03) == 0x03 then
  elseif (c & 0x03) == 0x03 then
    if (t & 0x04) ~= 0 then return false end
  elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
    return false
  end
  return true
end
local function zAfter(x, y, z)
  local c = prop1(x, y)
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end
local function key(x, y) return y * 256 + x end
local ZS = { 0, 1, 2, 3 }
-- every short-entrance source on each map (short_entrance.dat _221/_225)
local DOORS221 = { {13,21},{23,17},{42,28},{43,24},{44,48},{44,41},{49,38},
  {54,35},{38,57},{35,53},{34,50},{30,42},{35,33},{31,30},{30,21},{35,15},
  {15,39},{12,36},{49,31},{33,9} }
local DOORS225 = { {12,44},{11,17},{21,15},{52,57},{47,47},{59,35},{46,9},
  {118,27},{104,27},{83,62},{124,56},{98,62},{110,55},{66,57},{11,62},
  {30,62},{30,34},{35,14} }
local function doorSet(list)
  local s = {}
  for _, d in ipairs(list) do s[key(d[1], d[2])] = true end
  return s
end
local W221, W225 = doorSet(DOORS221), doorSet(DOORS225)

local function firstStep(sx, sy, tx, ty, walls)
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local function nkey(x, y, z) return (z << 16) | (y << 8) | x end
  local seen, q, qi = {}, {}, 1
  for _, z in ipairs(ZS) do
    seen[nkey(sx, sy, z)] = true
    q[#q + 1] = { sx, sy, z, nil }
  end
  while qi <= #q do
    local x, y, z, f = q[qi][1], q[qi][2], q[qi][3], q[qi][4]
    qi = qi + 1
    if x == tx and y == ty then return f end
    local zn = zAfter(x, y, z)
    for _, mv in ipairs(MOVES) do
      local d = DELTA[mv]
      local nx, ny = x + d[1], y + d[2]
      if nx >= 0 and ny >= 0 and nx <= xm and ny <= ym
         and (not walls[key(nx, ny)] or (nx == tx and ny == ty)) then
        local k = nkey(nx, ny, zn)
        if not seen[k] and stepAllowed(x, y, mv, z) then
          seen[k] = true
          q[#q + 1] = { nx, ny, zn, f or mv }
        end
      end
    end
  end
  return nil
end

-- walk to (tx,ty) recomputing the door-walled first step each aligned
-- frame; a body on the next tile just holds the press until it moves.
-- opts.arriveMap terminates on the map flip (door targets); extraWalls
-- adds tiles (Dadaluma's body) to the wall set.
local function followPath(tx, ty, opts)
  opts = opts or {}
  local extra = {}
  for _, w in ipairs(opts.extraWalls or {}) do extra[key(w[1], w[2])] = true end
  local hb = 0
  return H.driveUntil(function()
    if opts.arriveMap then
      if map() == opts.arriveMap then H.setPad({}); return true end
      return false
    end
    if H.fieldX() == tx and H.fieldY() == ty and H.tileAligned() then
      H.setPad({})
      return true
    end
    return false
  end, opts.maxFrames or 20000, {
    H.call(function()
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("[path] ->(%d,%d) f+%d at (%d,%d)", tx, ty, hb,
          H.fieldX(), H.fieldY()))
      end
      if H.battleLoadStarted() then
        -- an encounter mid-route is FOUGHT (issue #75): the edge-tapped A
        -- opens the command list, confirms Fight, takes the default target
        -- and pages the victory text
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then return end
      local walls = map() == 221 and W221 or W225
      if next(extra) then
        local merged = {}
        for k in pairs(walls) do merged[k] = true end
        for k in pairs(extra) do merged[k] = true end
        walls = merged
      end
      local mv = firstStep(H.fieldX(), H.fieldY(), tx, ty, walls)
      if not mv then H.setPad({}); return end
      H.setPad({ [PRESS[mv]] = true })
    end),
  }, string.format("followPath (%d,%d)", tx, ty))
end

local function door(sx, sy, destMap, what)
  return H.cond(function() return true end, {
    followPath(sx, sy, { arriveMap = destMap, maxFrames = 30000 }),
    H.waitUntil(settled, 2400, what .. " settled", 5),
    -- door loads finalize the decompressed prop table LATE (gen_zozo2's
    -- measured rule); settle before any pathfinding reads it
    H.waitFrames(150),
    H.logStep(function() return string.format("%s: landed map %d (%d,%d)",
      what, map(), H.fieldX(), H.fieldY()) end),
  })
end

-- THE WEST-ROOM CROSSING (map 225): the party lands at (118,26) from door
-- 221(15,39) and must reach the exit door (104,27)->221 (the W33 strip).  This
-- leg is why `followPath` timed out (measured twice + probe_westroom.lua):
--  * The two chambers of the west room connect ONLY through a "\" diagonal
--    beam (111,15)->(110,14)->(109,13)->(108,12); a cardinal-only door-walled
--    BFS finds NO path, and (104,27)'s only non-door neighbour is (104,26),
--    reachable solely from the beam top.  followPath's all-z BFS *does* route
--    over the beam, but drives it WRONG:
--  * Stepping onto (111,15) fires a ONE-SHOT SCENE (screen fade, the party's
--    z flips 2->3).  It MUST be ridden with A -- holding/pulsing a DIRECTION
--    into it hangs control forever (measured: 6000+ frames frozen, ev stuck
--    true).  With A it completes in ~900 frames and returns control at z=3.
--  * At z=3 the beam is traversable up-left across the gap; dropping onto the
--    left chamber's flat `02` floor restores z=2 for the descent to the door.
-- So it is a hand-coded per-tile table (gen_opera5/corridorFollow precedent),
-- canStep-gated on the LIVE z, that A-mashes any scene/dialog and walks the
-- table otherwise.  Verified end-to-end by probe_westroom.lua (lands map 221).
local WESTROOM = {}
local function wr(x, y, dir) WESTROOM[key(x, y)] = dir end
for yy = 16, 26 do wr(118, yy, "up") end               -- climb the x=118 column
for xx = 113, 117 do wr(xx, 15, "left") end            -- west along y=15
wr(118, 15, "left"); wr(112, 15, "left")
wr(111, 15, "upleft"); wr(110, 14, "upleft")           -- the beam (z=3 post-scene)
wr(109, 13, "upleft"); wr(108, 12, "left")
wr(107, 12, "down"); wr(107, 13, "down"); wr(107, 14, "down"); wr(107, 15, "left")
wr(106, 15, "down"); wr(106, 16, "left"); wr(105, 16, "left"); wr(104, 16, "down")
for yy = 17, 26 do wr(104, yy, "down") end             -- (104,26) -> door (104,27)
local function westRoomCross()
  local hb = 0
  return H.cond(function() return true end, {
    H.driveUntil(function() return map() == 221 end, 30000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format("[westroom] f+%d at (%d,%d) z%d", hb,
            H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3))
        end
        if H.battleLoadStarted() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return   -- fought, not kill-bit
        end
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        -- the (111,15) scene: RIDE it with A -- a direction press here hangs
        if not H.hasControl() or H.eventRunning() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local dir = WESTROOM[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, "west room -> (104,27) exit"),
    H.waitUntil(settled, 2400, "W33 strip settled", 5),
    H.waitFrames(150),
    H.logStep(function() return string.format(
      "westRoomCross: landed map %d (%d,%d)", map(), H.fieldX(), H.fieldY()) end),
  })
end

-- THE BRIDGE-ROOM APPROACH (map 221): after the J33 jump the party is at
-- ~(28,33) and must reach the door (31,30)->225.  followPath timed out here
-- too: the route climbs a "/" z-loop beam (tiles $41/$44/$49 at
-- (31,35)->(34,32), the same motif corridorFollow drives for (30,22)->(30,13)),
-- and followPath's all-z BFS mispredicts the live z across the beam.  A single
-- door-walled BFS is z-consistent (probe_bridge.lua, identical route at every
-- seed z), so this is a canStep-gated per-tile table like corridorFollow.
local BRIDGE = {}
local function br(x, y, dir) BRIDGE[key(x, y)] = dir end
br(28, 33, "right"); br(29, 33, "right"); br(30, 33, "down"); br(30, 34, "down")
br(30, 35, "right")                                    -- into the "/" beam base
br(31, 35, "upright"); br(32, 34, "upright"); br(33, 33, "upright"); br(34, 32, "up")
br(34, 31, "left"); br(33, 31, "left"); br(32, 31, "left"); br(31, 31, "up")  -- -> (31,30) door
local function bridgeCross()
  local hb = 0
  return H.cond(function() return true end, {
    H.driveUntil(function() return map() == 225 end, 24000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format("[bridge] f+%d at (%d,%d) z%d", hb,
            H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3))
        end
        if H.battleLoadStarted() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return   -- fought, not kill-bit
        end
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local dir = BRIDGE[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, "bridge room approach -> (31,30) exit"),
    H.waitUntil(settled, 2400, "bridge room settled", 5),
    H.waitFrames(150),
    H.logStep(function() return string.format(
      "bridgeCross: landed map %d (%d,%d)", map(), H.fieldX(), H.fieldY()) end),
  })
end

-- THE BRIDGE-ROOM CLIMB (map 225): from (30,61) up to the door (30,34)->221
-- (top roof).  The direct x=30 column is z-split; the real route is a 50-step
-- SWITCHBACK LADDER over "/" ($43/$4B) and "\" ($83/$8B) z-loop beams
-- (probe_westroom.lua solve; a single-live-z door-walled BFS gives the same
-- route, verified probe_climb_suppress.lua).  The table below IS correct and
-- reaches (30,34) at z=2 every rung.
--
-- THE REAL BLOCKER WAS A HANGING RANDOM ENCOUNTER, NOT A WARP (sixth pass,
-- probe_climb_dump/live/stall/suppress).  The v0.5 fifth-pass diagnosis --
-- "(30,41) is a corrupting warp that chains 225->5->18->19, the Narshe intro"
-- -- was WRONG.  Measured facts that overturn it:
--   * (30,41) has p1=$43, byte-identical to (30,57) which the party crosses
--     fine one rung below; it is NEITHER a short/long entrance (all 22 map-225
--     records decode to map 221, none at (30,41)) NOR an event trigger (map
--     225 has exactly 3: the clock {98,59} and {125,46}/{103,55}).
--   * Stepping (29,41)->(30,41) rolls a RANDOM ENCOUNTER: the event PC jumps
--     to $CA0029 = inside RandBattle ($CA0018).  On this ambiguous-z beam the
--     party sprite's z oscillates 0/2/3 and the pre-battle scroll_obj never
--     settles, so the encounter HANGS at $CA0029 forever -- battleLoadStarted
--     never latches (so the kill-bit can't fire it) and both A-mash and a
--     neutral pad leave it stuck.  Riding that hang under A is what the fifth
--     pass mis-rode into the intro maps.
-- THE HONEST CROSSING (issue #75 -- the old fix wrote $1f6e/$1f6f to 0
-- every frame, suppressing the roll; a mint script may never write game
-- state, so that is gone).  What replaced it is what a cautious PLAYER
-- can actually do, informed by the same mechanism (battle.asm:350-388):
-- every step adds the map's rate to the 16-bit accumulator $1f6e, a
-- battle-RNG byte is compared against its HIGH byte $1f6f, and a win
-- ZEROES the counter -- so the roll probability right after any fight is
-- as low as it ever gets.  So each climb attempt:
--   1. BURNS the pending encounter at the BASE, on flat ground: pace
--      (30,61)<->(30,60) until the roll fires on a safe tile, then FIGHT
--      it honestly (tap-A).  The counter is now zero.
--   2. climbs the BRIDGE2 ladder immediately, watching for the hang
--      signature (control lost, no battle latch, position frozen, the
--      event PC inside RandBattle) -- a roll that lands on one of the
--      ambiguous-z beams anyway.
--   3. a hang or an in-climb loss RELOADS the pre-climb checkpoint (the
--      mint-script spelling of a player reloading a save) and goes
--      again; the burn pacing itself reshuffles every subsequent roll.
-- Five attempts; if all five hang, the mint FAILS with the full
-- characterization on the record -- that outcome is the product bug the
-- header describes (a human player crossing this shaft can hit the same
-- un-settleable encounter and softlock), and it must be fixed game-side,
-- not scripted around.  A held direction into a beam base still must not
-- outlive its step, so the walker pulses the pad like corridorFollow.
local BRIDGE2 = {}
do
  local seq = {
    { 30, 61, "up" }, { 30, 60, "up" }, { 30, 59, "left" }, { 29, 59, "up" },
    { 29, 58, "up" }, { 29, 57, "right" }, { 30, 57, "upright" }, { 31, 56, "upright" },
    { 32, 55, "upright" }, { 33, 54, "upright" }, { 34, 53, "upright" }, { 35, 52, "upright" },
    { 36, 51, "right" }, { 37, 51, "up" }, { 37, 50, "up" }, { 37, 49, "left" },
    { 36, 49, "upleft" }, { 35, 48, "upleft" }, { 34, 47, "upleft" }, { 33, 46, "upleft" },
    { 32, 45, "upleft" }, { 31, 44, "upleft" }, { 30, 43, "left" }, { 29, 43, "up" },
    { 29, 42, "up" }, { 29, 41, "right" }, { 30, 41, "upright" }, { 31, 40, "upright" },
    { 32, 39, "upright" }, { 33, 38, "upright" }, { 34, 37, "upright" }, { 35, 36, "upright" },
    { 36, 35, "upright" }, { 37, 34, "upright" }, { 38, 33, "upright" }, { 39, 32, "right" },
    { 40, 32, "up" }, { 40, 31, "left" }, { 39, 31, "left" }, { 38, 31, "left" },
    { 37, 31, "left" }, { 36, 31, "left" }, { 35, 31, "left" }, { 34, 31, "left" },
    { 33, 31, "down" }, { 33, 32, "down" }, { 33, 33, "left" }, { 32, 33, "left" },
    { 31, 33, "left" }, { 30, 33, "down" },   -- (30,33) -> door (30,34)
  }
  for _, s in ipairs(seq) do BRIDGE2[key(s[1], s[2])] = s[3] end
end
local climbBlob, climbDone = nil, false
local climbFail = nil
local function hangLine(tag)
  return string.format("%s at f%d: map=%d tile=(%d,%d) z=%d danger=$%04X " ..
    "ctl=%s batt=%s dlg=%s ev=%s evPC=%02X:%02X%02X", tag, H.frame, map(),
    H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3, H.readWord(0x1f6e),
    tostring(H.hasControl()), tostring(H.battleLoadStarted()),
    tostring(H.dialogWaiting()), tostring(H.eventRunning()),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5))
end
-- one pace-burn: walk (30,61)<->(30,60) until a battle fires ON FLAT
-- GROUND, fight it honestly, and settle.  Bounded; a base that never
-- rolls within the budget just proceeds with whatever the counter holds.
local function burnStep()
  local hb, fought, battN = 0, false, 0
  return H.driveUntil(function()
    return (fought and settled()) or (not fought and hb > 6000 and settled())
  end, 12000, {
    H.call(function()
      hb = hb + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        fought = true
        H.setPad(hb % 8 < 4 and { "a" } or {})   -- fight it, honestly
        return
      end
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      if fought then H.setPad({}); return end
      H.setPad({ [H.fieldY() >= 61 and "up" or "down"] = true })
    end),
  }, "burn the pending encounter on flat ground")
end
local function climbBody(n)
  local hb, stuckN, lx, ly = 0, 0, -1, -1
  local battN = 0
  return H.driveUntil(function()
    return map() == 221 or climbFail ~= nil
  end, 40000, {
    H.call(function()
      hb = hb + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if hb % 600 == 0 then
        H.log(string.format("[bridge2] f+%d at (%d,%d) z%d ctl=%s danger=$%04X",
          hb, H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3,
          tostring(H.hasControl()), H.readWord(0x1f6e)))
      end
      if hb > 30000 then
        climbFail = hangLine("[bridge2] attempt " .. n .. " TIMED OUT")
        H.log(climbFail)
        return
      end
      -- the hang signature: no control, no battle latch, no dialog, the
      -- party frozen in place for 900 straight frames.  A real battle
      -- entry latches battleLoadStarted within dozens of frames and a
      -- post-battle fade returns control within ~150; nothing legitimate
      -- on this ladder goes quiet for 900.
      local x, y = H.fieldX(), H.fieldY()
      local frozen = (x == lx and y == ly and not H.hasControl()
        and not H.battleLoadStarted() and not H.dialogWaiting())
      lx, ly = x, y
      stuckN = frozen and stuckN + 1 or 0
      if stuckN >= 900 then
        climbFail = hangLine("[bridge2] attempt " .. n ..
          " HUNG (the un-settleable beam encounter)")
        H.log(climbFail)
        H.screenshot("bridge2_hang" .. n)
        return
      end
      if battN >= 3 then
        if battN == 3 then
          local w = H.formationWords()
          H.log(string.format("[bridge2] in-climb battle at (%d,%d) f%d " ..
            "(%04X %04X %04X %04X %04X %04X) -- fighting", x, y, H.frame,
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() or H.eventRunning() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      local dir = BRIDGE2[key(x, y)]
      if dir and H.canStep(x, y, dir) then
        H.setPad({ [PRESS[dir]] = true })
      else
        H.setPad({})
      end
    end),
  }, "bridge room climb -> (30,34) exit, attempt " .. n)
end
-- Reloading a savestate and replaying identical input replays the
-- identical outcome -- the emulator is deterministic -- so each ladder
-- attempt VARIES ITS INPUT: (n-1)*2 extra pace steps between the burn and
-- the climb.  The battle RNG advances once per step (UpdateBattleRng,
-- battle.asm:385), so the extra steps reshuffle every subsequent roll
-- along the ladder at the cost of a whisper of danger.
local function jitterStep(k)
  local moves, lx, ly = 0, nil, nil
  return H.cond(function() return k > 0 end, {
    H.driveUntil(function() return moves >= k end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then
          H.setPad(H.frame % 8 < 4 and { "a" } or {})   -- fought if rolled
          return
        end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if lx ~= nil and (x ~= lx or y ~= ly) then moves = moves + 1 end
        lx, ly = x, y
        H.setPad({ [y >= 61 and "up" or "down"] = true })
      end),
    }, "jitter " .. k .. " steps"),
    H.call(function() H.setPad({}) end),
  }, {})
end
local function climbAttempt(n)
  local ldReq
  return H.cond(function() return not climbDone end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[bridge2] ATTEMPT %d -- reloading the " ..
          "pre-climb checkpoint (%s)", n, tostring(climbFail))
      end),
      H.call(function() ldReq = H.requestLoadState(climbBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "climb attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() climbFail = nil end),
    burnStep(),
    jitterStep((n - 1) * 2),
    H.logStep(function()
      return string.format("[bridge2] burned; danger=$%04X -- climbing " ..
        "(attempt %d)", H.readWord(0x1f6e), n)
    end),
    climbBody(n),
    H.cond(function() return climbFail == nil end, {
      H.waitUntil(settled, 2400, "top roof settled", 5),
      H.waitFrames(150),
      H.call(function()
        climbDone = true
        H.log(string.format("[bridge2] attempt %d landed map %d (%d,%d)",
          n, map(), H.fieldX(), H.fieldY()))
      end),
    }, {}),
  }, {})
end
local function bridgeClimb()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "pre-climb checkpoint")
      climbBlob = ckReq.blob
      H.log(string.format("[bridge2] pre-climb checkpoint captured " ..
        "(%d bytes) at (%d,%d) danger=$%04X", #climbBlob, H.fieldX(),
        H.fieldY(), H.readWord(0x1f6e)))
    end),
    climbAttempt(1),
    climbAttempt(2),
    climbAttempt(3),
    climbAttempt(4),
    climbAttempt(5),
    H.call(function()
      if not climbDone then
        error("[bridge2] the shaft could not be crossed honestly in 5 " ..
          "attempts -- last: " .. tostring(climbFail) .. " -- this is the " ..
          "PRODUCT BUG the header describes (a random encounter rolled on " ..
          "the ambiguous-z beams of map 225's shaft never settles and " ..
          "never latches battleLoadStarted; a human player softlocks the " ..
          "same way).  Fix it game-side; do not suppress it here.", 0)
      end
    end),
  })
end

-- the stair-room conveyor: route direction as a pure function of tile
local function stairDir(x, y)
  if x == 54 and y >= 12 and y <= 14 then
    return y == 12 and { "left" } or { "up" }
  end
  if y <= 12 and x >= 46 and x <= 53 then return { "left", "upleft" } end
  if x == 53 then
    if y == 14 then return { "right" } end
    return { "up" }
  end
  if y >= 30 then
    if x < 53 then return { "right" } end
    if x > 53 then return { "left" } end
    return { "up" }
  end
  if x < 53 and y >= 13 and y <= 17 then return { "right" } end
  if x > 54 then return { "left" } end
  return { "up" }
end
local function stairFollow()
  local hb = 0
  return H.driveUntil(function() return map() == 221 end, 24000, {
    H.call(function()
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("[stair] f+%d at (%d,%d)", hb, H.fieldX(), H.fieldY()))
      end
      if H.battleLoadStarted() then
        -- an encounter mid-route is FOUGHT (issue #75): the edge-tapped A
        -- opens the command list, confirms Fight, takes the default target
        -- and pages the victory text
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then return end
      local x, y = H.fieldX(), H.fieldY()
      for _, mv in ipairs(stairDir(x, y)) do
        if H.canStep(x, y, mv) then
          H.setPad({ [H.movePress(mv)] = true })
          return
        end
      end
      H.setPad({})
    end),
  }, "stair conveyor -> P12b")
end

-- the TOP-roof z-loop corridor, (30,22) -> (30,13): route direction(s) as
-- a pure function of tile, canStep-gated -- stairDir's pattern, for a
-- cousin of stairDir's reason.  followPath's firstStep seeds its BFS at
-- ALL FOUR z-levels (the party carries exactly one), and this corridor is
-- the one leg where that lies: its bridge-diag tiles move DIFFERENTLY per
-- z (diagonal at z=1, plain floor at z=2 -- player.asm's own c&$04 + z==2
-- suppression, transcribed in diagStep above), so the phantom-z first
-- step keeps disagreeing with the live engine and the leg oscillates on
-- the y=19 strip forever (measured twice: 9000-frame timeouts, x
-- wandering 30..35; it once passed on an older ROM by RNG luck).
--
-- The corridor itself, measured (p1/p2 dump of x24..40 y8..24 from
-- zozo_arrival -- the street is the same map 221, so the decompressed
-- prop tables are live there), is a THREE-RUNG SWITCHBACK of the header's
-- z-loop motif.  Every rung is the same four bytes: a $0B drop tile, a
-- $41 "/" beam base (zAfter flips the party to upper stepping off it), a
-- $44/$44/$49 upright chain, and a $03 both-z strip top:
--   A: (30,22)R (31,22)D (31,23)R $41(32,23) /$44(33,22)(34,21)
--      $49(35,20) U-> y=19 strip, west (35,19)..(31,19)
--   B: (31,19)D (31,20)R $41(32,20) /$44(33,19)(34,18)
--      $49(35,17) U-> y=16 strip, west (35,16)..(30,16)
--   C: (30,16)D (30,17)R $41(31,17) /$44(32,16)(33,15)
--      $49(34,14) U-> (34,13), west along y=13 to (30,13)
--      -- rung C is exactly the header's documented loop.
-- The loop tiles (33,19)/(32,16) are stood on TWICE -- flat westbound on
-- the lower level, diagonally on the climb -- so their entry lists the
-- climb first and canStep (live z) picks: upright is dead at z=2 by the
-- bridge suppression and alive at z=1, when it is also the right move.
-- THE DRIVE PULSES THE PAD: press only while tile-aligned, clear it the
-- frame the step commits.  A direction still held at the arrival instant
-- CHAINS -- the engine latches the next step before this callback can
-- swap the pad (measured here: the leg's first held right chained
-- (30,22)->(31,22)->(32,22) and parked off-route for the whole 9000-frame
-- budget).  stairFollow can hold its presses because every stairDir
-- corner is map-fenced and the column is body-throttled besides; this
-- corridor's turns are open floor ((32,22) is plain $0A), so no press may
-- outlive its own step.  Pulsing is also what keeps the one walkable
-- overshoot on the route, door (35,15) north of the y=16 strip, from
-- ever firing.  The $49 beam tops carry no east exit (p2=$0E), so the
-- diagonal chains are fenced by the map itself either way.  A tile off
-- this table (or a body on the next tile) parks the pad and waits,
-- stairFollow-style; the 300-frame heartbeat names the stuck tile.
local CORRIDOR = {}
local function corr(x, y, dirs) CORRIDOR[key(x, y)] = dirs end
corr(30, 22, { "right" })            -- rung A: hook east-south to the base
corr(31, 22, { "down" })
corr(32, 22, { "left" })             -- recovery: the measured pre-pulse
                                     -- chaining overshoot parked here
corr(31, 23, { "right" })
corr(32, 23, { "upright" })          -- $41 base: diag fires at any z
corr(33, 22, { "upright" })          -- $44
corr(34, 21, { "upright" })          -- $44
corr(35, 20, { "up" })               -- $49 top; no east exit
corr(35, 19, { "left" })             -- y=19 strip westbound (z drops to 2)
corr(34, 19, { "left" })
corr(33, 19, { "upright", "left" })  -- LOOP tile: climb at z=1, cross at z=2
corr(32, 19, { "left" })
corr(31, 19, { "down" })             -- rung B: hook south to the base
corr(31, 20, { "right" })
corr(32, 20, { "upright" })          -- $41 base
corr(34, 18, { "upright" })          -- $44 ((33,19) is the loop tile above)
corr(35, 17, { "up" })               -- $49 top
corr(35, 16, { "left" })             -- y=16 strip westbound
corr(34, 16, { "left" })
corr(33, 16, { "left" })
corr(32, 16, { "upright", "left" })  -- LOOP tile: rung C's chain
corr(31, 16, { "left" })
corr(30, 16, { "down" })             -- rung C: the header's documented loop
corr(30, 17, { "right" })
corr(31, 17, { "upright" })          -- $41 base -- "the / beam at (31,17)"
corr(33, 15, { "upright" })          -- $44 ((32,16) is the loop tile above)
corr(34, 14, { "up" })               -- $49 top -> the y=13 strip
corr(34, 13, { "left" })             -- west to the doorstep
corr(33, 13, { "left" })
corr(32, 13, { "left" })             -- $44 crossed flat (z=2 here, always)
corr(31, 13, { "left" })
-- Arrival must be QUIET, not merely positioned: the map rolls random
-- encounters (gen_zozo5 measured the same on the tower porch), and the
-- first clean walk of this route rolled trash on its FINAL steps -- a
-- position-only arrive fired while the battle load was already in flight
-- ($4c mid-fade, the object map's NPC byte cleared, battleLoadStarted
-- latched), and the minted doorstep booted INTO that battle, starving the
-- talk that follows (hasControl never true; measured via probe replay of
-- the contaminated state).  So the pred demands twenty straight settled()
-- frames at (30,13) -- jumpRow's calm-counter, aimed at a tile -- and a
-- last-step roll is FOUGHT by the same battle interrupt every other leg
-- carries, BEFORE the mint instead of inside it.
local function corridorFollow()
  local hb, calm = 0, 0
  return H.driveUntil(function()
    local there = H.fieldX() == 30 and H.fieldY() == 13 and settled()
    calm = there and calm + 1 or 0
    if calm >= 20 then
      H.setPad({})
      return true
    end
    return false
  end, 18000, {
    H.call(function()
      hb = hb + 1
      if hb % 300 == 0 then
        H.log(string.format("[corridor] f+%d at (%d,%d)", hb,
          H.fieldX(), H.fieldY()))
      end
      if H.battleLoadStarted() then
        -- an encounter mid-route is FOUGHT (issue #75): the edge-tapped A
        -- opens the command list, confirms Fight, takes the default target
        -- and pages the victory text
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      -- the pulse: a press must not outlive its own step (see above)
      if not H.tileAligned() then H.setPad({}); return end
      local x, y = H.fieldX(), H.fieldY()
      for _, mv in ipairs(CORRIDOR[key(x, y)] or {}) do
        if H.canStep(x, y, mv) then
          H.setPad({ [H.movePress(mv)] = true })
          return
        end
      end
      H.setPad({})
    end),
  }, "z-loop corridor -> (30,13)")
end

-- hold `dir` across a whole jump row; both of the row's facing-gated
-- triggers fire under the one hold, and the landing leaves the party
-- facing up so nothing re-fires.  pred names the far strip.
local function jumpRow(dir, pred, maxFrames, what)
  local evWas, calm, hb, lastFire = false, 0, 0, nil
  return H.cond(function() return true end, {
    H.driveUntil(function()
      local there = pred() and H.tileAligned()
      calm = there and calm + 1 or 0
      return calm >= 20
    end, maxFrames, {
      H.call(function()
        hb = hb + 1
        local ev = H.eventRunning()
        if ev and not evWas and hb - (lastFire or -100) >= 30 then
          lastFire = hb
          H.log(string.format("[jump] %s: fired at (%d,%d) $1EB6=%02X",
            what, H.fieldX(), H.fieldY(), H.readByte(0x1EB6)))
        end
        evWas = ev
        if H.battleLoadStarted() then
          H.setPad(hb % 8 < 4 and { "a" } or {})   -- fought, not kill-bit
          return
        end
        if ev or not H.hasControl() then
          H.setPad({})
          return
        end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.call(function() H.setPad({}) end),
  })
end

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
    H.assertEq(sw(0x034A), 1, "$034A SET -- the gentleman waits")
    H.assertEq(sw(0x0053), 0, "$0053 clear -- the Ramuh scene has not run")
  end),

  -- the climb
  door(38, 57, 225, "P9a street -> interior"),
  door(47, 47, 221, "P10b -> roof (35,54)"),
  door(34, 50, 225, "P11a -> stair room"),
  followPath(52, 30, { maxFrames = 18000 }),
  stairFollow(),
  H.waitUntil(settled, 2400, "U1 settled", 5),
  H.waitFrames(150),
  followPath(29, 39, { maxFrames = 18000 }),
  jumpRow("left", function()
    return H.fieldX() <= 18 and H.fieldY() == 39
  end, 9000, "J39 row westbound"),
  door(15, 39, 225, "P17a -> west room"),
  -- P18b: cross the west room to (104,27)->221.  followPath mispredicts +
  -- HANGS on the (111,15) scene-beam here; westRoomCross rides it (see above).
  westRoomCross(),
  followPath(18, 33, { maxFrames = 12000 }),
  jumpRow("right", function()
    return H.fieldX() >= 28 and H.fieldY() == 33
  end, 9000, "J33 row eastbound"),
  -- P14a: the "/" z-loop beam approach to (31,30) -- followPath mispredicts
  -- the live z here too; bridgeCross drives the measured table (see above).
  bridgeCross(),
  -- P15b: the bridge-room switchback ladder up to (30,34)->221.  bridgeClimb
  -- drives the measured z-loop table (correct) with random encounters SUPPRESSED
  -- -- the fifth pass's "(30,41) corrupting warp" was a mis-rode HANGING random
  -- encounter, not a warp (see bridgeClimb's header + wob-route sixth pass).
  bridgeClimb(),
  corridorFollow(),

  -- the doorstep: one A-press from battle 69.  The extra beat plus the
  -- settled assert keep this mint honest: the state is the suite's boot
  -- point, so a battle-load or event in flight here poisons everything
  -- downstream (see corridorFollow's arrive note for the measured case).
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 221, "on the roof (map 221)")
    H.assertEq(H.fieldX() == 30 and H.fieldY() == 13, true,
      "at (30,13), north of the gentleman")
    H.assertEq(settled(), true, "doorstep is QUIET -- no battle/event in flight")
    H.assertEq(sw(0x034A), 1, "$034A still set -- he waits below")
    H.log(string.format("[dadaluma_doorstep] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("dadaluma_doorstep")
  end),
  H.saveState("dadaluma_doorstep.mss"),

  -- face him and talk, then FIGHT battle 69 -- honestly (issue #75).
  -- _ca96a9: dlg $042D -> set_b_switch $4B -> `battle 69` -> _ca5ea9,
  -- which gates on battle-switch $40: a WIN despawns him ($034A=0, control
  -- back at (30,13)); a LOSS is `call GameOver`.  Formation 438 = DADALUMA
  -- $0107 + two $006C (verified probe_fight.lua).  The drive is the menu-
  -- episode fighter above, wrapped in a three-attempt retry ladder off the
  -- doorstep just minted: a wipe reloads the doorstep -- the mint-script
  -- spelling of a player reloading a save, caught BEFORE the GameOver
  -- fade -- and escalates the tier (2 adds EDGAR's AutoCrossbow, 3 adds
  -- SABIN's Pummel), which reshuffles every subsequent roll.  Outside the
  -- battle the driver still edge-A's broadly: the talk dialog, the reward
  -- and the win-tail text do NOT set the dialogWaiting latch.
  (function()
    local dadaBlob, dadaWon = nil, false
    local dadaLost = nil
    local function fightBody(tier)
      local F = mkFighter(tier, "dadaluma")
      local battN = 0
      return H.driveUntil(function()
        if F.lost then
          dadaLost = F.lost
          return true                 -- reload beats riding the GameOver
        end
        return sw(0x034A) == 0 and map() == 221 and H.hasControl()
          and H.tileAligned() and bright() >= 15
      end, 40000, {
        H.call(function()
          battN = H.battleLoadStarted() and battN + 1 or 0
          if battN >= 3 then
            F.frame(battN)
            return
          end
          F.idle()
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
        end),
      }, "Dadaluma fought honestly (tier " .. tier .. ") -> $034A clear")
    end
    local function attempt(n)
      local ldReq
      return H.cond(function() return not dadaWon end, {
        H.cond(function() return n > 1 end, {
          H.logStep(function()
            return string.format("[dadaluma] ATTEMPT %d -- reloading the " ..
              "doorstep after a loss (%s)", n, tostring(dadaLost))
          end),
          H.call(function() ldReq = H.requestLoadState(dadaBlob) end),
          H.waitFrames(2),
          H.call(function() H.checkReq(ldReq, "dadaluma attempt " .. n) end),
          H.waitFrames(60),
        }, {}),
        H.call(function() dadaLost = nil end),
        H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(4),
        fightBody(n),
        H.call(function()
          if dadaLost == nil then
            dadaWon = true
            H.log(string.format("[dadaluma] attempt %d WON battle 69 " ..
              "honestly at f%d", n, H.frame))
          end
        end),
      }, {})
    end
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "doorstep checkpoint")
        dadaBlob = ckReq.blob
        H.log(string.format("[dadaluma] doorstep checkpoint captured " ..
          "(%d bytes) f%d", #dadaBlob, H.frame))
      end),
      attempt(1),
      attempt(2),
      attempt(3),
      H.call(function()
        if not dadaWon then
          error(string.format("[dadaluma] battle 69 not won in 3 honest " ..
            "attempts -- last loss: %s -- the per-attempt numbers above " ..
            "are the balance finding (#74-style); do not rig this fight",
            tostring(dadaLost)), 0)
        end
      end),
    })
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x034A), 0, "$034A CLEAR -- the gentleman is gone")
    H.assertEq(map(), 221, "still on map 221")
    H.assertEq(H.fieldX() == 30 and H.fieldY() == 13, true,
      "control returned at (30,13)")
    H.assertEq(H.bfsPath(33, 10) ~= nil, true,
      "the tower porch is OPEN -- (33,10) walkable")
    H.assertEq(sw(0x0053), 0, "$0053 still clear -- TERRA waits upstairs")
    H.log(string.format("[dadaluma_won] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("dadaluma_won")
  end),
  H.saveState("dadaluma_won.mss"),
  H.logStep(function()
    return string.format(
      "dadaluma_won minted at frame %d -- the maze is climbed", H.frame)
  end),
})
