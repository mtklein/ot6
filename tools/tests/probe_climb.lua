-- probe_climb.lua -- the maze crack: arrival -> building door (44,48) ->
-- 225(12,43) diagonal-stair interior -> onward door -> a 221 rooftop.
-- DIAGONAL-flood the landing and report reachable jumps/Dadaluma/doors.
-- navTo IS diagonal-aware (bfsPath uses the 8 MOVES); only my probe floods
-- were cardinal, which is what made the interiors look sealed.
--
-- SUCCESSOR ROUTE NOTES -- the EXACT Zozo door tables (from
-- short_entrance.dat; my early probes used off-by-one guesses, hence the
-- dead crossings).  Doors are two-way; a crossing is navTo-a-neighbour +
-- one held press onto the source tile.
--
-- map 221 (rooftops) -> map 225 (interiors), source(221) -> dest(225):
--   (13,21)->225(124,55)  (23,17)->225(83,61)   (42,28)->225(98,61)CLOCK
--   (43,24)->225(110,54)  (44,48)->225(12,43)   (44,41)->225(11,16)
--   (49,38)->225(21,14)   (54,35)->225(66,56)   (38,57)->225(52,56)
--   (35,53)->225(48,48)   (34,50)->225(59,34)   (30,42)->225(47,10)
--   (35,33)->225(11,61)   (31,30)->225(30,61)   (30,21)->225(30,33)
--   (35,15)->225(35,13)   (15,39)->225(118,26)  (12,36)->225(104,26)
--   (49,31)->179          (33,9)->226(82,37) TOWER (Dadaluma-roof exit)
--
-- map 225 (interiors) -> map 221 (rooftops), source(225) -> dest(221):
--   (12,44)->221(44,49)   (11,17)->221(44,42)*  (21,15)->221(49,39)
--   (52,57)->221(38,58)   (47,47)->221(35,54)   (59,35)->221(34,51)
--   (46,9)->221(30,43)**  (118,27)->221(15,40)  (104,27)->221(12,37)
--   (83,62)->221(23,18)   (124,56)->221(13,22)  (98,62)->221(42,29)
--   (110,55)->221(43,25)* (66,57)->221(54,36)   (11,62)->221(35,34)
--   (30,62)->221(31,31)   (30,34)->221(30,22)** (35,14)->221(35,16)**
--   * measured DEAD 2-3 tile pockets (44,42) and (43,25).
--   ** the DADALUMA-region exits (221 x30-35): the 225 interior holding
--      (46,9)/(30,34)/(35,14) is the one to reach; it is NOT the (44,48)
--      building (that one only reaches (12,44)/(21,15)/(11,17)).  Which
--      rooftop enters it (via 221 (30,43)/(30,22)/(35,16)) is the open
--      question -- reached across the jump-39/33 rows and/or the crane.
--
-- THE DOOR-CROSSING TECHNIQUE (measured working): navTo the DOOR SOURCE
-- tile itself with { arrive = function() return map()==<dest> end } --
-- stepping onto a 221<->225 door tile transitions immediately (these are
-- walk-on transitions, NOT CheckDoor walls, so no held press is needed,
-- unlike castle doors).  navTo-to-a-NEIGHBOUR then a held press does NOT
-- work here and wasted several runs.
--
-- CONFIRMED HOP CHAIN so far (all measured, each a clean crossing):
--   arrival street (61,44)
--     -navTo(44,48)->            225 (12,44) interior  [159-tile diagonal]
--     -navTo(21,15) arrive 221-> 221 (49,39) rooftop   [26 tiles]
--       this roof's only onward door is (54,35)->225(66,56) -- the NEXT
--       building; the jump rows and Dadaluma are still hops beyond it.
--   The (44,48) building's other exits are DEAD ((11,17)->pocket (44,42);
--   the (12,44) side is the entrance).  A successor continues from
--   221(49,39): cross (54,35)->225(66,56), flood, follow its onward doors,
--   and keep hopping toward a rooftop bearing 221(30,43)/(30,22)/(35,16).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local MOVES = { "up","down","left","right","upright","downright","downleft","upleft" }
local DELTA = { up={0,-1}, down={0,1}, left={-1,0}, right={1,0},
  upright={1,-1}, downright={1,1}, downleft={-1,1}, upleft={-1,-1} }
local function floodDiag()
  local sx, sy = H.fieldX(), H.fieldY()
  local seen, q, qi = {}, { { sx, sy } }, 1
  local function key(x, y) return y * 256 + x end
  seen[key(sx, sy)] = true
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for _, mv in ipairs(MOVES) do
      if H.canStep(x, y, mv) then
        local d = DELTA[mv]; local nx, ny = x+d[1], y+d[2]
        if not seen[key(nx,ny)] then seen[key(nx,ny)]=true; q[#q+1]={nx,ny} end
      end
    end
  end
  return seen
end

H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  -- into the building at street door (44,48) -> 225 (12,43)
  H.navTo(44, 48, { arrive = function() return map() == 225 end, maxFrames = 12000 }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 end, 1500, "225", 5),
  H.waitFrames(150),
  H.call(function() H.log(string.format("[225] at (%d,%d)", H.fieldX(), H.fieldY())) end),
  -- across the diagonal-stair interior to the onward door (21,14) -> 221
  H.navTo(21, 14, { arrive = function() return map() == 221 end, maxFrames = 15000 }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 end, 1500, "221 roof", 5),
  H.waitFrames(150),
  H.call(function()
    local key = function(x, y) return y * 256 + x end
    H.log(string.format("[roof] landed 221 at (%d,%d); DIAG island:",
      H.fieldX(), H.fieldY()))
    local seen = floodDiag()
    local n = 0; for _ in pairs(seen) do n = n + 1 end
    H.log(string.format("  %d tiles", n))
    for _, t in ipairs({
        {28,39,"jumpL39"},{25,39,"jumpR39"},{21,39,"jumpL39b"},{19,39,"jumpR39b"},
        {28,33,"jumpL33"},{25,33,"jumpR33"},{21,33,"jumpL33b"},{19,33,"jumpR33b"},
        {35,41,"CRANE"},{30,14,"DADALUMA"},{33,9,"tower"},{41,32,"TERRAnpc"},
        {49,38,"d(21,14)back"},{54,35,"d->225(66,56)"},{35,33,"d->225(11,61)"},
        {30,42,"d->225(47,10)"},{30,21,"d->225(30,33)"},{35,15,"d->225(35,13)"},
        {44,41,"d->225(11,16)"},
      }) do
      local adj = seen[key(t[1],t[2])] or seen[key(t[1],t[2]+1)] or seen[key(t[1],t[2]-1)]
        or seen[key(t[1]+1,t[2])] or seen[key(t[1]-1,t[2])]
      if adj then H.log(string.format("  reach (%d,%d) %s%s", t[1], t[2], t[3],
        seen[key(t[1],t[2])] and " ON" or " adj")) end
    end
  end),
})
