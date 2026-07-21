-- probe_maze5.lua -- render the arrival island across the maze region so the
-- exact street/jump boundary is on record.  '@'=in-island walkable,
-- '.'=walkable but off-island, '#'=wall, plus jump(J)/crane(C)/Dadaluma(D)
-- /tower(T) trigger marks.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end

local function flood()
  local sx, sy = H.fieldX(), H.fieldY()
  local seen, q, qi = {}, { { sx, sy } }, 1
  local function key(x, y) return y * 256 + x end
  seen[key(sx, sy)] = true
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      local d = ({ up={0,-1}, down={0,1}, left={-1,0}, right={1,0} })[mv]
      local nx, ny = x + d[1], y + d[2]
      if not seen[key(nx, ny)] and H.canStep(x, y, mv) then
        seen[key(nx, ny)] = true; q[#q+1] = { nx, ny }
      end
    end
  end
  return seen
end

local MARK = {
  ["28,39"]="J",["25,39"]="J",["21,39"]="J",["19,39"]="J",
  ["28,33"]="J",["25,33"]="J",["21,33"]="J",["19,33"]="J",
  ["35,41"]="C",["30,14"]="D",["33,9"]="T",
  ["30,42"]="d",["35,33"]="d",["31,30"]="d",["30,21"]="d",["35,15"]="d",
  ["15,39"]="d",["12,36"]="d",
}

H.run({ maxFrames = 20000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    local key = function(x, y) return y * 256 + x end
    local seen = flood()
    H.log(string.format("[render] map %d from (%d,%d), maze region x8..44 y6..46:",
      map(), H.fieldX(), H.fieldY()))
    for y = 6, 46 do
      local row = {}
      for x = 8, 44 do
        local m = MARK[x..","..y]
        local t = H.maptile(x, y)
        local wall = (H.readByte(0x7E7600 + t) & 0x07) == 0x07
        local c
        if seen[key(x,y)] then c = m and m:lower() or "@"
        elseif not wall then c = m or "."
        else c = m or "#" end
        row[#row+1] = c
      end
      H.log(string.format("  y=%2d %s", y, table.concat(row)))
    end
    H.log("  legend: @ in-island, . off-island walkable, # wall;")
    H.log("  J/C/D/T=jump/crane/dadaluma/tower (lowercase = in-island); d=225 door")
  end),
})
