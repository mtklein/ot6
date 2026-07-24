-- probe_climb_dump.lua -- boot bridge_checkpoint (map 225, ~30,61) and DUMP
-- the bridge-room shaft prop tables + a door-walled all-z BFS to (30,34),
-- to resolve: is there a non-warp route to the (30,34) door, or is (30,41)
-- unavoidable?  Read-only measurement; mints nothing.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function key(x, y) return y * 256 + x end
local function prop1(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function prop2(x, y) return H.readByte(0x7E7700 + H.maptile(x, y)) end

local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }
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

local DOORS225 = { {12,44},{11,17},{21,15},{52,57},{47,47},{59,35},{46,9},
  {118,27},{104,27},{83,62},{124,56},{98,62},{110,55},{66,57},{11,62},
  {30,62},{30,34},{35,14} }

H.run({ maxFrames = 8000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/bridge_checkpoint.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[boot] map=%d (%d,%d) z%d xm=%d ym=%d", map(),
      H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3,
      H.readByte(0x0086), H.readByte(0x0087)))

    -- 1. p1 grid for x=24..42, y=30..62 (the shaft)
    H.log("=== p1 (prop1) grid  cols x=24..42 ===")
    H.log("      " .. (function()
      local s = ""
      for x = 24, 42 do s = s .. string.format("%02d ", x) end
      return s
    end)())
    for y = 30, 62 do
      local row = string.format("y%02d:  ", y)
      for x = 24, 42 do
        row = row .. string.format("%02X ", prop1(x, y))
      end
      H.log(row)
    end
    -- 2. p2 grid
    H.log("=== p2 (prop2 exit bits) grid  cols x=24..42 ===")
    for y = 30, 62 do
      local row = string.format("y%02d:  ", y)
      for x = 24, 42 do
        row = row .. string.format("%02X ", prop2(x, y))
      end
      H.log(row)
    end
  end),

  -- 3. door-walled all-z BFS to (30,34): with and without (30,41) walled.
  H.call(function()
    local function bfsFirst(sx, sy, tx, ty, walls)
      local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
      local function nkey(x, y, z) return (z << 16) | (y << 8) | x end
      local seen, q, qi, parent = {}, {}, 1, {}
      for z = 0, 3 do seen[nkey(sx, sy, z)] = true; q[#q+1] = { sx, sy, z } end
      while qi <= #q do
        local x, y, z = q[qi][1], q[qi][2], q[qi][3]; qi = qi + 1
        if x == tx and y == ty then
          local path, k = {}, nkey(x, y, z)
          while parent[k] do table.insert(path, 1, parent[k][2]); k = parent[k][1] end
          return path
        end
        local zn = zAfter(x, y, z)
        for _, mv in ipairs(MOVES) do
          local d = DELTA[mv]; local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and ny >= 0 and nx <= xm and ny <= ym
             and (not walls[key(nx, ny)] or (nx == tx and ny == ty)) then
            local nk = nkey(nx, ny, zn)
            if not seen[nk] and stepAllowed(x, y, mv, z) then
              seen[nk] = true
              parent[nk] = { nkey(x, y, z), string.format("%s@(%d,%d)z%d", mv, x, y, z) }
              q[#q+1] = { nx, ny, zn }
            end
          end
        end
      end
      return nil
    end
    local function doorWalls(extra)
      local w = {}
      for _, d in ipairs(DOORS225) do w[key(d[1], d[2])] = true end
      for _, e in ipairs(extra or {}) do w[key(e[1], e[2])] = true end
      return w
    end
    local sx, sy = H.fieldX(), H.fieldY()
    local p1 = bfsFirst(sx, sy, 30, 34, doorWalls())
    H.log("=== BFS (30,61)->(30,34), doors walled (NOT 30,41) ===")
    if p1 then
      H.log(string.format("PATH len=%d:", #p1))
      for i, s in ipairs(p1) do H.log(string.format("  %02d %s", i, s)) end
    else H.log("NO PATH") end
    local p2 = bfsFirst(sx, sy, 30, 34, doorWalls({ {30,41} }))
    H.log("=== BFS (30,61)->(30,34), doors + (30,41) walled ===")
    if p2 then
      H.log(string.format("PATH len=%d:", #p2))
      for i, s in ipairs(p2) do H.log(string.format("  %02d %s", i, s)) end
    else H.log("NO PATH (confirms 30,41 is the only model route)") end
  end),
})
