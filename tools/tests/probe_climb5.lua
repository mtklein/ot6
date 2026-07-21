-- probe_climb5.lua -- cross out of the (44,48) building onto a real 221
-- rooftop: 225(12,43) interior -> hold onto door (11,16) -> 221(44,42),
-- census it, and if a jump tile is reachable, FIRE it (navTo + face the
-- gap) to validate the jump mechanism -- the last unproven piece.
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
H.run({ maxFrames = 50000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.navTo(44, 48, { arrive = function() return map()==225 end, maxFrames=12000 }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright()>=15 end, 1500, "b1", 5),
  H.waitFrames(120),
  -- navTo beside door (11,16), then hold up/left onto it -> 221(44,42)
  H.navTo(11, 17, { maxFrames=15000 }),
  H.call(function() H.log(string.format("[at door nbr] (%d,%d) map %d",
    H.fieldX(), H.fieldY(), map())) end),
  H.driveUntil(function() return map()==221 end, 900, {
    H.hold({ "up" }), H.waitFrames(4),
  }, "cross (11,16) -> 221"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright()>=15 end, 1500, "roof", 5),
  H.waitFrames(150),
  H.call(function()
    local key = function(x,y) return y*256+x end
    H.log(string.format("[ROOF221] at (%d,%d)", H.fieldX(), H.fieldY()))
    local seen = floodDiag()
    local n=0; for _ in pairs(seen) do n=n+1 end
    H.log(string.format("  island %d tiles", n))
    for _, t in ipairs({
        {30,14,"DADALUMA"},{33,9,"TOWER"},{28,39,"jL39"},{25,39,"jR39"},
        {21,39,"jL39b"},{19,39,"jR39b"},{28,33,"jL33"},{25,33,"jR33"},
        {21,33,"jL33b"},{19,33,"jR33b"},{35,41,"CRANE"},
        {30,21,"d(30,33)"},{35,15,"d(35,13)"},{31,30,"d(30,61)"},
        {35,33,"d(11,61)"},{30,42,"d(47,10)"},{54,35,"d(66,56)"},
        {13,21,"d(124,55)"},{15,39,"d(118,26)"},{12,36,"d(104,26)"},
        {49,38,"d(21,14)"},{44,41,"d(11,16)back"},{34,50,"d(59,34)"},
      }) do
      local on = seen[key(t[1],t[2])]
      local adj = on or seen[key(t[1],t[2]+1)] or seen[key(t[1],t[2]-1)]
        or seen[key(t[1]+1,t[2])] or seen[key(t[1]-1,t[2])]
      if adj then H.log(string.format("  reach (%d,%d) %-11s %s", t[1],t[2],t[3],on and "ON" or "adj")) end
    end
  end),
})
