-- probe_climb2.lua -- from the maze rooftop reached via building (44,48)
-- [lands 221(22,14)], render the island and list ALL 221 door-source and
-- jump tiles it reaches (diagonal), to find the next hop toward Dadaluma.
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
-- all 221 door-source tiles (short_entrance _221) + jumps + landmarks
local TILES = {
  {13,21,"d225(124,55)"},{23,17,"d225(83,61)"},{42,28,"d225(98,61)"},
  {43,24,"d225(110,54)"},{44,48,"d225(12,43)"},{44,41,"d225(11,16)"},
  {49,38,"d225(21,14)"},{54,35,"d225(66,56)"},{38,57,"d225(52,56)"},
  {35,53,"d225(48,48)"},{34,50,"d225(59,34)"},{30,42,"d225(47,10)"},
  {35,33,"d225(11,61)"},{31,30,"d225(30,61)"},{30,21,"d225(30,33)"},
  {35,15,"d225(35,13)"},{15,39,"d225(118,26)"},{12,36,"d225(104,26)"},
  {49,31,"d179"},{33,9,"TOWER->226"},
  {28,39,"jL39"},{25,39,"jR39"},{21,39,"jL39b"},{19,39,"jR39b"},
  {28,33,"jL33"},{25,33,"jR33"},{21,33,"jL33b"},{19,33,"jR33b"},
  {35,41,"CRANE"},{30,14,"DADALUMA"},
}
H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.navTo(44, 48, { arrive = function() return map() == 225 end, maxFrames = 12000 }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright()>=15 end, 1500, "225", 5),
  H.waitFrames(120),
  H.navTo(21, 14, { arrive = function() return map() == 221 end, maxFrames = 15000 }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright()>=15 end, 1500, "221 roof", 5),
  H.waitFrames(150),
  H.call(function()
    local key = function(x, y) return y * 256 + x end
    local seen = floodDiag()
    H.log(string.format("[roof] at (%d,%d); exits reachable:", H.fieldX(), H.fieldY()))
    for _, t in ipairs(TILES) do
      local on = seen[key(t[1],t[2])]
      local adj = on or seen[key(t[1],t[2]+1)] or seen[key(t[1],t[2]-1)]
        or seen[key(t[1]+1,t[2])] or seen[key(t[1]-1,t[2])]
      if adj then H.log(string.format("  (%d,%d) %-14s %s", t[1],t[2],t[3],on and "ON" or "adj")) end
    end
    -- render the immediate area
    H.log("  render x14..40 y8..24:")
    for y = 8, 24 do
      local row = {}
      for x = 14, 40 do
        local t = H.maptile(x, y)
        local wall = (H.readByte(0x7E7600+t)&0x07)==0x07
        local c = seen[key(x,y)] and "@" or (wall and "#" or ".")
        if x==H.fieldX() and y==H.fieldY() then c="P" end
        row[#row+1]=c
      end
      H.log(string.format("  y=%2d %s", y, table.concat(row)))
    end
  end),
})
