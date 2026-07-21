-- probe_climb.lua -- the maze crack: arrival -> building door (44,48) ->
-- 225(12,43) diagonal-stair interior -> onward door (21,14) -> 221(49,39),
-- a maze rooftop.  Then DIAGONAL-flood the landing island and report which
-- jumps / Dadaluma / tower / onward doors it reaches.  navTo IS diagonal-
-- aware (bfsPath uses the 8 MOVES); only my probe floods were cardinal.
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
