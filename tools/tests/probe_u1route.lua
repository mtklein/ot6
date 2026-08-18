-- probe_u1route.lua -- measurement probe for gen_zozo4's U1 crane-roof
-- crossing (map 221, stair-exit landing (30,43) -> the J39 row at (29,39)).
-- The first table drive parked at (33,43) z=2 with canStep refusing
-- "upright" for a whole 24000-frame budget; the hypothesis is that (33,43)
-- is a mid-beam bridge-diag tile whose diagonal is z-suppressed at z=2, and
-- the real route enters the "/" beam at its $41 base via (31,44)/(32,44) --
-- the two baseline-trail tiles the first table wrote off as recovery
-- entries.  This probe reads the live prop bytes (the street is the same
-- map 221, so the decompressed tables are live from zozo_arrival) and walks
-- a single-z-tracked door-walled BFS from (30,43) at each z seed, printing
-- the move list.  Reads only.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end

-- gen_zozo4_dadaluma's transcription of player.asm's step rules (its
-- door-walled step model), z-tracked
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
                 left = { -1, 0 }, upright = { 1, -1 }, downright = { 1, 1 },
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
local DOORS221 = { {13,21},{23,17},{42,28},{43,24},{44,48},{44,41},{49,38},
  {54,35},{38,57},{35,53},{34,50},{30,42},{35,33},{31,30},{30,21},{35,15},
  {15,39},{12,36},{49,31},{33,9} }
local W221 = {}
for _, d in ipairs(DOORS221) do W221[key(d[1], d[2])] = true end

-- single-z-tracked BFS with parents; returns the move list or nil
local function route(sx, sy, sz, tx, ty)
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local function nkey(x, y, z) return (z << 16) | (y << 8) | x end
  local seen, q, qi = {}, {}, 1
  seen[nkey(sx, sy, sz)] = true
  q[1] = { sx, sy, sz, nil, nil }        -- x, y, z, parent qindex, move
  while qi <= #q do
    local x, y, z, pi, pmv = table.unpack(q[qi])
    if x == tx and y == ty then
      local out, i = {}, qi
      while q[i][4] do
        table.insert(out, 1, string.format("(%d,%d)%s->", q[q[i][4]][1],
          q[q[i][4]][2], q[i][5]))
        i = q[i][4]
      end
      return out
    end
    local zn = zAfter(x, y, z)
    for _, mv in ipairs(MOVES) do
      local d = DELTA[mv]
      local nx, ny = x + d[1], y + d[2]
      if nx >= 0 and ny >= 0 and nx <= xm and ny <= ym
         and (not W221[key(nx, ny)] or (nx == tx and ny == ty)) then
        local k = nkey(nx, ny, zn)
        if not seen[k] and stepAllowed(x, y, mv, z) then
          seen[k] = true
          q[#q + 1] = { nx, ny, zn, qi, mv }
        end
      end
    end
    qi = qi + 1
  end
  return nil
end

H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "zozo_arrival sits on map 221")
    -- the prop bytes of the crossing's neighbourhood
    for y = 38, 46 do
      local r1, r2 = {}, {}
      for x = 28, 38 do
        r1[#r1 + 1] = string.format("%02X", prop1(x, y))
        r2[#r2 + 1] = string.format("%02X", prop2(x, y))
      end
      H.log(string.format("[p1] y=%2d %s   [p2] %s", y,
        table.concat(r1, " "), table.concat(r2, " ")))
    end
    -- the engine-model route from the landing at each possible z seed
    for z = 0, 3 do
      local r = route(30, 43, z, 29, 39)
      H.log(string.format("[route z%d] %s", z,
        r and table.concat(r) .. "(29,39)" or "NO PATH"))
    end
  end),
})
